"""导出流程的失败处理和打包检查；完整 test.py 会一起运行。"""

import contextlib
import io
import os
import plistlib
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
import export as exporter
import godot
import make_macos_templates


class ExportTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.output = Path(self.temp.name) / "带空格的 output"
        self.fonts = SimpleNamespace(main=Mock())
        self.commands = []
        self.enterContext(patch.dict(sys.modules, {"make_web_fonts": self.fonts}))
        self.enterContext(patch.object(exporter.sync_balance, "sync", return_value=False))
        self.prepare_templates = self.enterContext(patch.object(exporter, "prepare_macos_templates"))
        self.enterContext(contextlib.redirect_stdout(io.StringIO()))

    def build(self, command: list[str], label: str) -> None:
        self.commands.append(command)
        if "--export-release" in command:
            destination = Path(command[-1])
            if command[-2].startswith("macOS"):
                cpu = 0x01000007 if command[-2] == "macOS (Intel)" else 0x0100000C
                self.mac_zip(destination, cpu=cpu)
            else:
                destination.write_bytes(b"new game")
            if command[-2] == "Web":
                for suffix in (".js", ".wasm", ".pck"):
                    destination.with_suffix(suffix).write_bytes(b"web resource")

    def mac_zip(self, destination: Path, permissions: int = 0o100755, resources: bool = True,
                cpu: int = 0x01000007) -> None:
        with zipfile.ZipFile(destination, "w") as zipped:
            zipped.writestr("dark-forest.app/Contents/Info.plist",
                            plistlib.dumps({"CFBundleExecutable": "dark-forest"}))
            executable = zipfile.ZipInfo("dark-forest.app/Contents/MacOS/dark-forest")
            executable.create_system = 3
            executable.external_attr = permissions << 16
            zipped.writestr(executable, struct.pack("<II", 0xFEEDFACF, cpu) + b"mac executable")
            if resources:
                zipped.writestr("dark-forest.app/Contents/Resources/dark-forest.pck", b"game resources")

    def test_all_packages_and_web_entry(self) -> None:
        with patch.object(exporter, "run_step", side_effect=self.build):
            exporter.export(list(exporter.TARGETS), "/path with spaces/godot", self.output)
        self.fonts.main.assert_called_once()
        self.assertIn("--import", self.commands[0])
        self.assertTrue(all(cmd[0] == "/path with spaces/godot" for cmd in self.commands))
        for filename, archive in [("dark-forest.exe", "dark-forest-windows.zip"),
                                  ("dark-forest-dev.exe", "dark-forest-windows-dev.zip")]:
            with zipfile.ZipFile(self.output / archive) as zipped:
                self.assertEqual(zipped.namelist(), [filename])
                self.assertEqual(zipped.read(filename), b"new game")
        self.assertIn('location.replace("../?debug" + extra)',
                      (self.output / "web/dev/index.html").read_text(encoding="utf-8"))
        self.assertFalse(list(self.output.glob(".export-*")))
        for target, cpu in exporter.MAC_ARCHITECTURES.items():
            exporter.check_macos_zip(self.output / exporter.TARGETS[target][1], cpu)

    def test_macos_keeps_godot_zip_without_repacking(self) -> None:
        original = []

        def build(command: list[str], label: str) -> None:
            self.build(command, label)
            if "--export-release" in command:
                original.append(Path(command[-1]).read_bytes())

        with patch.object(exporter, "run_step", side_effect=build):
            exporter.export(["macos-intel"], "godot", self.output)
        self.fonts.main.assert_not_called()
        self.assertEqual((self.output / "dark-forest-macos-intel.zip").read_bytes(), original[0])
        self.assertFalse((self.output / "dev").exists())
        self.assertFalse((self.output / "web").exists())

    def test_macos_rejects_missing_permissions_or_resources(self) -> None:
        for permissions, resources in [(0o100644, True), (0o100755, False)]:
            with self.subTest(permissions=permissions, resources=resources):
                path = Path(self.temp.name) / "bad-macos.zip"
                self.mac_zip(path, permissions, resources)
                with self.assertRaises(RuntimeError):
                    exporter.check_macos_zip(path, 0x01000007)

    def test_macos_rejects_broken_zip_or_missing_application(self) -> None:
        path = Path(self.temp.name) / "bad-macos.zip"
        path.write_bytes(b"broken archive")
        with self.assertRaises(RuntimeError):
            exporter.check_macos_zip(path, 0x01000007)
        with zipfile.ZipFile(path, "w") as zipped:
            zipped.writestr("README.txt", "no application")
        with self.assertRaises(RuntimeError):
            exporter.check_macos_zip(path, 0x01000007)

    def test_macos_rejects_other_chip_architecture(self) -> None:
        path = Path(self.temp.name) / "wrong-chip.zip"
        self.mac_zip(path, cpu=0x0100000C)
        with self.assertRaisesRegex(RuntimeError, "架构"):
            exporter.check_macos_zip(path, 0x01000007)

    def test_macos_cli_exports_both_chip_packages(self) -> None:
        with patch.object(sys, "argv", ["export.py", "macos"]):
            with patch.object(exporter, "find_godot", return_value="godot"):
                with patch.object(exporter, "export") as run:
                    self.assertEqual(exporter.main(), 0)
        self.assertEqual(run.call_args.args[0], ["macos-intel", "macos-apple-silicon"])

    def test_windows_does_not_prepare_fonts(self) -> None:
        with patch.object(exporter, "run_step", side_effect=self.build):
            exporter.export(["windows"], "godot", self.output)
        self.fonts.main.assert_not_called()
        self.prepare_templates.assert_not_called()
        self.assertFalse((self.output / "web").exists())
        self.assertFalse((self.output / "dark-forest-dev.exe").exists())

    def test_missing_export_does_not_accept_or_overwrite_old_file(self) -> None:
        self.output.mkdir()
        old = self.output / "dark-forest.exe"
        old.write_bytes(b"previous game")
        with patch.object(exporter, "run_step"), self.assertRaisesRegex(RuntimeError, "没有生成"):
            exporter.export(["windows"], "godot", self.output)
        self.assertEqual(old.read_bytes(), b"previous game")
        self.assertFalse((self.output / "dark-forest-windows.zip").exists())
        self.assertFalse(list(self.output.glob(".export-*")))

    def test_incomplete_web_aborts_before_publishing_windows(self) -> None:
        def incomplete(command: list[str], label: str) -> None:
            self.build(command, label)
            if command[-2] == "Web":
                Path(command[-1]).with_suffix(".wasm").unlink()

        with patch.object(exporter, "run_step", side_effect=incomplete), self.assertRaisesRegex(RuntimeError, "wasm"):
            exporter.export(list(exporter.TARGETS), "godot", self.output)
        self.assertEqual(list(self.output.iterdir()), [])

    def test_font_failure_stops_before_import(self) -> None:
        self.fonts.main.side_effect = OSError("download failed")
        with patch.object(exporter, "run_step") as run, self.assertRaises(OSError):
            exporter.export(["web"], "godot", self.output)
        run.assert_not_called()

    def test_import_failure_stops_before_export(self) -> None:
        with patch.object(exporter, "run_step", side_effect=RuntimeError("import failed")) as run:
            with self.assertRaises(RuntimeError):
                exporter.export(["windows"], "godot", self.output)
        self.assertEqual(run.call_count, 1)
        self.assertIn("--import", run.call_args.args[0])

    def test_exit_code_and_script_errors_are_failures(self) -> None:
        for code, log in [(1, "failed\n"), (0, "SCRIPT ERROR: broken script\n"), (0, "ERROR: failed export\n")]:
            with self.subTest(code=code, log=log):
                result = subprocess.CompletedProcess([], code, stdout=log)
                with patch.object(exporter.subprocess, "run", return_value=result), self.assertRaises(RuntimeError):
                    exporter.run_step(["godot"], "导出")

    def test_process_uses_argument_list_and_repository_directory(self) -> None:
        command = ["path with spaces/godot", "--path", str(exporter.GAME)]
        result = subprocess.CompletedProcess(command, 0, stdout="done\n")
        with patch.object(exporter.subprocess, "run", return_value=result) as run:
            exporter.run_step(command, "导入")
        self.assertEqual(run.call_args.args[0], command)
        self.assertEqual(run.call_args.kwargs["cwd"], exporter.ROOT)
        self.assertNotIn("shell", run.call_args.kwargs)

    def test_cli_resolves_output_from_callers_directory(self) -> None:
        with patch.object(sys, "argv", ["export.py", "windows-dev", "--godot", "custom", "--out-dir", "relative"]):
            with patch.object(exporter, "find_godot", return_value="/custom/godot") as find:
                with patch.object(exporter, "export") as run:
                    self.assertEqual(exporter.main(), 0)
        find.assert_called_once_with("custom")
        run.assert_called_once_with(["windows-dev"], "/custom/godot", Path("relative").resolve())


