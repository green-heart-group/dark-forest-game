# /// script
# requires-python = ">=3.11"
# ///
"""变异测试：故意给规则代码造一个小错，看测试能不能发现。

每次只改一处（比如把 < 改成 <=），跑一遍规则测试：测试失败了，就算「抓到」这个错；
测试照样全部通过，就说明这里出错时没有测试能发现，值得补测试。
最后给出变异分数（抓到的错 / 造出来的错），并列出没抓到的错。

    uv run game/tools/mutate.py geometry.gd              # 改 game/rules/geometry.gd
    uv run game/tools/mutate.py geometry.gd tech.gd      # 改几个文件
    uv run game/tools/mutate.py all                      # 改 game/rules/ 下所有文件（balance.gd 和生成的目录除外）
    uv run game/tools/mutate.py geometry.gd --view       # 规则测试没抓到的，再跑画面测试看能不能抓到
    uv run game/tools/mutate.py geometry.gd --only geo   # 只跑名字里带 geo 的规则测试
    uv run game/tools/mutate.py all --out mutate.txt     # 结果另外存一份
    uv run game/tools/mutate.py geometry.gd --list       # 只列出会造哪些错，不跑测试

为了快：
- 几份同时跑（--jobs，默认是 CPU 逻辑核数的四分之三）。在 16 核 32 线程的电脑上量过：8 份 133 秒，16 份 83 秒，24 份和 32 份都是 69 秒。
- 遇到第一个失败就停（只要知道有没有抓到），而且先跑快的测试：大部分错在快测试里就被抓到。
  每个测试要多久取自 tools/test.py 记下的 game/.godot/test_times.json，先跑一次 test.py 才有。
即使这样也很慢（没抓到的错要把测试全跑完），所以只在本地需要时跑，不放进 GitHub 上的检查。

原来的代码不动：先把 game/ 和 docs/ 复制到临时目录（有测试要读 docs/design/current-rules.md），只改副本。
每份副本用自己的存档目录（user://），几份同时写测试文件时不会互相删掉。
没抓到的错里可能有「改了也不影响结果」的（比如两个值永远不会相等时，< 和 <= 一样），要人看一眼再决定补不补测试。
"""

import argparse
import os
import queue
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from dataclasses import dataclass
from pathlib import Path

from test import GAME, DEFAULT_MS, find_godot, godot_args, load_times, rule_tests  # 同一目录下的 test.py

# 只放数值或自动生成的文件，改了也看不出测试好坏
SKIP_FILES = {"balance.gd", "balance_index.gd"}
# 符号互换。左边出现在代码里（不在注释、字符串里）时，换成右边
SWAPS = {
    "<": "<=", "<=": "<", ">": ">=", ">=": ">",
    "==": "!=", "!=": "==",
    "+": "-", "-": "+", "*": "/", "/": "*",
    "+=": "-=", "-=": "+=",
    "and": "or", "or": "and", "&&": "||", "||": "&&",
    "true": "false", "false": "true",
}
# 从长到短排，先认出 <= 再认 <；-> 和 ** 等不改，但要先认出来，免得被拆成 - 和 >
OPERATORS = sorted(
    ["->", "**", "**=", "<<", ">>", "<<=", ">>=", ":=", "*=", "/=", "%=", *SWAPS], key=len, reverse=True
)
TOKEN = re.compile(
    r'(?P<string>"""(?:.|\n)*?"""|\'\'\'(?:.|\n)*?\'\'\'|"(?:\\.|[^"\\\n])*"|\'(?:\\.|[^\'\\\n])*\')'
    r"|(?P<comment>#[^\n]*)"
    r"|(?P<number>(?:0x[0-9a-fA-F_]+|0b[01_]+|(?:\d[\d_]*\.?[\d_]*|\.\d[\d_]*)(?:[eE][+-]?\d+)?))"
    r"|(?P<name>[A-Za-z_]\w*)"
    r"|(?P<op>" + "|".join(re.escape(o) for o in OPERATORS) + r")"
    r"|(?P<other>.)",
    re.S,
)
# 每份副本的存档目录名，前面加上这个
USER_DIR_PREFIX = "dark-forest-mutate"


@dataclass
class Mutant:
    file: str  # game/rules/ 下的文件名
    start: int  # 在文件里的位置
    end: int
    old: str
    new: str
    line: int
    text: str  # 那一行原来的样子

    def describe(self) -> str:
        return f"{self.file}:{self.line}  {self.old} 改成 {self.new or '（去掉）'}    {self.text}"


