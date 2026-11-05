#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../../../.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
xcrun clang -std=c89 -Wall -Wextra -Werror -O2 \
  pkg/apple/ipad-lab/performance/stats_test.c -o "$work/stats"
"$work/stats"
sdk=$(xcrun --sdk iphoneos --show-sdk-path)
xcrun --sdk iphoneos clang -fsyntax-only -fobjc-arc \
  -target arm64-apple-ios26.0 -isysroot "$sdk" \
  -DHAVE_COCOATOUCH -DHAVE_RETROARCH_LAB_STIKJIT -DHAVE_RETROARCH_LAB_LIBRARY \
  -I. -Ilibretro-common/include -Ipkg/apple \
  -Werror=implicit-function-declaration -Werror=objc-method-access \
  ui/drivers/cocoa/RetroArchLabPerformance.m ui/drivers/cocoa/RetroArchLabRPCS3.m
