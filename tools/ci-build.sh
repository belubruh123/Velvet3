#!/usr/bin/env bash
#
# Release build, run on a macOS runner. See .github/workflows/build.yml.
#
# Two things this handles that a bare `make package` does not:
#
# 1. Xcode's iPhoneOS SDK contains only *public* frameworks. A preference bundle links
#    against Preferences.framework, which is private, so linking against Xcode's SDK
#    fails with "ld: framework 'Preferences' not found". Theos's patched SDKs ship stubs
#    for private frameworks — install one and pin the build to it. Pinning matters:
#    the Makefile asks for `latest`, and on a macOS runner that resolves to Xcode's own
#    (newer) SDK, straight back into the same error.
#
# 2. Verifying the architecture slices before anything is published. A package whose
#    arm64e slice carries the pre-iOS-14 ABI will not load on iOS 15+, and because dyld
#    prefers the arm64e slice it will not fall back to arm64 either — it just silently
#    fails to inject. Better to fail the build.
#
# The SDK version only governs which *public* API headers are available at compile time.
# Everything this tweak touches in SpringBoard is private and declared in headers/, so
# building against an older SDK is fine — the binary still runs on iOS 18.

set -euo pipefail

: "${THEOS:?THEOS must be set}"

DEPLOYMENT_TARGET="15.0"

if ! ls "$THEOS"/sdks/iPhoneOS*.sdk >/dev/null 2>&1; then
    echo "==> Installing Theos patched SDK (Xcode's SDK has no private frameworks)"
    "$THEOS/bin/install-sdk" latest
fi

SDK_PATH=$(ls -d "$THEOS"/sdks/iPhoneOS*.sdk | sort -V | tail -1)
SDK_VERSION=$(basename "$SDK_PATH" .sdk)
SDK_VERSION=${SDK_VERSION#iPhoneOS}

echo "==> Building against patched SDK $SDK_VERSION, deployment target $DEPLOYMENT_TARGET"
test -d "$SDK_PATH/System/Library/PrivateFrameworks/Preferences.framework" \
    || echo "warning: Preferences.framework stub not found in $SDK_PATH" >&2

# A command-line assignment overrides the Makefile's TARGET.
make package FINALPACKAGE=1 TARGET="iphone:clang:${SDK_VERSION}:${DEPLOYMENT_TARGET}" "$@"

echo "==> Verifying architecture slices"
python3 tools/check-slices.py --require-arm64e packages/*.deb
