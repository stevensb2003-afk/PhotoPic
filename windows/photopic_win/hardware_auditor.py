"""Host hardware capability auditor and performance config store for PhotoPic Windows."""

from __future__ import annotations

import ctypes
from dataclasses import asdict, dataclass
from enum import Enum
import importlib.util
import json
import os
from pathlib import Path
import platform


class PerformanceTier(str, Enum):
    FULL_AI = "fullAI"
    BALANCED_AI = "balancedAI"
    LIGHTWEIGHT_NO_AI = "lightweightNoAI"

    @property
    def title(self) -> str:
        titles = {
            PerformanceTier.FULL_AI: "Estudio Completo (IA Faces + Poses)",
            PerformanceTier.BALANCED_AI: "Equilibrado (Solo Rostros Rápidos)",
            PerformanceTier.LIGHTWEIGHT_NO_AI: "Modo Ligero (Sin IA · Solo Tethering y RAW)",
        }
        return titles[self]

    @property
    def subtitle(self) -> str:
        subtitles = {
            PerformanceTier.FULL_AI: "Detecta personas, rostros, parpadeo y poses de cuerpo completo con MediaPipe/OpenCV.",
            PerformanceTier.BALANCED_AI: "Detecta rostros y ojos sin ejecutar el modelo pesado de poses corporales.",
            PerformanceTier.LIGHTWEIGHT_NO_AI: "Desactiva toda la IA en segundo plano para PCs modestas o sesiones masivas.",
        }
        return subtitles[self]


@dataclass(frozen=True)
class HardwareAuditReport:
    cpu_brand: str
    architecture: str
    cpu_cores: int
    ram_gb: int
    has_mediapipe: bool
    has_opencv: bool
    recommended_tier: PerformanceTier
    recommendation_reason: str


@dataclass
class PerformancePreferences:
    tier: str = PerformanceTier.BALANCED_AI.value
    enable_vision_autotagging: bool = True
    detect_body_poses: bool = False
    preview_max_dimension: int = 1600
    has_completed_guided_setup: bool = False
    auto_start_session_timer: bool = True
    auto_check_updates: bool = True

    @classmethod
    def preset(
        cls,
        tier: PerformanceTier,
        completed: bool = False,
        auto_start_timer: bool = True,
        auto_check_updates: bool = True,
    ) -> PerformancePreferences:
        if tier == PerformanceTier.FULL_AI:
            return cls(tier.value, True, True, 1800, completed, auto_start_timer, auto_check_updates)
        if tier == PerformanceTier.BALANCED_AI:
            return cls(tier.value, True, False, 1500, completed, auto_start_timer, auto_check_updates)
        return cls(tier.value, False, False, 1280, completed, auto_start_timer, auto_check_updates)


class _MemoryStatusEx(ctypes.Structure):
    _fields_ = [
        ("dwLength", ctypes.c_ulong),
        ("dwMemoryLoad", ctypes.c_ulong),
        ("ullTotalPhys", ctypes.c_ulonglong),
        ("ullAvailPhys", ctypes.c_ulonglong),
        ("ullTotalPageFile", ctypes.c_ulonglong),
        ("ullAvailPageFile", ctypes.c_ulonglong),
        ("ullTotalVirtual", ctypes.c_ulonglong),
        ("ullAvailVirtual", ctypes.c_ulonglong),
        ("sullAvailExtendedVirtual", ctypes.c_ulonglong),
    ]


