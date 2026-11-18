"""Tests for Windows folder importer, group/session rename, RAW-named session guard, and persistent Shift rotation."""

from __future__ import annotations

from pathlib import Path
import struct
import tempfile
import unittest

from windows.photopic_win.folder_importer import FolderImportTransferMode, SessionFolderImporter
from windows.photopic_win.models import PhotoItem
from windows.photopic_win.photo_orientation import PhotoOrientationService
from windows.photopic_win.session_manager import SessionFileManager
from windows.photopic_win.session_metadata import (
    create_master_group,
    load_master_groups,
    suggested_imported_session_name,
)


def _write_minimal_tiff_dng(path: Path, orientation: int = 1) -> None:
    """Writes a minimal valid little-endian TIFF/DNG header containing IFD0 tag 0x0112 (Orientation)."""
    header = b"II" + struct.pack("<HI", 42, 8)
    entry_count = struct.pack("<H", 1)
    orient_entry = struct.pack("<HHIHH", 0x0112, 3, 1, orientation, 0)
    next_ifd = struct.pack("<I", 0)
    path.write_bytes(header + entry_count + orient_entry + next_ifd)


class TestWindowsImportRenameAndRotation(unittest.TestCase):
    def test_folder_importer_two_pass_segregation_collisions_and_xmp(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "PhotoPicRoot"
            root.mkdir()
            ext = Path(tmp) / "ExternalShoot"
            for sub in ("SubA", "SubB", "SplitRAW", "SplitJPG", "Mobile"):
                (ext / sub).mkdir(parents=True)

            _write_minimal_tiff_dng(ext / "SubA" / "IMG_101.DNG")
            (ext / "SubA" / "IMG_101.JPG").write_bytes(b"jpg-a")
            (ext / "SubA" / "IMG_101.xmp").write_text("<x:xmpmeta/>", encoding="utf-8")

            _write_minimal_tiff_dng(ext / "SubB" / "IMG_101.DNG")
            (ext / "SubB" / "IMG_101.JPG").write_bytes(b"jpg-b")

            _write_minimal_tiff_dng(ext / "SplitRAW" / "IMG_202.DNG")
            (ext / "SplitJPG" / "IMG_202.JPG").write_bytes(b"jpg-202")

            (ext / "Mobile" / "SOLO_303.JPG").write_bytes(b"solo-jpg")

            top_only = SessionFolderImporter.scan_folder(ext, include_subfolders=False)
            self.assertEqual(top_only.total_photo_units_count, 0)

            summary = SessionFolderImporter.scan_folder(ext, include_subfolders=True)
            self.assertEqual(summary.raw_units_count, 3)
            self.assertEqual(summary.paired_jpg_count, 3)
            self.assertEqual(summary.standalone_compressed_count, 1)
            self.assertEqual(summary.total_photo_units_count, 4)

            result = SessionFolderImporter.import_as_new_session(
                summary=summary,
                session_name="Imported_Boda",
                root_dir=root,
                group_name="Bodas_2026",
                initial_tags=["Offline", "RAW"],
                transfer_mode=FolderImportTransferMode.COPY,
            )
            self.assertEqual(result.imported_units_count, 4)
            self.assertTrue((ext / "SubA" / "IMG_101.DNG").exists())
            self.assertTrue((result.session.raw_folder / "IMG_101.xmp").exists())
            self.assertTrue((result.session.raw_folder / "IMG_101_2.DNG").exists())
            self.assertTrue((result.session.jpg_folder / "IMG_101_2.JPG").exists())

            # Audit Bug #1 parity: standalone compressed item returned from Para_Edicion -> RAW stays visible
            pending = SessionFileManager.load_photo_items(result.session.raw_folder, result.session.jpg_folder)
            solo = next(i for i in pending if i.filename == "SOLO_303.JPG")
            rec = SessionFileManager.move_item(solo, "Para_Edicion", result.session)
            editing = SessionFileManager.load_for_editing_items(result.session)
            self.assertTrue(any(i.filename == "SOLO_303.JPG" for i in editing))
            SessionFileManager.move_item(rec.item, "RAW", result.session)
            pending_after = SessionFileManager.load_photo_items(result.session.raw_folder, result.session.jpg_folder)
            self.assertTrue(any(i.filename == "SOLO_303.JPG" for i in pending_after))

            # Move mode check
            move_src = Path(tmp) / "MoveShoot"
            move_src.mkdir()
            _write_minimal_tiff_dng(move_src / "MOVE_01.DNG")
            move_summary = SessionFolderImporter.scan_folder(move_src, include_subfolders=True)
            move_res = SessionFolderImporter.import_as_new_session(
                summary=move_summary,
                session_name="Moved_Shoot",
                root_dir=root,
                transfer_mode=FolderImportTransferMode.MOVE,
            )
            self.assertFalse((move_src / "MOVE_01.DNG").exists())
            self.assertTrue((move_res.session.raw_folder / "MOVE_01.DNG").exists())

    def test_raw_named_session_inside_group_and_disk_rename(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "PhotoPic"
            root.mkdir()
            group = create_master_group("2026 Sesiones Navideñas", root)
            src_raw = Path(tmp) / "Familia_Navidad" / "RAW"
            src_raw.mkdir(parents=True)
            _write_minimal_tiff_dng(src_raw / "NAV_01.DNG")

            self.assertEqual(suggested_imported_session_name(src_raw), "Familia_Navidad")

            summary = SessionFolderImporter.scan_folder(src_raw, include_subfolders=False)
            SessionFolderImporter.import_as_new_session(
                summary=summary,
                session_name="RAW",
                root_dir=root,
                group_name=group,
                transfer_mode=FolderImportTransferMode.COPY,
            )

            groups = load_master_groups(root)
            sessions = SessionFileManager.load_sessions(root)
            self.assertIn(group, groups)
            self.assertFalse(any(s.name == group and s.group_name is None for s in sessions))
            raw_session = next(s for s in sessions if s.name == "RAW" and s.group_name == group)
            self.assertEqual(raw_session.counts.pending, 1)

            renamed_session = SessionFileManager.rename_session(raw_session, "Familia_Navidad", root)
            self.assertEqual(renamed_session.name, "Familia_Navidad")
            self.assertTrue(renamed_session.directory.exists())

            renamed_group = SessionFileManager.rename_group(group, "Navidad_2026", root)
            self.assertEqual(renamed_group, "Navidad_2026")
            reloaded = SessionFileManager.load_sessions(root)
            self.assertTrue(any(s.name == "Familia_Navidad" and s.group_name == "Navidad_2026" for s in reloaded))

    def test_persistent_shift_rotation_on_raw_and_xmp(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            dng = Path(tmp) / "PORTRAIT_01.DNG"
            xmp = Path(tmp) / "PORTRAIT_01.xmp"
            _write_minimal_tiff_dng(dng, orientation=1)
            xmp.write_text(
                '<rdf:Description xmlns:dc="http://purl.org/dc/elements/1.1/">\n    </rdf:Description>',
                encoding="utf-8",
            )
            item = PhotoItem(id="portrait_01.dng", file_path=dng)

            self.assertEqual(PhotoOrientationService.read_orientation(dng), 1)
            self.assertEqual(PhotoOrientationService.rotate_clockwise_90(item), 6)
            self.assertEqual(PhotoOrientationService.read_orientation(dng), 6)
            self.assertIn("<tiff:Orientation>6</tiff:Orientation>", xmp.read_text(encoding="utf-8"))

            self.assertEqual(PhotoOrientationService.rotate_clockwise_90(item), 3)
            self.assertEqual(PhotoOrientationService.rotate_clockwise_90(item), 8)
            self.assertEqual(PhotoOrientationService.rotate_clockwise_90(item), 1)
            self.assertEqual(PhotoOrientationService.read_orientation(dng), 1)


if __name__ == "__main__":
    unittest.main()
