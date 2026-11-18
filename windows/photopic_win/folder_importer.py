"""Offline folder importer for Windows with 2-pass RAW+JPG segregation, collision stems, and XMP sync."""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
import os
from pathlib import Path
import shutil
from typing import Callable

from .models import MediaFormatClassifier, MediaFormatKind, PhotoSession
from .session_manager import SessionFileManager
from .session_metadata import SESSION_META_FILENAME
from .tag_store import PhotoTagStore


class FolderImportTransferMode(str, Enum):
    COPY = "copy"
    MOVE = "move"


@dataclass(frozen=True)
class PlannedImportUnit:
    primary_path: Path
    companion_path: Path | None
    format_kind: MediaFormatKind
    file_size_bytes: int


@dataclass(frozen=True)
class FolderImportScanSummary:
    source_dir: Path
    include_subfolders: bool
    raw_units_count: int
    paired_jpg_count: int
    standalone_compressed_count: int
    total_bytes: int
    extension_breakdown: list[tuple[str, int]]
    units: list[PlannedImportUnit]

    @property
    def total_photo_units_count(self) -> int:
        return len(self.units)


@dataclass(frozen=True)
class FolderImportProgress:
    completed_units: int
    total_units: int
    current_filename: str


@dataclass(frozen=True)
class FolderImportResult:
    session: PhotoSession
    imported_units_count: int
    raw_count: int
    paired_jpg_count: int
    standalone_compressed_count: int
    skipped_files_count: int


