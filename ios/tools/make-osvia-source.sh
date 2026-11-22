#!/bin/bash
# Mac usage: bash ios/tools/make-osvia-source.sh /path/to/OSVIA.ipa
# The IPA must be the one published as release OSVIA-<build> (CFBundleVersion).
# Writes OSVIA-source.json at the repo root from the real IPA.
set -euo pipefail
IPA="$1"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
REPO="TSTZ-M/OSVIA"
TMP="$(mktemp -d)"
unzip -p "$IPA" 'Payload/OSVIA.app/Info.plist' > "$TMP/Info.plist"
BID=$(plutil -extract CFBundleIdentifier raw "$TMP/Info.plist")
test "$BID" = "com.Hao-Yi-Miao.TSTZ-Agent"
VER=$(plutil -extract CFBundleShortVersionString raw "$TMP/Info.plist")
BUILD=$(plutil -extract CFBundleVersion raw "$TMP/Info.plist")
SIZE=$(stat -f%z "$IPA")
DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
BASE="https://github.com/$REPO/releases/download/OSVIA-$BUILD"
# 下载地址：优先用环境变量 OSVIA_IPA_URL（CI 已逐字节校验过的镜像地址），否则回退到 Release
URL="${OSVIA_IPA_URL:-$BASE/OSVIA.ipa}"
# 更新说明：SideStore 的「更新」卡片会显示它，缺了会显示成 nil。环境变量 OSVIA_NOTES 由 CI 传入（取最近一次提交标题）
NOTES_RAW="${OSVIA_NOTES:-OSVIA 功能与稳定性更新}"
NOTES=$(printf '%s' "$NOTES_RAW" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()[:300], ensure_ascii=False))')
ICON="https://raw.githubusercontent.com/$REPO/main/ios/Sources/Assets.xcassets/AppIcon.appiconset/icon.png"
cat > "$ROOT/OSVIA-source.json" <<EOF
{
  "name": "OSVIA",
  "identifier": "OSVIA",
  "subtitle": "OSVIA unsigned IPA for SideStore",
  "nsfw": false,
  "apps": [
    {
      "name": "OSVIA",
      "bundleIdentifier": "com.Hao-Yi-Miao.TSTZ-Agent",
      "developerName": "OSVIA",
      "localizedDescription": "OSVIA iOS app. Unsigned IPA, signed on the device by SideStore.",
      "iconURL": "$ICON",
      "version": "$VER",
      "versionDate": "$DATE",
      "versionDescription": $NOTES,
      "downloadURL": "$URL",
      "size": $SIZE,
      "versions": [
        {
          "version": "$VER",
          "buildVersion": "$BUILD",
          "date": "$DATE",
          "localizedDescription": $NOTES,
          "downloadURL": "$URL",
          "size": $SIZE,
          "minOSVersion": "26.0"
        }
      ],
      "appPermissions": { "entitlements": [], "privacy": {} }
    }
  ],
  "news": []
}
EOF
rm -rf "$TMP"
echo "wrote $ROOT/OSVIA-source.json (version $VER, build $BUILD, size $SIZE)"
