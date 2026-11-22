"""Windows USB Plug & Play tethering via WPD (Shell.Application) and SD delta watcher."""

from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path
import platform
import subprocess
import tempfile
import threading
import time
import uuid

from .baseline_gate import TetherBaselineGate
from .models import DeviceCategory, KnownDevice, MediaFormatClassifier


@dataclass
class WinConnectedDevice:
    fingerprint: str
    name: str
    category: DeviceCategory
    status_label: str
    is_live: bool = False
    battery_level: int | None = None


class LowBatteryAlertTrackerWin:
    """Fires once when a tethered camera drops to <= 10% battery and resets above 15%."""

    ALERT_THRESHOLD = 10
    RECOVERY_THRESHOLD = 15

    def __init__(self) -> None:
        self._alerted: set[str] = set()

    def evaluate(self, fingerprint: str, battery_percent: int | None) -> bool:
        if battery_percent is None:
            return False
        if 0 <= battery_percent <= self.ALERT_THRESHOLD:
            if fingerprint not in self._alerted:
                self._alerted.add(fingerprint)
                return True
            return False
        if battery_percent > self.RECOVERY_THRESHOLD:
            self._alerted.discard(fingerprint)
        return False

    def reset(self, fingerprint: str) -> None:
        self._alerted.discard(fingerprint)

    def sync_connected(self, active_fingerprints: set[str]) -> None:
        self._alerted.intersection_update(active_fingerprints)


