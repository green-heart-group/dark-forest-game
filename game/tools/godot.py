"""测试、导出和录制工具共用的 Godot 查找方式。"""

import os
import shutil
from pathlib import Path


def find_godot(explicit: str | None = None) -> str:
    """指定路径优先；否则找 GODOT、godot_console、godot。路径里可以有空格。"""
    configured = explicit or os.environ.get("GODOT")
    if configured:
        found = shutil.which(configured)
        if not found:
            raise SystemExit(f"找不到指定的 Godot：{configured}")
        return str(Path(found).resolve())
    for name in ("godot_console", "godot"):
        if found := shutil.which(name):
            return str(Path(found).resolve())
    raise SystemExit("找不到 Godot：把 godot_console 或 godot 放进 PATH，或者用环境变量 GODOT 指定")
