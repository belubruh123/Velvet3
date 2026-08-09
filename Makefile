export THEOS_PACKAGE_SCHEME ?= rootless

# Architecture selection.
#
# A12+ devices run SpringBoard as arm64e, so a release build needs an arm64e slice.
# BUT: Theos on Linux can only emit the *pre-iOS-14* arm64e ABI (Mach-O cpusubtype
# 0x00000002, no CPU_SUBTYPE_PTRAUTH_ABI bit) because the new ABI exists only in
# Apple's closed Xcode clang. iOS 15+ refuses to load old-ABI arm64e dylibs, and
# dyld *prefers* the arm64e slice over the arm64 one — so including a Linux-built
# arm64e slice breaks the tweak outright.
#
# Therefore: Linux builds are arm64-only (for compile-checking and for testing
# whether arm64 injection works on the device), and release builds are produced on
# macOS via .github/workflows/build.yml, where both slices are correct.
ifeq ($(shell uname -s),Darwin)
ARCHS := arm64 arm64e
else
ARCHS := arm64
endif

TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Velvet3

Velvet3_FILES = src/Tweak.x src/VLTRuntime.m src/UIColor+Velvet.m src/Velvet3PrefsManager.m src/ColorDetection.m src/Velvet3Colorizer.m
Velvet3_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += preferences
include $(THEOS_MAKE_PATH)/aggregate.mk
