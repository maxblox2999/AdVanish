ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:15.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = adspeedprefs
adspeedprefs_FILES = ASPListBase.m ASPRootListController.m ASPAppListController.m
adspeedprefs_INSTALL_PATH = /Library/PreferenceBundles
adspeedprefs_FRAMEWORKS = UIKit
adspeedprefs_PRIVATE_FRAMEWORKS = Preferences
adspeedprefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
