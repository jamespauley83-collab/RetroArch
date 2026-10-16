#!/bin/bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(git -C "$HERE" rev-parse --show-toplevel)"
WORK="$ROOT/.armsx2-prototype"
SOURCE="$WORK/source"
ARTIFACTS="$WORK/artifacts"
PIN=e58489d349cdcd635fc6264546087e347c84bf8c
STAGE="${1:-build-probe}"
case "$STAGE" in
    build-probe) PROBE=ON; DEVICE_TEST=OFF ;;
    device-test) PROBE=OFF; DEVICE_TEST=ON ;;
    *) echo 'Expected build-probe or device-test.' >&2; exit 1 ;;
esac

if [ "$(uname -s)" != Darwin ]; then
    echo 'This experiment requires macOS with the iPhoneOS SDK.' >&2
    exit 1
fi
mkdir -p "$ARTIFACTS"
if [ "$(git -C "$SOURCE" rev-parse HEAD)" != "$PIN" ]; then
    echo 'ARMSX2 source does not match the reviewed pin.' >&2
    exit 1
fi
if [ -n "$(git -C "$SOURCE" status --porcelain)" ]; then
    echo 'Expected a fresh ARMSX2 checkout before applying experiment patches.' >&2
    exit 1
fi
for patch in "$HERE"/patches/*.patch; do
    git -C "$SOURCE" apply --check "$patch"
    git -C "$SOURCE" apply "$patch"
done

python3 "$HERE/run_native_tests.py" "$SOURCE" "$ROOT" "$WORK/native-tests"

cd "$SOURCE"
APPLE_PLATFORM=ios APPLE_DEPLOYMENT_TARGET=17.4 \
    bash .github/workflows/scripts/macos/build-dependencies-embedded.sh "$WORK/deps" \
    2>&1 | tee "$WORK/dependencies.log"

cmake -S "$SOURCE" -B "$WORK/build" -G Ninja \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_SYSTEM_PROCESSOR=arm64 \
    -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_SYSROOT=iphoneos \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.4 -DIOS=ON \
    -DCMAKE_PREFIX_PATH="$WORK/deps" -DCMAKE_FIND_ROOT_PATH="$WORK/deps" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_MACOSX_BUNDLE=OFF \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DCMAKE_LIBRARY_OUTPUT_DIRECTORY="$WORK/build/core" \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED=NO \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_DISABLE_PRECOMPILE_HEADERS=ON \
    -DENABLE_LIBRETRO=ON -DENABLE_QT_UI=OFF -DENABLE_SDL_FRONTEND=OFF \
    -DENABLE_TESTS=OFF -DENABLE_RECOMPILER_TEST_HOOKS=OFF \
    -DENABLE_GSRUNNER=OFF -DENABLE_EERUNNER=OFF -DENABLE_VURUNNER=OFF \
    -DENABLE_SETCAP=OFF -DUSE_BACKTRACE=OFF -DX11_API=OFF -DWAYLAND_API=OFF \
    -DUSE_VULKAN=OFF -DUSE_OPENGL=OFF -DDISABLE_ADVANCE_SIMD=TRUE \
    -DARMSX2_EMBED_RESOURCES=ON -DARMSX2_EMBED_PATCHES=OFF \
    -DRETROARCH_LAB_ARMSX2_BRIDGE=ON -DRETROARCH_LAB_ARMSX2_BUILD_PROBE="$PROBE" \
    -DRETROARCH_LAB_ARMSX2_DEVICE_TEST="$DEVICE_TEST" \
    2>&1 | tee "$WORK/configure.log"
cmake --build "$WORK/build" --config Release --target pcsx2-libretro --parallel 4 \
    2>&1 | tee "$WORK/build.log"

BINARY="$WORK/build/core/armsx2_libretro.dylib"
python3 "$HERE/verify.py" "$BINARY" "$ARTIFACTS" "$SOURCE" --stage "$STAGE"
cp "$HERE/README.md" "$ARTIFACTS/README.md"
cp "$SOURCE/COPYING.GPLv3" "$ARTIFACTS/ARMSX2-COPYING.GPLv3"
cp "$SOURCE/deps-build/SHASUMS" "$ARTIFACTS/dependency-SHASUMS"
cp "$HERE"/patches/*.patch "$ARTIFACTS/"
git archive --format=tar HEAD | gzip > "$ARTIFACTS/armsx2-pinned-source.tar.gz"
# Preserve downloaded dependency sources alongside their upstream checksum list.
python3 - "$SOURCE/deps-build" "$ARTIFACTS/dependency-sources.tar.gz" <<'PY'
import pathlib, sys, tarfile
source = pathlib.Path(sys.argv[1])
with tarfile.open(sys.argv[2], 'w:gz') as archive:
    for line in (source / 'SHASUMS').read_text().splitlines():
        name = line.split()[-1]
        archive.add(source / name, arcname=name)
PY