class HardwareCapabilityAuditor:
    """Audits Windows/cross-platform CPU, RAM, and AI runtime readiness on startup."""

    @classmethod
    def audit_host(cls) -> HardwareAuditReport:
        arch = platform.machine() or "x86_64"
        cpu_brand = platform.processor().strip() or arch
        cores = max(1, os.cpu_count() or 2)
        ram_gb = cls._detect_ram_gb()
        has_mp = importlib.util.find_spec("mediapipe") is not None
        has_cv2 = importlib.util.find_spec("cv2") is not None
        tier, reason = cls.evaluate_tier(cores=cores, ram_gb=ram_gb, has_mediapipe=has_mp, has_opencv=has_cv2)
        return HardwareAuditReport(
            cpu_brand=cpu_brand,
            architecture=arch,
            cpu_cores=cores,
            ram_gb=ram_gb,
            has_mediapipe=has_mp,
            has_opencv=has_cv2,
            recommended_tier=tier,
            recommendation_reason=reason,
        )

    @staticmethod
    def evaluate_tier(cores: int, ram_gb: int, has_mediapipe: bool, has_opencv: bool) -> tuple[PerformanceTier, str]:
        if ram_gb < 8 or cores < 4 or (not has_mediapipe and not has_opencv):
            return (
                PerformanceTier.LIGHTWEIGHT_NO_AI,
                f"PC con recursos ajustados ({ram_gb} GB RAM, {cores} núcleos). "
                "Recomendamos desactivar la IA automática para priorizar captura USB/WPD y revelado RAW fluido.",
            )
        if not has_mediapipe or ram_gb < 12 or cores < 6:
            return (
                PerformanceTier.BALANCED_AI,
                f"Equipo con {ram_gb} GB RAM y {cores} núcleos sin Neural Engine dedicado (ejecuta en CPU). "
                "El perfil Equilibrado detecta rostros/ojos sin sobrecargar el procesador con poses completas.",
            )
        return (
            PerformanceTier.FULL_AI,
            f"Equipo apto ({ram_gb} GB RAM, {cores} núcleos y MediaPipe disponible) para auto-etiquetado completo en tiempo real.",
        )

    @staticmethod
    def _detect_ram_gb() -> int:
        if os.name == "nt":
            try:
                stat = _MemoryStatusEx()
                stat.dwLength = ctypes.sizeof(_MemoryStatusEx)
                if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(stat)):  # type: ignore[attr-defined]
                    return max(1, round(stat.ullTotalPhys / (1024 ** 3)))
            except Exception:
                pass
        try:
            page_size = os.sysconf("SC_PAGE_SIZE")
            phys_pages = os.sysconf("SC_PHYS_PAGES")
            return max(1, round((page_size * phys_pages) / (1024 ** 3)))
        except Exception:
            return 8


class WindowsConfigStore:
    """Persists root folder and hardware/AI performance preferences in ~/.photopic_windows.json."""

    def __init__(self, config_path: Path | None = None) -> None:
        self.path = config_path or (Path.home() / ".photopic_windows.json")

    def load(self, default_audit: HardwareAuditReport) -> tuple[Path | None, PerformancePreferences]:
        if not self.path.exists():
            return None, PerformancePreferences.preset(default_audit.recommended_tier, completed=False)
        try:
            raw = json.loads(self.path.read_text(encoding="utf-8"))
        except Exception:
            return None, PerformancePreferences.preset(default_audit.recommended_tier, completed=False)

        root_str = str(raw.get("root_folder", "")).strip()
        root_dir = Path(root_str) if root_str and Path(root_str).exists() else None
        perf_raw = raw.get("performance")
        if isinstance(perf_raw, dict):
            prefs = PerformancePreferences(
                tier=str(perf_raw.get("tier", default_audit.recommended_tier.value)),
                enable_vision_autotagging=bool(perf_raw.get("enable_vision_autotagging", True)),
                detect_body_poses=bool(perf_raw.get("detect_body_poses", False)),
                preview_max_dimension=int(perf_raw.get("preview_max_dimension", 1600)),
                has_completed_guided_setup=bool(perf_raw.get("has_completed_guided_setup", root_dir is not None)),
                auto_start_session_timer=bool(perf_raw.get("auto_start_session_timer", True)),
                auto_check_updates=bool(perf_raw.get("auto_check_updates", True)),
            )
        else:
            prefs = PerformancePreferences.preset(default_audit.recommended_tier, completed=root_dir is not None)
        return root_dir, prefs

    def save(self, root_dir: Path | None, prefs: PerformancePreferences) -> None:
        payload = {
            "root_folder": str(root_dir) if root_dir is not None else "",
            "performance": asdict(prefs),
        }
        self.path.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
