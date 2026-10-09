# /// script
# requires-python = ">=3.11"
# dependencies = ["cogapp"]
# ///
"""更新文档里由代码决定的部分，免得手抄的数字和代码对不上：

1. 数字后面跟着看不见的标记 `<!-- 数值名 -->`（数组写 `<!-- 数值名[0] -->`）的，改成 balance.cfg 里写的值。
   原来写成百分数的按百分数写（0.55 写成 55%），原来带小数点的保留小数点（2.0 还写 2.0）。
2. `<!-- [[[cog ... ]]] -->` 和 `<!-- [[[end]]] -->` 之间的整块内容，用 cog 重新生成（比如科技价格表）。
   cog 的代码里可以 `import update_docs`，用这里的函数取数据。

    uv run game/tools/update_docs.py           # 改文件
    uv run game/tools/update_docs.py --check   # 只检查，有要改的就退出码 1

数值取自 balance.cfg，科技取自 tech.gd。
test.py 跑全部测试、全部通过时也会调用这里，GitHub 上跑完测试以后 docs/ 有变化就算失败。
"""

import argparse
import ast
import json
import re
import sys
from pathlib import Path

GAME = Path(__file__).resolve().parents[1]
DOCS = GAME.parent / "docs"
# 要更新的文件。只放「现在的事实」：开发日志这类历史记录里写着当时的数字，不能跟着改。
# 别的文件里要用标记或 cog 块时，加到这里。
FILES = [DOCS / "design" / "current-rules.md"]
TAG = re.compile(r"<!-- ([A-Z][A-Z0-9_]*)(?:\[(\w+)\])? -->")
# 标记前面的数字：数字、可能有的 %，再隔最多几个字的单位（E、格、回合）
NUMBER = re.compile(r"(\d+(?:\.\d+)?)(%?)([^\d<>\n]{0,4})$")


def _gd_dict(path: Path, const: str) -> dict:
    """读 GDScript 文件里 `const 名字 := { ... }` 这个字典（写法和 Python 一样，只差 true / false / null）。"""
    text = path.read_text(encoding="utf-8")
    m = re.search(rf"^const {const}\b[^=]*:= \{{\n(.*?)^\}}", text, re.M | re.S)
    if m is None:
        sys.exit(f"{path} 里找不到 const {const}")
    body = re.sub(r"\btrue\b", "True", re.sub(r"\bfalse\b", "False", re.sub(r"\bnull\b", "None", m.group(1))))
    return ast.literal_eval("{" + body + "}")


def balance() -> dict:
    """balance.cfg 里写的每个数值（用 sync_balance.py 读）。"""
    from sync_balance import read_cfg  # 同一目录下的 sync_balance.py

    result = {}
    for name, value in read_cfg():
        if name == "---":
            continue
        try:
            result[name] = ast.literal_eval(value)
        except (ValueError, SyntaxError):
            # R4 dictionaries contain Godot/JSON true and false. Keep support
            # for the existing Python-compatible literals without eval().
            result[name] = json.loads(value)
    return result


def techs() -> dict:
    """科技树：名字 → {code, name, tier, needs}，按 tech.gd 里的顺序。"""
    return _gd_dict(GAME / "rules" / "tech.gd", "ALL")


def price(cost: list) -> str:
    """[能量, 矿石] 写成「10E」「8E + 6M」「6M」。"""
    parts = [f"{n}{unit}" for n, unit in zip(cost, ["E", "M"]) if n]
    return " + ".join(parts) or "免费"


def tech_table(conditions: list[str]) -> str:
    """原型现在的规则 §4 的科技表：每一级一行，列出科技、价格和前置。
    conditions 是每一级的条件（文档里的说法），里面可以写 {数值名}，填 balance.cfg 里的值。"""
    all_techs = techs()
    values = balance()
    costs = values["TECH_COST"]
    rows = ["| 等级 | 条件 | 科技（价格 E + M） |", "| --- | --- | --- |"]
    for tier, (name, condition) in enumerate(zip(["0 级", "I 级", "II 级", "III 级"], conditions)):
        items = []
        for tid, t in all_techs.items():
            if t["tier"] != tier:
                continue
            text = f"{t['code']} {t['name']}"
            if tier > 0:
                text += " " + price(costs[tid])
                if t["needs"]:
                    text += "（要 " + "、".join(all_techs[n]["code"] for n in t["needs"]) + "）"
            items.append(text)
        rows.append(f"| {name} | {condition.format(**values)} | {'、'.join(items)} |")
    return "\n".join(rows) + "\n"


def _format(value: float, like: str, percent: bool) -> str:
    """按原来的写法写出新值：like 是原来的数字（看有没有小数点）。"""
    v = value * 100 if percent else value
    s = f"{v:.10g}"
    if "." in like and "." not in s:
        s += ".0"
    return s


def fix_numbers(text: str, values: dict) -> tuple[str, list[str]]:
    """把每个标记前面的数字改成 values 里的值，返回 (新文本, 问题)。"""
    problems: list[str] = []
    out: list[str] = []
    pos = 0
    for m in TAG.finditer(text):
        name, key = m.group(1), m.group(2)
        label = f"{name}[{key}]" if key else name
        line_start = text.rfind("\n", 0, m.start()) + 1
        n = NUMBER.search(text, line_start, m.start())
        if name not in values:
            problems.append(f"{label} 不是 balance.cfg 里的数值")
            continue
        if n is None:
            problems.append(f"{label} 前面没有数字（数字和标记之间最多隔几个字的单位）")
            continue
        value = values[name]
        if key is not None:
            value = value[int(key)] if isinstance(value, list) else value.get(key, value.get(int(key) if key.isdigit() else key))
        if not isinstance(value, (int, float)):
            problems.append(f"{label} 不是一个数（是 {value!r}），要写到数组里的哪一个，比如 {name}[0]")
            continue
        out.append(text[pos:n.start(1)])
        out.append(_format(value, n.group(1), n.group(2) == "%"))
        pos = n.end(1)
    out.append(text[pos:])
    return "".join(out), problems


def _cog(text: str, path: Path) -> str:
    from cogapp import Cog  # 只在要用时导入：mutate.py 导入 test.py 时不用装 cogapp

    sys.path.insert(0, str(Path(__file__).parent))
    try:
        return Cog().process_string(text, fname=str(path))
    finally:
        sys.path.pop(0)


def update(write: bool) -> tuple[list[Path], list[str]]:
    """更新 FILES 里的文件。返回 (要改或改了的文件, 问题)。"""
    values = balance()
    changed: list[Path] = []
    problems: list[str] = []
    for path in FILES:
        text = path.read_text(encoding="utf-8")
        new, found = fix_numbers(text, values)
        problems += [f"{path.relative_to(GAME.parent)}：{p}" for p in found]
        if "[[[cog" in new:
            new = _cog(new, path)
        if new != text:
            changed.append(path)
            if write:
                path.write_text(new, encoding="utf-8", newline="\n")
    return changed, problems


def main() -> int:
    parser = argparse.ArgumentParser(description="更新文档里由代码决定的数字和表格")
    parser.add_argument("--check", action="store_true", help="只检查，不改文件")
    args = parser.parse_args()
    changed, problems = update(write=not args.check)
    for p in problems:
        print(p)
    root = GAME.parent
    for path in changed:
        print(("要更新：" if args.check else "已更新：") + str(path.relative_to(root)))
    if not changed and not problems:
        print("文档里的数字和表格都是最新的")
    return 1 if problems or (args.check and changed) else 0


if __name__ == "__main__":
    sys.exit(main())
