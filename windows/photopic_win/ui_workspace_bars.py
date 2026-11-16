"""Reusable top header, HUD, and control bar builders for PhotoPic Windows workspace."""

from __future__ import annotations

from PySide6.QtWidgets import QCheckBox, QFrame, QHBoxLayout, QLabel, QPushButton

from .design_system import AppColors, AppSpacing


def build_workspace_topbar(session_name: str, on_back, on_tab, on_watch) -> tuple[QFrame, dict]:
    top = QFrame()
    top.setObjectName("TopBar")
    top.setFixedHeight(52)
    lay = QHBoxLayout(top)
    lay.setContentsMargins(AppSpacing.LG, 0, AppSpacing.LG, 0)

    back_btn = QPushButton("← Sesiones")
    back_btn.clicked.connect(on_back)
    lay.addWidget(back_btn)

    title = QLabel(session_name)
    title.setStyleSheet("font-weight: 600; font-size: 14px;")
    lay.addWidget(title)

    tab_cull = QPushButton("Filtrar (Pendientes)")
    tab_arch = QPushButton("Archivadas")
    tab_cull.clicked.connect(lambda: on_tab(0))
    tab_arch.clicked.connect(lambda: on_tab(1))
    lay.addSpacing(AppSpacing.LG)
    lay.addWidget(tab_cull)
    lay.addWidget(tab_arch)
    lay.addStretch()

    watch_btn = QPushButton("Vincular Carpeta/SD USB...")
    watch_btn.clicked.connect(on_watch)
    lay.addWidget(watch_btn)

    edit_badge = QLabel("Para Edición: 0")
    edit_badge.setStyleSheet(
        f"color: {AppColors.APPROVE_GREEN}; background: rgba(34,197,94,0.16); "
        "border-radius: 10px; padding: 4px 10px; font-weight: 600;"
    )
    lay.addWidget(edit_badge)
    return top, {"tab_cull": tab_cull, "tab_arch": tab_arch, "edit_badge": edit_badge}


def build_workspace_bottom_controls(callbacks: dict) -> tuple[QFrame, QCheckBox]:
    ctrl = QFrame()
    ctrl.setObjectName("ControlBar")
    ctrl.setFixedHeight(64)
    lay = QHBoxLayout(ctrl)

    prev_btn, next_btn = QPushButton("↑ Anterior"), QPushButton("↓ Siguiente")
    zoom_btn, undo_btn = QPushButton("Zoom 1:1 (Espacio)"), QPushButton("Deshacer (Ctrl+Z)")
    arch_btn, ok_btn = QPushButton("← Archivar"), QPushButton("Para Edición →")
    arch_btn.setObjectName("ArchiveButton")
    ok_btn.setObjectName("ApproveButton")
    follow_chk = QCheckBox("Seguir última captura")

    prev_btn.clicked.connect(callbacks["prev"])
    next_btn.clicked.connect(callbacks["next"])
    zoom_btn.clicked.connect(callbacks["zoom"])
    undo_btn.clicked.connect(callbacks["undo"])
    arch_btn.clicked.connect(callbacks["archive"])
    ok_btn.clicked.connect(callbacks["approve"])
    follow_chk.toggled.connect(callbacks["follow"])

    for w in (prev_btn, next_btn, zoom_btn):
        lay.addWidget(w)
    lay.addStretch()
    for w in (undo_btn, arch_btn, ok_btn):
        lay.addWidget(w)
    lay.addStretch()
    lay.addWidget(follow_chk)
    return ctrl, follow_chk
