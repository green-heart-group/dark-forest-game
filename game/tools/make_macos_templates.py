# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""从官方 macos.zip 的 Universal 程序生成 Intel、Apple Silicon 两种导出模板。

export.py 在导出 Mac 前自动调用；也可单独运行，以便在 Godot 编辑器中导出。
    uv run game/tools/make_macos_templates.py
    uv run game/tools/make_macos_templates.py --template /path/to/macos.zip

模板放在 build/macos_templates/，不进 Git；不会修改已安装的官方模板。
只提取 Mach-O 中已有的程序，不重新编译；由 Godot 在最终导出时重新签名。
"""

import argparse
import copy
import hashlib
import json
import os
import struct
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

from godot import find_godot

OUT = Path(__file__).resolve().parents[2] / "build" / "macos_templates"
ARCHITECTURES = {"intel": ("x86_64", 0x01000007), "apple-silicon": ("arm64", 0x0100000C)}


def thin_binary(binary: bytes, cpu: int) -> bytes:
    """从 32/64 位 FAT 容器选出目标 Mach-O；各偏移均相对官方容器。"""
    if len(binary) < 8:
        raise RuntimeError("macOS 模板中的程序头不完整")
    if struct.unpack_from("<II", binary) == (0xFEEDFACF, cpu):
        return binary
    magic, count = struct.unpack_from(">II", binary)
    if magic not in (0xCAFEBABE, 0xCAFEBABF):
        raise RuntimeError("macOS 模板不是支持的 Universal 程序")
    layout = ">IIIII" if magic == 0xCAFEBABE else ">IIQQII"
    step = struct.calcsize(layout)
    if not count or 8 + count * step > len(binary):
        raise RuntimeError("macOS 模板的架构目录不完整")
    for i in range(count):
        architecture, _, offset, size, *_ = struct.unpack_from(layout, binary, 8 + i * step)
        if architecture != cpu:
            continue
        if offset < 8 + count * step or size < 8 or offset + size > len(binary):
            raise RuntimeError("macOS 模板中的程序范围无效")
        selected = binary[offset:offset + size]
        if struct.unpack_from("<II", selected) != (0xFEEDFACF, cpu):
            raise RuntimeError("macOS 模板中的程序架构不一致")
        return selected
    raise RuntimeError("macOS 模板缺少所需芯片的程序")


def installed_template(godot: str) -> Path:
    result = subprocess.run([godot, "--version"], check=True, stdout=subprocess.PIPE,
                            encoding="utf-8", errors="replace")
    version = ".".join(result.stdout.strip().split(".")[:4])
    if sys.platform == "win32":
        data = Path(os.environ.get("APPDATA", Path.home() / "AppData/Roaming")) / "Godot"
    elif sys.platform == "darwin":
        data = Path.home() / "Library/Application Support/Godot"
    else:
        data = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share")) / "godot"
    # Godot 的便携模式把模板放在可执行文件旁的 editor_data 里。
    executable_dir = Path(godot).resolve().parent
    if any((executable_dir / marker).is_file() for marker in ("_sc_", "._sc_")):
        data = executable_dir / "editor_data"
    source = data / "export_templates" / version / "macos.zip"
    if not source.is_file():
        raise RuntimeError(f"找不到 macOS 模板：{source}。请安装与 Godot 同版本的 macos.zip 模板。")
    return source


def prepare(godot: str, source: Path | None = None, output: Path = OUT) -> None:
    source = source or installed_template(godot)
    with source.open("rb") as stream:
        fingerprint = {"format": 1, "sha256": hashlib.file_digest(stream, "sha256").hexdigest()}
    marker = output / "source.json"
    try:
        if json.loads(marker.read_text(encoding="utf-8")) == fingerprint and all(
            (output / f"macos-{name}.zip").is_file() for name in ARCHITECTURES
        ):
            return
    except (OSError, ValueError):
        pass
    print("从官方模板准备 Intel、Apple Silicon 导出模板……", flush=True)
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".templates-", dir=output) as temp:
        staging = Path(temp)
        with zipfile.ZipFile(source) as original:
            for name, (architecture, cpu) in ARCHITECTURES.items():
                with zipfile.ZipFile(staging / f"macos-{name}.zip", "w", zipfile.ZIP_DEFLATED) as result:
                    found = set()
                    for entry in original.infolist():
                        metadata = copy.copy(entry)
                        content = original.read(entry)
                        if "/Contents/MacOS/godot_macos_" in entry.filename:
                            if not entry.filename.endswith(".universal"):
                                continue
                            content = thin_binary(content, cpu)
                            metadata.filename = entry.filename.removesuffix(".universal") + "." + architecture
                            found.add(Path(metadata.filename).stem)
                        result.writestr(metadata, content)
                    if found != {"godot_macos_debug", "godot_macos_release"}:
                        raise RuntimeError("官方 macos.zip 缺少 debug 或 release 程序")
        for path in staging.iterdir():
            path.replace(output / path.name)
    marker.write_text(json.dumps(fingerprint), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="从官方 Universal 模板准备两个单芯片 macOS 模板")
    parser.add_argument("--template", type=Path, help="官方 macos.zip 的路径；默认查找已安装的模板")
    parser.add_argument("--godot", help="Godot 可执行文件路径或命令名")
    args = parser.parse_args()
    try:
        prepare(find_godot(args.godot), args.template)
    except (OSError, RuntimeError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print(f"准备 macOS 模板失败：{error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
