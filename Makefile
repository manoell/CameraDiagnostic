TARGET := iphone:clang:14.5:14.0
INSTALL_TARGET_PROCESSES = SpringBoard

TWEAK_NAME = CameraDiagnostic

CameraDiagnostic_FILES = Tweak.xm logger.m
CameraDiagnostic_CFLAGS = -fobjc-arc
CameraDiagnostic_FRAMEWORKS = UIKit AVFoundation CoreMedia CoreVideo

# Adicionar flags específicas para o arquivo Tweak.xm
CameraDiagnostic_XCFLAGS = -std=c++11

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk
