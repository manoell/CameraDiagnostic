#ifndef DIAGNOSTIC_TWEAK_H
#define DIAGNOSTIC_TWEAK_H

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
// Removemos a importação do Photos daqui
#import <objc/runtime.h>

// Imports dos utilitários
#import "Utils/Logger.h"
#import "Utils/MetadataExtractor.h"

// Definição para verificação de versão do iOS
#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v) ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)

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
extern NSDictionary *g_lastPhotoMetadata;
extern NSMutableDictionary *g_sessionInfo;

// Função para iniciar uma nova sessão de diagnóstico
void startNewDiagnosticSession(void);

// Função para registrar informações da sessão
void logSessionInfo(NSString *key, id value);

// Função para finalizar e salvar o diagnóstico
void finalizeDiagnosticSession(void);

#endif /* DIAGNOSTIC_TWEAK_H */
