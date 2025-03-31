#ifndef DIAGNOSTIC_TWEAK_H
#define DIAGNOSTIC_TWEAK_H

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <objc/runtime.h>

// Variáveis globais compartilhadas entre arquivos
extern NSString *g_sessionId;
extern NSString *g_appName;
extern NSString *g_bundleId;
extern CGSize g_cameraResolution;
extern CGSize g_frontCameraResolution;
extern CGSize g_backCameraResolution;
extern int g_videoOrientation;
extern BOOL g_isCapturingPhoto;
extern BOOL g_isRecordingVideo;
extern BOOL g_usingFrontCamera;
extern uint64_t g_frameCounter;

// Função para iniciar uma nova sessão de diagnóstico
void startNewDiagnosticSession(void);

// Função para finalizar e salvar o diagnóstico
void finalizeDiagnosticSession(void);

// Utilitário para converter formato de pixel para string legível
NSString *pixelFormatToString(OSType format);

#endif /* DIAGNOSTIC_TWEAK_H */
