ARCHS = arm64 arm64e
TARGET := iphone:clang:14.5:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CameraDiagnostic

$(TWEAK_NAME)_FILES = Tweak.xm
$(TWEAK_NAME)_CFLAGS = -fobjc-arc
$(TWEAK_NAME)_FRAMEWORKS = UIKit AVFoundation CoreMedia CoreVideo QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
