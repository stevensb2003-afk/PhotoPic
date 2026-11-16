"""Smart RAW + JPG pairing and late-arrival routing helper for Windows."""

from __future__ import annotations

from pathlib import Path
import shutil

from .models import MediaFormatClassifier, MediaFormatKind, PhotoItem, PhotoSession


def route_ingest(
    manager_cls,
    staged_path: Path,
    original_filename: str,
    device_alias: str | None,
    allow_jpg_when_no_raw: bool,
    session: PhotoSession,
    outcome_cls,
):
    manager_cls.ensure_subfolders(session)
    kind = MediaFormatClassifier.classify(original_filename)
    if kind is None:
        return outcome_cls(kind="ignored")

    base = Path(original_filename).stem.lower()
    if kind == MediaFormatKind.RAW:
        dest = manager_cls._unique_file(session.raw_folder, original_filename)
        shutil.move(str(staged_path), str(dest))

        demoted_name: str | None = None
        existing_comp = manager_cls._find_matching(base, MediaFormatKind.COMPRESSED, session.raw_folder)
        if existing_comp is not None:
            jpg_dest = manager_cls._unique_file(session.jpg_folder, existing_comp.name)
            shutil.move(str(existing_comp), str(jpg_dest))
            demoted_name = existing_comp.name

        companion = manager_cls._find_matching(base, MediaFormatKind.COMPRESSED, session.jpg_folder)
        stat = dest.stat()
        item = PhotoItem(
            id=dest.name.lower(),
            file_path=dest,
            paired_compressed_path=companion,
            file_size_bytes=stat.st_size,
            captured_at=stat.st_mtime,
            source_device_alias=device_alias,
        )
        return outcome_cls(
            kind="added_raw",
            item=item,
            demoted_compressed_name=demoted_name,
            destination_path=dest,
        )

    in_edit_raw = (
        manager_cls._find_matching(base, MediaFormatKind.RAW, session.for_editing_raw_folder) is not None
        or manager_cls._find_matching(base, MediaFormatKind.RAW, session.for_editing_folder) is not None
    )
    in_arch_raw = (
        manager_cls._find_matching(base, MediaFormatKind.RAW, session.archived_raw_folder) is not None
        or manager_cls._find_matching(base, MediaFormatKind.RAW, session.archived_folder) is not None
    )
    in_pending_raw = manager_cls._find_matching(base, MediaFormatKind.RAW, session.raw_folder) is not None
    if in_edit_raw or in_arch_raw or in_pending_raw or not allow_jpg_when_no_raw:
        target_jpg_dir = (
            session.for_editing_jpg_folder if in_edit_raw
            else (session.archived_jpg_folder if in_arch_raw else session.jpg_folder)
        )
        dest = manager_cls._unique_file(target_jpg_dir, original_filename)
        shutil.move(str(staged_path), str(dest))
        return outcome_cls(kind="separated_jpg", destination_path=dest)

    dest = manager_cls._unique_file(session.raw_folder, original_filename)
    shutil.move(str(staged_path), str(dest))
    stat = dest.stat()
    item = PhotoItem(
        id=dest.name.lower(),
        file_path=dest,
        file_size_bytes=stat.st_size,
        captured_at=stat.st_mtime,
        source_device_alias=device_alias,
    )
    return outcome_cls(kind="added_fallback", item=item, destination_path=dest)
