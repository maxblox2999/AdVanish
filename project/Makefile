THEOS_PACKAGE_SCHEME ?= rootless
export THEOS_PACKAGE_SCHEME
ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
FINALPACKAGE = 1
DEBUG = 0
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = advanish
advanish_INSTALL_PATH = /Library/MobileSubstrate/DynamicLibraries
advanish_FILES = Hooks.xm Runtime.mm ASPTimers.mm ASPUniversalSkip.mm ASPManualSkip.mm ASPAdSurface.mm ASPAdCompletion.mm
advanish_LOGOS_DEFAULT_GENERATOR = MobileSubstrate
advanish_CFLAGS = -fobjc-arc -fblocks
ifeq ($(AVN_CLOSE_DIAGNOSTICS),1)
advanish_CFLAGS += -DAVN_CLOSE_DIAGNOSTICS=1
endif
advanish_CCFLAGS = -std=c++11 -fno-rtti -fno-exceptions
advanish_FRAMEWORKS = Foundation UIKit QuartzCore CoreGraphics AVFoundation CoreMedia WebKit StoreKit
ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
advanish_CFLAGS += -DADSPEED_ROOTLESS=1
endif
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
advanish_CFLAGS += -DADSPEED_ROOTHIDE=1
advanish_LDFLAGS += -lroothide
endif
SUBPROJECTS = settings
include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

