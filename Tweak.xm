#include <execinfo.h>        // Para backtrace() e backtrace_symbols()
#include <objc/message.h>    // Para objc_msgSend
#include <objc/runtime.h>    // Para objc_getClass
#include <substrate.h>       // Para MSHookMessageEx e MSHookFunction
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <UIKit/UIKit.h>
#import "logger.h"

// Logger global
static Logger *logger;

// Controle do diagnóstico
static BOOL hasInstalledHooks = NO;
static BOOL isInspectionMode = YES;
static NSLock *bufferLock;

// Contador de buffers para sample logging
static NSUInteger bufferCounter = 0;

// Armazena informações sobre as sessões ativas
static NSMutableDictionary *activeSessions;
static NSMutableSet *detectedDelegates;

// Forward declarations para método originais que serão hooked
static id (*original_AVCaptureDeviceInput_initWithDevice)(id self, SEL _cmd, AVCaptureDevice *device, NSError **outError);
static void (*original_AVCaptureVideoDataOutput_setSampleBufferDelegate)(id self, SEL _cmd, id<AVCaptureVideoDataOutputSampleBufferDelegate> sampleBufferDelegate, dispatch_queue_t sampleBufferCallbackQueue);

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
@end

// Helpers para formatos
static NSString *DescribePixelFormat(OSType format) {
    char formatStr[5] = {0};
    formatStr[0] = (format >> 24) & 0xFF;
    formatStr[1] = (format >> 16) & 0xFF;
    formatStr[2] = (format >> 8) & 0xFF;
    formatStr[3] = format & 0xFF;
    return [NSString stringWithFormat:@"'%s'", formatStr];
}

static NSString *DescribeBuffer(CMSampleBufferRef buffer) {
    if (!buffer) return @"<NULL>";
    
    NSMutableString *desc = [NSMutableString string];
    [desc appendFormat:@"<CMSampleBuffer:%p", buffer];
    
    // Verifica validade
    [desc appendFormat:@", valid:%d", CMSampleBufferIsValid(buffer)];
    
    // Timestamp
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(buffer);
    [desc appendFormat:@", pts:%.3fs", CMTimeGetSeconds(pts)];
    
    // Imagem
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(buffer);
    if (imageBuffer) {
        // Dimensões
        size_t width = CVPixelBufferGetWidth(imageBuffer);
        size_t height = CVPixelBufferGetHeight(imageBuffer);
        OSType format = CVPixelBufferGetPixelFormatType(imageBuffer);
        [desc appendFormat:@", %zux%zu, fmt:%@", width, height, DescribePixelFormat(format)];
    }
    
    [desc appendString:@">"];
    return desc;
}

static void PrintBacktrace() {
    void *callstack[128];
    int frames = backtrace(callstack, 128);
    char **strs = backtrace_symbols(callstack, frames);
    
    NSMutableString *backtrace = [NSMutableString string];
    [backtrace appendString:@"STACK TRACE:"];
    
    for (int i = 0; i < frames; i++) {
        [backtrace appendFormat:@"\n%s", strs[i]];
    }
    
    LOG_INFO(@"%@", backtrace);
    free(strs);
}

// Implementações de métodos hooked
static id overridden_AVCaptureDeviceInput_initWithDevice(id self, SEL _cmd, AVCaptureDevice *device, NSError **outError) {
    id result = original_AVCaptureDeviceInput_initWithDevice(self, _cmd, device, outError);
    
    if (result) {
        LOG_INFO(@"✅ AVCaptureDeviceInput inicializado com dispositivo: %@", device.localizedName);
        LOG_INFO(@"  Posição: %ld", (long)device.position);
        LOG_INFO(@"  ID: %@", device.uniqueID);
        LOG_INFO(@"  Modelo: %@", device.modelID);
    } else if (outError && *outError) {
        LOG_ERROR(@"❌ Falha ao inicializar AVCaptureDeviceInput: %@", *outError);
    }
    
    return result;
}

