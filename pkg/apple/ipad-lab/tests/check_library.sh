#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../../../.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
xcrun clang -fobjc-arc -Wall -Wextra -Werror -I. \
  pkg/apple/ipad-lab/tests/library_support.m -framework Foundation -o "$work/library-support"
"$work/library-support"
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
# griffin_objc.m imports the Cocoa preamble before its included implementations.
xcrun --sdk iphoneos clang -fsyntax-only -fobjc-arc \
  -target arm64-apple-ios15.0 -isysroot "$sdk" \
  -DHAVE_COCOATOUCH -DHAVE_MENU -DHAVE_RETROARCH_LAB_LIBRARY \
  -I. -Ilibretro-common/include -Ipkg/apple \
  -include ui/drivers/cocoa/cocoa_common.h \
  -Werror=implicit-function-declaration -Werror=objc-method-access \
  ui/drivers/cocoa/RetroArchLabLibrary.m
printf 'Native iOS library screen type-check passed\n'

xcrun --sdk iphoneos clang -fsyntax-only -fobjc-arc \
  -target arm64-apple-ios26.0 -isysroot "$sdk" \
  -DHAVE_COCOATOUCH -DHAVE_MENU -DHAVE_RETROARCH_LAB_LIBRARY -DHAVE_RETROARCH_LAB_STIKJIT \
  -I. -Ilibretro-common/include -Ipkg/apple \
  -include ui/drivers/cocoa/cocoa_common.h \
  -Werror=implicit-function-declaration -Werror=objc-method-access \
  ui/drivers/cocoa/RetroArchLabLibrary.m ui/drivers/cocoa/RetroArchLabJIT.m