def find_mutants(file: str, source: str) -> list[Mutant]:
    lines = source.splitlines()
    result = []
    for m in TOKEN.finditer(source):
        kind, word = m.lastgroup, m.group()
        if kind not in ("op", "name"):
            continue
        line = source.count("\n", 0, m.start()) + 1
        text = lines[line - 1].strip()
        if word in SWAPS:
            result.append(Mutant(file, m.start(), m.end(), word, SWAPS[word], line, text))
        elif word == "not":
            # 去掉 not 和后面的空格
            end = m.end() + len(source[m.end():]) - len(source[m.end():].lstrip(" "))
            result.append(Mutant(file, m.start(), end, "not", "", line, text))
    return result


def apply(source: str, mu: Mutant) -> str:
    return source[: mu.start] + mu.new + source[mu.end :]


def run_suite(godot: str, game: Path, suite: str, args: list[str], timeout: float | None) -> tuple[str, str]:
    """跑一组测试，返回 (结果, 输出)。结果是 通过 / 测试失败 / 编译不了 / 超时。"""
    proc = subprocess.Popen(godot_args(godot, game, suite, args), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, encoding="utf-8", errors="replace")
    try:
        out, _ = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        kill_tree(proc)
        return "超时", ""
    if proc.returncode == 0:
        return "通过", out
    if "Parse Error" in out or "编译不了" in out:
        return "编译不了", out
    return "测试失败", out


def kill_tree(proc: subprocess.Popen) -> None:
    # Windows 上的 godot_console 会再开一个 Godot 进程，要连它一起关掉
    if os.name == "nt":
        subprocess.run(["taskkill", "/T", "/F", "/PID", str(proc.pid)], capture_output=True)
    else:
        proc.kill()
    proc.communicate()


def user_dir(name: str) -> Path:
    """Godot 的自定义存档目录 custom_user_dir_name 在这台电脑上的位置。"""
    if os.name == "nt":
        return Path(os.environ["APPDATA"]) / name
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / name
    return Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share")) / name


def make_copy(root: Path, user_dir_name: str) -> Path:
    """照仓库的样子摆一份：game/ 旁边放 docs/；存档目录换成自己的。返回副本里的 game/。"""
    game = root / "game"
    shutil.copytree(GAME, game, ignore=shutil.ignore_patterns(".vscode"))
    shutil.copytree(GAME.parent / "docs", root / "docs", ignore=shutil.ignore_patterns("local"))
    project = game / "project.godot"
    text = project.read_text(encoding="utf-8").replace(
        "[application]\n",
        f'[application]\n\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="{user_dir_name}"\n', 1)
    project.write_text(text, encoding="utf-8")
    return game


