"""Centralized darkroom design tokens and QSS styling for PhotoPic Windows."""

from __future__ import annotations

from pathlib import Path
import sys


class AppColors:
    STAGE_BG = "#0B0B0C"
    WINDOW_CANVAS = "#111112"
    PANEL_SURFACE = "#18181A"
    ELEVATED_SURFACE = "#202023"
    CONTROL_HOVER = "#2A2A2E"
    BORDER_SUBTLE = "rgba(255, 255, 255, 0.08)"
    BORDER_STRONG = "rgba(255, 255, 255, 0.16)"
    TEXT_PRIMARY = "#F4F4F6"
    TEXT_SECONDARY = "#A8A8B0"
    TEXT_TERTIARY = "#73737C"
    TEXT_ON_ACCENT = "#0E0E10"
    PRIMARY_FILL = "#F0F0F2"
    APPROVE_GREEN = "#22C55E"
    ARCHIVE_RED = "#EF4444"
    WARNING_AMBER = "#F59E0B"
    INFO_BLUE = "#38BDF8"


class AppSpacing:
    XS = 6
    SM = 8
    MD = 12
    LG = 16
    XL = 24
    XXL = 32


def resolve_asset_path(relative_path: str) -> Path:
    """Resolves bundled assets cleanly both from source and inside PyInstaller .exe."""
    base = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parents[2]))
    candidate = base / relative_path
    if candidate.exists():
        return candidate
    repo_root = Path(__file__).resolve().parents[2]
    return repo_root / relative_path


def build_darkroom_stylesheet() -> str:
    return f"""
    QMainWindow, QWidget {{
        background-color: {AppColors.WINDOW_CANVAS};
        color: {AppColors.TEXT_PRIMARY};
        font-family: "Segoe UI", "Inter", sans-serif;
        font-size: 13px;
    }}
    QFrame#PanelSurface {{
        background-color: {AppColors.PANEL_SURFACE};
        border: 1px solid {AppColors.BORDER_SUBTLE};
        border-radius: 10px;
    }}
    QFrame#TopBar, QFrame#ControlBar {{
        background-color: {AppColors.PANEL_SURFACE};
        border-bottom: 1px solid {AppColors.BORDER_SUBTLE};
    }}
    QFrame#ControlBar {{
        border-top: 1px solid {AppColors.BORDER_SUBTLE};
        border-bottom: none;
    }}
    QPushButton {{
        background-color: {AppColors.ELEVATED_SURFACE};
        color: {AppColors.TEXT_PRIMARY};
        border: 1px solid {AppColors.BORDER_SUBTLE};
        border-radius: 8px;
        padding: 7px 14px;
        font-weight: 500;
    }}
    QPushButton:hover {{
        background-color: {AppColors.CONTROL_HOVER};
        border: 1px solid {AppColors.BORDER_STRONG};
    }}
    QPushButton:disabled {{
        color: {AppColors.TEXT_TERTIARY};
    }}
    QPushButton#PrimaryButton {{
        background-color: {AppColors.PRIMARY_FILL};
        color: {AppColors.TEXT_ON_ACCENT};
        border: none;
        font-weight: 600;
    }}
    QPushButton#ApproveButton {{
        background-color: rgba(34, 197, 94, 0.16);
        color: {AppColors.APPROVE_GREEN};
        border: 1px solid rgba(34, 197, 94, 0.35);
    }}
    QPushButton#ArchiveButton {{
        background-color: rgba(239, 68, 68, 0.16);
        color: {AppColors.ARCHIVE_RED};
        border: 1px solid rgba(239, 68, 68, 0.35);
    }}
    QLineEdit {{
        background-color: {AppColors.STAGE_BG};
        color: {AppColors.TEXT_PRIMARY};
        border: 1px solid {AppColors.BORDER_STRONG};
        border-radius: 6px;
        padding: 6px 10px;
    }}
    QListWidget {{
        background-color: {AppColors.WINDOW_CANVAS};
        border: none;
    }}
    """
