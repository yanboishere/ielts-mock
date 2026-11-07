#!/bin/zsh
# Builds a self-contained 雅思模考.app (question bank bundled in Contents/Resources/Bank) and packs it into
# build/雅思模考-<version>.dmg with an /Applications shortcut.
#   scripts/make_dmg.sh [BANK_DIR]     (default: ~/Library/Application Support/IELTSMock/Bank)
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
BANK="${1:-$HOME/Library/Application Support/IELTSMock/Bank}"
VERSION=$(cat VERSION 2>/dev/null || echo "1.0.0")
APP="$ROOT/build/雅思模考.app"
STAGE="$ROOT/build/dmg-stage"
DMG="$ROOT/build/雅思模考-$VERSION.dmg"

[[ -d "$BANK/exams" ]] || { echo "no bank at $BANK"; exit 1; }
scripts/build_app.sh >/dev/null
echo "bundling bank from $BANK"
rm -rf "$APP/Contents/Resources/Bank"
mkdir -p "$APP/Contents/Resources/Bank"
for d in exams images audio pages; do
  [[ -d "$BANK/$d" ]] && cp -cR "$BANK/$d" "$APP/Contents/Resources/Bank/" 2>/dev/null || cp -R "$BANK/$d" "$APP/Contents/Resources/Bank/"
done
codesign --force --deep --sign - "$APP"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -cR "$APP" "$STAGE/" 2>/dev/null || cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/安装说明.txt" <<TXT
把「雅思模考」拖到「Applications（应用程序）」即可。

首次打开：这是本地自签名的 App，macOS 可能提示"无法验证开发者"。
请在 Finder 中右键点 App →「打开」→ 再点「打开」；或到「系统设置 › 隐私与安全性」点「仍要打开」。

题库（剑桥雅思 4–18 学术类，共 60 套，含听力音频）已内置在 App 中。
练习记录、AI Key 等个人数据保存在 ~/Library/Application Support/IELTSMock 和钥匙串里，覆盖安装新版本不会丢失。
仅供个人学习使用。Cambridge IELTS 内容版权归 Cambridge University Press & Assessment 所有。
TXT
# makehybrid + convert build the image without mounting a scratch volume under /Volumes
# (which `hdiutil create -srcfolder` needs and sandboxed shells refuse).
RAW="$ROOT/build/dmg-raw.dmg"
rm -f "$RAW" "$DMG"
hdiutil makehybrid -hfs -hfs-volume-name "雅思模考" -o "$RAW" "$STAGE" >/dev/null
hdiutil convert "$RAW" -format ULMO -o "$DMG" >/dev/null
rm -rf "$STAGE" "$RAW"
ls -lh "$DMG"
