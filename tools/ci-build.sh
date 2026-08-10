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

# iPhoneOS16.5 is the newest SDK theos/sdks publishes. The SDK version only governs which
# public API headers exist at compile time, and nothing here uses public API newer than
# that, so pinning it costs us nothing.
SDK_NAME="iPhoneOS16.5.sdk"

# Downloaded straight from the release asset rather than via $THEOS/bin/install-sdk.
# install-sdk resolves the download through api.github.com unauthenticated, and CI
# runners share IPs that are usually over the 60-request/hour anonymous rate limit — it
# fails with "ERROR: api.github.com request failed?!" and takes the build with it.
# /releases/latest/download/<asset> redirects without touching the API at all.
SDK_URL="https://github.com/theos/sdks/releases/latest/download/${SDK_NAME}.tar.xz"

if ! ls "$THEOS"/sdks/iPhoneOS*.sdk >/dev/null 2>&1; then
    echo "==> Installing patched SDK $SDK_NAME (Xcode's SDK has no private frameworks)"
    mkdir -p "$THEOS/sdks"
    curl -fsSL "$SDK_URL" | tar -xJ -C "$THEOS/sdks"
fi

PREFERENCES_STUB="$THEOS/sdks/$SDK_NAME/System/Library/PrivateFrameworks/Preferences.framework/Preferences.tbd"
if [ ! -f "$PREFERENCES_STUB" ]; then
    echo "error: $PREFERENCES_STUB missing — the preference bundle will fail to link" >&2
    exit 1
fi

SDK_PATH=$(ls -d "$THEOS"/sdks/iPhoneOS*.sdk | sort -V | tail -1)
SDK_VERSION=$(basename "$SDK_PATH" .sdk)
SDK_VERSION=${SDK_VERSION#iPhoneOS}

echo "==> Building against patched SDK $SDK_VERSION, deployment target $DEPLOYMENT_TARGET"
# A command-line assignment overrides the Makefile's TARGET.
make package FINALPACKAGE=1 TARGET="iphone:clang:${SDK_VERSION}:${DEPLOYMENT_TARGET}" "$@"

echo "==> Verifying architecture slices"
python3 tools/check-slices.py --require-arm64e packages/*.deb
