TARGET := iphone:clang:14.5:14.0
INSTALL_TARGET_PROCESSES = SpringBoard Camera

TWEAK_NAME = CameraDiagnostic

CameraDiagnostic_FILES = DiagnosticTweak.xm Hooks/CaptureSessionHooks.xm Hooks/VideoOutputHooks.xm Hooks/PhotoOutputHooks.xm Hooks/DeviceHooks.xm Hooks/OrientationHooks.xm Utils/Logger.mm Utils/MetadataExtractor.mm
CameraDiagnostic_CFLAGS = -fobjc-arc -std=c++11
CameraDiagnostic_FRAMEWORKS = UIKit AVFoundation CoreMedia CoreVideo CoreGraphics Photos

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
