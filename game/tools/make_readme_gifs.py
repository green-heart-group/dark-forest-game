# /// script
# requires-python = ">=3.11"
# ///
"""重新录 README 里的四段动图（build/readme_gifs/*.gif，不进仓库）。画面改了以后跑一次：

    uv run game/tools/make_readme_gifs.py

要装好 Godot（和跑测试时一样找：环境变量 GODOT、godot_console 或 godot）和 ffmpeg。
先由 game/tools/record_gifs.gd 把每一帧存成 PNG（会在屏幕外开一个游戏窗口，大约一分钟），
再用 ffmpeg 拼成 480 像素宽的 GIF。帧放在 build/readme_frames/（不进仓库）。
重录后上传到 GitHub 的 README 演示素材 Issue，再更新 README 的图片链接，见 docs/guides/code.md。
"""

import subprocess
from pathlib import Path

from test import find_godot  # 同一目录下的 test.py

ROOT = Path(__file__).resolve().parents[2]
FRAMES = ROOT / "build" / "readme_frames"
IMAGES = ROOT / "build" / "readme_gifs"

# 帧的目录名：每秒几帧
GIFS = {"explore": 12, "domain": 10, "dimension-strike": 10, "zero-dimension": 10}
# 文件名和帧的目录名不一样的
NAMES = {"domain": "black-domain"}


def main() -> None:
    FRAMES.mkdir(parents=True, exist_ok=True)
    IMAGES.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        [find_godot(), "--path", "game", "--script", "res://tools/record_gifs.gd",
         "--", f"out={FRAMES.as_posix()}"],
        cwd=ROOT, check=True, timeout=600,
    )
    for name, fps in GIFS.items():
        target = IMAGES / f"{NAMES.get(name, name)}.gif"
        # 先按这段画面算一套 128 色的调色板，再用它上色；只有变了的地方重画，文件小一些
        palette = ("scale=480:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];"
                   "[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle")
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(fps), "-i", str(FRAMES / name / "%04d.png"),
             "-vf", palette, "-loop", "0", str(target)],
            check=True,
        )
        print(f"{target.relative_to(ROOT)}：{target.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
