# /// script
# requires-python = ">=3.11"
# dependencies = ["fonttools", "brotli"]
# ///
"""做网页版要带的字体：网页里用不了电脑上装的字体（微软雅黑等），中文和 emoji 会变成方框。

下载思源黑体（Noto Sans SC）、Noto Color Emoji 和 Noto Sans Math（箭头、▬ 这类符号），
只留下 game/ 里文字用到的字，存到 game/view/web_fonts/（不进仓库）。
导出网页版之前跑一次（GitHub 上发布时会自动跑）：

    uv run game/tools/make_web_fonts.py

哪个字三种字体里都没有，会列出来（网页上会显示成方框）。
三种字体都是 SIL Open Font License，可以随游戏一起发。
"""

import urllib.request
from pathlib import Path

from fontTools import subset

GAME = Path(__file__).resolve().parents[1]
OUT = GAME / "view" / "web_fonts"
CACHE = GAME.parent / "build" / "font_cache"

# 按顺序找字：前面的字体没有的字才用后面的。文件名和 window_settings.gd 的 WEB_FONTS 对应。
FONTS = {
    "cjk.otf": "https://github.com/notofonts/noto-cjk/raw/Sans2.004/Sans/SubsetOTF/SC/NotoSansSC-Regular.otf",
    "emoji.ttf": "https://github.com/googlefonts/noto-emoji/raw/v2026-09-24-unicode18_0/2D/fonts/NotoColorEmoji.ttf",
    "symbols.ttf": "https://github.com/google/fonts/raw/dbd1ab6e65dc59bcda3ca8de9fd372f58f98e0af/ofl/notosansmath/NotoSansMath-Regular.ttf",
}

# 从这些文件里收集用到的字
TEXT_SUFFIXES = {".gd", ".tscn", ".tres", ".cfg", ".md"}
# 组合 emoji 要用的连接符和「用彩色显示」记号，本身不显示
JOINERS = "‍️"


def used_text() -> str:
    chars = {chr(c) for c in range(0x20, 0x7F)}  # 英文字母、数字和符号全留着（输入种子、坐标等）
    for path in GAME.rglob("*"):
        if path.suffix in TEXT_SUFFIXES and ".godot" not in path.parts:
            chars.update(path.read_text(encoding="utf-8"))
    chars.update(JOINERS)
    return "".join(sorted(c for c in chars if c >= " "))


def download(name: str, url: str) -> Path:
    path = CACHE / name
    if not path.exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        print(f"下载 {url}")
        urllib.request.urlretrieve(url, path)
    return path


def main() -> None:
    text = used_text()
    missing = set(text) - set(JOINERS)
    OUT.mkdir(parents=True, exist_ok=True)
    for name, url in FONTS.items():
        options = subset.Options()
        options.layout_features = ["*"]  # 留着排版规则（emoji 组合要用）
        font = subset.load_font(download(name, url), options)
        missing -= {chr(c) for c in font.getBestCmap()}
        subsetter = subset.Subsetter(options)
        subsetter.populate(text=text)
        subsetter.subset(font)
        target = OUT / name
        subset.save_font(font, target, options)
        print(f"{target.relative_to(GAME.parent)}：{target.stat().st_size // 1024} KB")
    print(f"共 {len(text)} 个字")
    if missing:
        print("这些字哪种字体都没有，网页上会显示成方框：")
        for ch in sorted(missing):
            print(f"  U+{ord(ch):04X} {ch}")


if __name__ == "__main__":
    main()
