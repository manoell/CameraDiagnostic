ARCHS = arm64
TARGET := iphone:clang:latest:15.0
INSTALL_TARGET_PROCESSES = SpringBoard

THEOS_DEVICE_IP=192.168.0.181

TWEAK_NAME = CameraDiagnostic

CameraDiagnostic_FILES = DiagnosticTweak.xm DiagnosticHooks.xm
CameraDiagnostic_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
CameraDiagnostic_FRAMEWORKS = UIKit AVFoundation CoreMedia CoreVideo CoreGraphics

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tweak.mk

# Adiciona regra para limpar arquivos temporários
after-clean::
	rm -rf ./packages
	rm -rf ./.theos
