#!/bin/bash
# 一次性签名设置（在 Mac 上运行）：找到 Xcode 里登录的 Apple ID 的团队 ID，写进 Local.xcconfig。
# 之后每次下载新版代码，Xcode 都不用再手动给 OSVIA、OSVIALive 选 Team。
# 用法：bash ios/tools/setup-signing.sh            （自动找）
#       bash ios/tools/setup-signing.sh ABCDE12345  （手动指定团队 ID）
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"   # …/OSVIA-main/ios
TEAM="$1"
if [ -z "$TEAM" ]; then
  TEAM=$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null | grep -Eo 'teamID = "?[A-Z0-9]{10}' | head -1 | grep -Eo '[A-Z0-9]{10}$' || true)
fi
if [ -z "$TEAM" ] && [ -f "$HERE/OSVIA.xcodeproj/project.pbxproj" ]; then
  TEAM=$(grep -Eo 'DEVELOPMENT_TEAM = [A-Z0-9]{10}' "$HERE/OSVIA.xcodeproj/project.pbxproj" | head -1 | grep -Eo '[A-Z0-9]{10}$' || true)
fi
if [ -z "$TEAM" ]; then
  echo "没找到团队 ID。请先在 Xcode 的 Signing & Capabilities 里给 OSVIA 选一次 Team，再运行本脚本；或手动指定：bash setup-signing.sh ABCDE12345"
  exit 1
fi
echo "DEVELOPMENT_TEAM = $TEAM" > "$HERE/Config/Local.xcconfig"
# 再存一份在代码文件夹的上上级（比如 ~/Desktop/TSTZ-M/），下载解压新版本后也自动生效
echo "DEVELOPMENT_TEAM = $TEAM" > "$HERE/../../OSVIA-Local.xcconfig"
# 免去 Xcode 对 mlx-swift-lm 宏的「信任并启用」弹窗
defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES
echo "完成：团队 ID $TEAM 已写入。重新打开 Xcode 即可直接运行。"
