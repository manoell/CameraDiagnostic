#import "logger.h"
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <objc/runtime.h>

// Verificação de versão do iOS
#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v)  ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)

// Variáveis globais para rastrear informações sobre a câmera
//static BOOL g_diagActive = YES;
static NSString *g_currentAppName = nil;
static NSString *g_currentAppBundle = nil;
static int g_videoOrientation = 0;
static CGSize g_captureResolution = CGSizeZero;
static NSMutableArray *g_cameraClasses = nil;
static NSMutableDictionary *g_delegateClasses = nil;
static NSMutableDictionary *g_cameraFlow = nil;
static int g_callSequence = 0;
static NSMutableDictionary *g_cameraConfigs = nil;

// Função para verificar se o aplicativo atual usa câmera
static BOOL isAppUsingCamera() {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSString *processName = [NSProcessInfo processInfo].processName;
    
    // Lista de aplicativos conhecidos que usam câmera
    NSArray *knownCameraApps = @[
        @"com.apple.camera",
        @"org.telegram.messenger",
        @"net.whatsapp.WhatsApp",
        @"com.instagram.Instagram",
        @"com.burbn.instagram",
        @"com.facebook.Messenger",
        @"com.zhiliaoapp.musically",
        @"com.atebits.Tweetie2"
    ];
    
    // Se for um aplicativo de câmera conhecido, retorne true
    if (bundleID && [knownCameraApps containsObject:bundleID]) {
        return YES;
    }
    
    // Se for o processo de Fotos ou Câmera, retorne true
    if ([processName isEqualToString:@"Camera"] ||
        [processName isEqualToString:@"MobileSlideShow"]) {
        return YES;
    }
    
    // Para outros aplicativos, carregamos de forma mais seletiva
    return NO;
}

// Função para verificar se é seguro executar um hook (verificação por app)
static BOOL isSafeToRunHook() {
    // Se o aplicativo não usa câmera por padrão, ignore os hooks
    if (!isAppUsingCamera()) {
        return NO;
    }
    
    // Para aplicativos específicos, podemos personalizar comportamentos
    NSString *appBundle = [[NSBundle mainBundle] bundleIdentifier];
    
    // Exemplos de personalizações por aplicativo
    if ([appBundle isEqualToString:@"org.telegram.messenger"]) {
        // Configurações específicas para o Telegram
        return YES;
    }
    
    if ([appBundle isEqualToString:@"net.whatsapp.WhatsApp"]) {
        // Configurações específicas para o WhatsApp
        return YES;
    }
    
    // Por padrão, permitir hooks em aplicativos de câmera
    return YES;
}

// Função para registrar informações do aplicativo atual
static void registerCurrentApp() {
    @try {
        if (!g_currentAppName) {
            g_currentAppName = [NSProcessInfo processInfo].processName;
            g_currentAppBundle = [[NSBundle mainBundle] bundleIdentifier];
            writeLog(@"[APP] Diagnóstico iniciado em: %@ (%@)", g_currentAppName, g_currentAppBundle);
            
            // Inicializar estruturas de dados
            if (!g_cameraClasses) {
                g_cameraClasses = [NSMutableArray new];
            }
            
            if (!g_delegateClasses) {
                g_delegateClasses = [NSMutableDictionary new];
            }
            
            if (!g_cameraFlow) {
                g_cameraFlow = [NSMutableDictionary new];
            }
            
            if (!g_cameraConfigs) {
                g_cameraConfigs = [NSMutableDictionary new];
            }
        }
    } @catch (NSException *exception) {
        writeLog(@"[ERROR] Erro ao registrar app: %@", exception);
    }
}

// Função para registrar uma classe relacionada à câmera
static void registerCameraClass(NSString *className) {
    @try {
        registerCurrentApp();
        
        if (className && ![g_cameraClasses containsObject:className]) {
            [g_cameraClasses addObject:className];
            writeLog(@"[CLASS] Detectada classe de câmera: %@", className);
        }
    } @catch (NSException *exception) {
        writeLog(@"[ERROR] Erro ao registrar classe: %@", exception);
    }
}

