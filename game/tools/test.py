# /// script
# requires-python = ">=3.11"
# ///
"""一条命令跑全部测试：先导入（新加了 class_name 时要导入一次），再跑规则测试和画面测试。
本地和 GitHub 上都用它，所以两边跑的东西一样。

    uv run game/tools/test.py                  # 导入，跑规则测试和画面测试
    uv run game/tools/test.py rules            # 只跑规则测试（view 只跑画面测试）
    uv run game/tools/test.py rules --only ai  # 只跑名字里带 ai 的规则测试
    uv run game/tools/test.py --no-import      # 不导入，快一点

用哪个 Godot：有环境变量 GODOT 就用它，否则先找 godot_console（Windows 上会等程序跑完并显示输出），再找 godot。
一组失败了也接着跑下一组，最后有失败时退出码为 1。
"""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

GAME = Path(__file__).resolve().parents[1]
SUITES = {
    "rules": ("规则测试", "res://tests/run_tests.gd"),
    "view": ("画面测试", "res://tests/run_view_tests.gd"),
}


def find_godot() -> str:
    for name in [os.environ.get("GODOT"), "godot_console", "godot"]:
        if name and shutil.which(name):
            return name
    sys.exit("找不到 Godot：把 godot_console 或 godot 放进 PATH，或者用环境变量 GODOT 指定")


def main() -> int:
    parser = argparse.ArgumentParser(description="跑规则测试和画面测试")
    parser.add_argument("which", nargs="?", choices=["all", *SUITES], default="all", help="跑哪一组（默认全部）")
    parser.add_argument("--only", help="只跑名字里带这个词的测试（最好和 rules 或 view 一起用）")
    parser.add_argument("--no-import", action="store_true", help="不先导入")
    args = parser.parse_args()

    godot = find_godot()
    base = [godot, "--headless", "--path", str(GAME)]
    if not args.no_import:
        print("导入……", flush=True)
        if subprocess.run([*base, "--import"]).returncode != 0:
            print("导入失败")
            return 1

    failed = []
    for key in SUITES if args.which == "all" else [args.which]:
        title, script = SUITES[key]
        extra = ["--", f"only={args.only}"] if args.only else []
        if subprocess.run([*base, "--script", script, *extra]).returncode != 0:
            failed.append(title)

    print("全部通过" if not failed else "有失败：" + "、".join(failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