static void overridden_AVCaptureVideoDataOutput_setSampleBufferDelegate(id self, SEL _cmd, id<AVCaptureVideoDataOutputSampleBufferDelegate> sampleBufferDelegate, dispatch_queue_t sampleBufferCallbackQueue) {
    LOG_INFO(@"✅ AVCaptureVideoDataOutput setSampleBufferDelegate: %@ (%p), Queue: %@",
           [sampleBufferDelegate class], sampleBufferDelegate, sampleBufferCallbackQueue);
    
    // Registra o delegate para análise
    if (sampleBufferDelegate) {
        [detectedDelegates addObject:sampleBufferDelegate];
        
        // Log de métodos implementados
        BOOL hasOutputMethod = [sampleBufferDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)];
        BOOL hasDropMethod = [sampleBufferDelegate respondsToSelector:@selector(captureOutput:didDropSampleBuffer:fromConnection:)];
        
        LOG_INFO(@"  Implementa didOutputSampleBuffer: %d", hasOutputMethod);
        LOG_INFO(@"  Implementa didDropSampleBuffer: %d", hasDropMethod);
    }
    
    // Backtrace
    PrintBacktrace();
    
    original_AVCaptureVideoDataOutput_setSampleBufferDelegate(self, _cmd, sampleBufferDelegate, sampleBufferCallbackQueue);
}

static void overridden_captureOutput_didOutputSampleBuffer(id self, SEL _cmd, AVCaptureOutput *output, CMSampleBufferRef sampleBuffer, AVCaptureConnection *connection) {
    // Analisa o buffer se estiver em modo de inspeção
    if (isInspectionMode) {
        [NSObject analyzeBuffer:sampleBuffer fromOutput:output connection:connection];
    }
    
    // Chama o método original (usando objc_msgSend para manter os tipos corretos)
    ((void(*)(id, SEL, AVCaptureOutput*, CMSampleBufferRef, AVCaptureConnection*))objc_msgSend)(
        self, _cmd, output, sampleBuffer, connection);
}

%ctor {
    @autoreleasepool {
        // Inicializa estruturas de controle
        bufferLock = [[NSLock alloc] init];
        activeSessions = [NSMutableDictionary dictionary];
        detectedDelegates = [NSMutableSet set];
        
        // Configura logger
        NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *logPath = [documentsPath stringByAppendingPathComponent:@"camera_diagnostic.log"];
        logger = [Logger sharedInstance];
        [logger setLogFilePath:logPath];
        
        // Inicializa diagnóstico
        LOG_INFO(@"======= CAMERA DIAGNOSTIC TWEAK INICIADO =======");
        LOG_INFO(@"Bundle: %@", [[NSBundle mainBundle] bundleIdentifier]);
        LOG_INFO(@"Processo: %@", [NSProcessInfo processInfo].processName);
        LOG_INFO(@"OS Version: %@", [UIDevice currentDevice].systemVersion);
        
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
        
        // Instala hooks com pequeno atraso para permitir inicialização do app
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [NSObject installHooks];
        });
    }
}

// Implementação da categoria de diagnóstico
@implementation NSObject (CameraDiagnosticHelper)

// IMPLEMENTAÇÃO DO MÉTODO QUE ESTAVA FALTANDO
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
    
    LOG_INFO(@"Configuração do diagnóstico de câmera concluída");
}

