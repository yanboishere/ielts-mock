#!/bin/zsh
# Builds 雅思模考.app (release) into ./build and optionally installs it to /Applications.
#   scripts/build_app.sh            build only
#   scripts/build_app.sh --install  build and copy to /Applications
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
APP="$ROOT/build/雅思模考.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/IELTSMock"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/IELTSMock"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# speech.cpp engine for the Speaking test (scripts/build_speech.sh builds it)
if [[ -x "$ROOT/Vendor/speech/speech" ]]; then
  mkdir -p "$APP/Contents/Resources/speech"
  cp "$ROOT/Vendor/speech/speech" "$ROOT"/Vendor/speech/LICENSE-* "$APP/Contents/Resources/speech/"
else
  echo "warning: Vendor/speech/speech missing — run scripts/build_speech.sh (the Speaking test needs it)"
fi
VERSION=$(cat "$ROOT/VERSION" 2>/dev/null || echo "1.0.0")
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>雅思模考</string>
  <key>CFBundleDisplayName</key><string>雅思模考</string>
  <key>CFBundleIdentifier</key><string>local.ieltsmock.app</string>
  <key>CFBundleExecutable</key><string>IELTSMock</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>口语考试需要录下你的回答，录音只保存在本机，用于本地语音识别和回放。</string>
  <key>NSHumanReadableCopyright</key><string>Personal study tool. Cambridge IELTS content © Cambridge University Press &amp; Assessment.</string>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$APP"
echo "Built: $APP"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf "/Applications/雅思模考.app"
  cp -R "$APP" "/Applications/雅思模考.app"
  echo "Installed: /Applications/雅思模考.app"
fi
