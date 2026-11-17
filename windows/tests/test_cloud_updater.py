"""Unit tests for Windows Cloud OTA updater SHA-256 verification and staging."""

import hashlib
from pathlib import Path
import tempfile
import unittest
import zipfile

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from photopic_win.cloud_updater import load_local_build_identity, stage_windows_archive, verify_sha256_file
from photopic_win.hardware_auditor import HardwareCapabilityAuditor, WindowsConfigStore


class TestWindowsCloudUpdater(unittest.TestCase):
    def test_stage_windows_archive_validates_sha256_and_extracts(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            exe_dummy = root / "PhotoPic.exe"
            exe_dummy.write_bytes(b"MZ-DUMMY-EXE")

            zip_path = root / "PhotoPic-Windows-x64.zip"
            with zipfile.ZipFile(zip_path, "w") as zf:
                zf.write(exe_dummy, arcname="PhotoPic.exe")

            sha = hashlib.sha256(zip_path.read_bytes()).hexdigest()
            self.assertTrue(verify_sha256_file(zip_path, sha))
            self.assertFalse(verify_sha256_file(zip_path, "0" * 64))

            staged = stage_windows_archive(zip_path, sha, build_number=777)
            self.assertTrue((staged / "PhotoPic.exe").exists())

            with self.assertRaises(ValueError):
                stage_windows_archive(zip_path, "f" * 64, build_number=778)

    def test_identity_fallback_and_legacy_auto_check_default(self) -> None:
        ident = load_local_build_identity()
        self.assertTrue(ident.version.startswith("2."))
        with tempfile.TemporaryDirectory() as tmp:
            cfg = Path(tmp) / "cfg.json"
            cfg.write_text('{"root_folder":"","performance":{"tier":"balancedAI"}}', encoding="utf-8")
            _, prefs = WindowsConfigStore(config_path=cfg).load(HardwareCapabilityAuditor.audit_host())
            self.assertTrue(prefs.auto_check_updates)


if __name__ == "__main__":
    unittest.main()