+ (void)applicationDidBecomeActive:(NSNotification *)notification {
    LOG_INFO(@"Aplicativo ativo: %@", [[NSBundle mainBundle] bundleIdentifier]);
    
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
    LOG_INFO(@"Sessão de captura iniciou: %p", session);
    
    // Registra sessão ativa
    NSString *sessionKey = [NSString stringWithFormat:@"%p", session];
    [activeSessions setObject:session forKey:sessionKey];
    
    // Analisa a sessão
    [self analyzeSession:session];
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
    
    LOG_INFO(@"Instalando hooks para diagnóstico...");
    
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
                
                if (device.formats.count > 0) {
                    LOG_INFO(@"    Formato ativo: %@", device.activeFormat);
                    
                    LOG_INFO(@"    Formatos disponíveis: %lu", (unsigned long)device.formats.count);
                    for (AVCaptureDeviceFormat *format in device.formats) {
                        CMFormatDescriptionRef formatDescription = format.formatDescription;
                        CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
                        LOG_DEBUG(@"      %dx%d - %@", dimensions.width, dimensions.height, format.mediaType);
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
                }
                
                // Registra o delegate para análise
                if (delegate) {
                    [detectedDelegates addObject:delegate];
                }
                
                // Analisa conexões
                if (videoOutput.connections.count > 0) {
                    LOG_INFO(@"    === CONEXÕES: %lu ===", (unsigned long)videoOutput.connections.count);
                    for (AVCaptureConnection *connection in videoOutput.connections) {
                        LOG_INFO(@"    Conexão: %p", connection);
                        LOG_INFO(@"      Ativa: %d", connection.enabled);
                        LOG_INFO(@"      Número de entradas: %lu", (unsigned long)connection.inputPorts.count);
                        
                        if ([connection isVideoMirroringSupported]) {
                            LOG_INFO(@"      Espelhamento de vídeo: %d", connection.videoMirrored);
                        }
                        
                        if ([connection isVideoOrientationSupported]) {
                            LOG_INFO(@"      Orientação de vídeo: %ld", (long)connection.videoOrientation);
                        }
                    }
                }
            } else if ([output isKindOfClass:[AVCaptureMovieFileOutput class]]) {
                AVCaptureMovieFileOutput *movieOutput = (AVCaptureMovieFileOutput *)output;
                LOG_INFO(@"  MovieFileOutput: %p", movieOutput);
                LOG_INFO(@"    Recording: %d", movieOutput.isRecording);
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
}

+ (void)analyzeRenderPipeline {
    LOG_INFO(@"====== ANÁLISE DE PIPELINE DE RENDERIZAÇÃO ======");
    
    // Localiza a janela key
    UIWindow *keyWindow = nil;
    
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive) {
                for (UIWindow *window in [(UIWindowScene *)scene windows]) {
                    if (window.isKeyWindow) {
                        keyWindow = window;
                        break;
                    }
                }
            }
            if (keyWindow) break;
        }
    } else {
        keyWindow = UIApplication.sharedApplication.keyWindow;
    }
    
    if (!keyWindow) {
        LOG_WARNING(@"Não foi possível encontrar a janela principal");
        return;
    }
    
    // Inspeciona hierarquia de visões
    [self inspectViewHierarchy:keyWindow indent:0];
}

+ (void)inspectViewHierarchy:(UIView *)view indent:(int)indent {
    NSMutableString *indentStr = [NSMutableString string];
    for (int i = 0; i < indent; i++) {
        [indentStr appendString:@"  "];
    }
    
    LOG_DEBUG(@"%@View: %@ (Frame: %@)", indentStr, [view class], NSStringFromCGRect(view.frame));
    
    // Verifica se é uma visão relacionada à câmera
    BOOL isCameraRelated = NO;
    
    if ([view isKindOfClass:NSClassFromString(@"PLCameraView")] ||
        [view isKindOfClass:NSClassFromString(@"PLPreviewView")] ||
        [view isKindOfClass:NSClassFromString(@"CAMViewfinderView")] ||
        [view isKindOfClass:NSClassFromString(@"CAMPreviewView")]) {
        isCameraRelated = YES;
    }
    
    // Analisa a camada se for view relacionada à câmera
    if (isCameraRelated || [view.layer isKindOfClass:[AVCaptureVideoPreviewLayer class]]) {
        LOG_INFO(@"%@⭐️ VISÃO DE CÂMERA ENCONTRADA: %@", indentStr, [view class]);
        [self inspectLayerHierarchy:view.layer indent:indent+1];
    }
    
    // Recursivamente inspeciona subviews
    for (UIView *subview in view.subviews) {
        [self inspectViewHierarchy:subview indent:indent+1];
    }
}

