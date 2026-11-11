#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="${SMARTINFO_BUILD_DIR:-$ROOT/Build}"
APP="$OUT/SMART Info Native.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$OUT/module-cache"
SDK="$(xcrun --show-sdk-path)"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx13.0 -sdk "$SDK" -module-cache-path "$OUT/module-cache" -parse-as-library "$ROOT/Sources/SMARTCore.swift" "$ROOT/Sources/SMARTDetails.swift" "$ROOT/Sources/SMARTInfoApp.swift" -o "$APP/Contents/MacOS/SMARTInfoNative" -framework SwiftUI -framework AppKit
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
xcrun swiftc -swift-version 5 -target arm64-apple-macosx13.0 -sdk "$SDK" -module-cache-path "$OUT/module-cache" "$ROOT/Resources/MakeIcon.swift" -o "$OUT/MakeIcon" -framework AppKit
"$OUT/MakeIcon" "$OUT/AppIcon.iconset"
iconutil -c icns "$OUT/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
if [[ -x "$ROOT/Engine/smartctl" ]]; then
    cp "$ROOT/Engine/smartctl" "$APP/Contents/Resources/smartctl"
    if [[ -f "$ROOT/Engine/COPYING" ]]; then cp "$ROOT/Engine/COPYING" "$APP/Contents/Resources/smartmontools-COPYING.txt"; fi
    if [[ -f "$ROOT/Engine/drivedb.h" ]]; then cp "$ROOT/Engine/drivedb.h" "$APP/Contents/Resources/drivedb.h"; fi
    codesign --force --sign - "$APP/Contents/Resources/smartctl"
fi
codesign --force --sign - "$APP"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx13.0 -sdk "$SDK" -module-cache-path "$OUT/module-cache" -parse-as-library "$ROOT/Sources/SMARTCore.swift" "$ROOT/Sources/SMARTDetails.swift" "$ROOT/Tests/SMARTTests.swift" -o "$OUT/SMARTTests"
"$OUT/SMARTTests"
file "$APP/Contents/MacOS/SMARTInfoNative"
codesign --verify --deep --strict "$APP"
