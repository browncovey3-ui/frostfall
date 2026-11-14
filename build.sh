#!/bin/bash
# Builds build/Frostfall.app with the Swift compiler (Xcode or the Command Line Tools).
# ARCHS="arm64 x86_64" bash build.sh makes a universal app; the default is the architecture of this Mac.
set -euo pipefail
cd "$(dirname "$0")"

ARCHS="${ARCHS:-$(uname -m)}"
APP="build/Frostfall.app"

rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

BINARIES=()
for arch in $ARCHS; do
    echo "Compiling for $arch"
    swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" Sources/*.swift -o "build/Frostfall-$arch"
    BINARIES+=("build/Frostfall-$arch")
done

lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/Frostfall"
rm -f "${BINARIES[@]}"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Built $APP"
echo "Run it with: open $APP"