class SessionFolderImporter:
    """Scans an existing Windows folder, segregates RAW vs JPG pairs across flat or nested
    subfolders, allocates collision-free synchronized stems, and copies/moves `.xmp` sidecars."""

    @classmethod
    def scan_folder(cls, source_dir: Path, include_subfolders: bool = True) -> FolderImportScanSummary:
        if not source_dir.exists() or not source_dir.is_dir():
            raise ValueError(f"No se pudo leer la carpeta seleccionada: {source_dir}")

        image_paths = cls._collect_supported_images(source_dir, include_subfolders)
        raw_files: list[Path] = []
        compressed_files: list[Path] = []
        ext_counts: dict[str, int] = {}

        for path in image_paths:
            kind = MediaFormatClassifier.classify(path.name)
            if kind is None:
                continue
            ext = path.suffix.lstrip(".").upper()
            ext_counts[ext] = ext_counts.get(ext, 0) + 1
            if kind == MediaFormatKind.RAW:
                raw_files.append(path)
            else:
                compressed_files.append(path)

        units = cls._pair_images_two_pass(raw_files, compressed_files)
        raw_units = sum(1 for u in units if u.format_kind == MediaFormatKind.RAW)
        paired_jpgs = sum(1 for u in units if u.format_kind == MediaFormatKind.RAW and u.companion_path is not None)
        standalone = sum(1 for u in units if u.format_kind == MediaFormatKind.COMPRESSED)
        total_bytes = sum(u.file_size_bytes for u in units)
        breakdown = sorted(ext_counts.items(), key=lambda kv: (-kv[1], kv[0]))

        return FolderImportScanSummary(
            source_dir=source_dir,
            include_subfolders=include_subfolders,
            raw_units_count=raw_units,
            paired_jpg_count=paired_jpgs,
            standalone_compressed_count=standalone,
            total_bytes=total_bytes,
            extension_breakdown=breakdown,
            units=units,
        )

    @classmethod
    def import_as_new_session(
        cls,
        summary: FolderImportScanSummary,
        session_name: str,
        root_dir: Path,
        group_name: str | None = None,
        initial_tags: list[str] | None = None,
        transfer_mode: FolderImportTransferMode = FolderImportTransferMode.COPY,
        on_progress: Callable[[FolderImportProgress], None] | None = None,
    ) -> FolderImportResult:
        if not summary.units:
            raise ValueError("No se encontraron fotos compatibles (RAW, JPG, HEIC, PNG, TIFF o WebP) en esa carpeta.")

        effective_name = session_name.strip() or summary.source_dir.name
        created = SessionFileManager.create_session(
            raw_name=effective_name,
            root_dir=root_dir,
            group_name=group_name,
            initial_tags=initial_tags,
        )
        try:
            return cls.import_into_existing_session(
                summary=summary,
                session=created,
                transfer_mode=transfer_mode,
                on_progress=on_progress,
            )
        except Exception:
            counts = SessionFileManager.read_disk_counts(created)
            if counts.total_all_images == 0 and counts.companion_jpgs == 0:
                shutil.rmtree(created.directory, ignore_errors=True)
            raise

    @classmethod
    def import_into_existing_session(
        cls,
        summary: FolderImportScanSummary,
        session: PhotoSession,
        transfer_mode: FolderImportTransferMode = FolderImportTransferMode.COPY,
        on_progress: Callable[[FolderImportProgress], None] | None = None,
    ) -> FolderImportResult:
        if not summary.units:
            raise ValueError("No se encontraron fotos compatibles en la carpeta seleccionada.")

        cls._validate_no_overlap(summary.source_dir, session.directory, transfer_mode)
        SessionFileManager.ensure_subfolders(session)

        imported = 0
        raw_count = 0
        paired_jpg_count = 0
        standalone_count = 0
        skipped = 0
        last_error: str | None = None
        total = len(summary.units)

        for idx, unit in enumerate(summary.units):
            if on_progress is not None:
                on_progress(FolderImportProgress(idx, total, unit.primary_path.name))
            primary_target, companion_target = cls._allocate_target_paths(unit, session)
            try:
                cls._transfer_file(unit.primary_path, primary_target, transfer_mode)
                cls._transfer_xmp_sidecar_if_present(unit.primary_path, primary_target, transfer_mode)
                if unit.companion_path is not None and companion_target is not None:
                    cls._transfer_file(unit.companion_path, companion_target, transfer_mode)
                    paired_jpg_count += 1
                imported += 1
                if unit.format_kind == MediaFormatKind.RAW:
                    raw_count += 1
                else:
                    standalone_count += 1
            except OSError as exc:
                skipped += 1
                last_error = str(exc)

        if on_progress is not None:
            on_progress(FolderImportProgress(total, total, ""))

        if imported == 0 and last_error:
            raise OSError(f"No se pudieron importar los archivos: {last_error}")

        session.counts = SessionFileManager.read_disk_counts(session)
        return FolderImportResult(
            session=session,
            imported_units_count=imported,
            raw_count=raw_count,
            paired_jpg_count=paired_jpg_count,
            standalone_compressed_count=standalone_count,
            skipped_files_count=skipped,
        )

    @classmethod
    def _collect_supported_images(cls, source_dir: Path, include_subfolders: bool) -> list[Path]:
        collected: list[Path] = []
        if include_subfolders:
            for dirpath, dirnames, filenames in os.walk(source_dir):
                current = Path(dirpath)
                dirnames[:] = sorted(
                    d for d in dirnames
                    if not d.startswith(".") and not (current / d / SESSION_META_FILENAME).exists()
                )
                for fname in sorted(filenames):
                    if fname.startswith("."):
                        continue
                    candidate = current / fname
                    if MediaFormatClassifier.is_supported_image(candidate):
                        collected.append(candidate)
        else:
            for entry in sorted(source_dir.iterdir(), key=lambda p: str(p).lower()):
                if entry.is_file() and not entry.name.startswith(".") and MediaFormatClassifier.is_supported_image(entry):
                    collected.append(entry)
        return collected

    @classmethod
    def _pair_images_two_pass(
        cls,
        raw_files: list[Path],
        compressed_files: list[Path],
    ) -> list[PlannedImportUnit]:
        def _priority(p: Path) -> tuple[int, str]:
            ext = p.suffix.lstrip(".").upper()
            rank = 0 if ext in ("JPG", "JPEG") else (1 if ext in ("HEIC", "HEIF") else 2)
            return rank, str(p.resolve()).lower()

        prioritized = sorted(compressed_files, key=_priority)
        remaining = set(prioritized)
        same_dir: dict[tuple[Path, str], list[Path]] = {}
        global_stem: dict[str, list[Path]] = {}

        for comp in prioritized:
            stem = MediaFormatClassifier.base_filename(comp)
            same_dir.setdefault((comp.parent.resolve(), stem), []).append(comp)
            global_stem.setdefault(stem, []).append(comp)

        paired_by_raw: dict[Path, Path] = {}

        # Pass 1: exact same-directory stem match
        for raw_p in raw_files:
            key = (raw_p.parent.resolve(), MediaFormatClassifier.base_filename(raw_p))
            for cand in same_dir.get(key, []):
                if cand in remaining:
                    paired_by_raw[raw_p] = cand
                    remaining.remove(cand)
                    break

        # Pass 2: cross-subdirectory stem match (e.g. `RAW/IMG_01.CR2` + `JPG/IMG_01.JPG`)
        for raw_p in raw_files:
            if raw_p in paired_by_raw:
                continue
            stem = MediaFormatClassifier.base_filename(raw_p)
            for cand in global_stem.get(stem, []):
                if cand in remaining:
                    paired_by_raw[raw_p] = cand
                    remaining.remove(cand)
                    break

        units: list[PlannedImportUnit] = []
        for raw_p in raw_files:
            comp = paired_by_raw.get(raw_p)
            size = cls._file_size(raw_p) + (cls._file_size(comp) if comp is not None else 0)
            units.append(PlannedImportUnit(raw_p, comp, MediaFormatKind.RAW, size))

        # Pass 3: standalone compressed images stay eligible for `Filtrar`
        for comp in remaining:
            units.append(PlannedImportUnit(comp, None, MediaFormatKind.COMPRESSED, cls._file_size(comp)))

        return sorted(units, key=lambda u: (u.primary_path.name.lower(), str(u.primary_path.resolve()).lower()))

    @staticmethod
    def _file_size(path: Path) -> int:
        try:
            return path.stat().st_size
        except OSError:
            return 0

    @staticmethod
    def _validate_no_overlap(source_dir: Path, session_dir: Path, mode: FolderImportTransferMode) -> None:
        src = source_dir.resolve()
        dst = session_dir.resolve()
        if src == dst or dst in src.parents:
            raise ValueError(f"La carpeta origen coincide o está dentro de la sesión destino ({session_dir.name}).")
        if mode == FolderImportTransferMode.MOVE and src in dst.parents:
            raise ValueError(f"No se puede mover una carpeta padre hacia una subcarpeta destino ({source_dir.name}).")

    @staticmethod
    def _allocate_target_paths(unit: PlannedImportUnit, session: PhotoSession) -> tuple[Path, Path | None]:
        stem = unit.primary_path.stem
        primary_ext = unit.primary_path.suffix
        comp_ext = unit.companion_path.suffix if unit.companion_path is not None else ""

        suffix = 1
        while True:
            resolved_stem = stem if suffix == 1 else f"{stem}_{suffix}"
            primary_target = session.raw_folder / f"{resolved_stem}{primary_ext}"
            if unit.companion_path is not None:
                companion_target = session.jpg_folder / f"{resolved_stem}{comp_ext}"
                if not primary_target.exists() and not companion_target.exists():
                    return primary_target, companion_target
            elif not primary_target.exists():
                return primary_target, None
            suffix += 1

    @staticmethod
    def _transfer_file(src: Path, dst: Path, mode: FolderImportTransferMode) -> None:
        if mode == FolderImportTransferMode.COPY:
            shutil.copy2(str(src), str(dst))
        else:
            shutil.move(str(src), str(dst))

    @classmethod
    def _transfer_xmp_sidecar_if_present(
        cls,
        src_primary: Path,
        dst_primary: Path,
        mode: FolderImportTransferMode,
    ) -> None:
        src_xmp = PhotoTagStore.xmp_sidecar_path(src_primary)
        if not src_xmp.exists():
            return
        dst_xmp = PhotoTagStore.xmp_sidecar_path(dst_primary)
        if dst_xmp.exists():
            dst_xmp.unlink()
        cls._transfer_file(src_xmp, dst_xmp, mode)
