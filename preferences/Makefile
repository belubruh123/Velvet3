# Upstream pinned SDK 14.5 here while deploying to 15.0 — an SDK older than the
# deployment target. Track the tweak's own TARGET instead (see ../Makefile for the
# arm64e ABI note).
ifeq ($(shell uname -s),Darwin)
ARCHS := arm64 arm64e
else
ARCHS := arm64
endif

TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = Preferences

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = Velvet3

Velvet3_FILES = $(wildcard *.m CustomCells/*.m ../src/VLTRuntime.m ../src/Velvet3PrefsManager.m ../src/UIColor+Velvet.m ../src/ColorDetection.m ../src/Velvet3Colorizer.m)
Velvet3_FRAMEWORKS = UIKit
Velvet3_PRIVATE_FRAMEWORKS = Preferences
# NOT $(THEOS_PACKAGE_INSTALL_PREFIX)/Library/... — under THEOS_PACKAGE_SCHEME=rootless
# Theos already prefixes install paths with /var/jb, so spelling it out again produced
# /var/jb/var/jb/Library/PreferenceBundles and a settings pane that never appeared.
Velvet3_INSTALL_PATH = /Library/PreferenceBundles
Velvet3_CFLAGS = -fobjc-arc -DPACKAGE_VERSION='@"$(THEOS_PACKAGE_BASE_VERSION)"'

include $(THEOS_MAKE_PATH)/bundle.mk
