"""Cloud OTA updater for PhotoPic Windows (GitHub Releases latest.json + SHA-256 + atomic restart)."""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
import zipfile

from .design_system import resolve_asset_path

DEFAULT_REPOSITORY = "stevensb2003-afk/PhotoPic"


@dataclass(frozen=True)
class LocalBuildIdentityWin:
    version: str
    build_number: int
    commit_sha: str
    repository: str
    is_frozen_exe: bool


@dataclass(frozen=True)
class CloudUpdateEventWin:
    kind: str  # "checking", "up_to_date", "downloading", "ready", "error"
    message: str
    version: str = ""
    build_number: int = 0
    release_notes: str = ""
    staged_dir: Path | None = None


def load_local_build_identity() -> LocalBuildIdentityWin:
    meta_path = resolve_asset_path("build_version.json")
    if meta_path.exists():
        try:
            raw = json.loads(meta_path.read_text(encoding="utf-8-sig"))
            return LocalBuildIdentityWin(
                version=str(raw.get("version", "2.6")),
                build_number=int(raw.get("build_number", 0) or 0),
                commit_sha=str(raw.get("commit_sha", "dev")),
                repository=str(raw.get("repository", DEFAULT_REPOSITORY)),
                is_frozen_exe=bool(getattr(sys, "frozen", False)),
            )
        except Exception:
            pass

    ver_file = resolve_asset_path("VERSION")
    base_ver = ver_file.read_text(encoding="utf-8").strip() if ver_file.exists() else "2.6"
    return LocalBuildIdentityWin(
        version=base_ver,
        build_number=0,
        commit_sha="dev",
        repository=DEFAULT_REPOSITORY,
        is_frozen_exe=bool(getattr(sys, "frozen", False)),
    )


def verify_sha256_file(file_path: Path, expected_hex: str) -> bool:
    digest = hashlib.sha256()
    with file_path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().lower() == expected_hex.strip().lower()


def stage_windows_archive(zip_path: Path, expected_sha256: str, build_number: int) -> Path:
    if not verify_sha256_file(zip_path, expected_sha256):
        raise ValueError("Error de verificación SHA-256 en la actualización de Windows.")

    staging_root = Path(tempfile.gettempdir()) / f"PhotoPicWinUpdate_{build_number}"
    shutil.rmtree(staging_root, ignore_errors=True)
    extract_dir = staging_root / "extracted"
    extract_dir.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(zip_path, "r") as zf:
        zf.extractall(extract_dir)

    if (extract_dir / "PhotoPic.exe").exists():
        return extract_dir
    nested = [p for p in extract_dir.iterdir() if p.is_dir() and (p / "PhotoPic.exe").exists()]
    if nested:
        return nested[0]
    raise FileNotFoundError("El archivo descargado no contiene PhotoPic.exe.")