+ (void)inspectLayerHierarchy:(CALayer *)layer indent:(int)indent {
    NSMutableString *indentStr = [NSMutableString string];
    for (int i = 0; i < indent; i++) {
        [indentStr appendString:@"  "];
    }
    
    LOG_DEBUG(@"%@Layer: %@ (Frame: %@)", indentStr, [layer class], NSStringFromCGRect(layer.frame));
    
    // Verifica se é uma camada de preview de câmera
    if ([layer isKindOfClass:[AVCaptureVideoPreviewLayer class]]) {
        AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)layer;
        LOG_INFO(@"%@⭐️ AVCaptureVideoPreviewLayer: %p", indentStr, previewLayer);
        LOG_INFO(@"%@  Sessão: %@", indentStr, previewLayer.session);
        
        if (previewLayer.connection) {
            LOG_INFO(@"%@  Conexão: %p", indentStr, previewLayer.connection);
            LOG_INFO(@"%@    Enabled: %d", indentStr, previewLayer.connection.enabled);
            LOG_INFO(@"%@    Video Orientation: %ld", indentStr, (long)previewLayer.connection.videoOrientation);
            LOG_INFO(@"%@    Video Mirrored: %d", indentStr, previewLayer.connection.videoMirrored);
        }
        
        LOG_INFO(@"%@  Gravity: %@", indentStr, previewLayer.videoGravity);
        
        // Registra a sessão se não estiver registrada
        if (previewLayer.session) {
            NSString *sessionKey = [NSString stringWithFormat:@"%p", previewLayer.session];
            if (!activeSessions[sessionKey]) {
                activeSessions[sessionKey] = previewLayer.session;
                [self analyzeSession:previewLayer.session];
            }
        }
    }
    
    // Recursivamente inspeciona sublayers
    for (CALayer *sublayer in layer.sublayers) {
        [self inspectLayerHierarchy:sublayer indent:indent+1];
    }
}

