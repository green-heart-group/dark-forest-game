# 导出和发布

怎么在本地导出游戏，以及 GitHub 自动发布出来的是什么。最常用的两条命令在仓库首页 [README「发布」](../../README.md#发布)；
导出设置和工具的分工见 [代码结构「导出」](code.md#导出)，Godot 导出的原理见 [Godot 入门](godot.md#导出和分发)。

## GitHub 自动发布

推送 `v` 开头的标签（如 `v0.1.0`）后，GitHub 自动跑测试，导出 Windows、macOS 和网页版：

- exe 打包挂到 [Releases](https://github.com/green-heart-group/dark-forest-game/releases)：
  `dark-forest-windows.zip` 是普通版，`dark-forest-windows-dev.zip` 是一打开就有调试面板的开发者版。
- Mac 版也挂到 Releases：Intel 芯片选 `dark-forest-macos-intel.zip`，Apple Silicon（M 系列）选 `dark-forest-macos-apple-silicon.zip`。
- 网页版发到 <https://green-heart-group.github.io/dark-forest-game/>；
  带调试面板的网页版在 <https://green-heart-group.github.io/dark-forest-game/dev/>（见 [调试模式](debug-tools.md#怎么打开)）。
- 标签里带「-」（如 `v0.1.0-test`）的标成预发布。步骤写在 [`.github/workflows/release.yml`](../../.github/workflows/release.yml)。

也可以在 GitHub Actions 的「发布」页面手动选择分支运行：只检查和导出，不创建 Release 或部署网页；完成后在运行页面下载产物。
CI 导出到 `build/release/`，发布前检查测试生成的文档和数值声明是否已提交，全部导出成功才上传。
Release 同时附上玩家用的芯片选择、安装入口、普通版与调试版区别及签名状态；不会把临时签名标为已公证。

## 本地导出

先安装好 uv、Godot 4.7.2，并在 Godot「编辑器 → 管理导出模板」里安装同版本模板。
Windows、macOS、Linux 都在仓库根目录用下面的命令；GitHub 发布也调用同一个工具。
工具自动同步数值声明、准备网页字体、导入资源、创建输出目录、导出和打包，失败时停止并返回非零退出码。

```bash
# 导出全部：网页版、Windows 普通版和开发者版、macOS
uv run game/tools/export.py

# 也可以只导出其中一版
uv run game/tools/export.py web
uv run game/tools/export.py windows
uv run game/tools/export.py windows-dev
uv run game/tools/export.py macos

# Mac 也可以只导出一种芯片
uv run game/tools/export.py macos-intel
uv run game/tools/export.py macos-apple-silicon

# 指定输出目录（相对当前工作目录）；查看所有参数
uv run game/tools/export.py --out-dir build/release
uv run game/tools/export.py --help
```

## 产物和注意事项

- 默认产物在 `build/`：两个 exe 和对应的 Windows ZIP；网页版在 `build/web/`，发布时上传整个目录。网页版同时生成 `/dev/` 开发者入口。
- Mac 版在 `build/` 中分别生成 Intel 和 Apple Silicon 两个 ZIP，在对应的 Mac 上解压后打开其中的 `.app`。
  导出它需要安装同版本的官方 `macos.zip` 模板；工具自动提取两个芯片各自的模板，再由 Godot 签名和导出 ZIP，以保留程序的执行权限。
- 在 Godot 编辑器里手动导出 Mac 版前，先运行 `uv run game/tools/make_macos_templates.py` 准备模板；生成文件位于 `build/macos_templates/`，不进仓库。
- Mac 版使用内置临时签名，没有做 Apple 公证，首次打开可能需要在系统安全设置中允许运行，
  见 [Godot 的 macOS 分发说明](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_macos.html#code-signing-and-notarization)。
- 第一次导出网页版需要联网下载字体，之后复用 `build/font_cache/` 的下载缓存。
- Godot 的查找顺序是环境变量 `GODOT`、`godot_console`、`godot`；也可以用 `--godot "可执行文件路径"` 指定，路径有空格时加引号。
- 每次导出都先在临时目录检查产物，通过后才复制到输出目录，避免上次的文件掩盖本次失败。
- 导出工具不运行游戏测试，发布前仍需按 [README「测试和平衡模拟」](../../README.md#测试和平衡模拟)验证。

## Mac 的正式签名和公证

当前自动发布仍生成临时签名包。取得 Apple Developer ID Application 证书后，在 Mac 钥匙串中安装证书及私钥，并安装 Xcode 命令行工具。先用 `security find-identity -v -p codesigning` 确认有效身份。

按 [Apple 的公证流程](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)配置凭据：运行 `xcrun notarytool store-credentials dark-forest-notary`，在终端交互提示中填写，凭据保存在钥匙串。不要把密码、私钥或证书密码写入仓库、导出预设或命令历史。

先用上面的本地导出命令生成两个 Mac ZIP，再分别运行：

```bash
uv run game/tools/sign_macos.py build/dark-forest-macos-apple-silicon.zip \
  --identity 'Developer ID Application: 证书中的完整名称 (TEAMID)' \
  --keychain-profile dark-forest-notary --out-dir build/signed

uv run game/tools/sign_macos.py build/dark-forest-macos-intel.zip \
  --identity 'Developer ID Application: 证书中的完整名称 (TEAMID)' \
  --keychain-profile dark-forest-notary --out-dir build/signed
```

工具只签名副本：启用 hardened runtime 和时间戳、验证签名、提交 Apple 并等待 Accepted、附加并验证公证票据、通过 Gatekeeper 检查，最后用 `ditto` 重新打包以保留权限。只有全部通过才生成输出；原包不变，已有签名包也不会被覆盖。当前游戏没有原生插件；以后加入嵌套框架或辅助程序时须先补内部签名步骤。

如果公证等待超时，Apple 可能仍在处理。先根据工具输出的提交 ID，用 `xcrun notarytool info ID --keychain-profile dark-forest-notary` 查询，失败用 `log` 查看详情，避免盲目重复提交。

发布者在另一台 Mac 下载并首次启动 `build/signed/` 中的最终 ZIP，验证后再上传并在发布说明中改为已公证。此工具不会创建 Release、上传 GitHub 或修改当前自动发布流程；缺少 Apple 凭据时只能验证工具逻辑，不能宣称签名、公证已完成。原理和权限说明见 [Godot 的 macOS 分发指南](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_macos.html#code-signing-and-notarization)。