class MacTemplateTests(unittest.TestCase):
    def fat(self, wide: bool = False) -> bytes:
        layout = ">IIQQII" if wide else ">IIIII"
        stride = struct.calcsize(layout)
        programs = [struct.pack("<II", 0xFEEDFACF, cpu) + b"program"
                    for cpu in (0x01000007, 0x0100000C)]
        header = struct.pack(">II", 0xCAFEBABF if wide else 0xCAFEBABE, 2)
        offset = 8 + stride * 2
        for cpu, program in zip((0x01000007, 0x0100000C), programs):
            fields = [cpu, 0, offset, len(program), 0]
            if wide:
                fields.append(0)
            header += struct.pack(layout, *fields)
            offset += len(program)
        return header + b"".join(programs)

    def test_extracts_each_chip_from_fat32_and_fat64(self) -> None:
        for wide in (False, True):
            for cpu in (0x01000007, 0x0100000C):
                with self.subTest(wide=wide, cpu=cpu):
                    selected = make_macos_templates.thin_binary(self.fat(wide), cpu)
                    self.assertEqual(selected, struct.pack("<II", 0xFEEDFACF, cpu) + b"program")

    def test_rejects_truncated_missing_or_out_of_range_architecture(self) -> None:
        bad_offset = bytearray(self.fat())
        struct.pack_into(">I", bad_offset, 16, len(bad_offset) + 1)
        for content, cpu in [(b"short", 0x01000007), (self.fat()[:12], 0x01000007),
                             (self.fat(), 123), (bytes(bad_offset), 0x01000007)]:
            with self.subTest(content=content[:8], cpu=cpu), self.assertRaises(RuntimeError):
                make_macos_templates.thin_binary(content, cpu)

    def test_templates_keep_programs_permissions_and_resources(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "macos.zip"
            with zipfile.ZipFile(source, "w") as zipped:
                zipped.writestr("macos_template.app/Contents/Info.plist", b"template resource")
                for mode in ("debug", "release"):
                    entry = zipfile.ZipInfo(f"macos_template.app/Contents/MacOS/godot_macos_{mode}.universal")
                    entry.create_system = 3
                    entry.external_attr = 0o100755 << 16
                    zipped.writestr(entry, self.fat())
            with contextlib.redirect_stdout(io.StringIO()):
                make_macos_templates.prepare("unused", source, root / "out")
            for name, (architecture, cpu) in make_macos_templates.ARCHITECTURES.items():
                with zipfile.ZipFile(root / "out" / f"macos-{name}.zip") as zipped:
                    self.assertEqual(zipped.read("macos_template.app/Contents/Info.plist"), b"template resource")
                    for mode in ("debug", "release"):
                        path = f"macos_template.app/Contents/MacOS/godot_macos_{mode}.{architecture}"
                        self.assertEqual(zipped.read(path), struct.pack("<II", 0xFEEDFACF, cpu) + b"program")
                        self.assertEqual(zipped.getinfo(path).external_attr >> 16, 0o100755)
                    self.assertFalse(any(name.endswith(".universal") for name in zipped.namelist()))
            with patch.object(make_macos_templates, "thin_binary") as thin:
                make_macos_templates.prepare("unused", source, root / "out")
            thin.assert_not_called()


class GodotTests(unittest.TestCase):
    def test_explicit_path_wins_over_environment(self) -> None:
        with patch.dict(os.environ, {"GODOT": "environment"}):
            with patch.object(godot.shutil, "which", return_value="relative dir/godot") as which:
                self.assertEqual(godot.find_godot("explicit"), str(Path("relative dir/godot").resolve()))
        which.assert_called_once_with("explicit")

    def test_invalid_configuration_does_not_silently_use_another_version(self) -> None:
        with patch.dict(os.environ, {"GODOT": "missing"}):
            with patch.object(godot.shutil, "which", return_value=None) as which:
                with self.assertRaisesRegex(SystemExit, "missing"):
                    godot.find_godot()
        which.assert_called_once_with("missing")

    def test_console_then_regular_command(self) -> None:
        with patch.dict(os.environ, {"GODOT": ""}):
            with patch.object(godot.shutil, "which", side_effect=[None, "/usr/bin/godot"]) as which:
                self.assertEqual(godot.find_godot(), str(Path("/usr/bin/godot").resolve()))
        self.assertEqual([call.args[0] for call in which.call_args_list], ["godot_console", "godot"])


if __name__ == "__main__":
    unittest.main()
