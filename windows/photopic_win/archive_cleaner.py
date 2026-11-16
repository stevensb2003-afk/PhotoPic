"""Permanent deletion cleaner restricted strictly to a session's Archivadas/ directory."""

from __future__ import annotations

from pathlib import Path

from .models import PhotoItem, PhotoSession
from .session_manager import SessionFileManager
from .tag_store import PhotoTagStore


class SessionArchiveCleaner:
    """Safely deletes rejected photos in `Archivadas/`, `.xmp` sidecars, and optional JPG pairs."""

    @staticmethod
    def permanently_delete_archived_item(
        item: PhotoItem,
        session: PhotoSession,
        delete_companion_jpg: bool = False,
    ) -> None:
        archived_dir = session.archived_folder.resolve()
        item_parent = item.file_path.resolve().parent
        if item_parent != archived_dir:
            raise ValueError("Operación bloqueada: el archivo no pertenece a Archivadas/ de esta sesión.")

        if item.file_path.exists():
            item.file_path.unlink()

        PhotoTagStore.remove_tags_and_sidecar(item, session)

        if delete_companion_jpg and item.paired_compressed_path is not None:
            SessionArchiveCleaner._delete_companion_jpg(item.paired_compressed_path, session)

    @classmethod
    def permanently_delete_all_archived(
        cls,
        session: PhotoSession,
        delete_companion_jpgs: bool = False,
    ) -> int:
        items = SessionFileManager.load_photo_items(session.archived_folder, session.jpg_folder)
        if not items:
            return 0

        bases: set[str] = set()
        paths: list[Path] = []
        for item in items:
            if item.file_path.exists():
                item.file_path.unlink()
            bases.add(item.base_filename)
            paths.append(item.file_path)
            if delete_companion_jpgs and item.paired_compressed_path is not None:
                cls._delete_companion_jpg(item.paired_compressed_path, session)

        PhotoTagStore.remove_tags_and_sidecars(bases, paths, session)
        return len(items)

    @staticmethod
    def _delete_companion_jpg(companion_path: Path, session: PhotoSession) -> None:
        if companion_path.resolve().parent == session.jpg_folder.resolve() and companion_path.exists():
            companion_path.unlink()