// Função para registrar um delegado
static void registerDelegate(NSString *delegateClass, NSString *protocolName) {
    @try {
        registerCurrentApp();
        
        if (delegateClass && protocolName && ![g_delegateClasses objectForKey:delegateClass]) {
            [g_delegateClasses setObject:protocolName forKey:delegateClass];
            writeLog(@"[DELEGATE] Registrado: %@ implementando %@", delegateClass, protocolName);
        }
    } @catch (NSException *exception) {
        writeLog(@"[ERROR] Erro ao registrar delegado: %@", exception);
    }
}

// Função para registrar fluxo de chamadas da câmera
static void registerCameraFlow(NSString *method, NSString *details) {
    @try {
        registerCurrentApp();
        
        if (method && details) {
            g_callSequence++;
            NSString *key = [NSString stringWithFormat:@"%04d_%@", g_callSequence, method];
            [g_cameraFlow setObject:details forKey:key];
            writeLog(@"[FLOW:%04d] %@ -> %@", g_callSequence, method, details);
        }
    } @catch (NSException *exception) {
        writeLog(@"[ERROR] Erro ao registrar fluxo: %@", exception);
    }
}

// Função para registrar configurações da câmera
static void registerCameraConfig(NSString *key, id value) {
    @try {
        registerCurrentApp();
        
        if (key && value) {
            [g_cameraConfigs setObject:value forKey:key];
            writeLog(@"[CONFIG] %@ = %@", key, [value description]);
        }
    } @catch (NSException *exception) {
        writeLog(@"[ERROR] Erro ao registrar configuração: %@", exception);
    }
}

// Função para converter FourCharCode para NSString de forma segura
static NSString *fourCharCodeToString(FourCharCode code) {
    @try {
        char str[5] = {0};
        str[0] = (char)((code >> 24) & 0xFF);
        str[1] = (char)((code >> 16) & 0xFF);
        str[2] = (char)((code >> 8) & 0xFF);
        str[3] = (char)(code & 0xFF);
        return [NSString stringWithUTF8String:str];
    } @catch (NSException *exception) {
        writeLog(@"[ERROR] Erro ao converter FourCharCode: %@", exception);
        return @"unknown";
    }
}

// Função para exportar o diagnóstico completo para arquivo JSON
static void exportDiagnosticData() {
    @try {
        registerCurrentApp();
        
        NSDictionary *diagnosticData = @{
            @"appName": g_currentAppName ?: @"Unknown",
            @"bundleID": g_currentAppBundle ?: @"Unknown",
            @"cameraClasses": g_cameraClasses ?: @[],
            @"delegateClasses": g_delegateClasses ?: @{},
            @"cameraFlow": g_cameraFlow ?: @{},
            @"cameraConfigs": g_cameraConfigs ?: @{},
            @"captureResolution": NSStringFromCGSize(g_captureResolution),
            @"videoOrientation": @(g_videoOrientation),
            @"timestamp": [NSDate date].description
        };
        
        NSError *error;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:diagnosticData
                                                           options:NSJSONWritingPrettyPrinted
                                                             error:&error];
        
        if (jsonData) {
            NSString *appSpecificName = [g_currentAppName stringByReplacingOccurrencesOfString:@" " withString:@"_"];
            NSString *filename = [NSString stringWithFormat:@"/var/tmp/CameraDiag_%@_%ld.json",
                                 appSpecificName, (long)[[NSDate date] timeIntervalSince1970]];
            
            [jsonData writeToFile:filename atomically:YES];
            writeLog(@"[EXPORT] Diagnóstico exportado para: %@", filename);
        } else {
            writeLog(@"[EXPORT] Erro ao serializar diagnóstico: %@", error);
        }
    } @catch (NSException *exception) {
        writeLog(@"[ERROR] Erro ao exportar diagnóstico: %@", exception);
    }
}

// Função para examinar uma classe e seus métodos de forma segura
static void inspectClass(Class cls) {
    @try {
        if (!cls) return;
        
        NSString *className = NSStringFromClass(cls);
        
        // Ignorar classes do sistema que não são relevantes
        if ([className hasPrefix:@"NS"] || [className hasPrefix:@"__NS"] ||
            [className hasPrefix:@"OS_"] || [className hasPrefix:@"_UIKit"]) {
            return;
        }
        
        registerCameraClass(className);
        
        // Registrar protocolos implementados
        unsigned int protocolCount;
        Protocol * __unsafe_unretained * protocols = class_copyProtocolList(cls, &protocolCount);
        
        if (protocols) {
            for (unsigned int i = 0; i < protocolCount; i++) {
                Protocol *protocol = protocols[i];
                NSString *protocolName = [NSString stringWithUTF8String:protocol_getName(protocol)];
                
                if ([protocolName containsString:@"AVCapture"] ||
                    [protocolName containsString:@"Camera"] ||
                    [protocolName containsString:@"Photo"]) {
                    registerDelegate(className, protocolName);
                }
            }
            
            free(protocols);
        }
    } @catch (NSException *exception) {
        writeLog(@"[ERROR] Erro ao inspecionar classe: %@", exception);
    }
}

