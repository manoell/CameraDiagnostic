TARGET := iphone:clang:14.5:14.0
INSTALL_TARGET_PROCESSES = SpringBoard Camera MobileSlideShow Telegram Instagram WhatsApp

TWEAK_NAME = CameraDiagnostic

CameraDiagnostic_FILES = Tweak.xm CameraHooks.xm PhotoHooks.xm PreviewHooks.xm UIHooks.xm DiagnosticCollector.m logger.m
CameraDiagnostic_CFLAGS = -fobjc-arc
CameraDiagnostic_FRAMEWORKS = UIKit AVFoundation CoreMedia CoreVideo CoreGraphics Photos

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk