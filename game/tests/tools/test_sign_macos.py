"""签名、公证流程的顺序与失败边界；不需要 Apple 凭据，不访问 Apple 服务。"""

import contextlib
import io
import json
import plistlib
import shutil
import struct
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import sign_macos


class SignMacTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.package = self.root / "dark-forest-macos-apple-silicon.zip"
        self.output = self.root / "signed output"
        self.identity = "Developer ID Application: Example (TESTTEAM)"
        self.commands = []
        self.status = "Accepted"
        self.fail = None
        self.enterContext(patch.object(sign_macos.sys, "platform", "darwin"))
        self.enterContext(patch.object(sign_macos, "run", side_effect=self.run_command))
        self.enterContext(contextlib.redirect_stdout(io.StringIO()))
        with zipfile.ZipFile(self.package, "w") as archive:
            archive.writestr("dark-forest.app/Contents/Info.plist", plistlib.dumps({"CFBundleExecutable": "dark-forest"}))
            binary = zipfile.ZipInfo("dark-forest.app/Contents/MacOS/dark-forest")
            binary.external_attr = 0o100755 << 16
            archive.writestr(binary, struct.pack("<II", 0xFEEDFACF, 0x0100000C))
            archive.writestr("dark-forest.app/Contents/Resources/dark-forest.pck", b"game")
        self.original = self.package.read_bytes()

    def run_command(self, command):
        self.commands.append(command)
        if self.fail and self.fail(command):
            raise RuntimeError("simulated failure")
        if command[0] == "security":
            return f'1) 0123456789 "{self.identity}"'
        if command[:3] == ["ditto", "-x", "-k"]:
            with zipfile.ZipFile(command[3]) as archive:
                archive.extractall(command[4])
        elif command[:3] == ["ditto", "-c", "-k"]:
            shutil.copyfile(self.package, command[-1])
        elif command[:3] == ["xcrun", "notarytool", "submit"]:
            return json.dumps({"id": "test-submission", "status": self.status})
        return ""

    def sign(self):
        return sign_macos.sign(self.package, self.output, self.identity, "notary profile")

    def test_signs_then_notarizes_staples_verifies_and_packages(self):
        result = self.sign()
        self.assertTrue(result.is_file())
        self.assertEqual(self.package.read_bytes(), self.original)
        names = [" ".join(c[:3]) for c in self.commands]
        self.assertLess(names.index("codesign --force --options"), names.index("xcrun notarytool submit"))
        self.assertLess(names.index("xcrun notarytool submit"), names.index("xcrun stapler staple"))
        self.assertLess(names.index("xcrun stapler validate"), names.index("spctl --assess --type"))
        self.assertEqual(self.commands[-1][:4], ["ditto", "-c", "-k", "--keepParent"])
        submit = next(c for c in self.commands if c[:3] == ["xcrun", "notarytool", "submit"])
        self.assertIn("--keychain-profile", submit)
        self.assertNotIn("--password", submit)
        self.assertFalse(list(self.output.glob(".sign-*")))

    def test_rejection_or_timeout_never_produces_release(self):
        for status in ["Invalid", "In Progress", None]:
            with self.subTest(status=status):
                self.status = status
                self.commands.clear()
                with self.assertRaisesRegex(RuntimeError, "Apple"):
                    self.sign()
                self.assertFalse((self.output / self.package.name).exists())
                self.assertFalse(any(c[:2] == ["xcrun", "stapler"] for c in self.commands))
                self.assertEqual(self.package.read_bytes(), self.original)

    def test_each_signing_or_verification_failure_stops_publication(self):
        for prefix in [["codesign", "--force"], ["codesign", "--verify"],
                       ["xcrun", "notarytool", "submit"], ["xcrun", "stapler", "staple"],
                       ["xcrun", "stapler", "validate"], ["spctl"]]:
            with self.subTest(prefix=prefix):
                self.fail = lambda command: command[:len(prefix)] == prefix
                with self.assertRaises(RuntimeError):
                    self.sign()
                self.assertFalse((self.output / self.package.name).exists())
                self.assertEqual(self.package.read_bytes(), self.original)

    def test_preserves_existing_output_and_refuses_in_place_signing(self):
        self.output.mkdir()
        old = self.output / self.package.name
        old.write_bytes(b"previous signed release")
        for output in [self.output, self.package.parent]:
            with self.assertRaisesRegex(RuntimeError, "覆盖"):
                sign_macos.sign(self.package, output, self.identity, "profile")
        self.assertEqual(old.read_bytes(), b"previous signed release")
        self.assertFalse(self.commands)

    def test_missing_certificate_stops_before_upload(self):
        with self.assertRaisesRegex(RuntimeError, "钥匙串"):
            sign_macos.sign(self.package, self.output, self.identity + " other", "profile")
        self.assertEqual(len(self.commands), 1)

    def test_rejects_unsafe_archive_before_extraction(self):
        with zipfile.ZipFile(self.package, "a") as archive:
            archive.writestr("../outside", "invalid")
        with self.assertRaisesRegex(RuntimeError, "ZIP"):
            self.sign()
        self.assertFalse(self.commands)


if __name__ == "__main__":
    unittest.main()
