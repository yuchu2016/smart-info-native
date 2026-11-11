#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$ROOT/Engine" "$ROOT/EngineWork"
if [[ ! -f "$ROOT/Engine/smartmontools-7.5.tar.gz" ]]; then
    curl -fL --connect-timeout 15 --max-time 90 "https://downloads.sourceforge.net/project/smartmontools/smartmontools/7.5/smartmontools-7.5.tar.gz" -o "$ROOT/Engine/smartmontools-7.5.tar.gz"
fi
if [[ ! -d "$ROOT/EngineWork/smartmontools-7.5" ]]; then
    tar -xzf "$ROOT/Engine/smartmontools-7.5.tar.gz" -C "$ROOT/EngineWork"
fi
cd "$ROOT/EngineWork/smartmontools-7.5"
export SDKROOT="$(xcrun --show-sdk-path)"
./configure --prefix="$ROOT/EngineWork/local" --with-drivedbdir=no --with-update-smart-drivedb=no --without-libcap-ng --without-libsystemd CXX="$(xcrun --find clang++)" CC="$(xcrun --find clang)" CXXFLAGS="-O2 -arch arm64 -mmacosx-version-min=13.0" CFLAGS="-O2 -arch arm64 -mmacosx-version-min=13.0" LDFLAGS="-arch arm64 -mmacosx-version-min=13.0"
make -j4 smartctl
cp smartctl "$ROOT/Engine/smartctl"
cp COPYING "$ROOT/Engine/COPYING"
codesign --force --sign - "$ROOT/Engine/smartctl"
file "$ROOT/Engine/smartctl"
otool -L "$ROOT/Engine/smartctl"
"$ROOT/Engine/smartctl" --version
