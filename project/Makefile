THEOS_PACKAGE_SCHEME ?= rootless
export THEOS_PACKAGE_SCHEME
ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
FINALPACKAGE = 1
DEBUG = 0
include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = advanish
advanish_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries
advanish_FILES = Runtime.mm ASPUniversalSkip.mm ASPManualSkip.mm ASPAdSurface.mm ASPAdCompletion.mm
advanish_CFLAGS = -fobjc-arc -fblocks
advanish_CCFLAGS = -std=c++11 -fno-rtti -fno-exceptions
advanish_FRAMEWORKS = Foundation UIKit QuartzCore CoreGraphics AVFoundation CoreMedia WebKit
ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
advanish_CFLAGS += -DADSPEED_ROOTLESS=1
endif
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
advanish_CFLAGS += -DADSPEED_ROOTHIDE=1
advanish_LDFLAGS += -lroothide
endif
SUBPROJECTS = settings
include $(THEOS_MAKE_PATH)/library.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

after-stage::
	mkdir -p "$(THEOS_STAGING_DIR)$(THEOS_PACKAGE_INSTALL_PREFIX)/Library/MobileSubstrate/DynamicLibraries"
	cp advanish.plist "$(THEOS_STAGING_DIR)$(THEOS_PACKAGE_INSTALL_PREFIX)/Library/MobileSubstrate/DynamicLibraries/"
