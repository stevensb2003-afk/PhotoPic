"""Unit tests covering Master Groups, project tags, shooting timer, EXIF formatting, and safe session deletion."""

from pathlib import Path
import tempfile
import time
import unittest

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from photopic_win.hardware_auditor import HardwareCapabilityAuditor, WindowsConfigStore
from photopic_win.models import PhotoExifMetadata, PhotoSession
from photopic_win.session_manager import SessionFileManager
from photopic_win.session_metadata import (
    SessionMetadata,
    SessionMetadataStore,
    create_master_group,
    load_master_groups,
)


class TestGroupsTimerAndProjectDelete(unittest.TestCase):
    def test_retrocompatible_flat_and_grouped_sessions(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            flat = SessionFileManager.create_session("Sesion_Plana_Antigua", root)
            grouped = SessionFileManager.create_session(
                "Nimrod_Y_Katherine",
                root,
                group_name="Sesiones Navidenas 2026",
                initial_tags=["Navidad", "Familia"],
            )

            groups = load_master_groups(root)
            self.assertEqual(groups, ["Sesiones Navidenas 2026"])

            loaded = SessionFileManager.load_sessions(root)
            by_name = {s.name: s for s in loaded}
            self.assertIn("Sesion_Plana_Antigua", by_name)
            self.assertIn("Nimrod_Y_Katherine", by_name)
            self.assertIsNone(by_name["Sesion_Plana_Antigua"].group_name)
            self.assertEqual(by_name["Nimrod_Y_Katherine"].group_name, "Sesiones Navidenas 2026")
            self.assertEqual(by_name["Nimrod_Y_Katherine"].tags, ["Navidad", "Familia"])

            moved = SessionFileManager.move_session_to_group(flat, "Sesiones Navidenas 2026", root)
            self.assertEqual(moved.group_name, "Sesiones Navidenas 2026")
            self.assertTrue((moved.directory / "RAW").is_dir())

            # Remove from group back to root
            un_grouped = SessionFileManager.move_session_to_group(grouped, None, root)
            self.assertIsNone(un_grouped.group_name)

    def test_session_timer_first_shot_anchor_and_manual_controls(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            session = SessionFileManager.create_session("Timer_Win", root)
            meta = SessionMetadataStore.load(session.directory)
            self.assertTrue(meta.has_never_started_timer)
            self.assertEqual(meta.formatted_duration(), "00:00:00")

            now = time.time()
            first_shot = now - 75.0
            meta.auto_start_from_first_shot(captured_at=first_shot, now=now)
            self.assertTrue(meta.is_timer_running)
            self.assertGreaterEqual(meta.elapsed_seconds(now=now), 74.9)

            meta.stop_and_finish(now=now + 10.0)
            self.assertFalse(meta.is_timer_running)
            self.assertTrue(meta.is_timer_finished)
            SessionMetadataStore.save(meta, session.directory)

            reloaded = SessionMetadataStore.load(session.directory)
            self.assertGreaterEqual(reloaded.accumulated_seconds, 84.9)
            self.assertTrue(reloaded.is_timer_finished)

            # Future or ancient >12h clock-skew camera timestamps clamp safely to host `now`
            skewed = SessionMetadata()
            skewed.auto_start_from_first_shot(captured_at=now - (48 * 3600), now=now)
            self.assertEqual(skewed.timer_started_at_epoch, now)

    def test_legacy_config_defaults_and_exif_helpers(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            cfg = Path(tmp) / "legacy.json"
            cfg.write_text('{"root_folder":"","performance":{"tier":"balancedAI"}}', encoding="utf-8")
            audit = HardwareCapabilityAuditor.audit_host()
            _, prefs = WindowsConfigStore(config_path=cfg).load(audit)
            self.assertTrue(prefs.auto_start_session_timer)

        exif = PhotoExifMetadata(iso=800, aperture=2.8, shutter_seconds=1 / 250, focal_length_mm=85, pixel_width=6000, pixel_height=4000)
        self.assertEqual(exif.formatted_iso, "ISO 800")
        self.assertEqual(exif.formatted_aperture, "f/2.8")
        self.assertEqual(exif.formatted_shutter, "1/250s")
        self.assertEqual(exif.formatted_focal, "85mm")
        self.assertEqual(exif.formatted_dimensions, "6000×4000 (24.0 MP)")

    def test_permanent_project_delete_and_safety_guards(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "Root"
            outside = Path(tmp) / "Outside"
            root.mkdir()
            (outside / "RAW").mkdir(parents=True)

            # Safety guard 1: refuse deleting root itself
            with self.assertRaises(ValueError):
                SessionFileManager.permanently_delete_session(PhotoSession("Root", root), root)

            # Safety guard 2: refuse deleting outside root
            with self.assertRaises(ValueError):
                SessionFileManager.permanently_delete_session(PhotoSession("Out", outside), root)

            # Safety guard 3: refuse deleting Master Group container directly (lacks RAW/)
            grp = create_master_group("Navidad_2026", root)
            with self.assertRaises(ValueError):
                SessionFileManager.permanently_delete_session(PhotoSession(grp, root / grp), root)

            # Valid session delete wipes entire session directory
            sess = SessionFileManager.create_session("Proyecto_Borrar", root, group_name=grp)
            (sess.raw_folder / "IMG_1.DNG").write_bytes(b"raw")
            SessionFileManager.permanently_delete_session(sess, root)
            self.assertFalse(sess.directory.exists())


if __name__ == "__main__":
    unittest.main()
