"""Generate the R4 parameter reference from balance.cfg and the technology catalog."""
import argparse
import json
from pathlib import Path
from sync_balance import GAME, read_cfg

TARGET = GAME.parent / "docs/design/r4-parameters.md"


def render():
    values = dict(read_cfg())
    profiles = {name: json.loads(values["R4_ECONOMY_"+name]) for name in ("B", "C")}
    physics = json.loads(values["R4_PHYSICS"])
    catalog = json.loads((GAME / "rules/r4/catalog.json").read_text(encoding="utf-8"))
    lines = ["# 数值候选参数", "", "由 `game/tools/r4_parameters.py` 生成；数值唯一来源为 `game/balance.cfg`，节点身份来源为 `game/rules/r4/catalog.json`。",
             "不要直接修改此文档。B 为初值，C 为候选拟合值；名称不代表经过实测校准。", "",
             "成本列顺序为 M / E / 工作量。规则与字段含义见 [数值候选规则](r4-current-rules.md)。", ""]
    for section, title in [("technologies", "科技"), ("units", "单位"), ("ship_modules", "舰船模块")]:
        lines += ["## "+title, "", "| ID | 名称 | 前置 | B：M / E / 工作量 | C：M / E / 工作量 |",
                  "| --- | --- | --- | --- | --- |"]
        for key, row in profiles["B"][section].items():
            node = catalog.get(key, {})
            costs = []
            for profile in ("B", "C"):
                item = profiles[profile][section][key]
                prefix = "research_" if section == "technologies" else "cost_"
                costs.append(" / ".join(str(item.get(field, "—")) for field in (prefix+"M", prefix+"E", "work")))
            lines.append(f"| {key} | {node.get('name', row.get('name', key))} | {', '.join(node.get('dependencies', [])) or '—'} | {costs[0]} | {costs[1]} |")
        lines.append("")
    for profile, economy in profiles.items():
        common = {k:v for k,v in economy.items() if k not in ("technologies", "units", "ship_modules")}
        lines += [f"## {profile} 经济与流程参数", "", "```json", json.dumps(common, ensure_ascii=False, indent=2), "```", ""]
    lines += ["## 共用物理参数", "", "```json", json.dumps(physics, ensure_ascii=False, indent=2), "```", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    expected = render()
    matches = TARGET.exists() and TARGET.read_text(encoding="utf-8") == expected
    if args.check:
        print("R4 parameter reference current" if matches else "R4 parameter reference needs regeneration")
        return 0 if matches else 1
    TARGET.write_text(expected, encoding="utf-8", newline="\n")
    print("Generated docs/design/r4-parameters.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
