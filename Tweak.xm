#include <execinfo.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <substrate.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <UIKit/UIKit.h>
#import "logger.h"
#import "LowLevelCameraInterceptor.h"
#import "CameraBufferSubstitutionInterceptor.h"

// Logger global
static Logger *logger;

// Controle do diagnóstico
static BOOL hasInstalledHooks = NO;
static BOOL isInspectionMode = YES;
static NSLock *bufferLock;

// Contador para sample logging
static uint64_t bufferCounter = 0;
static const uint64_t BUFFER_LOG_INTERVAL = 30;   // Log a cada 30 frames (1s a 30 FPS)
static const uint64_t BUFFER_ANALYSIS_INTERVAL = 300; // Análise a cada 300 frames (~10s a 30 FPS)

// Armazena informações sobre as sessões ativas
static NSMutableDictionary *activeSessions;
static NSMutableSet *detectedDelegates;

// Estatísticas
static NSMutableDictionary *statsPerApp;
static NSDate *startTime;

// Forward declarations para método originais que serão hooked
static id (*original_AVCaptureDeviceInput_initWithDevice)(id self, SEL _cmd, AVCaptureDevice *device, NSError **outError);
static void (*original_AVCaptureVideoDataOutput_setSampleBufferDelegate)(id self, SEL _cmd, id<AVCaptureVideoDataOutputSampleBufferDelegate> sampleBufferDelegate, dispatch_queue_t sampleBufferCallbackQueue);
static OSStatus (*original_CMSampleBufferCreate)(CFAllocatorRef allocator, CMBlockBufferRef dataBuffer, Boolean dataReady, CMSampleBufferMakeDataReadyCallback makeDataReadyCallback, void *makeDataReadyRefcon, CMFormatDescriptionRef formatDescription, CMItemCount numSamples, CMItemCount numSampleTimingEntries, const CMSampleTimingInfo *sampleTimingArray, CMItemCount numSampleSizeEntries, const size_t *sampleSizeArray, CMSampleBufferRef *sBufOut);

// Categoria para métodos auxiliares
@interface NSObject (CameraDiagnosticHelper)
+ (void)setupTweakDiagnostic;
+ (void)applicationDidBecomeActive:(NSNotification *)notification;
+ (void)captureSessionRuntimeError:(NSNotification *)notification;
+ (void)captureSessionDidStartRunning:(NSNotification *)notification;
+ (void)captureSessionDidStopRunning:(NSNotification *)notification;
+ (void)installHooks;
+ (void)analyzeActiveSessions;
+ (void)analyzeSession:(AVCaptureSession *)session;
+ (void)analyzeRenderPipeline;
+ (void)inspectViewHierarchy:(UIView *)view indent:(int)indent;
+ (void)inspectLayerHierarchy:(CALayer *)layer indent:(int)indent;
+ (void)analyzeBuffer:(CMSampleBufferRef)sampleBuffer fromOutput:(AVCaptureOutput *)output connection:(AVCaptureConnection *)connection;
+ (void)analyzeBufferInDetail:(CMSampleBufferRef)sampleBuffer fromOutput:(AVCaptureOutput *)output connection:(AVCaptureConnection *)connection;
+ (void)logStatistics;
@end

