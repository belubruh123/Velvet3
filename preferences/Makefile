# Was SDK 14.5 with a 15.0 deployment target — an SDK older than what it deploys to.
TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = Preferences

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = Velvet2

Velvet2_FILES = $(wildcard *.m CustomCells/*.m ../src/VLTRuntime.m ../src/Velvet2PrefsManager.m ../src/UIColor+Velvet.m ../src/ColorDetection.m ../src/Velvet2Colorizer.m)
Velvet2_FRAMEWORKS = UIKit
Velvet2_PRIVATE_FRAMEWORKS = Preferences
# NOT $(THEOS_PACKAGE_INSTALL_PREFIX)/Library/... — under THEOS_PACKAGE_SCHEME=rootless
# Theos already applies the /var/jb prefix, so spelling it out again installed the
# bundle to /var/jb/var/jb/Library/PreferenceBundles and Settings never found it.
Velvet2_INSTALL_PATH = /Library/PreferenceBundles
Velvet2_CFLAGS = -fobjc-arc -DPACKAGE_VERSION='@"$(THEOS_PACKAGE_BASE_VERSION)"'

include $(THEOS_MAKE_PATH)/bundle.mk
