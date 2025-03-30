TARGET := iphone:clang:latest:14
INSTALL_TARGET_PROCESSES = SpringBoard

THEOS_DEVICE_IP=192.168.0.181

TWEAK_NAME = CameraDiagnostic

CameraDiagnostic_FILES = DiagnosticTweak.xm DiagnosticHooks.xm Utils/Logger.mm Utils/MetadataExtractor.mm
CameraDiagnostic_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
CameraDiagnostic_FRAMEWORKS = UIKit AVFoundation CoreMedia CoreVideo CoreGraphics Photos

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