// Novos hooks para CMSampleBuffer
OSStatus replaced_CMSampleBufferCreate(CFAllocatorRef allocator, CMBlockBufferRef dataBuffer, Boolean dataReady, CMSampleBufferMakeDataReadyCallback makeDataReadyCallback, void *makeDataReadyRefcon, CMFormatDescriptionRef formatDescription, CMItemCount numSamples, CMItemCount numSampleTimingEntries, const CMSampleTimingInfo *sampleTimingArray, CMItemCount numSampleSizeEntries, const size_t *sampleSizeArray, CMSampleBufferRef *sBufOut) {
    
    static uint64_t callCounter = 0;
    callCounter++;
    
    // Executar a função original primeiro
    OSStatus result = original_CMSampleBufferCreate(allocator, dataBuffer, dataReady, makeDataReadyCallback, makeDataReadyRefcon, formatDescription, numSamples, numSampleTimingEntries, sampleTimingArray, numSampleSizeEntries, sampleSizeArray, sBufOut);
    
    // Log a cada X chamadas para não sobrecarregar
    if (callCounter % 50 == 0) {
        NSString *backtraceString = [NSThread callStackSymbols].description;
        
        // Informações do formato de vídeo (se disponível)
        NSString *formatInfo = @"N/A";
        if (formatDescription) {
            CMMediaType mediaType = CMFormatDescriptionGetMediaType(formatDescription);
            FourCharCode mediaSubType = CMFormatDescriptionGetMediaSubType(formatDescription);
            
            char mediaTypeStr[5] = {0};
            mediaTypeStr[0] = (mediaType >> 24) & 0xFF;
            mediaTypeStr[1] = (mediaType >> 16) & 0xFF;
            mediaTypeStr[2] = (mediaType >> 8) & 0xFF;
            mediaTypeStr[3] = mediaType & 0xFF;
            
            char mediaSubTypeStr[5] = {0};
            mediaSubTypeStr[0] = (mediaSubType >> 24) & 0xFF;
            mediaSubTypeStr[1] = (mediaSubType >> 16) & 0xFF;
            mediaSubTypeStr[2] = (mediaSubType >> 8) & 0xFF;
            mediaSubTypeStr[3] = mediaSubType & 0xFF;
            
            if (mediaType == kCMMediaType_Video) {
                CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
                formatInfo = [NSString stringWithFormat:@"Video %dx%d, Type: '%s', SubType: '%s'", 
                              dimensions.width, dimensions.height, mediaTypeStr, mediaSubTypeStr];
            } else {
                formatInfo = [NSString stringWithFormat:@"Media Type: '%s', SubType: '%s'", mediaTypeStr, mediaSubTypeStr];
            }
        }
        
        LOG_INFO(@"⚡️ CMSampleBufferCreate chamado: Buffer %p, Formato: %@, Resultado: %d", 
                 (sBufOut ? *sBufOut : NULL), formatInfo, result);
        LOG_DEBUG(@"  Backtrace: %@", backtraceString);
        
        // Registrar em estatísticas
        NSString *appName = [[NSBundle mainBundle] bundleIdentifier];
        NSMutableDictionary *appStats = statsPerApp[appName];
        if (!appStats) {
            appStats = [NSMutableDictionary dictionary];
            statsPerApp[appName] = appStats;
        }
        
        NSNumber *bufferCount = appStats[@"sampleBuffersCreated"];
        if (!bufferCount) {
            bufferCount = @0;
        }
        appStats[@"sampleBuffersCreated"] = @(bufferCount.integerValue + 1);
    }
    
    return result;
}

%ctor {
    @autoreleasepool {
        startTime = [NSDate date];
        
        // Inicializa estruturas de controle
        bufferLock = [[NSLock alloc] init];
        activeSessions = [NSMutableDictionary dictionary];
        detectedDelegates = [NSMutableSet set];
        statsPerApp = [NSMutableDictionary dictionary];
        
        // Configura logger
        NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *logPath = [documentsPath stringByAppendingPathComponent:@"camera_diagnostic.log"];
        logger = [Logger sharedInstance];
        [logger setLogFilePath:logPath];
        
        // Inicializa diagnóstico
        LOG_INFO(@"======= CAMERA DIAGNOSTIC UNIVERSAL INICIADO =======");
        LOG_INFO(@"Data/Hora: %@", [NSDate date]);
        LOG_INFO(@"Bundle: %@", [[NSBundle mainBundle] bundleIdentifier]);
        LOG_INFO(@"Processo: %@", [NSProcessInfo processInfo].processName);
        LOG_INFO(@"OS Version: %@", [UIDevice currentDevice].systemVersion);
        LOG_INFO(@"Device: %@", [UIDevice currentDevice].model);
        
        // Registra notificações
        [[NSNotificationCenter defaultCenter] addObserver:[NSObject class]
                                                 selector:@selector(applicationDidBecomeActive:)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:[NSObject class]
                                                 selector:@selector(captureSessionRuntimeError:)
                                                     name:AVCaptureSessionRuntimeErrorNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:[NSObject class]
                                                 selector:@selector(captureSessionDidStartRunning:)
                                                     name:AVCaptureSessionDidStartRunningNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:[NSObject class]
                                                 selector:@selector(captureSessionDidStopRunning:)
                                                     name:AVCaptureSessionDidStopRunningNotification
                                                   object:nil];
        
        // Iniciar interceptor de baixo nível
        LowLevelCameraInterceptor *lowLevelInterceptor = [LowLevelCameraInterceptor sharedInstance];
        [lowLevelInterceptor startMonitoring];
        
        // Instala hooks com pequeno atraso para permitir inicialização do app
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [NSObject installHooks];
            
            // Registrar notificação para logs periódicos de estatísticas
            [NSTimer scheduledTimerWithTimeInterval:60.0 
                                             target:[NSObject class] 
                                           selector:@selector(logStatistics) 
                                           userInfo:nil 
                                            repeats:YES];
        });
    }
}