class CloudAutoUpdaterWin:
    """Checks GitHub Releases for newer builds, downloads + verifies ZIP, and installs on restart."""

    def __init__(self, on_event=None, auto_check: bool = True) -> None:
        self.identity = load_local_build_identity()
        self.on_event = on_event
        self.auto_check = auto_check
        self._busy = False
        self._staged_dir: Path | None = None
        self._staged_build: int = 0
        self._lock = threading.Lock()

    def manifest_url(self) -> str:
        stamp = int(time.time())
        return f"https://github.com/{self.identity.repository}/releases/latest/download/latest.json?t={stamp}"

    def check_async(self, user_initiated: bool = False) -> None:
        with self._lock:
            if self._busy:
                return
            self._busy = True
        thread = threading.Thread(
            target=self._run_check_worker,
            args=(user_initiated,),
            daemon=True,
        )
        thread.start()

    def _emit(self, event: CloudUpdateEventWin) -> None:
        if self.on_event is not None:
            self.on_event(event)

    def _run_check_worker(self, user_initiated: bool) -> None:
        try:
            self._emit(CloudUpdateEventWin("checking", "Buscando nueva versión en GitHub Cloud..."))
            req = urllib.request.Request(
                self.manifest_url(),
                headers={"User-Agent": f"PhotoPicWin/{self.identity.version}", "Cache-Control": "no-cache"},
            )
            with urllib.request.urlopen(req, timeout=15) as resp:
                manifest = json.loads(resp.read().decode("utf-8"))

            remote_build = int(manifest.get("buildNumber", 0) or 0)
            remote_ver = str(manifest.get("version", ""))
            notes = str(manifest.get("releaseNotes", ""))
            if remote_build <= self.identity.build_number:
                self._emit(CloudUpdateEventWin("up_to_date", f"Estás al día (v{self.identity.version}).", self.identity.version, self.identity.build_number))
                return

            if self._staged_dir is not None and self._staged_build == remote_build and self._staged_dir.exists():
                self._emit(CloudUpdateEventWin("ready", f"v{remote_ver} lista para instalar.", remote_ver, remote_build, notes, self._staged_dir))
                return

            win_url = str(manifest.get("windowsZipURL") or "").strip()
            win_sha = str(manifest.get("windowsSha256") or "").strip()
            if not win_url or not win_sha:
                raise ValueError("El manifiesto latest.json no incluye paquete Windows.")

            self._emit(CloudUpdateEventWin("downloading", f"Descargando v{remote_ver} en segundo plano...", remote_ver, remote_build, notes))
            dl_dir = Path(tempfile.gettempdir()) / f"PhotoPicWinDL_{remote_build}"
            dl_dir.mkdir(parents=True, exist_ok=True)
            zip_path = dl_dir / "PhotoPic-Windows-x64.zip"

            dl_req = urllib.request.Request(win_url, headers={"User-Agent": f"PhotoPicWin/{self.identity.version}"})
            with urllib.request.urlopen(dl_req, timeout=180) as src, zip_path.open("wb") as dst:
                shutil.copyfileobj(src, dst, length=1024 * 256)

            staged = stage_windows_archive(zip_path, win_sha, remote_build)
            shutil.rmtree(dl_dir, ignore_errors=True)
            self._staged_dir = staged
            self._staged_build = remote_build
            self._emit(CloudUpdateEventWin("ready", f"Nueva versión v{remote_ver} verificada (SHA-256) y lista.", remote_ver, remote_build, notes, staged))
        except urllib.error.HTTPError as http_err:
            if http_err.code == 404:
                self._emit(CloudUpdateEventWin("up_to_date", f"Estás al día (v{self.identity.version}).", self.identity.version, self.identity.build_number))
            elif user_initiated:
                self._emit(CloudUpdateEventWin("error", f"Error de servidor ({http_err.code})."))
        except Exception as exc:
            if user_initiated:
                self._emit(CloudUpdateEventWin("error", f"No se pudo buscar actualización: {exc}"))
        finally:
            with self._lock:
                self._busy = False

    def install_staged_and_restart(self) -> bool:
        if not self.identity.is_frozen_exe or self._staged_dir is None or not self._staged_dir.exists():
            return False

        target_exe = Path(sys.executable).resolve()
        target_dir = target_exe.parent
        ps_path = Path(tempfile.gettempdir()) / f"photopic_win_ota_{os.getpid()}.ps1"
        script = f"""
$ErrorActionPreference = "Stop"
$TargetPid = {os.getpid()}
while (Get-Process -Id $TargetPid -ErrorAction SilentlyContinue) {{ Start-Sleep -Milliseconds 300 }}
Copy-Item -Path "{self._staged_dir}\\*" -Destination "{target_dir}" -Recurse -Force
Start-Process -FilePath "{target_exe}"
Remove-Item -Path "{self._staged_dir.parent}" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
"""
        ps_path.write_text(script.strip(), encoding="utf-8")
        flags = getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0) | getattr(subprocess, "DETACHED_PROCESS", 0)
        subprocess.Popen(
            ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", str(ps_path)],
            creationflags=flags,
            close_fds=True,
        )
        return True
