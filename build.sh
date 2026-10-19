#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/AI网络守护.app"
python3 - "$ROOT/dist" <<'PY'
import shutil,sys
shutil.rmtree(sys.argv[1], ignore_errors=True)
PY
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>AIGuard</string>
<key>CFBundleIdentifier</key><string>local.jerry.ai-network-guard</string>
<key>CFBundleName</key><string>AI网络守护</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
swiftc "$ROOT/main.swift" -o "$APP/Contents/MacOS/AIGuard" -framework Cocoa
"$APP/Contents/MacOS/AIGuard" --test
codesign --force --sign - "$APP"
echo "已生成：$APP"