// Implementação dos hooks principais - com proteção extra contra crashes

%group DiagnosticHooks

// Hook para AVCaptureSession para detectar início da câmera
%hook AVCaptureSession

- (void)startRunning {
    if (!isSafeToRunHook()) {
        %orig;
        return;
    }
    
    @try {
        writeLog(@"[HOOK] AVCaptureSession startRunning");
        registerCameraClass(NSStringFromClass([self class]));
        registerCameraFlow(@"startRunning", @"Iniciando sessão de captura");
        
        // Examinar e registrar as entradas da sessão
        NSArray *inputs = [self inputs];
        for (AVCaptureInput *input in inputs) {
            registerCameraClass(NSStringFromClass([input class]));
            
            if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
                AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
                AVCaptureDevice *device = deviceInput.device;
                
                registerCameraConfig(@"deviceType", device.deviceType);
                registerCameraConfig(@"devicePosition", @(device.position));
                registerCameraConfig(@"deviceLocalizedName", device.localizedName);
                
                // Obter formato ativo e resolução
                AVCaptureDeviceFormat *format = device.activeFormat;
                if (format) {
                    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
                    g_captureResolution = CGSizeMake(dimensions.width, dimensions.height);
                    
                    registerCameraConfig(@"activeFormatDimensions", NSStringFromCGSize(g_captureResolution));
                    
                    // Usar nossa função auxiliar para converter FourCharCode para NSString
                    FourCharCode mediaType = CMFormatDescriptionGetMediaType(format.formatDescription);
                    registerCameraConfig(@"activeFormatMediaType", fourCharCodeToString(mediaType));
                    
                    if (format.videoSupportedFrameRateRanges.count > 0) {
                        registerCameraConfig(@"activeFormatMaxFrameRate", @(format.videoSupportedFrameRateRanges.firstObject.maxFrameRate));
                    }
                }
            }
        }
        
        // Examinar e registrar as saídas da sessão
        NSArray *outputs = [self outputs];
        for (AVCaptureOutput *output in outputs) {
            registerCameraClass(NSStringFromClass([output class]));
            
            // Registrar conexões
            for (AVCaptureConnection *connection in [output connections]) {
                g_videoOrientation = connection.videoOrientation;
                registerCameraConfig(@"videoOrientation", @(connection.videoOrientation));
                registerCameraConfig(@"videoMirrored", @(connection.isVideoMirrored));
                registerCameraConfig(@"videoStabilizationEnabled", @(connection.preferredVideoStabilizationMode));
            }
            
            // Verificar delegados de saída
            if ([output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
                AVCaptureVideoDataOutput *videoOutput = (AVCaptureVideoDataOutput *)output;
                id<AVCaptureVideoDataOutputSampleBufferDelegate> delegate = [videoOutput sampleBufferDelegate];
                if (delegate) {
                    inspectClass([delegate class]);
                }
                
                // Registrar configurações de formato de saída
                NSDictionary *settings = videoOutput.videoSettings;
                NSNumber *pixelFormat = settings[@"PixelFormatType"];
                if (pixelFormat) {
                    registerCameraConfig(@"videoOutputPixelFormat", pixelFormat);
                } else {
                    // Tentar com kCVPixelBufferPixelFormatTypeKey
                    pixelFormat = settings[(id)kCVPixelBufferPixelFormatTypeKey];
                    if (pixelFormat) {
                        registerCameraConfig(@"videoOutputPixelFormat", pixelFormat);
                    }
                }
            }
            else if ([output isKindOfClass:[AVCapturePhotoOutput class]]) {
                AVCapturePhotoOutput *photoOutput = (AVCapturePhotoOutput *)output;
                
                // Verificar suporte a propriedades em tempo de execução
                if ([photoOutput respondsToSelector:@selector(availablePhotoPixelFormatTypes)]) {
                    registerCameraConfig(@"photoOutputAvailablePhotoPixelFormats", photoOutput.availablePhotoPixelFormatTypes);
                }
            }
        }
    } @catch (NSException *exception) {
        writeLog(@"[ERROR] Erro em startRunning: %@", exception);
    }
    
    %orig;
}