// Implementação da categoria de diagnóstico
@implementation NSObject (CameraDiagnosticHelper)

+ (void)setupTweakDiagnostic {
    LOG_INFO(@"Configurando diagnóstico da câmera...");
    
    // Inicializa estruturas de controle se ainda não tiverem sido inicializadas
    if (!bufferLock) {
        bufferLock = [[NSLock alloc] init];
    }
    
    if (!activeSessions) {
        activeSessions = [NSMutableDictionary dictionary];
    }
    
    if (!detectedDelegates) {
        detectedDelegates = [NSMutableSet set];
    }
    
    // Configura o logger se necessário
    if (!logger) {
        NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *logPath = [documentsPath stringByAppendingPathComponent:@"camera_diagnostic.log"];
        logger = [Logger sharedInstance];
        [logger setLogFilePath:logPath];
    }
    
    // Instala hooks se ainda não estiverem instalados
    if (!hasInstalledHooks) {
        [self installHooks];
    }
    
    // Analisa sessões ativas existentes
    [self analyzeActiveSessions];
    [self analyzeRenderPipeline];
    
    // Iniciar interceptor de baixo nível
    LowLevelCameraInterceptor *lowLevelInterceptor = [LowLevelCameraInterceptor sharedInstance];
    [lowLevelInterceptor startMonitoring];
    
    LOG_INFO(@"Configuração do diagnóstico de câmera concluída");
}

+ (void)applicationDidBecomeActive:(NSNotification *)notification {
    NSString *appID = [[NSBundle mainBundle] bundleIdentifier];
    LOG_INFO(@"Aplicativo ativo: %@", appID);
    
    // Registrar no dicionário de estatísticas
    if (!statsPerApp[appID]) {
        statsPerApp[appID] = [NSMutableDictionary dictionary];
    }
    
    // Analisa estado atual da câmera
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self analyzeActiveSessions];
        [self analyzeRenderPipeline];
    });
    
    // Verifica permissões
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    LOG_INFO(@"Status de autorização da câmera: %ld", (long)authStatus);
    
    // Se ainda não instalou hooks, tenta novamente
    if (!hasInstalledHooks) {
        [self installHooks];
    }
}

+ (void)captureSessionRuntimeError:(NSNotification *)notification {
    AVCaptureSession *session = notification.object;
    NSError *error = notification.userInfo[AVCaptureSessionErrorKey];
    LOG_ERROR(@"Erro em sessão de captura: %@, Erro: %@", session, error);
}

+ (void)captureSessionDidStartRunning:(NSNotification *)notification {
    AVCaptureSession *session = notification.object;
    LOG_INFO(@"⚡️ Sessão de captura iniciou: %p", session);
    
    // Registra sessão ativa
    NSString *sessionKey = [NSString stringWithFormat:@"%p", session];
    [activeSessions setObject:session forKey:sessionKey];
    
    // Analisa a sessão
    [self analyzeSession:session];
    
    // Registrar em estatísticas
    NSString *appName = [[NSBundle mainBundle] bundleIdentifier];
    NSMutableDictionary *appStats = statsPerApp[appName];
    if (!appStats) {
        appStats = [NSMutableDictionary dictionary];
        statsPerApp[appName] = appStats;
    }
    
    NSNumber *sessionCount = appStats[@"captureSessionsStarted"];
    if (!sessionCount) {
        sessionCount = @0;
    }
    appStats[@"captureSessionsStarted"] = @(sessionCount.integerValue + 1);
}

+ (void)captureSessionDidStopRunning:(NSNotification *)notification {
    AVCaptureSession *session = notification.object;
    LOG_INFO(@"Sessão de captura parou: %p", session);
    
    // Remove da lista de sessões ativas
    NSString *sessionKey = [NSString stringWithFormat:@"%p", session];
    [activeSessions removeObjectForKey:sessionKey];
}

+ (void)installHooks {
    if (hasInstalledHooks) return;
    
    LOG_INFO(@"Instalando hooks para diagnóstico universal...");
    
    // Hook em AVCaptureDeviceInput init para capturar dispositivos de câmera
    MSHookMessageEx(
        objc_getClass("AVCaptureDeviceInput"),
        @selector(initWithDevice:error:),
        (IMP)&overridden_AVCaptureDeviceInput_initWithDevice,
        (IMP*)&original_AVCaptureDeviceInput_initWithDevice
    );
    
    // Hook em AVCaptureVideoDataOutput setSampleBufferDelegate para capturar delegados
    MSHookMessageEx(
        objc_getClass("AVCaptureVideoDataOutput"),
        @selector(setSampleBufferDelegate:queue:),
        (IMP)&overridden_AVCaptureVideoDataOutput_setSampleBufferDelegate,
        (IMP*)&original_AVCaptureVideoDataOutput_setSampleBufferDelegate
    );
    
    // Hook em CMSampleBufferCreate - ponto crucial de criação de buffers
    void *cmSampleBufferCreateSymbol = dlsym(RTLD_DEFAULT, "CMSampleBufferCreate");
    if (cmSampleBufferCreateSymbol) {
        MSHookFunction(cmSampleBufferCreateSymbol, (void *)replaced_CMSampleBufferCreate, (void **)&original_CMSampleBufferCreate);
        LOG_INFO(@"Hooked CMSampleBufferCreate");
    } else {
        LOG_ERROR(@"Não foi possível encontrar CMSampleBufferCreate");
    }
    
    // Registra detecção de classes que implementam o protocolo
    unsigned int count;
    Class *classes = objc_copyClassList(&count);
    
    for (unsigned int i = 0; i < count; i++) {
        if (class_conformsToProtocol(classes[i], objc_getProtocol("AVCaptureVideoDataOutputSampleBufferDelegate"))) {
            LOG_INFO(@"Detectada classe que implementa AVCaptureVideoDataOutputSampleBufferDelegate: %s", class_getName(classes[i]));
            
            // Tenta hook no método delegate
            Method m = class_getInstanceMethod(classes[i], @selector(captureOutput:didOutputSampleBuffer:fromConnection:));
            if (m) {
                LOG_INFO(@"  Possui método didOutputSampleBuffer - instalando hook");
                
                IMP originalIMP = method_getImplementation(m);
                IMP hookedIMP = (IMP)&overridden_captureOutput_didOutputSampleBuffer;
                
                // Armazena IMP original e instala o hook
                MSHookFunction((void *)originalIMP, (void *)hookedIMP, NULL);
            }
        }
    }
    
    free(classes);
    hasInstalledHooks = YES;
    LOG_INFO(@"Hooks instalados com sucesso");
}

+ (void)analyzeActiveSessions {
    LOG_INFO(@"====== ANÁLISE DE SESSÕES ATIVAS ======");
    LOG_INFO(@"Total de sessões ativas detectadas: %lu", (unsigned long)activeSessions.count);
    
    for (NSString *key in activeSessions) {
        AVCaptureSession *session = activeSessions[key];
        [self analyzeSession:session];
    }
}

