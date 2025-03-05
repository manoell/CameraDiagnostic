TARGET := iphone:clang:14.5:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CameraDiagnostic

CameraDiagnostic_FILES = Tweak.xm \
    CameraBufferSubstitutionInterceptor.m \
    CameraDiagnosticFramework.m \
    CameraFeedSubstitutionSource.m \
    BufferContentInspector.m \
    LowLevelCameraInterceptor.m \
    logger.m

CameraDiagnostic_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
CameraDiagnostic_FRAMEWORKS = UIKit AVFoundation CoreMedia CoreVideo ImageIO IOSurface IOKit
CameraDiagnostic_PRIVATE_FRAMEWORKS = MediaToolbox CameraKit
CameraDiagnostic_LIBRARIES = substrate iconv resolv

include $(THEOS_MAKE_PATH)/tweak.mk