- (void)stopRunning {
    if (!isSafeToRunHook()) {
        %orig;
        return;
    }
    
    @try {
        writeLog(@"[HOOK] AVCaptureSession stopRunning");
        registerCameraFlow(@"stopRunning", @"Parando sessão de captura");
        
        // Exportar dados quando a sessão for encerrada
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            exportDiagnosticData();
        });
    } @catch (NSException *exception) {
        writeLog(@"[ERROR] Erro em stopRunning: %@", exception);
    }
    
    %orig;
}

- (void)addInput:(AVCaptureInput *)input {
    if (!isSafeToRunHook()) {
        %orig;
        return;
    }
    
    @try {
        writeLog(@"[HOOK] AVCaptureSession addInput: %@", NSStringFromClass([input class]));
        registerCameraFlow(@"addInput", NSStringFromClass([input class]));
        
        if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
            AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
            registerCameraConfig(@"inputDeviceType", deviceInput.device.deviceType);
            registerCameraConfig(@"inputDevicePosition", @(deviceInput.device.position));
        }
    } @catch (NSException *exception) {
        writeLog(@"[ERROR] Erro em addInput: %@", exception);
    }
    
    %orig;
}

- (void)addOutput:(AVCaptureOutput *)output {
    if (!isSafeToRunHook()) {
        %orig;
        return;
    }
    
    @try {
        writeLog(@"[HOOK] AVCaptureSession addOutput: %@", NSStringFromClass([output class]));
        registerCameraFlow(@"addOutput", NSStringFromClass([output class]));
    } @catch (NSException *exception) {
        writeLog(@"[ERROR] Erro em addOutput: %@", exception);
    }
    
    %orig;
}

%end

// Hook para AVCaptureVideoDataOutput para capturar delegados de processamento
%hook AVCaptureVideoDataOutput

- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    if (!isSafeToRunHook()) {
        %orig;
        return;
    }
    
    @try {
        NSString *delegateClass = sampleBufferDelegate ? NSStringFromClass([sampleBufferDelegate class]) : @"(null)";
        writeLog(@"[HOOK] AVCaptureVideoDataOutput setSampleBufferDelegate: %@", delegateClass);
        registerCameraFlow(@"setSampleBufferDelegate", delegateClass);
        
        if (sampleBufferDelegate) {
            inspectClass([sampleBufferDelegate class]);
        }
    } @catch (NSException *exception) {
        writeLog(@"[ERROR] Erro em setSampleBufferDelegate: %@", exception);
    }
    
    %orig;
}

%end

// Hook para conexões da câmera para monitorar orientação
%hook AVCaptureConnection

- (void)setVideoOrientation:(AVCaptureVideoOrientation)videoOrientation {
    if (!isSafeToRunHook()) {
        %orig;
        return;
    }
    
    @try {
        writeLog(@"[HOOK] AVCaptureConnection setVideoOrientation: %ld", (long)videoOrientation);
        registerCameraFlow(@"setVideoOrientation", [NSString stringWithFormat:@"%ld", (long)videoOrientation]);
        
        g_videoOrientation = videoOrientation;
        
        NSString *orientationDesc;
        switch ((int)videoOrientation) {
            case 1: orientationDesc = @"Portrait"; break;
            case 2: orientationDesc = @"PortraitUpsideDown"; break;
            case 3: orientationDesc = @"LandscapeRight"; break;
            case 4: orientationDesc = @"LandscapeLeft"; break;
            default: orientationDesc = @"Unknown"; break;
        }
        
        registerCameraConfig(@"videoOrientationValue", @(videoOrientation));
        registerCameraConfig(@"videoOrientationDesc", orientationDesc);
    } @catch (NSException *exception) {
        writeLog(@"[ERROR] Erro em setVideoOrientation: %@", exception);
    }
    
    %orig;
}

%end

// Hook para captura de fotos
%hook AVCapturePhotoOutput

- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    if (!isSafeToRunHook()) {
        %orig;
        return;
    }
    
    @try {
        writeLog(@"[HOOK] AVCapturePhotoOutput capturePhotoWithSettings");
        registerCameraFlow(@"capturePhotoWithSettings", NSStringFromClass([delegate class]));
        
        if (delegate) {
            inspectClass([delegate class]);
        }
        
        // Registrar configurações da foto
        if (settings) {
            registerCameraConfig(@"photoSettingsFormat", settings.format);
            registerCameraConfig(@"photoSettingsPreviewFormat", settings.previewPhotoFormat);
            registerCameraConfig(@"photoSettingsFlashMode", @(settings.flashMode));
        }
    } @catch (NSException *exception) {
        writeLog(@"[ERROR] Erro em capturePhotoWithSettings: %@", exception);
    }
    
    %orig;
}

%end

// Hook para representação final da foto
%hook AVCapturePhoto

- (NSData *)fileDataRepresentation {
    if (!isSafeToRunHook()) {
        return %orig;
    }
    
    NSData *data = %orig;
    
    @try {
        writeLog(@"[HOOK] AVCapturePhoto fileDataRepresentation");
        registerCameraFlow(@"fileDataRepresentation", @"Obtendo representação de arquivo da foto");
        
        if (data) {
            registerCameraConfig(@"capturePhotoDataSize", @(data.length));
        }
    } @catch (NSException *exception) {
        writeLog(@"[ERROR] Erro em fileDataRepresentation: %@", exception);
    }
    
    return data;
}

%end

// Hook para gravação de vídeo
%hook AVCaptureMovieFileOutput

- (void)startRecordingToOutputFileURL:(NSURL *)outputFileURL recordingDelegate:(id<AVCaptureFileOutputRecordingDelegate>)delegate {
    if (!isSafeToRunHook()) {
        %orig;
        return;
    }
    
    @try {
        writeLog(@"[HOOK] AVCaptureMovieFileOutput startRecordingToOutputFileURL: %@", outputFileURL.path);
        registerCameraFlow(@"startRecordingVideo", outputFileURL.path);
        registerCameraConfig(@"videoOutputURL", outputFileURL.path);
        registerCameraConfig(@"videoRecordingDelegate", NSStringFromClass([delegate class]));
        
        if (delegate) {
            inspectClass([delegate class]);
        }
    } @catch (NSException *exception) {
        writeLog(@"[ERROR] Erro em startRecordingToOutputFileURL: %@", exception);
    }
    
    %orig;
}

- (void)stopRecording {
    if (!isSafeToRunHook()) {
        %orig;
        return;
    }
    
    @try {
        writeLog(@"[HOOK] AVCaptureMovieFileOutput stopRecording");
        registerCameraFlow(@"stopRecordingVideo", @"Finalizando gravação de vídeo");
    } @catch (NSException *exception) {
        writeLog(@"[ERROR] Erro em stopRecording: %@", exception);
    }
    
    %orig;
}

%end

%end // grupo DiagnosticHooks

// Grupo para hooks relacionados a callbacks e delegados - mais críticos e precisa de mais proteções
%group CallbackHooks

%hook NSObject

// Método crítico para processamento de frames de vídeo - PRINCIPAL PONTO DE INJEÇÃO
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (![self respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)] || !isSafeToRunHook()) {
        return %orig;
    }
    
    @try {
        static NSString *lastClassName = nil;
        NSString *className = NSStringFromClass([self class]);
        
        // Evitar logging excessivo registrando apenas na primeira vez ou quando mudar de classe
        if (!lastClassName || ![lastClassName isEqualToString:className]) {
            writeLog(@"[HOOK] %@ captureOutput:didOutputSampleBuffer", className);
            registerCameraFlow(@"captureOutput:didOutputSampleBuffer", className);
            lastClassName = className;
            
            // Registrar resolução do buffer
            if (sampleBuffer && CMSampleBufferIsValid(sampleBuffer)) {
                CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
                if (imageBuffer) {
                    size_t width = CVPixelBufferGetWidth(imageBuffer);
                    size_t height = CVPixelBufferGetHeight(imageBuffer);
                    OSType pixelFormat = CVPixelBufferGetPixelFormatType(imageBuffer);
                    
                    g_captureResolution = CGSizeMake(width, height);
                    registerCameraConfig(@"sampleBufferResolution", NSStringFromCGSize(g_captureResolution));
                    registerCameraConfig(@"sampleBufferPixelFormat", @(pixelFormat));
                    
                    // Examinar as propriedades do formato
                    CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
                    if (formatDesc) {
                        FourCharCode mediaType = CMFormatDescriptionGetMediaType(formatDesc);
                        FourCharCode mediaSubType = CMFormatDescriptionGetMediaSubType(formatDesc);
                        
                        registerCameraConfig(@"mediaType", fourCharCodeToString(mediaType));
                        registerCameraConfig(@"mediaSubType", fourCharCodeToString(mediaSubType));
                    }
                }
            }
        }
    } @catch (NSException *exception) {
        writeLog(@"[ERROR] Erro em didOutputSampleBuffer: %@", exception);
    }
    
    %orig;
}