+ (void)analyzeBuffer:(CMSampleBufferRef)sampleBuffer fromOutput:(AVCaptureOutput *)output connection:(AVCaptureConnection *)connection {
    if (!sampleBuffer || !CMSampleBufferIsValid(sampleBuffer)) {
        return;
    }
    
    bufferCounter++;
    
    // Log a cada 30 frames (aprox. 1s a 30 FPS) para não sobrecarregar
    if (bufferCounter % 30 != 0) {
        return;
    }
    
    [bufferLock lock];
    
    LOG_INFO(@"====== ANÁLISE DE BUFFER DE AMOSTRA ======");
    LOG_INFO(@"Buffer: %@", DescribeBuffer(sampleBuffer));
    
    // Informações de tempo
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    CMTime dts = CMSampleBufferGetDecodeTimeStamp(sampleBuffer);
    CMTime duration = CMSampleBufferGetDuration(sampleBuffer);
    
    LOG_INFO(@"Tempo: PTS=%.3fs, DTS=%.3fs, Duration=%.3fs",
           CMTimeGetSeconds(pts), CMTimeGetSeconds(dts), CMTimeGetSeconds(duration));
    
    // Formato
    CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
    if (formatDesc) {
        FourCharCode mediaType = CMFormatDescriptionGetMediaType(formatDesc);
        FourCharCode mediaSubType = CMFormatDescriptionGetMediaSubType(formatDesc);
        LOG_INFO(@"Formato: Type=%@, SubType=%@",
               DescribePixelFormat(mediaType), DescribePixelFormat(mediaSubType));
        
        // Para vídeo, obter dimensões
        if (mediaType == kCMMediaType_Video) {
            CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDesc);
            LOG_INFO(@"Dimensões: %dx%d", dimensions.width, dimensions.height);
        }
    }
    
    // Imagem
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (imageBuffer) {
        size_t width = CVPixelBufferGetWidth(imageBuffer);
        size_t height = CVPixelBufferGetHeight(imageBuffer);
        OSType pixelFormat = CVPixelBufferGetPixelFormatType(imageBuffer);
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
        size_t dataSize = CVPixelBufferGetDataSize(imageBuffer);
        
        LOG_INFO(@"ImageBuffer: %zux%zu, Format=%@, BytesPerRow=%zu, DataSize=%zu",
               width, height, DescribePixelFormat(pixelFormat), bytesPerRow, dataSize);
        
        // Informações sobre planes para formatos planares
        size_t planeCount = CVPixelBufferGetPlaneCount(imageBuffer);
        if (planeCount > 0) {
            LOG_INFO(@"Planes: %zu", planeCount);
            for (size_t i = 0; i < planeCount; i++) {
                size_t planeWidth = CVPixelBufferGetWidthOfPlane(imageBuffer, i);
                size_t planeHeight = CVPixelBufferGetHeightOfPlane(imageBuffer, i);
                size_t planeBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, i);
                
                LOG_INFO(@"  Plane %zu: %zux%zu, BytesPerRow=%zu",
                       i, planeWidth, planeHeight, planeBytesPerRow);
            }
        }
        
        // Attachments
        CFDictionaryRef attachments = CVBufferGetAttachments(imageBuffer, kCVAttachmentMode_ShouldPropagate);
        if (attachments && CFDictionaryGetCount(attachments) > 0) {
            LOG_INFO(@"ImageBuffer Attachments: %ld", CFDictionaryGetCount(attachments));
        }
    }
    
    // Attachments do buffer
    CFArrayRef sampleAttachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, false);
    if (sampleAttachments && CFArrayGetCount(sampleAttachments) > 0) {
        LOG_INFO(@"Sample Attachments: %ld", CFArrayGetCount(sampleAttachments));
        
        CFDictionaryRef attachmentDict = (CFDictionaryRef)CFArrayGetValueAtIndex(sampleAttachments, 0);
        if (attachmentDict) {
            // Verifica alguns attachments comuns
            CFBooleanRef notSync;
            if (CFDictionaryGetValueIfPresent(attachmentDict, kCMSampleAttachmentKey_NotSync, (const void **)&notSync)) {
                LOG_INFO(@"  NotSync: %d", notSync == kCFBooleanTrue);
            }
            
            CFBooleanRef partialSync;
            if (CFDictionaryGetValueIfPresent(attachmentDict, kCMSampleAttachmentKey_PartialSync, (const void **)&partialSync)) {
                LOG_INFO(@"  PartialSync: %d", partialSync == kCFBooleanTrue);
            }
            
            CFBooleanRef independentSubsamples;
            if (CFDictionaryGetValueIfPresent(attachmentDict, kCMSampleAttachmentKey_HasRedundantCoding, (const void **)&independentSubsamples)) {
                LOG_INFO(@"  HasRedundantCoding: %d", independentSubsamples == kCFBooleanTrue);
            }
        }
    }
    
    // Informações sobre a conexão
    if (connection) {
        LOG_INFO(@"Conexão: %p", connection);
        LOG_INFO(@"  Ativa: %d", connection.enabled);
        LOG_INFO(@"  Portas de entrada: %lu", (unsigned long)connection.inputPorts.count);
        
        if ([connection isVideoMirroringSupported]) {
            LOG_INFO(@"  Espelhamento de vídeo: %d", connection.videoMirrored);
        }
        
        if ([connection isVideoOrientationSupported]) {
            LOG_INFO(@"  Orientação de vídeo: %ld", (long)connection.videoOrientation);
        }
    }
    
    // Informações sobre o output
    if (output) {
        LOG_INFO(@"Output: %@ (%p)", [output class], output);
        
        if ([output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
            AVCaptureVideoDataOutput *videoOutput = (AVCaptureVideoDataOutput *)output;
            LOG_INFO(@"  VideoDataOutput Settings: %@", videoOutput.videoSettings);
            LOG_INFO(@"  Delegate: %@ (%p)", [videoOutput.sampleBufferDelegate class], videoOutput.sampleBufferDelegate);
            LOG_INFO(@"  Queue: %@", videoOutput.sampleBufferCallbackQueue);
        }
    }
    
    // Backtrace para ver a pilha de chamadas
    PrintBacktrace();
    
    [bufferLock unlock];
}

@end

%hook AVCaptureSession

- (void)startRunning {
    LOG_INFO(@"⚡️ AVCaptureSession startRunning: %p", self);
    PrintBacktrace();
    %orig;
}

- (void)stopRunning {
    LOG_INFO(@"⚡️ AVCaptureSession stopRunning: %p", self);
    PrintBacktrace();
    %orig;
}

