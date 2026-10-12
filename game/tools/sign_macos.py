# /// script
# requires-python = ">=3.11"
# dependencies = []
# ///
"""在 Mac 上为 export.py 生成的 ZIP 签名、公证并附加票据；凭据只从钥匙串读取。"""

import argparse
import json
import stat
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

from export import MAC_ARCHITECTURES, ROOT, TARGETS, check_macos_zip


def run(command: list[str]) -> str:
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            encoding="utf-8", errors="replace")
    print(result.stdout, end="", flush=True)
    if result.returncode:
        raise RuntimeError(f"{command[0]} 失败（退出码 {result.returncode}），未生成发布包。")
    return result.stdout


def sign(package: Path, output: Path, identity: str, profile: str) -> Path:
    if sys.platform != "darwin":
        raise RuntimeError("签名和公证须在安装 Xcode 命令行工具的 Mac 上运行。")
    package, output = package.resolve(), output.resolve()
    architectures = {TARGETS[target][1]: cpu for target, cpu in MAC_ARCHITECTURES.items()}
    if package.name not in architectures:
        raise RuntimeError("请选择 export.py 生成的 dark-forest-macos-intel.zip 或 dark-forest-macos-apple-silicon.zip。")
    destination = output / package.name
    if destination == package or destination.exists():
        raise RuntimeError("输出不能覆盖原包或已有签名包，请选择另一个输出目录。")
    check_macos_zip(package, architectures[package.name])
    # 当前项目是单个可执行文件，没有原生插件或嵌套代码。拒绝不属于这个格式的包。
    with zipfile.ZipFile(package) as archive:
        for entry in archive.infolist():
            path = PurePosixPath(entry.filename)
            if path.is_absolute() or ".." in path.parts or path.parts[0] != "dark-forest.app" \
                    or stat.S_ISLNK(entry.external_attr >> 16):
                raise RuntimeError("ZIP 必须是导出工具生成的独立 dark-forest.app。")
    if not identity.startswith("Developer ID Application:") or not profile.strip():
        raise RuntimeError("需要完整的 Developer ID Application 身份和公证钥匙串配置名。")
    identities = run(["security", "find-identity", "-v", "-p", "codesigning"])
    if f'"{identity}"' not in identities:
        raise RuntimeError("钥匙串里没有指定的有效 Developer ID Application 身份。")
    run(["xcrun", "--find", "notarytool"])
    run(["xcrun", "--find", "stapler"])
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".sign-", dir=output) as temp:
        staging = Path(temp)
        run(["ditto", "-x", "-k", str(package), str(staging)])
        app = staging / "dark-forest.app"
        # 给未来的原生扩展留一个明确错误，不能漏签内部代码后继续发布。
        if list((app / "Contents/Frameworks").glob("*")) or list((app / "Contents/Helpers").glob("*")):
            raise RuntimeError("包含嵌套代码；请先为内部框架或辅助程序增加签名步骤。")
        run(["codesign", "--force", "--options", "runtime", "--timestamp", "--sign", identity, str(app)])
        run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)])
        submitted = staging / "submission.zip"
        run(["ditto", "-c", "-k", "--keepParent", str(app), str(submitted)])
        result = json.loads(run(["xcrun", "notarytool", "submit", str(submitted),
                                 "--keychain-profile", profile, "--wait", "--timeout", "30m",
                                 "--output-format", "json"]))
        if result.get("status") != "Accepted":
            raise RuntimeError(f"Apple 未接受公证：{result.get('status')}，提交 ID：{result.get('id')}。")
        run(["xcrun", "stapler", "staple", str(app)])
        run(["xcrun", "stapler", "validate", str(app)])
        run(["codesign", "--verify", "--deep", "--strict", str(app)])
        run(["spctl", "--assess", "--type", "execute", "--verbose=2", str(app)])
        final = staging / package.name
        run(["ditto", "-c", "-k", "--keepParent", str(app), str(final)])
        check_macos_zip(final, architectures[package.name])
        final.replace(destination)
    return destination


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path, help="export.py 生成的 Mac ZIP")
    parser.add_argument("--identity", required=True, help="Developer ID Application 证书完整名称")
    parser.add_argument("--keychain-profile", required=True, help="notarytool store-credentials 保存的配置名")
    parser.add_argument("--out-dir", type=Path, default=ROOT / "build/signed", help="新包输出目录")
    args = parser.parse_args()
    try:
        destination = sign(args.package, args.out_dir, args.identity, args.keychain_profile)
    except (OSError, RuntimeError, ValueError, zipfile.BadZipFile) as error:
        print(f"签名发布包失败：{error}", file=sys.stderr)
        return 1
    print(f"已签名、公证并验证：{destination}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
