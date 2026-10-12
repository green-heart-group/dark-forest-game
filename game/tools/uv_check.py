"""直接用 python 跑工具脚本时，先查 Python 版本和依赖，不对就说清楚要用 uv 跑。

每个脚本开头的 `# /// script` 块写了要哪个 Python、哪些库，`uv run` 会照着准备好；
直接 `python 脚本.py` 不会读它，缺库时要么一开头报 ModuleNotFoundError，要么跑到一半才失败。
脚本在所有导入之前调用这里（只在直接运行时，被别的脚本导入时不查）：

    if __name__ == "__main__":
        import uv_check  # 同一目录下的 uv_check.py
        uv_check.require(__file__)

这个文件要在旧版 Python 上也能运行到给出提示，所以不用新语法。
"""

import re
import sys
from pathlib import Path

UV_INSTALL = "https://docs.astral.sh/uv/getting-started/installation/"


def read_header(script):
    """读出脚本开头 `# /// script` 块里的 Python 版本下限和依赖的包名。"""
    text = Path(script).read_text(encoding="utf-8")
    block = re.search(r"^# /// script\s*$(.*?)^# ///\s*$", text, re.M | re.S)
    if not block:
        return None, []
    body = block.group(1)
    version = re.search(r'requires-python\s*=\s*">=\s*(\d+)\.(\d+)', body)
    minimum = (int(version.group(1)), int(version.group(2))) if version else None
    deps = re.search(r"dependencies\s*=\s*\[(.*?)\]", body, re.S)
    names = []
    if deps:
        for dep in re.findall(r'"([^"]+)"', deps.group(1)):
            names.append(re.split(r"[\s<>=!~;\[]", dep, maxsplit=1)[0])
    return minimum, names


def missing_packages(names):
    try:
        from importlib import metadata
    except ImportError:  # Python 3.7 以前没有，版本检查已经会先拦下
        return []
    missing = []
    for name in names:
        try:
            metadata.distribution(name)
        except metadata.PackageNotFoundError:
            missing.append(name)
    return missing


def require(script):
    """版本太低或缺依赖时，打印该怎么跑并退出（退出码 1）。"""
    minimum, names = read_header(script)
    problems = []
    if minimum and sys.version_info[:2] < minimum:
        problems.append("要 Python {}.{} 或更新，现在是 {}.{}。".format(minimum[0], minimum[1], *sys.version_info[:2]))
    missing = missing_packages(names)
    if missing:
        problems.append("缺少依赖：{}。".format("、".join(missing)))
    if not problems:
        return
    path = Path(script).resolve()
    root = path.parents[2]  # game/tools/脚本.py 往上两层是仓库根目录
    try:
        shown = path.relative_to(root).as_posix()
    except ValueError:
        shown = path.as_posix()
    command = " ".join(["uv", "run", shown] + sys.argv[1:])
    lines = problems + [
        "这个脚本要用 uv 运行，uv 会自动准备对应的 Python 和依赖。在仓库根目录：",
        "  " + command,
        "没装 uv 的话，安装方法见 " + UV_INSTALL,
    ]
    sys.stderr.write("\n".join(lines) + "\n")
    sys.exit(1)
