"""Sequential R4 regressions using an existing Godot; no downloads or installs."""
import argparse
from contextlib import contextmanager
import json
import os
from pathlib import Path
import shutil
import subprocess
import time
import uuid

GAME = Path(__file__).resolve().parents[1]
SUITES = ("ledger", "space", "state", "events", "acceptance", "boundaries",
          "late_boundaries", "convergence", "optimizations", "view", "diagnostics")


@contextmanager
def isolated_user_data():
    # Keep each run in the ignored build directory for review, avoiding user saves
    # and restrictive Windows ACLs created by TemporaryDirectory.
    path = GAME.parent / "build/r4-tests" / uuid.uuid4().hex
    path.mkdir(parents=True)
    yield str(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=os.environ.get("GODOT"))
    parser.add_argument("--no-import", action="store_true")
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    godot = args.godot or shutil.which("godot_console") or shutil.which("godot")
    if not godot:
        parser.error("Set GODOT or --godot to an existing Godot 4.7.2 executable")
    if args.out and args.out.exists():
        parser.error("Output exists; choose a new report path")
    results = []
    with isolated_user_data() as temp:
        env = os.environ.copy()
        env.update(APPDATA=temp, LOCALAPPDATA=temp, XDG_DATA_HOME=temp)
        flags = (subprocess.CREATE_NO_WINDOW | subprocess.BELOW_NORMAL_PRIORITY_CLASS) if os.name == "nt" else 0
        commands = ([] if args.no_import else [("import", ["--import"])])
        commands += [(name, ["--script", f"res://tests/test_r4_{name}.gd"]) for name in SUITES]
        for name, tail in commands:
            argv = [str(godot), "--headless", "--path", str(GAME), *tail]
            started = time.perf_counter()
            try:
                result = subprocess.run(argv, env=env, capture_output=True, text=True,
                                        encoding="utf-8", errors="replace", timeout=600, creationflags=flags)
                output = result.stdout + result.stderr
                summaries = []
                for line in output.splitlines():
                    try:
                        item = json.loads(line)
                        if isinstance(item, dict) and "failure_count" in item:
                            summaries.append(item)
                    except json.JSONDecodeError:
                        pass
                passed = (result.returncode == 0 and "SCRIPT ERROR" not in output
                          and (name == "import" or (len(summaries) == 1
                               and summaries[0]["failure_count"] == 0 and summaries[0]["checks"] > 0)))
                entry = {"suite": name, "passed": passed, "exit_code": result.returncode,
                         "elapsed_seconds": time.perf_counter()-started, "results": summaries,
                         "command": argv, "output": output}
            except subprocess.TimeoutExpired:
                entry = {"suite": name, "passed": False, "error": "technical_timeout", "command": argv}
            results.append(entry)
            print(json.dumps({k: v for k, v in entry.items() if k not in ("output", "command")}, ensure_ascii=False), flush=True)
            if args.out:
                args.out.parent.mkdir(parents=True, exist_ok=True)
                args.out.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
            if not entry["passed"]:
                print(entry.get("output", entry.get("error")))
                return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