- (BOOL)addInput:(AVCaptureInput *)input {
    LOG_INFO(@"⚡️ AVCaptureSession addInput: %@ (%p)", [input class], input);
    
    if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
        AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
        LOG_INFO(@"  Dispositivo: %@, Posição: %ld", deviceInput.device.localizedName, (long)deviceInput.device.position);
    }
    
    BOOL result = %orig;
    LOG_INFO(@"  Resultado: %d", result);
    return result;
}

- (void)removeInput:(AVCaptureInput *)input {
    LOG_INFO(@"⚡️ AVCaptureSession removeInput: %@ (%p)", [input class], input);
    %orig;
}

- (BOOL)addOutput:(AVCaptureOutput *)output {
    LOG_INFO(@"⚡️ AVCaptureSession addOutput: %@ (%p)", [output class], output);
    
    BOOL result = %orig;
    LOG_INFO(@"  Resultado: %d", result);
    return result;
}

- (void)removeOutput:(AVCaptureOutput *)output {
    LOG_INFO(@"⚡️ AVCaptureSession removeOutput: %@ (%p)", [output class], output);
    %orig;
}

- (void)beginConfiguration {
    LOG_INFO(@"⚡️ AVCaptureSession beginConfiguration: %p", self);
    %orig;
}

- (void)commitConfiguration {
    LOG_INFO(@"⚡️ AVCaptureSession commitConfiguration: %p", self);
    %orig;
    
    // Bom momento para analisar a configuração atualizada
    [NSObject analyzeSession:self];
}

%end

%hook AVCaptureVideoPreviewLayer

- (id)initWithSession:(AVCaptureSession *)session {
    LOG_INFO(@"⚡️ AVCaptureVideoPreviewLayer initWithSession: %p", session);
    id result = %orig;
    LOG_INFO(@"  Resultado: %@ (%p)", [result class], result);
    return result;
}

- (void)setSession:(AVCaptureSession *)session {
    LOG_INFO(@"⚡️ AVCaptureVideoPreviewLayer setSession: %p", session);
    %orig;
}

- (void)setVideoGravity:(AVLayerVideoGravity)videoGravity {
    LOG_INFO(@"⚡️ AVCaptureVideoPreviewLayer setVideoGravity: %@", videoGravity);
    %orig;
}

%end

%hook AVCaptureDevice

+ (NSArray<AVCaptureDevice *> *)devicesWithMediaType:(AVMediaType)mediaType {
    NSArray<AVCaptureDevice *> *devices = %orig;
    LOG_INFO(@"⚡️ AVCaptureDevice devicesWithMediaType: %@, Encontrados: %lu", mediaType, (unsigned long)devices.count);
    
    for (AVCaptureDevice *device in devices) {
        LOG_INFO(@"  Dispositivo: %@, Posição: %ld", device.localizedName, (long)device.position);
    }
    
    return devices;
}

+ (AVCaptureDevice *)defaultDeviceWithMediaType:(AVMediaType)mediaType {
    AVCaptureDevice *device = %orig;
    LOG_INFO(@"⚡️ AVCaptureDevice defaultDeviceWithMediaType: %@, Resultado: %@", mediaType, device.localizedName);
    return device;
}

- (BOOL)lockForConfiguration:(NSError **)outError {
    BOOL result = %orig;
    LOG_INFO(@"⚡️ AVCaptureDevice lockForConfiguration: %@, Resultado: %d", self.localizedName, result);
    return result;
}

- (void)unlockForConfiguration {
    LOG_INFO(@"⚡️ AVCaptureDevice unlockForConfiguration: %@", self.localizedName);
    %orig;
}

%end

// Hook no método principais do delegado
%hook NSObject

// Verifica dinamicamente se a classe implementa o método do delegado
- (BOOL)respondsToSelector:(SEL)aSelector {
    BOOL result = %orig;
    
    if (result && aSelector == @selector(captureOutput:didOutputSampleBuffer:fromConnection:)) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            LOG_INFO(@"Detectado delegado AVCaptureVideoDataOutputSampleBufferDelegate: %@", [self class]);
        });
    }
    
    return result;
}

%end
