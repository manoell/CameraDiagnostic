ARCHS = arm64 arm64e
TARGET := iphone:clang:14.5:14.0
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CameraDiagnostic
$(TWEAK_NAME)_FILES = Tweak.xm logger.m
$(TWEAK_NAME)_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
$(TWEAK_NAME)_FRAMEWORKS = UIKit AVFoundation CoreMedia CoreVideo QuartzCore Metal SceneKit ARKit
$(TWEAK_NAME)_PRIVATE_FRAMEWORKS = MediaToolbox CameraKit
$(TWEAK_NAME)_LOGOS_DEFAULT_GENERATOR = internal

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
