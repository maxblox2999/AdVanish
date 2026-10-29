ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = adspeedprefs
adspeedprefs_FILES = ASPListBase.m ASPRootListController.m ASPAppListController.m
adspeedprefs_INSTALL_PATH = /Library/PreferenceBundles
adspeedprefs_FRAMEWORKS = UIKit
adspeedprefs_PRIVATE_FRAMEWORKS = Preferences
adspeedprefs_CFLAGS = -fobjc-arc
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
adspeedprefs_CFLAGS += -DADSPEED_ROOTHIDE=1
adspeedprefs_LDFLAGS += -lroothide
endif

include $(THEOS_MAKE_PATH)/bundle.mk
