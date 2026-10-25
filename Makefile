THEOS_PACKAGE_SCHEME ?= rootless
export THEOS_PACKAGE_SCHEME
ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0
DEBUG = 0
FINALPACKAGE = 1
FOR_RELEASE = 1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = advanish
advanish_FILES = Tweak.xm ASPUniversalSkip.mm ASPManualSkip.mm
advanish_CFLAGS = -fobjc-arc
advanish_CCFLAGS = -std=c++11 -fno-rtti -fno-exceptions -DNDEBUG
advanish_FRAMEWORKS = UIKit QuartzCore CoreGraphics AVFoundation CoreMedia WebKit
SUBPROJECTS = adspeedprefs

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