class WindowsTetherService:
    """Polls connected MTP/PTP devices (DSLR, Android, iPhone) and watchfolders cleanly."""

    def __init__(self, on_file_staged=None, on_devices_changed=None) -> None:
        self.on_file_staged = on_file_staged
        self.on_devices_changed = on_devices_changed
        self.known_devices: dict[str, KnownDevice] = {}
        self.gates: dict[str, TetherBaselineGate] = {}
        self.active_watch_folders: dict[str, Path] = {}
        self.keep_originals_on_device: bool = True
        self._pending_sizes: dict[str, int] = {}
        self._stop_event = threading.Event()
        self._thread: threading.Thread | None = None
        self._script_path = Path(__file__).resolve().parents[1] / "scripts" / "wpd_bridge.ps1"

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._stop_event.clear()
        self._thread = threading.Thread(target=self._poll_loop, daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop_event.set()

    @staticmethod
    def _is_hidden_path(path_parts: tuple[str, ...] | list[str]) -> bool:
        return any(part.startswith(".") or part.lower() == "thumbnails" for part in path_parts)

    def attach_watch_folder(self, folder: Path, profile: KnownDevice) -> None:
        """Indexes pre-existing files in a tethered watch/SD folder so old files never import."""
        gate = TetherBaselineGate(connected_at_epoch=time.time())
        if folder.exists():
            for path in folder.rglob("*"):
                if path.is_file() and MediaFormatClassifier.is_supported_image(path):
                    if self._is_hidden_path(path.relative_to(folder).parts):
                        continue
                    stat = path.stat()
                    if stat.st_size <= 0:
                        continue
                    key = gate.item_key(str(path), path.name, stat.st_size)
                    gate.record_pre_catalog_item(key, stat.st_mtime)
        gate.mark_catalog_complete()
        self.known_devices[profile.fingerprint] = profile
        self.gates[profile.fingerprint] = gate
        self.active_watch_folders[profile.fingerprint] = folder

    def _poll_loop(self) -> None:
        while not self._stop_event.is_set():
            self._scan_watch_folders()
            if platform.system() == "Windows":
                self._poll_wpd_devices()
            self._stop_event.wait(1.5)

    def _scan_watch_folders(self) -> None:
        for fp, folder in list(self.active_watch_folders.items()):
            gate = self.gates.get(fp)
            profile = self.known_devices.get(fp)
            if not gate or not profile or not folder.exists():
                continue

            for path in folder.rglob("*"):
                if not path.is_file() or not MediaFormatClassifier.is_supported_image(path):
                    continue
                if self._is_hidden_path(path.relative_to(folder).parts):
                    continue
                stat = path.stat()
                if stat.st_size <= 0:
                    continue
                path_key = str(path)
                if self._pending_sizes.get(path_key) != stat.st_size:
                    self._pending_sizes[path_key] = stat.st_size
                    continue
                key = gate.item_key(path_key, path.name, stat.st_size)
                if gate.should_download_live_item(key, stat.st_mtime, was_added_after_catalog=False):
                    self._pending_sizes.pop(path_key, None)
                    staging = Path(tempfile.gettempdir()) / "PhotoPicStaging" / str(uuid.uuid4())
                    staging.mkdir(parents=True, exist_ok=True)
                    staged_file = staging / path.name
                    staged_file.write_bytes(path.read_bytes())
                    if not (profile.keep_originals_on_device and self.keep_originals_on_device):
                        try:
                            path.unlink()
                        except OSError:
                            pass
                    if self.on_file_staged:
                        self.on_file_staged(staged_file, path.name, profile)

    def _poll_wpd_devices(self) -> None:
        if not self._script_path.exists():
            return
        try:
            proc = subprocess.run(
                ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(self._script_path), "-Action", "list"],
                capture_output=True,
                text=True,
                timeout=6,
            )
            if proc.returncode != 0 or not proc.stdout.strip():
                return
            devices_raw = json.loads(proc.stdout)
            if isinstance(devices_raw, dict):
                devices_raw = [devices_raw]
            connected = [self._to_device_state(entry) for entry in devices_raw if entry.get("Name")]
            if self.on_devices_changed:
                self.on_devices_changed(connected)
            for dev in connected:
                self._sync_wpd_device_items(dev)
        except Exception:
            pass

    def _sync_wpd_device_items(self, dev: WinConnectedDevice) -> None:
        profile = self.known_devices.get(dev.fingerprint)
        if not profile or not profile.auto_connect_on_plug:
            return
        gate = self.gates.setdefault(dev.fingerprint, TetherBaselineGate(connected_at_epoch=time.time()))
        try:
            proc = subprocess.run(
                ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(self._script_path), "-Action", "scan", "-DeviceName", dev.name],
                capture_output=True,
                text=True,
                timeout=10,
            )
            if proc.returncode != 0 or not proc.stdout.strip():
                return
            items = json.loads(proc.stdout)
            if isinstance(items, dict):
                items = [items]
            first_pass = not gate.is_catalog_complete
            for item in items:
                name = str(item.get("Name", ""))
                size = int(item.get("Size", 0))
                sub_path = str(item.get("SubPath", name))
                if self._is_hidden_path(sub_path.split("/")):
                    continue
                if not MediaFormatClassifier.classify(name):
                    continue
                if not first_pass and size <= 0:
                    continue
                key = gate.item_key(dev.fingerprint, name, size)
                if first_pass:
                    gate.record_pre_catalog_item(key, None)
                elif gate.should_download_live_item(key, time.time(), was_added_after_catalog=True):
                    self._copy_wpd_item(dev.name, sub_path, name, profile)
            if first_pass:
                gate.mark_catalog_complete()
        except Exception:
            pass

    def _copy_wpd_item(self, device_name: str, sub_path: str, filename: str, profile: KnownDevice) -> None:
        staging = Path(tempfile.gettempdir()) / "PhotoPicStaging" / str(uuid.uuid4())
        staging.mkdir(parents=True, exist_ok=True)
        subprocess.run(
            [
                "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
                "-File", str(self._script_path),
                "-Action", "copy", "-DeviceName", device_name,
                "-ItemPath", sub_path, "-DestDir", str(staging),
            ],
            capture_output=True,
            timeout=20,
        )
        candidate = staging / filename
        if candidate.exists() and self.on_file_staged:
            self.on_file_staged(candidate, filename, profile)

    @staticmethod
    def _to_device_state(entry: dict) -> WinConnectedDevice:
        name = str(entry.get("Name", "USB Camera"))
        lower = name.lower()
        if "iphone" in lower or "ipad" in lower or "apple" in lower:
            cat = DeviceCategory.IPHONE_IOS
        elif any(k in lower for k in ("canon", "eos", "nikon", "sony", "alpha", "fujifilm", "lumix")):
            cat = DeviceCategory.DSLR_MIRRORLESS
        else:
            cat = DeviceCategory.ANDROID_PTP
        return WinConnectedDevice(
            fingerprint=f"wpd:{name.lower().replace(' ', '_')}",
            name=name,
            category=cat,
            status_label="Conectado vía WPD (MTP/PTP)",
            is_live=True,
        )
