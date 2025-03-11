TARGET := iphone:clang:14.5:14.0
INSTALL_TARGET_PROCESSES = Camera

TWEAK_NAME = CameraDiagnostic

CameraDiagnostic_FILES = DiagnosticTweak.xm DiagnosticHooks.xm Utils/Logger.mm Utils/MetadataExtractor.mm
CameraDiagnostic_CFLAGS = -fobjc-arc
CameraDiagnostic_FRAMEWORKS = UIKit AVFoundation CoreMedia CoreVideo CoreGraphics Photos

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
