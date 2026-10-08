# /// script
# requires-python = ">=3.11"
# ///
"""一条命令跑全部测试：先导入（新加了 class_name 时要导入一次），再跑规则测试和画面测试。
本地和 GitHub 上都用它，所以两边跑的东西一样。

    uv run game/tools/test.py                  # 导入，跑规则测试和画面测试
    uv run game/tools/test.py rules            # 只跑规则测试（view 只跑画面测试）
    uv run game/tools/test.py rules --only ai  # 只跑名字里带 ai 的规则测试
    uv run game/tools/test.py --no-import      # 不导入，快一点
    uv run game/tools/test.py --jobs 1         # 规则测试只用一个进程

为了快，几个 Godot 进程同时跑：规则测试分成几份（默认 CPU 核数，最多 8 份），画面测试一个进程，一起开始。
画面测试后面的测试要用前面留下的局面，不能拆开。
每次跑完把每个规则测试用了多久记在 game/.godot/test_times.json（不进 git），下次分的时候让每份的总时间差不多；
没有记录时（比如 GitHub 上）轮流分。
只有失败的进程才把它的完整输出打出来，免得几个进程的输出混在一起。

用哪个 Godot：有环境变量 GODOT 就用它，否则先找 godot_console（Windows 上会等程序跑完并显示输出），再找 godot。
有失败时退出码为 1。
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

GAME = Path(__file__).resolve().parents[1]
SUITES = {
    "rules": ("规则测试", "res://tests/run_tests.gd"),
    "view": ("画面测试", "res://tests/run_view_tests.gd"),
}
TIMES = GAME / ".godot" / "test_times.json"
# 没有记录的测试，当它要这么多毫秒
DEFAULT_MS = 100


def find_godot() -> str:
    for name in [os.environ.get("GODOT"), "godot_console", "godot"]:
        if name and shutil.which(name):
            return name
    sys.exit("找不到 Godot：把 godot_console 或 godot 放进 PATH，或者用环境变量 GODOT 指定")


def rule_tests(game: Path = GAME) -> list[str]:
    """所有规则测试的名字（文件名.函数名），顺序和 run_tests.gd 自己找的一样。"""
    names = []
    for f in sorted((game / "tests" / "rules").glob("test_*.gd")):
        for m in re.finditer(r"^func (test_\w+)\(", f.read_text(encoding="utf-8"), re.M):
            names.append(f"{f.stem}.{m.group(1)}")
    return names


def load_times() -> dict[str, float]:
    """上次记下的每个规则测试用了几毫秒。"""
    try:
        return json.loads(TIMES.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def save_times(times: dict[str, float]) -> None:
    old = load_times()
    old.update(times)
    TIMES.parent.mkdir(exist_ok=True)
    TIMES.write_text(json.dumps(old, ensure_ascii=False, indent=0, sort_keys=True), encoding="utf-8")


def split(names: list[str], times: dict[str, float], n: int) -> list[list[str]]:
    """把测试分成 n 份，每份的总时间差不多：从最慢的开始，每个分给目前最空的那份。每份里保持原来的顺序。"""
    shares: list[list[str]] = [[] for _ in range(n)]
    load = [0.0] * n
    for name in sorted(names, key=lambda x: -times.get(x, DEFAULT_MS)):
        i = load.index(min(load))
        shares[i].append(name)
        load[i] += times.get(name, DEFAULT_MS)
    order = {name: i for i, name in enumerate(names)}
    return [sorted(s, key=order.get) for s in shares if s]


def godot_args(godot: str, game: Path, suite: str, args: list[str]) -> list[str]:
    cmd = [godot, "--headless", "--path", str(game), "--script", SUITES[suite][1]]
    return cmd + ["--", *args] if args else cmd


def main() -> int:
    parser = argparse.ArgumentParser(description="跑规则测试和画面测试")
    parser.add_argument("which", nargs="?", choices=["all", *SUITES], default="all", help="跑哪一组（默认全部）")
    parser.add_argument("--only", help="只跑名字里带这个词的测试（最好和 rules 或 view 一起用）")
    parser.add_argument("--no-import", action="store_true", help="不先导入")
    parser.add_argument("--jobs", type=int, default=min(os.cpu_count() or 1, 8), help="规则测试分几个进程跑")
    args = parser.parse_args()

    godot = find_godot()
    if not args.no_import:
        print("导入……", flush=True)
        if subprocess.run([godot, "--headless", "--path", str(GAME), "--import"]).returncode != 0:
            print("导入失败")
            return 1

    suites = list(SUITES) if args.which == "all" else [args.which]
    with tempfile.TemporaryDirectory(prefix="test-") as tmp:
        # 要开的进程：(哪一组, 第几份, 参数)
        jobs: list[tuple[str, int, list[str]]] = []
        if "rules" in suites:
            names = [n for n in rule_tests() if not args.only or args.only in n]
            if not names:
                print(f"没有名字里带「{args.only}」的规则测试")
                return 1
            for i, share in enumerate(split(names, load_times(), max(1, args.jobs))):
                listing = Path(tmp) / f"rules{i}.txt"
                listing.write_text("\n".join(share), encoding="utf-8")
                jobs.append(("rules", i, [f"tests={listing}"]))
        if "view" in suites:
            jobs.append(("view", 0, [f"only={args.only}"] if args.only else []))

        t0 = time.monotonic()
        running = []
        for suite, i, extra in jobs:
            report = Path(tmp) / f"{suite}{i}.json"
            log = Path(tmp) / f"{suite}{i}.log"
            with open(log, "w", encoding="utf-8") as out:
                proc = subprocess.Popen(godot_args(godot, GAME, suite, [*extra, f"report={report}"]),
                                        stdout=out, stderr=subprocess.STDOUT)
            running.append((suite, proc, report, log))
        # 每个进程跑完的时刻，用来算每组用了多久
        done_at = {}
        def wait(proc: subprocess.Popen) -> None:
            proc.wait()
            done_at[proc.pid] = time.monotonic()
        waiters = [threading.Thread(target=wait, args=(proc,)) for _, proc, _, _ in running]
        for w in waiters:
            w.start()
        for w in waiters:
            w.join()

        failed = []
        for suite in suites:
            mine = [(proc, report, log) for s, proc, report, log in running if s == suite]
            results = [(proc.returncode, report, log) for proc, report, log in mine]
            seconds = max(done_at[proc.pid] for proc, _, _ in mine) - t0
            text, ok = summary(suite, results, seconds, len(names) if suite == "rules" else None)
            print(text, flush=True)
            if not ok:
                failed.append(SUITES[suite][0])

    print("全部通过" if not failed else "有失败：" + "、".join(failed))
    return 1 if failed else 0


def summary(suite: str, results: list[tuple[int, Path, Path]], seconds: float,
            expected: int | None) -> tuple[str, bool]:
    """合并一组测试几个进程的结果，写成和 test_log.gd 一样的汇总，返回 (汇总, 是否全部通过)。
    有失败的进程，汇总前面先放它的完整输出。"""
    title = SUITES[suite][0]
    tests = checks = 0
    failed: list[str] = []
    times: dict[str, float] = {}
    lines: list[str] = []
    for i, (code, report, log) in enumerate(results):
        data = json.loads(report.read_text(encoding="utf-8")) if report.exists() else None
        if code != 0 or data is None:
            lines.append(f"（{title}第 {i + 1} 个进程的输出）")
            lines.append(log.read_text(encoding="utf-8", errors="replace").rstrip())
        if data is None:
            failed.append(f"（第 {i + 1} 个进程没写出结果）")
            continue
        tests += data["tests"]
        checks += data["checks"]
        failed += data["failed"]
        times.update(data["times"])
    if expected is not None and tests != expected and not failed:
        failed.append(f"（应该跑 {expected} 个测试，只跑了 {tests} 个）")
    if suite == "rules" and not failed:
        save_times(times)
    procs = f"，分 {len(results)} 个进程" if len(results) > 1 else ""
    lines.append(f"{title}：{tests} 个测试，{len(failed)} 个失败（{checks} 次检查，{seconds:.1f} 秒{procs}）")
    slow = sorted((n for n in times if times[n] >= 1000), key=lambda n: -times[n])[:3]
    if slow:
        lines.append("最慢的：" + "，".join(f"{n} {times[n] / 1000:.1f} 秒" for n in slow))
    if failed:
        lines.append("失败的测试：" + "，".join(failed))
    return "\n".join(lines), not failed and all(code == 0 for code, *_ in results)


if __name__ == "__main__":
    sys.exit(main())
