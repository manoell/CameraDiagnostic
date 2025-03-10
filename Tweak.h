#ifndef TWEAK_H
#define TWEAK_H

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>
#import "logger.h"
#import "DiagnosticCollector.h"

// Definição para verificação de versão do iOS
#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v) ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)

// Variáveis globais compartilhadas entre arquivos
extern NSString *g_processName;
extern NSString *g_processID;
extern NSString *g_sessionID;
extern BOOL g_isVideoOrientationSet;
extern int g_videoOrientation;
extern CGSize g_originalCameraResolution;
extern CGSize g_originalFrontCameraResolution;
extern CGSize g_originalBackCameraResolution;
extern BOOL g_usingFrontCamera;
extern BOOL g_isCaptureActive;

// Declarações antecipadas para tipos e funções importantes
@class DiagnosticCollector;
void logDelegates(void);
void detectCameraResolutions(void);

#endif /* TWEAK_H */