+ (void)analyzeSession:(AVCaptureSession *)session {
    if (!session) return;
    
    LOG_INFO(@"------ Sessão: %p ------", session);
    LOG_INFO(@"  Preset: %@", session.sessionPreset);
    LOG_INFO(@"  Em execução: %d", session.isRunning);
    
    // Analisa inputs
    if (session.inputs.count > 0) {
        LOG_INFO(@"  === INPUTS: %lu ===", (unsigned long)session.inputs.count);
        for (AVCaptureInput *input in session.inputs) {
            if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
                AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
                AVCaptureDevice *device = deviceInput.device;
                
                LOG_INFO(@"  Input: %p - Dispositivo: %@", input, device.localizedName);
                LOG_INFO(@"    Posição: %ld", (long)device.position);
                LOG_INFO(@"    Modelo ID: %@", device.modelID);
                LOG_INFO(@"    Uniquue ID: %@", device.uniqueID);
                
                if (device.formats.count > 0) {
                    LOG_INFO(@"    Formato ativo: %@", device.activeFormat);
                    
                    // Analisar propriedades do formato ativo
                    AVCaptureDeviceFormat *activeFormat = device.activeFormat;
                    CMFormatDescriptionRef formatDesc = activeFormat.formatDescription;
                    if (formatDesc) {
                        CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDesc);
                        FourCharCode mediaSubType = CMFormatDescriptionGetMediaSubType(formatDesc);
                        char mediaSubTypeStr[5] = {0};
                        mediaSubTypeStr[0] = (mediaSubType >> 24) & 0xFF;
                        mediaSubTypeStr[1] = (mediaSubType >> 16) & 0xFF;
                        mediaSubTypeStr[2] = (mediaSubType >> 8) & 0xFF;
                        mediaSubTypeStr[3] = mediaSubType & 0xFF;
                        
                        LOG_INFO(@"      Formato Ativo: %dx%d, Codec: '%s'", 
                                dimensions.width, dimensions.height, mediaSubTypeStr);
                        
                        // Mais informações do formato
                        LOG_INFO(@"      Min/Max Zoom: %.2f/%.2f", device.minAvailableVideoZoomFactor, device.maxAvailableVideoZoomFactor);
                        LOG_INFO(@"      Auto Focus: %d, Auto Exposure: %d", 
                                [device isAdjustingFocus], [device isAdjustingExposure]);
                    }
                    
                    LOG_INFO(@"    Total de formatos disponíveis: %lu", (unsigned long)device.formats.count);
                    for (AVCaptureDeviceFormat *format in device.formats) {
                        CMFormatDescriptionRef formatDescription = format.formatDescription;
                        CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
                        
                        // Obter FPS
                        NSString *fpsRange = @"";
                        for (AVFrameRateRange *range in format.videoSupportedFrameRateRanges) {
                            fpsRange = [NSString stringWithFormat:@"%.0f-%.0f", range.minFrameRate, range.maxFrameRate];
                            break;
                        }
                        
                        LOG_DEBUG(@"      %dx%d - %@ - FPS: %@", 
                                 dimensions.width, dimensions.height, format.mediaType, fpsRange);
                    }
                }
            } else {
                LOG_INFO(@"  Input: %p - Tipo: %@", input, [input class]);
            }
        }
    }
    
    // Analisa outputs
    if (session.outputs.count > 0) {
        LOG_INFO(@"  === OUTPUTS: %lu ===", (unsigned long)session.outputs.count);
        for (AVCaptureOutput *output in session.outputs) {
            if ([output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
                AVCaptureVideoDataOutput *videoOutput = (AVCaptureVideoDataOutput *)output;
                id<AVCaptureVideoDataOutputSampleBufferDelegate> delegate = videoOutput.sampleBufferDelegate;
                
                LOG_INFO(@"  VideoDataOutput: %p", videoOutput);
                LOG_INFO(@"    Delegate: %p (%@)", delegate, [delegate class]);
                LOG_INFO(@"    alwaysDiscardsLateVideoFrames: %d", videoOutput.alwaysDiscardsLateVideoFrames);
                
                // Analisa configurações de vídeo
                NSDictionary *settings = videoOutput.videoSettings;
                if (settings) {
                    LOG_INFO(@"    Video Settings: %@", settings);
                    
                    // Extrair configurações-chave
                    NSNumber *width = settings[(NSString*)kCVPixelBufferWidthKey];
                    NSNumber *height = settings[(NSString*)kCVPixelBufferHeightKey];
                    NSNumber *pixelFormat = settings[(NSString*)kCVPixelBufferPixelFormatTypeKey];
                    
                    if (width && height && pixelFormat) {
                        uint32_t format = [pixelFormat unsignedIntValue];
                        char formatStr[5] = {0};
                        formatStr[0] = (format >> 24) & 0xFF;
                        formatStr[1] = (format >> 16) & 0xFF;
                        formatStr[2] = (format >> 8) & 0xFF;
                        formatStr[3] = format & 0xFF;
                        
                        LOG_INFO(@"    Saída configurada para: %@x%@ pixels, Formato: '%s'", 
                                width, height, formatStr);
                    }
                }
                
                // Analisar métodos do delegate
                if (delegate) {
                    Class delegateClass = [delegate class];
                    BOOL implementsDidOutputSampleBuffer = [delegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)];
                    BOOL implementsDidDropSampleBuffer = [delegate respondsToSelector:@selector(captureOutput:didDropSampleBuffer:fromConnection:)];
                    
                    LOG_INFO(@"    Delegate implementa didOutputSampleBuffer: %d", implementsDidOutputSampleBuffer);
                    LOG_INFO(@"    Delegate implementa didDropSampleBuffer: %d", implementsDidDropSampleBuffer);
                    
                    // Registrar o delegate para análise posterior
                    if (![detectedDelegates containsObject:delegate]) {
                        [detectedDelegates addObject:delegate];
                    }
                    
                    // Verificar a hierarquia de classes do delegate
                    NSMutableString *classHierarchy = [NSMutableString string];
                    Class currentClass = delegateClass;
                    while (currentClass) {
                        [classHierarchy appendFormat:@"%s -> ", class_getName(currentClass)];
                        currentClass = class_getSuperclass(currentClass);
                    }
                    [classHierarchy appendString:@"nil"];
                    LOG_DEBUG(@"    Hierarquia de classes do delegate: %@", classHierarchy);
                }
                
                // Analisa conexões
                if (videoOutput.connections.count > 0) {
                    LOG_INFO(@"    === CONEXÕES: %lu ===", (unsigned long)videoOutput.connections.count);
                    for (AVCaptureConnection *connection in videoOutput.connections) {
                        LOG_INFO(@"    Conexão: %p", connection);
                        LOG_INFO(@"      Ativa: %d", connection.enabled);
                        LOG_INFO(@"      Número de entradas: %lu", (unsigned long)connection.inputPorts.count);
                        
                        // Propriedades específicas de vídeo
                        if ([connection isVideoOrientationSupported]) {
                            LOG_INFO(@"      Orientação de vídeo: %ld", (long)connection.videoOrientation);
                        }
                        
                        if ([connection isVideoMirroringSupported]) {
                            LOG_INFO(@"      Espelhamento de vídeo: %d", connection.isVideoMirrored);
                        }
                        
                        if ([connection isVideoStabilizationSupported]) {
                            LOG_INFO(@"      Estabilização de vídeo: %ld", (long)connection.preferredVideoStabilizationMode);
                        }
                        
                        // Tentar identificar o dispositivo de origem
                        for (AVCaptureInputPort *port in connection.inputPorts) {
                            AVCaptureInput *input = port.input;
                            if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
                                AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
                                LOG_INFO(@"      Porta conectada ao dispositivo: %@, posição: %ld", 
                                        deviceInput.device.localizedName, 
                                        (long)deviceInput.device.position);
                            }
                        }
                    }
                }
            } else if ([output isKindOfClass:[AVCaptureMovieFileOutput class]]) {
                AVCaptureMovieFileOutput *movieOutput = (AVCaptureMovieFileOutput *)output;
                LOG_INFO(@"  MovieFileOutput: %p", movieOutput);
                LOG_INFO(@"    Gravando: %d", movieOutput.isRecording);
                if (movieOutput.isRecording) {
                    LOG_INFO(@"    URL de Gravação: %@", movieOutput.outputFileURL);
                    LOG_INFO(@"    Duração: %.2f segundos", CMTimeGetSeconds(movieOutput.recordedDuration));
                }
            } else if ([output isKindOfClass:[AVCaptureStillImageOutput class]]) {
                AVCaptureStillImageOutput *stillImageOutput = (AVCaptureStillImageOutput *)output;
                LOG_INFO(@"  StillImageOutput: %p", stillImageOutput);
                
                NSDictionary *settings = stillImageOutput.outputSettings;
                if (settings) {
                    LOG_INFO(@"    Output Settings: %@", settings);
                }
            } else {
                LOG_INFO(@"  Output: %p - Tipo: %@", output, [output class]);
            }
        }
    }
    
    // Verificar objetos associados à sessão para análise de contexto
    objc_property_t *properties = class_copyPropertyList([session class], NULL);
    if (properties) {
        unsigned int count = 0;
        while (properties[count]) {
            objc_property_t property = properties[count];
            const char *propertyName = property_getName(property);
            NSString *name = [NSString stringWithUTF8String:propertyName];
            
            // Tentar acessar propriedades públicas e privadas conhecidas
            if ([name isEqualToString:@"running"] || 
                [name isEqualToString:@"interrupted"] || 
                [name isEqualToString:@"_sessionPreset"] || 
                [name isEqualToString:@"_inputs"] || 
                [name isEqualToString:@"_outputs"]) {
                
                LOG_DEBUG(@"  Propriedade encontrada: %@", name);
            }
            
            count++;
        }
        free(properties);
    }
    
    // Verificar objetos associados via Objective-C runtime
    // Isso pode revelar conexões ocultas com outras classes
    unsigned int outCount;
    Ivar *ivars = class_copyIvarList([session class], &outCount);
    if (ivars) {
        for (unsigned int i = 0; i < outCount; i++) {
            Ivar ivar = ivars[i];
            const char *ivarName = ivar_getName(ivar);
            if (ivarName) {
                LOG_DEBUG(@"  Ivar: %s", ivarName);
            }
        }
        free(ivars);
    }
}