def main() -> int:
    parser = argparse.ArgumentParser(description="变异测试：故意造错，看测试能不能发现")
    parser.add_argument("files", nargs="+", help="要改的文件（game/rules/ 下的文件名，比如 geometry.gd），all 是全部")
    parser.add_argument("--view", action="store_true", help="规则测试没抓到的，再跑画面测试")
    parser.add_argument("--only", help="只跑名字里带这个词的规则测试")
    parser.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 1) * 3 // 4), help="同时跑几份")
    parser.add_argument("--out", help="结果另外存到这个文件")
    parser.add_argument("--list", action="store_true", help="只列出会造哪些错，不跑测试")
    args = parser.parse_args()

    rules = GAME / "rules"
    if args.files == ["all"]:
        files = sorted(f.name for f in rules.glob("*.gd") if f.name not in SKIP_FILES)
    else:
        files = [Path(f).name for f in args.files]
        missing = [f for f in files if not (rules / f).exists()]
        if missing:
            sys.exit("game/rules/ 下没有：" + "、".join(missing))
    sources = {f: (rules / f).read_text(encoding="utf-8") for f in files}
    mutants = [mu for f in files for mu in find_mutants(f, sources[f])]
    if args.list:
        for mu in mutants:
            print(mu.describe())
        print(f"共 {len(mutants)} 个")
        return 0
    if not mutants:
        print("这些文件里没有可以改的地方")
        return 0

    godot = find_godot()
    jobs = max(1, min(args.jobs, len(mutants)))
    # 快的测试先跑：大部分错在快测试里就能抓到
    times = load_times()
    names = [n for n in rule_tests() if not args.only or args.only in n]
    if not names:
        sys.exit(f"没有名字里带「{args.only}」的规则测试")
    names.sort(key=lambda n: times.get(n, DEFAULT_MS))
    user_dirs = [f"{USER_DIR_PREFIX}-{os.getpid()}-{i}" for i in range(jobs)]
    t0 = time.monotonic()
    try:
        with tempfile.TemporaryDirectory(prefix="mutate-") as tmp:
            listing = Path(tmp) / "tests.txt"
            listing.write_text("\n".join(names), encoding="utf-8")
            rule_args = [f"tests={listing}", "stop_on_fail"]
            view_args = ["stop_on_fail"]
            copies = [make_copy(Path(tmp) / str(i), user_dirs[i]) for i in range(jobs)]

            # 先跑一遍不改的，确认测试本来就通过，顺便量出要多久
            timeouts = {}
            for suite, extra in [("rules", rule_args), ("view", view_args)][: 2 if args.view else 1]:
                started = time.monotonic()
                status, out = run_suite(godot, copies[0], suite, extra, None)
                if status != "通过":
                    print(out)
                    print(f"没改代码时{'规则' if suite == 'rules' else '画面'}测试就没通过（{status}），先修好再跑")
                    return 1
                took = time.monotonic() - started
                timeouts[suite] = max(took * 3, took + 30)
                if suite == "rules":
                    print(f"{len(files)} 个文件，{len(mutants)} 个错，{jobs} 份同时跑；不改时规则测试跑一遍 {took:.1f} 秒"
                          + ("，规则测试没抓到的再跑画面测试" if args.view else ""), flush=True)

            todo: queue.Queue[int] = queue.Queue()
            for i in range(len(mutants)):
                todo.put(i)
            results: dict[int, str] = {}
            lock = threading.Lock()
            step = max(1, len(mutants) // 20)

            def worker(game: Path) -> None:
                while True:
                    try:
                        i = todo.get_nowait()
                    except queue.Empty:
                        return
                    mu = mutants[i]
                    target = game / "rules" / mu.file
                    target.write_text(apply(sources[mu.file], mu), encoding="utf-8")
                    status, _ = run_suite(godot, game, "rules", rule_args, timeouts["rules"])
                    if status == "通过" and args.view:
                        status, _ = run_suite(godot, game, "view", view_args, timeouts["view"])
                        if status != "通过":
                            status = "画面测试" + status
                    target.write_text(sources[mu.file], encoding="utf-8")
                    with lock:
                        results[i] = status
                        if status == "通过":
                            print(f"没抓到：{mu.describe()}", flush=True)
                        if len(results) % step == 0 or len(results) == len(mutants):
                            print(f"[{len(results)}/{len(mutants)}] 用了 {time.monotonic() - t0:.0f} 秒", flush=True)

            threads = [threading.Thread(target=worker, args=(c,)) for c in copies]
            for th in threads:
                th.start()
            for th in threads:
                th.join()
    finally:
        for name in user_dirs:
            shutil.rmtree(user_dir(name), ignore_errors=True)

    report = make_report(files, mutants, results, time.monotonic() - t0)
    print()
    print(report)
    if args.out:
        Path(args.out).write_text(report + "\n", encoding="utf-8")
    return 0


def score(caught: int, total: int) -> str:
    return f"{caught}/{total} = {caught / total:.0%}" if total else "0/0"


def make_report(files: list[str], mutants: list[Mutant], results: dict[int, str], seconds: float) -> str:
    # 改完编译不了的（比如两个字符串之间的 + 改成 -，脚本分不出类型）不是测试抓到的，不算进分数
    broken = {i for i, r in results.items() if "编译不了" in r}
    lines = []
    caught_all = 0
    for f in files:
        mine = [i for i, mu in enumerate(mutants) if mu.file == f and i not in broken]
        caught = sum(1 for i in mine if results[i] != "通过")
        caught_all += caught
        lines.append(f"  {f}：{score(caught, len(mine))}")
    kinds = {}
    for i, r in results.items():
        if r != "通过" and i not in broken:
            kinds[r] = kinds.get(r, 0) + 1
    detail = "，".join(f"{k} {v}" for k, v in sorted(kinds.items()))
    head = [f"变异分数：{score(caught_all, len(mutants) - len(broken))}（{detail}），用了 {seconds:.0f} 秒"]
    if broken:
        head.append(f"另有 {len(broken)} 处改完编译不了（比如两个字符串之间的 + 改成 -），不算进分数")
    if len(files) > 1:
        head.append("每个文件：")
        head += lines
    survived = [mutants[i] for i in sorted(results) if results[i] == "通过"]
    if survived:
        head.append("没抓到的错（这里出错时没有测试发现）：")
        head += [f"  {mu.describe()}" for mu in survived]
    return "\n".join(head)


if __name__ == "__main__":
    sys.exit(main())