// Método para callback de processamento de foto
- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(NSError *)error {
    if (![self respondsToSelector:@selector(captureOutput:didFinishProcessingPhoto:error:)] || !isSafeToRunHook()) {
        return %orig;
    }
    
    @try {
        writeLog(@"[HOOK] didFinishProcessingPhoto");
        registerCameraFlow(@"didFinishProcessingPhoto", NSStringFromClass([photo class]));
        
        if (error) {
            registerCameraConfig(@"photoProcessingError", error.localizedDescription);
        } else if (photo) {
            // Registrar metadados disponíveis de forma segura
            NSDictionary *metadata = photo.metadata;
            if (metadata) {
                // Registrar algumas informações EXIF importantes
                NSDictionary *exif = metadata[(NSString *)kCGImagePropertyExifDictionary];
                if (exif) {
                    registerCameraConfig(@"capturedPhotoExifKeys", [exif allKeys]);
                }
                
                // Registrar orientação da imagem
                NSNumber *orientation = metadata[(NSString *)kCGImagePropertyOrientation];
                if (orientation) {
                    registerCameraConfig(@"capturedPhotoOrientation", orientation);
                }
            }
        }
    } @catch (NSException *exception) {
        writeLog(@"[ERROR] Erro em didFinishProcessingPhoto: %@", exception);
    }
    
    %orig;
}

// Método para finalização de gravação de vídeo
- (void)captureOutput:(AVCaptureFileOutput *)output didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray<AVCaptureConnection *> *)connections error:(NSError *)error {
    if (![self respondsToSelector:@selector(captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:)] || !isSafeToRunHook()) {
        return %orig;
    }
    
    @try {
        writeLog(@"[HOOK] didFinishRecordingToOutputFileAtURL: %@", outputFileURL.path);
        registerCameraFlow(@"didFinishRecordingVideo", outputFileURL.path);
        
        if (error) {
            registerCameraConfig(@"videoRecordingError", error.localizedDescription);
        }
    } @catch (NSException *exception) {
        writeLog(@"[ERROR] Erro em didFinishRecordingToOutputFileAtURL: %@", exception);
    }
    
    %orig;
}

%end

%end // grupo CallbackHooks

// Carregar o hook
%ctor {
    @autoreleasepool {
        setLogLevel(5); // Nível de log máximo para diagnóstico
        
        // Adicionar try-catch global
        @try {
            writeLog(@"[INIT] CameraDiagnostic carregado em: %@", [NSProcessInfo processInfo].processName);
            
            // Registrar app atual
            registerCurrentApp();
            
            // Inicializar os hooks principais
            %init(DiagnosticHooks);
            
            // Inicializar os hooks de callback
            %init(CallbackHooks);
            
            // Exportar diagnóstico quando o aplicativo for fechado
            NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
            [center addObserverForName:UIApplicationWillTerminateNotification
                                object:nil
                                 queue:nil
                            usingBlock:^(NSNotification *note) {
                                @try {
                                    writeLog(@"[APP] Aplicativo será encerrado, exportando diagnóstico final");
                                    exportDiagnosticData();
                                } @catch (NSException *exception) {
                                    writeLog(@"[ERROR] Erro em observer de término: %@", exception);
                                }
                            }];
            
        } @catch (NSException *exception) {
            writeLog(@"[ERROR] Erro na inicialização: %@", exception);
        }
    }
}
