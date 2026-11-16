"""Session directory operations, smart RAW+JPG pairing, disk moves, and Undo for Windows."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re
import shutil

from .ingest_router import route_ingest
from .models import (
    MediaFormatClassifier,
    MediaFormatKind,
    PhotoItem,
    PhotoSession,
    SessionDiskCounts,
)
from .tag_store import PhotoTagStore


@dataclass
class IngestOutcome:
    kind: str  # "added_raw", "added_fallback", "separated_jpg", "ignored"
    item: PhotoItem | None = None
    demoted_compressed_name: str | None = None
    destination_path: Path | None = None


@dataclass
class MoveRecord:
    item: PhotoItem
    original_path: Path
    moved_path: Path
    destination_folder_name: str
    original_companion_path: Path | None = None
    moved_companion_path: Path | None = None


class SessionFileManager:
    SUBFOLDERS = ("RAW", "JPG", "Para_Edicion", "Archivadas")

    @classmethod
    def create_session(cls, raw_name: str, root_dir: Path) -> PhotoSession:
        sanitized = re.sub(r'[<>:"/\\|?*]', "-", raw_name).strip()
        if not sanitized:
            raise ValueError("El nombre de la sesión no puede estar vacío.")

        session_dir = cls._unique_dir(root_dir, sanitized)
        session_dir.mkdir(parents=True, exist_ok=True)
        for sub in cls.SUBFOLDERS:
            (session_dir / sub).mkdir(parents=True, exist_ok=True)
        for dest in ("Para_Edicion", "Archivadas"):
            (session_dir / dest / "RAW").mkdir(parents=True, exist_ok=True)
            (session_dir / dest / "JPG").mkdir(parents=True, exist_ok=True)

        stat = session_dir.stat()
        return PhotoSession(name=session_dir.name, directory=session_dir, created_at=stat.st_mtime)

    @classmethod
    def ensure_subfolders(cls, session: PhotoSession) -> None:
        for sub in cls.SUBFOLDERS:
            (session.directory / sub).mkdir(parents=True, exist_ok=True)
        for folder in (
            session.for_editing_raw_folder,
            session.for_editing_jpg_folder,
            session.archived_raw_folder,
            session.archived_jpg_folder,
        ):
            folder.mkdir(parents=True, exist_ok=True)

    @classmethod
    def load_sessions(cls, root_dir: Path) -> list[PhotoSession]:
        if not root_dir.exists():
            return []
        sessions: list[PhotoSession] = []
        for entry in root_dir.iterdir():
            if entry.is_dir() and (entry / "RAW").exists():
                session = PhotoSession(
                    name=entry.name,
                    directory=entry,
                    created_at=entry.stat().st_mtime,
                )
                session.counts = cls.read_disk_counts(session)
                sessions.append(session)
        return sorted(sessions, key=lambda s: s.created_at, reverse=True)

    @classmethod
    def read_disk_counts(cls, session: PhotoSession) -> SessionDiskCounts:
        return SessionDiskCounts(
            pending=cls._count_images(session.raw_folder),
            for_editing=cls._count_bucket(session.for_editing_raw_folder, session.for_editing_jpg_folder, session.for_editing_folder),
            archived=cls._count_bucket(session.archived_raw_folder, session.archived_jpg_folder, session.archived_folder),
            companion_jpgs=cls._count_images(session.jpg_folder),
        )

    @classmethod
    def load_archived_items(cls, session: PhotoSession, tag_map: dict | None = None) -> list[PhotoItem]:
        primary = cls.load_photo_items(session.archived_raw_folder, session.archived_jpg_folder, tag_map, session.jpg_folder)
        legacy = cls.load_photo_items(session.archived_folder, session.archived_jpg_folder, tag_map, session.jpg_folder)
        raw_bases = {i.base_filename for i in primary + legacy}
        standalone = [
            i for i in cls.load_photo_items(session.archived_jpg_folder, session.archived_jpg_folder, tag_map)
            if i.base_filename not in raw_bases
        ]
        return sorted(primary + legacy + standalone, key=lambda i: (i.captured_at, i.filename))

    @classmethod
    def load_photo_items(
        cls,
        folder: Path,
        jpg_folder: Path,
        tag_map: dict | None = None,
        fallback_jpg_folder: Path | None = None,
    ) -> list[PhotoItem]:
        if not folder.exists():
            return []
        tags = tag_map or {}
        companion_index = cls._index_by_base(fallback_jpg_folder) if fallback_jpg_folder else {}
        companion_index.update(cls._index_by_base(jpg_folder))
        items: list[PhotoItem] = []

        for path in folder.iterdir():
            if path.is_file() and MediaFormatClassifier.is_supported_image(path):
                base = MediaFormatClassifier.base_filename(path)
                stat = path.stat()
                items.append(
                    PhotoItem(
                        id=path.name.lower(),
                        file_path=path,
                        paired_compressed_path=companion_index.get(base),
                        file_size_bytes=stat.st_size,
                        captured_at=stat.st_mtime,
                        vision_tags=tags.get(base),
                    )
                )
        return sorted(items, key=lambda i: (i.captured_at, i.filename))

    @classmethod
    def ingest_captured_file(
        cls,
        staged_path: Path,
        original_filename: str,
        device_alias: str | None,
        allow_jpg_when_no_raw: bool,
        session: PhotoSession,
    ) -> IngestOutcome:
        return route_ingest(
            cls, staged_path, original_filename, device_alias, allow_jpg_when_no_raw, session, IngestOutcome
        )

    @classmethod
    def move_item(cls, item: PhotoItem, dest_folder_name: str, session: PhotoSession) -> MoveRecord:
        cls.ensure_subfolders(session)
        target_dir = session.raw_bucket(dest_folder_name) if item.format_kind == MediaFormatKind.RAW else session.jpg_bucket(dest_folder_name)
        target_path = cls._unique_file(target_dir, item.file_path.name)
        old_path = item.file_path
        shutil.move(str(old_path), str(target_path))
        PhotoTagStore.relocate_sidecar_if_present(old_path, target_path)
        item.file_path = target_path

        orig_comp: Path | None = None
        moved_comp: Path | None = None
        if item.format_kind == MediaFormatKind.RAW:
            comp = cls._resolve_companion(item, session)
            jpg_dest_dir = session.jpg_bucket(dest_folder_name)
            if comp is not None and comp.resolve().parent != jpg_dest_dir.resolve():
                jpg_target = cls._unique_file(jpg_dest_dir, comp.name)
                shutil.move(str(comp), str(jpg_target))
                orig_comp, moved_comp = comp, jpg_target
                item.paired_compressed_path = jpg_target

        return MoveRecord(
            item=item,
            original_path=old_path,
            moved_path=target_path,
            destination_folder_name=dest_folder_name,
            original_companion_path=orig_comp,
            moved_companion_path=moved_comp,
        )

    @classmethod
    def undo_move(cls, record: MoveRecord) -> PhotoItem:
        target = (
            record.original_path
            if not record.original_path.exists()
            else cls._unique_file(record.original_path.parent, record.original_path.name)
        )
        shutil.move(str(record.moved_path), str(target))
        PhotoTagStore.relocate_sidecar_if_present(record.moved_path, target)
        record.item.file_path = target
        if record.moved_companion_path and record.original_companion_path and record.moved_companion_path.exists():
            comp_target = (
                record.original_companion_path
                if not record.original_companion_path.exists()
                else cls._unique_file(record.original_companion_path.parent, record.original_companion_path.name)
            )
            shutil.move(str(record.moved_companion_path), str(comp_target))
            record.item.paired_compressed_path = comp_target
        return record.item

    @classmethod
    def _resolve_companion(cls, item: PhotoItem, session: PhotoSession) -> Path | None:
        if item.paired_compressed_path and item.paired_compressed_path.exists():
            return item.paired_compressed_path
        for fld in (session.jpg_folder, session.archived_jpg_folder, session.for_editing_jpg_folder):
            match = cls._index_by_base(fld).get(item.base_filename)
            if match is not None:
                return match
        return None

    @classmethod
    def _count_bucket(cls, raw_folder: Path, jpg_folder: Path, legacy_root: Path) -> int:
        raw_bases = set(cls._index_by_base(raw_folder).keys())
        legacy_count = cls._count_images(legacy_root)
        standalone_jpgs = sum(1 for k in cls._index_by_base(jpg_folder).keys() if k not in raw_bases)
        return len(raw_bases) + legacy_count + standalone_jpgs

    @staticmethod
    def _count_images(folder: Path) -> int:
        if not folder.exists():
            return 0
        return sum(1 for p in folder.iterdir() if p.is_file() and MediaFormatClassifier.is_supported_image(p))

    @staticmethod
    def _index_by_base(folder: Path) -> dict[str, Path]:
        if not folder.exists():
            return {}
        return {
            MediaFormatClassifier.base_filename(p): p
            for p in folder.iterdir()
            if p.is_file() and MediaFormatClassifier.is_supported_image(p)
        }

    @staticmethod
    def _find_matching(base: str, kind: MediaFormatKind, folder: Path) -> Path | None:
        if not folder.exists():
            return None
        for p in folder.iterdir():
            if (
                p.is_file()
                and MediaFormatClassifier.base_filename(p) == base
                and MediaFormatClassifier.classify(p.name) == kind
            ):
                return p
        return None

    @staticmethod
    def _unique_dir(parent: Path, name: str) -> Path:
        candidate = parent / name
        idx = 2
        while candidate.exists():
            candidate = parent / f"{name}_{idx}"
            idx += 1
        return candidate

    @staticmethod
    def _unique_file(folder: Path, filename: str) -> Path:
        stem, suffix = Path(filename).stem, Path(filename).suffix
        candidate = folder / filename
        idx = 2
        while candidate.exists():
            candidate = folder / f"{stem}_{idx}{suffix}"
            idx += 1
        return candidate
