# /// script
# requires-python = ">=3.11"
# dependencies = ["fonttools", "brotli"]
# ///
"""跨平台导出工具：同步数值声明、准备网页字体、导入、导出并打包。

    uv run game/tools/export.py                # Web、Windows 普通版和开发者版、macOS
    uv run game/tools/export.py web
    uv run game/tools/export.py windows
    uv run game/tools/export.py windows-dev
    uv run game/tools/export.py macos
    uv run game/tools/export.py macos-intel
    uv run game/tools/export.py macos-apple-silicon

需要 uv、Godot 和版本一致的导出模板。预设以 game/export_presets.cfg 为准。
默认输出到仓库的 build/；--out-dir 指定别处，相对路径从当前工作目录算。
--godot 指定可执行文件；否则和测试一样查找 GODOT、godot_console、godot。
Windows、macOS、Linux 使用相同参数；按导出目标安装相应模板。
macOS 直接由 Godot 导出 ZIP，保留 .app 的可执行权限，不能重新按普通文件打包。
只在全部导出成功并检查过产物后，将临时目录里的结果复制到输出目录。
"""

import argparse
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

import sync_balance
from godot import find_godot
from make_macos_templates import prepare as prepare_macos_templates

ROOT = Path(__file__).resolve().parents[2]
GAME = ROOT / "game"
TARGETS = {
    "windows": ("Windows Desktop", "dark-forest.exe", "dark-forest-windows.zip"),
    "windows-dev": ("Windows Desktop (dev)", "dark-forest-dev.exe", "dark-forest-windows-dev.zip"),
    "web": ("Web", "web/index.html", None),
    "macos-intel": ("macOS (Intel)", "dark-forest-macos-intel.zip", None),
    "macos-apple-silicon": ("macOS (Apple Silicon)", "dark-forest-macos-apple-silicon.zip", None),
}
MAC_ARCHITECTURES = {"macos-intel": 0x01000007, "macos-apple-silicon": 0x0100000C}
DEV_PAGE = """<!DOCTYPE html>
<meta charset="utf-8">
<title>黑暗森林（开发者调试）</title>
<script>
  var extra = location.search ? "&" + location.search.slice(1) : "";
  location.replace("../?debug" + extra);
</script>
"""


def run_step(command: list[str], label: str) -> None:
    """保留 Godot 输出；退出码非零或日志里代码出错，都中止导出。"""
    print(f"{label}……", flush=True)
    result = subprocess.run(command, cwd=ROOT, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, encoding="utf-8", errors="replace")
    print(result.stdout, end="", flush=True)
    if result.returncode or any(line.startswith(("SCRIPT ERROR", "ERROR:"))
                                for line in result.stdout.splitlines()):
        raise RuntimeError(f"{label}失败（退出码 {result.returncode}）。请检查上面的日志；导出模板版本要与 Godot 一致。")


def require_files(paths: list[Path]) -> None:
    for path in paths:
        if not path.is_file() or path.stat().st_size == 0:
            raise RuntimeError(f"没有生成有效的导出文件：{path}")


def check_macos_zip(path: Path, cpu: int) -> None:
    """检查 Godot 的 .app ZIP，尤其是从 Windows 导出时必须保留的执行权限。"""
    try:
        with zipfile.ZipFile(path) as zipped:
            manifests = [name for name in zipped.namelist() if name.endswith(".app/Contents/Info.plist")]
            if len(manifests) != 1:
                raise RuntimeError("macOS ZIP 应包含一个完整的 .app")
            contents = manifests[0].removesuffix("Info.plist")
            manifest = plistlib.loads(zipped.read(manifests[0]))
            executable = zipped.getinfo(contents + "MacOS/" + manifest["CFBundleExecutable"])
            if not executable.file_size or not (executable.external_attr >> 16) & 0o111:
                raise RuntimeError("macOS ZIP 中的游戏程序为空或缺少执行权限")
            with zipped.open(executable) as binary:
                header = binary.read(8)
            if len(header) != 8 or struct.unpack("<II", header) != (0xFEEDFACF, cpu):
                raise RuntimeError("macOS ZIP 的程序架构与所选芯片不一致")
            resources = [entry for entry in zipped.infolist()
                         if entry.filename.startswith(contents + "Resources/") and entry.filename.endswith(".pck")]
            if not resources or any(not entry.file_size for entry in resources):
                raise RuntimeError("macOS ZIP 缺少游戏资源包")
    except (zipfile.BadZipFile, plistlib.InvalidFileException, KeyError) as error:
        raise RuntimeError(f"无效的 macOS ZIP：{path}") from error


def export(targets: list[str], godot: str, output: Path) -> None:
    if any(target in MAC_ARCHITECTURES for target in targets):
        prepare_macos_templates(godot)
    if sync_balance.sync(write=True):
        print("已更新 game/rules/balance.gd 里的数值声明，记得一起提交")
    if "web" in targets:
        import make_web_fonts

        print("准备网页字体……", flush=True)
        make_web_fonts.main()
    run_step([godot, "--headless", "--path", str(GAME), "--import"], "导入资源")
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".export-", dir=output) as temp:
        staging = Path(temp)
        for target in targets:
            preset, filename, archive = TARGETS[target]
            destination = staging / filename
            destination.parent.mkdir(parents=True, exist_ok=True)
            run_step([godot, "--headless", "--path", str(GAME), "--export-release",
                      preset, str(destination)], f"导出 {preset}")
            required = [destination]
            if target == "web":
                required += [destination.with_suffix(suffix) for suffix in (".js", ".wasm", ".pck")]
            require_files(required)
            if target in MAC_ARCHITECTURES:
                check_macos_zip(destination, MAC_ARCHITECTURES[target])
            if archive:
                with zipfile.ZipFile(staging / archive, "w", zipfile.ZIP_DEFLATED) as zipped:
                    zipped.write(destination, arcname=destination.name)
            elif target == "web":
                dev = destination.parent / "dev" / "index.html"
                dev.parent.mkdir(exist_ok=True)
                dev.write_text(DEV_PAGE, encoding="utf-8", newline="\n")
        # 产物先放到独立临时目录，避免上次的文件掩盖本次导出失败。
        for path in staging.iterdir():
            if path.is_dir():
                shutil.copytree(path, output / path.name, dirs_exist_ok=True)
            else:
                shutil.copy2(path, output / path.name)
    for target in targets:
        _, filename, archive = TARGETS[target]
        print(f"已导出：{output / filename}")
        if archive:
            print(f"已打包：{output / archive}")


def main() -> int:
    parser = argparse.ArgumentParser(description="导出 Web、Windows 和 macOS 游戏（包含字体、导入和打包）")
    parser.add_argument("target", nargs="?", default="all", choices=["all", "macos", *TARGETS],
                        help="导出哪一版，默认全部；macos 一次导出两个 Mac 芯片版本")
    parser.add_argument("--godot", help="Godot 可执行文件的路径或命令名")
    parser.add_argument("--out-dir", type=Path, default=ROOT / "build", help="输出目录，默认仓库的 build/")
    args = parser.parse_args()
    targets = list(TARGETS) if args.target == "all" else list(MAC_ARCHITECTURES) if args.target == "macos" else [args.target]
    try:
        export(targets, find_godot(args.godot), args.out_dir.resolve())
    except (OSError, RuntimeError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print(f"导出失败：{error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
