"""Reusable top header, HUD, and control bar builders for PhotoPic Windows workspace."""

from __future__ import annotations

from PySide6.QtWidgets import QCheckBox, QFrame, QHBoxLayout, QLabel, QPushButton

from .design_system import AppColors, AppSpacing


def build_workspace_topbar(
    session_name: str,
    on_back,
    on_tab,
    on_watch,
    on_help=None,
    timer_widget=None,
    on_import_folder=None,
    on_detect_faces=None,
) -> tuple[QFrame, dict]:
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

    tab_cull = QPushButton("Filtrar (0)")
    tab_live = QPushButton("Vista en Vivo")
    tab_sel = QPushButton("Seleccionadas (0)")
    tab_arch = QPushButton("Archivadas (0)")
    tab_cull.clicked.connect(lambda: on_tab(0))
    tab_live.clicked.connect(lambda: on_tab(1))
    tab_sel.clicked.connect(lambda: on_tab(2))
    tab_arch.clicked.connect(lambda: on_tab(3))
    lay.addSpacing(AppSpacing.MD)
    lay.addWidget(tab_cull)
    lay.addWidget(tab_live)
    lay.addWidget(tab_sel)
    lay.addWidget(tab_arch)
    lay.addStretch()

    if on_detect_faces is not None:
        ai_btn = QPushButton("Detectar rostros")
        ai_btn.setToolTip("Analizar rostros, ojos cerrados y poses en todas las fotos pendientes con IA")
        ai_btn.clicked.connect(on_detect_faces)
        lay.addWidget(ai_btn)

    if on_import_folder is not None:
        imp_btn = QPushButton("Importar carpeta")
        imp_btn.setToolTip("Importar fotos desde una carpeta de tu PC a esta sesión (Ctrl+I)")
        imp_btn.clicked.connect(on_import_folder)
        lay.addWidget(imp_btn)

    watch_btn = QPushButton("Carpeta puente")
    watch_btn.setToolTip("Vincular carpeta puente / SD / transmisor Wi-Fi en tiempo real")
    watch_btn.clicked.connect(on_watch)
    lay.addWidget(watch_btn)

    if on_help is not None:
        help_btn = QPushButton("Ayuda (?)")
        help_btn.clicked.connect(on_help)
        lay.addWidget(help_btn)

    if timer_widget is not None:
        lay.addWidget(timer_widget)

    edit_badge = QLabel("Seleccionadas: 0")
    edit_badge.setStyleSheet(
        f"color: {AppColors.APPROVE_GREEN}; background: rgba(34,197,94,0.16); "
        "border-radius: 10px; padding: 4px 10px; font-weight: 600;"
    )
    lay.addWidget(edit_badge)
    return top, {"tab_cull": tab_cull, "tab_sel": tab_sel, "tab_arch": tab_arch, "edit_badge": edit_badge}


def build_workspace_bottom_controls(callbacks: dict) -> tuple[QFrame, QCheckBox]:
    ctrl = QFrame()
    ctrl.setObjectName("ControlBar")
    ctrl.setFixedHeight(64)
    lay = QHBoxLayout(ctrl)

    zoom_btn = QPushButton("Zoom 1:1 (Espacio)")
    rotate_btn = QPushButton("↻ Rotar (Shift)")
    undo_btn = QPushButton("Deshacer (Ctrl+Z)")
    arch_btn = QPushButton("← Archivar")
    prev_btn = QPushButton("↑ Anterior")
    next_btn = QPushButton("↓ Siguiente")
    ok_btn = QPushButton("Edición →")
    arch_btn.setObjectName("ArchiveButton")
    ok_btn.setObjectName("ApproveButton")
    follow_chk = QCheckBox("Seguir última captura")

    zoom_btn.clicked.connect(callbacks["zoom"])
    if "rotate" in callbacks:
        rotate_btn.clicked.connect(callbacks["rotate"])
    undo_btn.clicked.connect(callbacks["undo"])
    arch_btn.clicked.connect(callbacks["archive"])
    prev_btn.clicked.connect(callbacks["prev"])
    next_btn.clicked.connect(callbacks["next"])
    ok_btn.clicked.connect(callbacks["approve"])
    follow_chk.toggled.connect(callbacks["follow"])

    for w in (zoom_btn, rotate_btn, undo_btn):
        lay.addWidget(w)
    lay.addStretch()
    for w in (arch_btn, prev_btn, next_btn, ok_btn):
        lay.addWidget(w)
    lay.addStretch()
    lay.addWidget(follow_chk)
    return ctrl, follow_chk
