"""Unit tests verifying core Windows PhotoPic modules using Python stdlib only."""

from pathlib import Path
import tempfile
import time
import unittest

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from photopic_win.archive_cleaner import SessionArchiveCleaner
from photopic_win.baseline_gate import TetherBaselineGate
from photopic_win.hardware_auditor import (
    HardwareCapabilityAuditor,
    PerformancePreferences,
    PerformanceTier,
    WindowsConfigStore,
)
from photopic_win.models import MediaFormatClassifier, MediaFormatKind, PhotoVisionTags
from photopic_win.session_manager import SessionFileManager
from photopic_win.tag_store import PhotoTagStore


class TestWindowsCorePipeline(unittest.TestCase):
    def test_expanded_format_classifier(self) -> None:
        for ext in ("cr2", "cr3", "dng", "arw", "nef", "nrw", "raf", "orf", "rw2", "3fr", "iiq"):
            self.assertEqual(MediaFormatClassifier.classify(f"shot.{ext}"), MediaFormatKind.RAW)
        for ext in ("jpg", "jpeg", "heic", "heif", "hif", "avif", "jxl", "webp", "png", "tiff"):
            self.assertEqual(MediaFormatClassifier.classify(f"shot.{ext}"), MediaFormatKind.COMPRESSED)

    def test_anti_old_gallery_shield(self) -> None:
        now = time.time()
        gate = TetherBaselineGate(connected_at_epoch=now)

        for idx in range(1, 201):
            key = gate.item_key(str(idx), f"OLD_{idx}.DNG", 30_000_000)
            old_ts = now - idx * 60
            gate.record_pre_catalog_item(key, old_ts)
            self.assertFalse(gate.should_download_live_item(key, old_ts, was_added_after_catalog=False))

        gate.mark_catalog_complete()

        for idx in range(1, 201):
            key = gate.item_key(str(idx), f"OLD_{idx}.DNG", 30_000_000)
            self.assertFalse(gate.should_download_live_item(key, now - idx * 60, was_added_after_catalog=False))

        new_key = gate.item_key("999", "NEW_001.DNG", 32_000_000)
        self.assertTrue(gate.should_download_live_item(new_key, now + 0.5, was_added_after_catalog=True))
        self.assertFalse(gate.should_download_live_item(new_key, now + 0.5, was_added_after_catalog=False))

    def test_session_ingest_moves_undo_and_xmp_sync(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            session = SessionFileManager.create_session("Boda_Windows_Test", root)
            for sub in ("RAW", "JPG", "Para_Edicion", "Archivadas"):
                self.assertTrue((session.directory / sub).is_dir())

            stage = root / "stage"
            stage.mkdir()
            jpg_mob = stage / "MBL_001.JPG"
            dng_mob = stage / "MBL_001.DNG"
            jpg_mob.write_bytes(b"jpg-bytes")
            dng_mob.write_bytes(b"dng-bytes")

            res_jpg = SessionFileManager.ingest_captured_file(jpg_mob, "MBL_001.JPG", "Pixel", True, session)
            self.assertEqual(res_jpg.kind, "added_fallback")

            res_dng = SessionFileManager.ingest_captured_file(dng_mob, "MBL_001.DNG", "Pixel", True, session)
            self.assertEqual(res_dng.kind, "added_raw")
            self.assertEqual(res_dng.demoted_compressed_name, "MBL_001.JPG")
            self.assertTrue((session.jpg_folder / "MBL_001.JPG").exists())
            self.assertTrue((session.raw_folder / "MBL_001.DNG").exists())

            tags = PhotoVisionTags(person_count=2, face_count=2, auto_tags=["2 personas", "Pareja", "Ojos abiertos"])
            PhotoTagStore.save(tags, res_dng.item, session, write_xmp=True)
            xmp_raw = PhotoTagStore.xmp_sidecar_path(res_dng.item.file_path)
            self.assertTrue(xmp_raw.exists())

            rec = SessionFileManager.move_item(res_dng.item, "Para_Edicion", session)
            self.assertFalse(xmp_raw.exists())
            self.assertTrue(PhotoTagStore.xmp_sidecar_path(rec.moved_path).exists())

            restored = SessionFileManager.undo_move(rec)
            self.assertTrue(PhotoTagStore.xmp_sidecar_path(restored.file_path).exists())
            loaded_tags = PhotoTagStore.load_all(session)
            self.assertIn("Pareja", loaded_tags["mbl_001"].all_tags)

    def test_hardware_auditor_and_config_store(self) -> None:
        audit = HardwareCapabilityAuditor.audit_host()
        self.assertGreaterEqual(audit.ram_gb, 1)
        self.assertGreaterEqual(audit.cpu_cores, 1)

        low_tier, _ = HardwareCapabilityAuditor.evaluate_tier(cores=2, ram_gb=4, has_mediapipe=False, has_opencv=False)
        self.assertEqual(low_tier, PerformanceTier.LIGHTWEIGHT_NO_AI)

        mid_tier, _ = HardwareCapabilityAuditor.evaluate_tier(cores=4, ram_gb=8, has_mediapipe=True, has_opencv=True)
        self.assertEqual(mid_tier, PerformanceTier.BALANCED_AI)

        high_tier, _ = HardwareCapabilityAuditor.evaluate_tier(cores=8, ram_gb=16, has_mediapipe=True, has_opencv=True)
        self.assertEqual(high_tier, PerformanceTier.FULL_AI)

        with tempfile.TemporaryDirectory() as tmp:
            cfg = Path(tmp) / "cfg.json"
            root = Path(tmp) / "Root"
            root.mkdir()
            store = WindowsConfigStore(config_path=cfg)
            prefs = PerformancePreferences.preset(PerformanceTier.LIGHTWEIGHT_NO_AI, completed=True)
            store.save(root, prefs)
            loaded_root, loaded_prefs = store.load(audit)
            self.assertEqual(loaded_root, root)
            self.assertFalse(loaded_prefs.enable_vision_autotagging)
            self.assertTrue(loaded_prefs.has_completed_guided_setup)

    def test_permanent_archive_delete_and_safety_guard(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            session = SessionFileManager.create_session("Delete_Win_Test", root)
            stage = root / "stage"
            stage.mkdir()

            items = []
            for idx in (1, 2, 3):
                raw_p = stage / f"WIN_{idx}.DNG"
                jpg_p = stage / f"WIN_{idx}.JPG"
                raw_p.write_bytes(b"raw")
                jpg_p.write_bytes(b"jpg")
                res_r = SessionFileManager.ingest_captured_file(raw_p, raw_p.name, "Cam", False, session)
                SessionFileManager.ingest_captured_file(jpg_p, jpg_p.name, "Cam", False, session)
                items.append(res_r.item)

            # Move 1 -> Para_Edicion, 2 & 3 -> Archivadas
            SessionFileManager.move_item(items[0], "Para_Edicion", session)
            SessionFileManager.move_item(items[1], "Archivadas", session)
            SessionFileManager.move_item(items[2], "Archivadas", session)

            # Reload from disk (links companion JPGs created after RAW)
            arch_items = SessionFileManager.load_photo_items(session.archived_folder, session.jpg_folder)
            self.assertEqual(len(arch_items), 2)

            # Safety guard: refusing deletion outside Archivadas/
            with self.assertRaises(ValueError):
                SessionArchiveCleaner.permanently_delete_archived_item(items[0], session)

            PhotoTagStore.save(PhotoVisionTags(1, 1, auto_tags=["1 persona"]), arch_items[0], session, write_xmp=True)
            xmp1 = PhotoTagStore.xmp_sidecar_path(arch_items[0].file_path)
            self.assertTrue(xmp1.exists())

            SessionArchiveCleaner.permanently_delete_archived_item(arch_items[0], session, delete_companion_jpg=False)
            self.assertFalse(arch_items[0].file_path.exists())
            self.assertFalse(xmp1.exists())
            self.assertIsNotNone(arch_items[0].paired_compressed_path)
            self.assertTrue(arch_items[0].paired_compressed_path.exists())
            self.assertNotIn(arch_items[0].base_filename, PhotoTagStore.load_all(session))

            removed = SessionArchiveCleaner.permanently_delete_all_archived(session, delete_companion_jpgs=True)
            self.assertEqual(removed, 1)
            self.assertFalse(arch_items[1].file_path.exists())
            self.assertIsNotNone(arch_items[1].paired_compressed_path)
            self.assertFalse(arch_items[1].paired_compressed_path.exists())
            counts = SessionFileManager.read_disk_counts(session)
            self.assertEqual(counts.for_editing, 1)
            self.assertEqual(counts.archived, 0)


if __name__ == "__main__":
    unittest.main()
