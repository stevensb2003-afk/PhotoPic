"""Session directory operations, smart RAW+JPG pairing, disk moves, and Undo for Windows."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re
import shutil

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

        stat = session_dir.stat()
        return PhotoSession(name=session_dir.name, directory=session_dir, created_at=stat.st_mtime)

    @classmethod
    def ensure_subfolders(cls, session: PhotoSession) -> None:
        for sub in cls.SUBFOLDERS:
            (session.directory / sub).mkdir(parents=True, exist_ok=True)

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
            for_editing=cls._count_images(session.for_editing_folder),
            archived=cls._count_images(session.archived_folder),
            companion_jpgs=cls._count_images(session.jpg_folder),
        )

    @classmethod
    def load_photo_items(cls, folder: Path, jpg_folder: Path, tag_map: dict | None = None) -> list[PhotoItem]:
        if not folder.exists():
            return []
        tags = tag_map or {}
        companion_index = cls._index_by_base(jpg_folder)
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
        cls.ensure_subfolders(session)
        kind = MediaFormatClassifier.classify(original_filename)
        if kind is None:
            return IngestOutcome(kind="ignored")

        base = Path(original_filename).stem.lower()
        if kind == MediaFormatKind.RAW:
            dest = cls._unique_file(session.raw_folder, original_filename)
            shutil.move(str(staged_path), str(dest))

            demoted_name: str | None = None
            existing_comp = cls._find_matching(base, MediaFormatKind.COMPRESSED, session.raw_folder)
            if existing_comp is not None:
                jpg_dest = cls._unique_file(session.jpg_folder, existing_comp.name)
                shutil.move(str(existing_comp), str(jpg_dest))
                demoted_name = existing_comp.name

            companion = cls._find_matching(base, MediaFormatKind.COMPRESSED, session.jpg_folder)
            stat = dest.stat()
            item = PhotoItem(
                id=dest.name.lower(),
                file_path=dest,
                paired_compressed_path=companion,
                file_size_bytes=stat.st_size,
                captured_at=stat.st_mtime,
                source_device_alias=device_alias,
            )
            return IngestOutcome(
                kind="added_raw",
                item=item,
                demoted_compressed_name=demoted_name,
                destination_path=dest,
            )

        has_raw = any(
            cls._find_matching(base, MediaFormatKind.RAW, fld) is not None
            for fld in (session.raw_folder, session.for_editing_folder, session.archived_folder)
        )
        if has_raw or not allow_jpg_when_no_raw:
            dest = cls._unique_file(session.jpg_folder, original_filename)
            shutil.move(str(staged_path), str(dest))
            return IngestOutcome(kind="separated_jpg", destination_path=dest)

        dest = cls._unique_file(session.raw_folder, original_filename)
        shutil.move(str(staged_path), str(dest))
        stat = dest.stat()
        item = PhotoItem(
            id=dest.name.lower(),
            file_path=dest,
            file_size_bytes=stat.st_size,
            captured_at=stat.st_mtime,
            source_device_alias=device_alias,
        )
        return IngestOutcome(kind="added_fallback", item=item, destination_path=dest)

    @classmethod
    def move_item(cls, item: PhotoItem, dest_folder_name: str, session: PhotoSession) -> MoveRecord:
        cls.ensure_subfolders(session)
        target_dir = session.directory / dest_folder_name
        target_path = cls._unique_file(target_dir, item.file_path.name)
        old_path = item.file_path
        shutil.move(str(old_path), str(target_path))
        PhotoTagStore.relocate_sidecar_if_present(old_path, target_path)
        item.file_path = target_path
        return MoveRecord(
            item=item,
            original_path=old_path,
            moved_path=target_path,
            destination_folder_name=dest_folder_name,
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
        return record.item

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
