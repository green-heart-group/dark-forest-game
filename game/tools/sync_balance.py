"""按 game/balance.cfg 重新生成 game/rules/balance.gd 里的数值声明，加、删数值时只改 balance.cfg 就行。

    uv run game/tools/sync_balance.py           # 改 balance.gd
    uv run game/tools/sync_balance.py --check   # 只检查，要改就退出码 1

balance.gd 里两行标记之间的部分整段重写：balance.cfg 的每个数值一行 `static var 名字: 类型`，
分段标题（`; ----------` 开头的注释）照抄过去。类型按值猜（整数 int、小数 float、数组 Array、字典 Dictionary）；
balance.gd 里已经有的数值保留原来写的类型，所以要更具体的类型（比如 Array[int]）就直接改那一行。
test.py 每次跑测试之前先调用这里。
"""

import argparse
import re
import sys
from pathlib import Path

GAME = Path(__file__).resolve().parents[1]
CFG = GAME / "balance.cfg"
GD = GAME / "rules" / "balance.gd"
BEGIN = "# >>> 下面这段由 game/tools/sync_balance.py 按 balance.cfg 生成，只有类型可以手改（重新生成时留着）"
END = "# <<< 生成的到这里为止"


def _guess_type(value: str) -> str:
    value = value.strip()
    if value.startswith("{"):
        return "Dictionary"
    if value.startswith("["):
        return "Array"
    if value.startswith('"'):
        return "String"
    if value in ("true", "false"):
        return "bool"
    if re.fullmatch(r"-?\d+", value):
        return "int"
    return "float"


def read_cfg(text: str | None = None) -> list[tuple[str, str]]:
    """balance.cfg 按顺序拆成 [(名字, 值的原文)]，分段标题是 ("---", 标题原文)。
    值的原文去掉了注释，跨几行的字典合成一段；写法（数、数组、字典）和 Python 一样。
    update_docs.py 也用这里读数值，读 balance.cfg 的只有这一处（Godot 那边是 Balance._read_file）。"""
    if text is None:
        text = CFG.read_text(encoding="utf-8")
    items: list[tuple[str, str]] = []
    for line in text.split("\n"):
        line = line.strip()
        if line.startswith(";"):
            if line[1:].strip().startswith("---"):
                items.append(("---", line[1:]))
            continue
        line = line.split(";")[0].strip()  # 值里没有分号，分号后面都是注释
        m = re.match(r"^(\w+)\s*=(.*)$", line)
        if m:
            items.append((m.group(1), m.group(2).strip()))
        elif line and not line.startswith("[") and items and items[-1][0] != "---":
            items[-1] = (items[-1][0], items[-1][1] + "\n" + line)  # 字典的下一行
    return items


def declarations(items: list[tuple[str, str]], old_types: dict[str, str]) -> list[str]:
    """read_cfg 的结果 → 标记之间的那些行。"""
    lines: list[str] = []
    for name, value in items:
        if name == "---":
            if lines:
                lines.append("")
            lines.append("#" + value)
        else:
            lines.append(f"static var {name}: {old_types.get(name) or _guess_type(value)}")
    return lines


def sync(write: bool) -> bool:
    """balance.gd 和 balance.cfg 对得上就返回 False；对不上时返回 True（write 为真时顺便改好）。"""
    gd = GD.read_text(encoding="utf-8")
    if BEGIN not in gd or END not in gd:
        sys.exit(f"{GD} 里找不到生成部分的标记，照原样补回这两行：\n{BEGIN}\n{END}")
    head, rest = gd.split(BEGIN, 1)
    body, tail = rest.split(END, 1)
    old_types = dict(re.findall(r"^static var (\w+)\s*:\s*(.+?)\s*$", body, re.M))
    new_body = "\n" + "\n".join(declarations(read_cfg(), old_types)) + "\n"
    if new_body == body:
        return False
    if write:
        GD.write_text(head + BEGIN + new_body + END + tail, encoding="utf-8", newline="\n")
    return True


def main() -> int:
    parser = argparse.ArgumentParser(description="按 balance.cfg 重新生成 balance.gd 里的数值声明")
    parser.add_argument("--check", action="store_true", help="只检查，不改文件")
    args = parser.parse_args()
    changed = sync(write=not args.check)
    if not changed:
        print("balance.gd 和 balance.cfg 对得上")
    else:
        print("要更新：game/rules/balance.gd" if args.check else "已更新：game/rules/balance.gd")
    return 1 if args.check and changed else 0


if __name__ == "__main__":
    sys.exit(main())
