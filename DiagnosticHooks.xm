#import "DiagnosticTweak.h"

// Variáveis para registro de dados por aplicativo
static NSMutableDictionary *appDiagnosticData = nil;

// Flag para controlar se o app atual deve ser monitorado
static BOOL g_isTargetApp = NO;

// Declarações antecipadas de funções
static void saveDiagnosticData(void);
static void logToFile(NSString *message);

// Verificar se o aplicativo é adequado para diagnóstico
static BOOL isAppSuitableForDiagnostic() {
    // Lista de bundle IDs conhecidos por causarem problemas
    static NSArray *excludedBundleIds = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        excludedBundleIds = @[
            @"com.apple.springboard",
            @"com.apple.backboardd",
            // Outros processos do sistema podem ser adicionados aqui
        ];
    });
    
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
    
    // Verifica se o bundle ID está na lista de exclusão
    if ([excludedBundleIds containsObject:bundleId]) {
        return NO;
    }
    
    return YES;
}

// Ativar diagnóstico para o app atual
static void activateForCurrentApp() {
    if (g_isTargetApp) return; // Já ativado
    
    // Verificar se este app deve ser monitorado
    if (!isAppSuitableForDiagnostic()) return;
    
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
    NSString *appName = [NSProcessInfo processInfo].processName;
    
    g_isTargetApp = YES;
    
    // Inicializar dicionário de diagnóstico
    if (!appDiagnosticData) {
        appDiagnosticData = [NSMutableDictionary dictionary];
    }
    
    // Registrar ativação
    logToFile([NSString stringWithFormat:@"Ativando diagnóstico para: %@ (%@)", appName, bundleId]);
    
    // Iniciar sessão de diagnóstico
    startNewDiagnosticSession();
}

// Log para arquivo de texto com prevenção de erros - similar ao vcam_log do VCamWebRTC
static void logToFile(NSString *message) {
    if (!message) return;
    
    @try {
        NSString *logDir = @"/var/tmp/CameraDiagnostic";
        NSString *logFile = [logDir stringByAppendingPathComponent:@"diagnostic.log"];
        
        // Adicionar timestamp e info do app
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        NSString *timestamp = [formatter stringFromDate:[NSDate date]];
        NSString *appInfo = [NSString stringWithFormat:@"%@ (%@)",
                             [NSProcessInfo processInfo].processName,
                             [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown"];
        NSString *logMessage = [NSString stringWithFormat:@"[%@] [%@] %@\n", timestamp, appInfo, message];
        
        // Criar arquivo ou adicionar ao existente - abordagem similar ao VCamWebRTC
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:logDir]) {
            [fileManager createDirectoryAtPath:logDir
                  withIntermediateDirectories:YES
                                   attributes:nil
                                        error:nil];
        }
        
        if (![fileManager fileExistsAtPath:logFile]) {
            [logMessage writeToFile:logFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
        } else {
            NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:logFile];
            if (fileHandle) {
                [fileHandle seekToEndOfFile];
                [fileHandle writeData:[logMessage dataUsingEncoding:NSUTF8StringEncoding]];
                [fileHandle closeFile];
            }
        }
    } @catch (NSException *exception) {
        // NSLog é seguro e não deve causar crashes
        NSLog(@"[CameraDiagnostic] Erro ao registrar log: %@", exception);
    }
}

// Adicionar dados para o diagnóstico do aplicativo atual
static void addDiagnosticData(NSString *eventType, NSDictionary *eventData) {
    if (!eventType || !eventData || !g_isTargetApp) return;
    
    @try {
        @synchronized(appDiagnosticData) {
            if (!appDiagnosticData) {
                appDiagnosticData = [NSMutableDictionary dictionary];
            }
            
            NSString *appName = [NSProcessInfo processInfo].processName;
            NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
            
            // Garantir que temos dados para este app
            if (!appDiagnosticData[bundleId]) {
                appDiagnosticData[bundleId] = [NSMutableDictionary dictionary];
                appDiagnosticData[bundleId][@"appName"] = appName;
                appDiagnosticData[bundleId][@"bundleId"] = bundleId;
                appDiagnosticData[bundleId][@"timestamp"] = [NSDate date].description;
                appDiagnosticData[bundleId][@"deviceModel"] = [[UIDevice currentDevice] model];
                appDiagnosticData[bundleId][@"iosVersion"] = [[UIDevice currentDevice] systemVersion];
                appDiagnosticData[bundleId][@"events"] = [NSMutableArray array];
            }
            
            // Adicionar evento com timestamp
            NSMutableDictionary *event = [NSMutableDictionary dictionaryWithDictionary:eventData];
            event[@"eventType"] = eventType;
            event[@"timestamp"] = [NSDate date].description;
            
            // Adicionar à lista de eventos
            NSMutableArray *events = appDiagnosticData[bundleId][@"events"];
            [events addObject:event];
            
            // Salvar dados atualizados
            saveDiagnosticData();
        }
    } @catch (NSException *exception) {
        logToFile([NSString stringWithFormat:@"Erro ao adicionar dados de diagnóstico: %@", exception]);
    }
}

// Salvar os dados coletados em um arquivo JSON por aplicativo
static void saveDiagnosticData(void) {
    if (!appDiagnosticData || !g_isTargetApp) return;
    
    @try {
        NSString *logDir = @"/var/tmp/CameraDiagnostic";
        NSFileManager *fileManager = [NSFileManager defaultManager];
        
        // Verificar se o diretório existe e criar se não existir
        if (![fileManager fileExistsAtPath:logDir]) {
            [fileManager createDirectoryAtPath:logDir
                  withIntermediateDirectories:YES
                                   attributes:nil
                                        error:nil];
        }
        
        @synchronized(appDiagnosticData) {
            for (NSString *bundleId in appDiagnosticData) {
                NSDictionary *appData = appDiagnosticData[bundleId];
                NSString *appName = appData[@"appName"];
                
                if (!appName || !bundleId) continue;
                
                // Criar nome de arquivo com app
                NSString *filename = [NSString stringWithFormat:@"%@_%@_diagnostics.json", appName, bundleId];
                NSString *filePath = [logDir stringByAppendingPathComponent:filename];
                
                // Salvar como JSON
                NSError *error;
                NSData *jsonData = [NSJSONSerialization dataWithJSONObject:appData
                                                                   options:NSJSONWritingPrettyPrinted
                                                                     error:&error];
                if (jsonData) {
                    [jsonData writeToFile:filePath atomically:YES];
                    logToFile([NSString stringWithFormat:@"Diagnóstico atualizado para %@", appName]);
                } else {
                    logToFile([NSString stringWithFormat:@"Erro ao salvar diagnóstico: %@", error.localizedDescription]);
                }
            }
        }
    } @catch (NSException *exception) {
        logToFile([NSString stringWithFormat:@"Erro ao salvar dados de diagnóstico: %@", exception]);
    }
}

// Hook para AVCaptureDevice igual ao do VCamWebRTC
%hook AVCaptureDevice

+ (AVCaptureDevice *)defaultDeviceWithMediaType:(NSString *)mediaType {
    AVCaptureDevice *device = %orig;
    
    @try {
        if ([mediaType isEqualToString:AVMediaTypeVideo]) {
            // Quando um app solicita a câmera, marcamos como app de interesse
            activateForCurrentApp();
            
            NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
            NSString *appName = [NSProcessInfo processInfo].processName;
            
            logToFile([NSString stringWithFormat:@"Câmera solicitada por: %@ (%@)", appName, bundleId]);
            
            if (g_isTargetApp && device) {
                addDiagnosticData(@"cameraRequest", @{
                    @"mediaType": mediaType,
                    @"deviceName": device.localizedName ?: @"unknown",
                    @"devicePosition": @(device.position)
                });
            }
        }
    } @catch (NSException *exception) {
        logToFile([NSString stringWithFormat:@"Erro ao processar defaultDeviceWithMediaType: %@", exception]);
    }
    
    return device;
}

%end

// Hook para adicionar camada de visualização similar ao VCamWebRTC
%hook AVCaptureVideoPreviewLayer

- (void)addSublayer:(CALayer *)layer {
    %orig;
    
    @try {
        // Detectar uso da câmera
        activateForCurrentApp();
        
        if (g_isTargetApp) {
            logToFile(@"AVCaptureVideoPreviewLayer addSublayer chamado");
            
            addDiagnosticData(@"previewLayerSublayer", @{
                @"layerClass": NSStringFromClass([layer class]) ?: @"unknown"
            });
        }
    } @catch (NSException *exception) {
        logToFile([NSString stringWithFormat:@"Erro ao processar addSublayer: %@", exception]);
    }
}

%end

// Hook para AVCaptureSession similar ao VCamWebRTC
%hook AVCaptureSession

- (void)startRunning {
    // Detectar uso da câmera
    activateForCurrentApp();
    
    if (g_isTargetApp) {
        logToFile(@"AVCaptureSession startRunning chamado");
        
        @try {
            // Salvar informações da sessão
            NSMutableDictionary *sessionInfo = [NSMutableDictionary dictionary];
            
            // Capturar preset da sessão
            if ([self respondsToSelector:@selector(sessionPreset)]) {
                sessionInfo[@"sessionPreset"] = [self sessionPreset] ?: @"unknown";
            }
            
            // Capturar informações de inputs
            if ([self respondsToSelector:@selector(inputs)]) {
                NSArray *inputs = [self inputs];
                NSMutableArray *inputsInfo = [NSMutableArray array];
                
                for (AVCaptureInput *input in inputs) {
                    NSMutableDictionary *inputDict = [NSMutableDictionary dictionary];
                    inputDict[@"class"] = NSStringFromClass([input class]);
                    
                    if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
                        AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
                        AVCaptureDevice *device = deviceInput.device;
                        
                        if (device) {
                            inputDict[@"deviceName"] = device.localizedName ?: @"unknown";
                            inputDict[@"uniqueID"] = device.uniqueID ?: @"unknown";
                            inputDict[@"position"] = @(device.position);
                            
                            // Câmera frontal/traseira
                            BOOL isFrontCamera = (device.position == AVCaptureDevicePositionFront);
                            g_usingFrontCamera = isFrontCamera;
                            inputDict[@"isFrontCamera"] = @(isFrontCamera);
                            
                            // Formato da câmera
                            AVCaptureDeviceFormat *format = device.activeFormat;
                            if (format) {
                                CMFormatDescriptionRef formatDesc = format.formatDescription;
                                if (formatDesc) {
                                    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDesc);
                                    inputDict[@"width"] = @(dimensions.width);
                                    inputDict[@"height"] = @(dimensions.height);
                                    
                                    // Salvar resolução global
                                    CGSize resolution = CGSizeMake(dimensions.width, dimensions.height);
                                    if (isFrontCamera) {
                                        g_frontCameraResolution = resolution;
                                    } else {
                                        g_backCameraResolution = resolution;
                                    }
                                    g_cameraResolution = resolution;
                                    
                                    // Adicionar dimensões ao log
                                    logToFile([NSString stringWithFormat:@"Resolução da câmera: %dx%d",
                                              (int)dimensions.width, (int)dimensions.height]);
                                }
                            }
                            
                            // Detalhes do formato de vídeo
                            if (format) {
                                NSMutableArray *frameRates = [NSMutableArray array];
                                for (AVFrameRateRange *range in format.videoSupportedFrameRateRanges) {
                                    [frameRates addObject:@{
                                        @"minFrameRate": @(range.minFrameRate),
                                        @"maxFrameRate": @(range.maxFrameRate)
                                    }];
                                }
                                inputDict[@"frameRates"] = frameRates;
                            }
                        }
                    }
                    
                    [inputsInfo addObject:inputDict];
                }
                
                sessionInfo[@"inputs"] = inputsInfo;
            }
            
            // Capturar informações de outputs
            if ([self respondsToSelector:@selector(outputs)]) {
                NSArray *outputs = [self outputs];
                NSMutableArray *outputsInfo = [NSMutableArray array];
                
                for (AVCaptureOutput *output in outputs) {
                    NSMutableDictionary *outputDict = [NSMutableDictionary dictionary];
                    outputDict[@"class"] = NSStringFromClass([output class]);
                    
                    if ([output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
                        AVCaptureVideoDataOutput *videoOutput = (AVCaptureVideoDataOutput *)output;
                        outputDict[@"type"] = @"videoData";
                        
                        if (videoOutput.videoSettings) {
                            outputDict[@"videoSettings"] = videoOutput.videoSettings;
                            
                            // Extrair dimensões
                            id widthValue = videoOutput.videoSettings[(id)kCVPixelBufferWidthKey];
                            id heightValue = videoOutput.videoSettings[(id)kCVPixelBufferHeightKey];
                            if (widthValue && heightValue) {
                                outputDict[@"width"] = widthValue;
                                outputDict[@"height"] = heightValue;
                            }
                            
                            // Extrair formato de pixel
                            id formatValue = videoOutput.videoSettings[(id)kCVPixelBufferPixelFormatTypeKey];
                            if (formatValue) {
                                uint32_t pixelFormat = [formatValue unsignedIntValue];
                                char formatStr[5] = {0};
                                formatStr[0] = (pixelFormat >> 24) & 0xFF;
                                formatStr[1] = (pixelFormat >> 16) & 0xFF;
                                formatStr[2] = (pixelFormat >> 8) & 0xFF;
                                formatStr[3] = pixelFormat & 0xFF;
                                
                                outputDict[@"pixelFormat"] = formatValue;
                                outputDict[@"pixelFormatString"] = [NSString stringWithCString:formatStr encoding:NSASCIIStringEncoding];
                            }
                        }
                    }
                    
                    [outputsInfo addObject:outputDict];
                }
                
                sessionInfo[@"outputs"] = outputsInfo;
            }
            
            // Capturar informações de conexões
            if ([self respondsToSelector:@selector(connections)]) {
                NSArray *connections = [self connections];
                NSMutableArray *connectionsInfo = [NSMutableArray array];
                
                for (AVCaptureConnection *connection in connections) {
                    NSMutableDictionary *connectionDict = [NSMutableDictionary dictionary];
                    connectionDict[@"enabled"] = @(connection.enabled);
                    
                    if ([connection isVideoOrientationSupported]) {
                        connectionDict[@"videoOrientationSupported"] = @YES;
                        connectionDict[@"videoOrientation"] = @(connection.videoOrientation);
                        connectionDict[@"videoMirrored"] = @(connection.isVideoMirrored);
                        
                        // Mapear orientação para string
                        NSString *orientationString;
                        switch (connection.videoOrientation) {
                            case AVCaptureVideoOrientationPortrait:
                                orientationString = @"Portrait";
                                break;
                            case AVCaptureVideoOrientationPortraitUpsideDown:
                                orientationString = @"PortraitUpsideDown";
                                break;
                            case AVCaptureVideoOrientationLandscapeRight:
                                orientationString = @"LandscapeRight";
                                break;
                            case AVCaptureVideoOrientationLandscapeLeft:
                                orientationString = @"LandscapeLeft";
                                break;
                            default:
                                orientationString = @"Unknown";
                                break;
                        }
                        connectionDict[@"orientationString"] = orientationString;
                    }
                    
                    // Capturar informações de portas de entrada
                    NSMutableArray *inputPortsInfo = [NSMutableArray array];
                    for (AVCaptureInputPort *port in connection.inputPorts) {
                        [inputPortsInfo addObject:@{
                            @"mediaType": port.mediaType ?: @"unknown",
                            @"sourceDevicePosition": @(port.sourceDevicePosition)
                        }];
                    }
                    connectionDict[@"inputPorts"] = inputPortsInfo;
                    
                    [connectionsInfo addObject:connectionDict];
                }
                
                sessionInfo[@"connections"] = connectionsInfo;
            }
            
            // Adicionar ao diagnóstico do app
            addDiagnosticData(@"sessionStart", sessionInfo);
        } @catch (NSException *exception) {
            logToFile([NSString stringWithFormat:@"Erro ao processar startRunning: %@", exception]);
        }
    }
    
    // Chamar o método original
    %orig;
}

- (void)stopRunning {
    if (g_isTargetApp) {
        logToFile(@"AVCaptureSession stopRunning chamado");
        addDiagnosticData(@"sessionStop", @{@"reason": @"stopRunning chamado"});
    }
    %orig;
}

%end

// Hook para AVCaptureVideoDataOutput similar ao VCamWebRTC
%hook AVCaptureVideoDataOutput

- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    // Detectar uso da câmera
    activateForCurrentApp();
    
    if (g_isTargetApp) {
        logToFile(@"AVCaptureVideoDataOutput setSampleBufferDelegate: chamado");
        
        @try {
            NSMutableDictionary *delegateInfo = [NSMutableDictionary dictionary];
            delegateInfo[@"delegateClass"] = NSStringFromClass([sampleBufferDelegate class]) ?: @"nil";
            delegateInfo[@"hasQueue"] = sampleBufferCallbackQueue ? @YES : @NO;
            
            addDiagnosticData(@"videoDelegate", delegateInfo);
            
            // Baseado no VCamWebRTC: hook dinâmico para o método de delegado
            if (sampleBufferDelegate != nil && sampleBufferCallbackQueue != nil) {
                // Lista para controlar quais classes já foram "hooked"
                static NSMutableArray *hookedDelegates = nil;
                static dispatch_once_t onceToken;
                dispatch_once(&onceToken, ^{
                    hookedDelegates = [NSMutableArray new];
                });
                
                // Obtém o nome da classe do delegate
                NSString *className = NSStringFromClass([sampleBufferDelegate class]);
                
                // Verifica se esta classe já foi "hooked"
                if (![hookedDelegates containsObject:className]) {
                    logToFile([NSString stringWithFormat:@"Hooking delegate class: %@", className]);
                    [hookedDelegates addObject:className];
                    
                    // Hook para o método que recebe cada frame de vídeo
                    __block void (*original_method)(id self, SEL _cmd, AVCaptureOutput *output, CMSampleBufferRef sampleBuffer, AVCaptureConnection *connection) = nil;
                    
                    MSHookMessageEx(
                        [sampleBufferDelegate class],
                        @selector(captureOutput:didOutputSampleBuffer:fromConnection:),
                        imp_implementationWithBlock(^(id self, AVCaptureOutput *output, CMSampleBufferRef sampleBuffer, AVCaptureConnection *connection){
                            // Detectar uso de câmera
                            activateForCurrentApp();
                            
                            if (g_isTargetApp) {
                                static int frameCounter = 0;
                                frameCounter++;
                                
                                // Limitar logging para 1 a cada 100 frames para não sobrecarregar
                                if (frameCounter % 100 == 0) {
                                    @try {
                                        logToFile([NSString stringWithFormat:@"Frame #%d capturado", frameCounter]);
                                        
                                        NSMutableDictionary *frameInfo = [NSMutableDictionary dictionary];
                                        frameInfo[@"frameNumber"] = @(frameCounter);
                                        frameInfo[@"delegateClass"] = NSStringFromClass([self class]);
                                        
                                        // Extrair informações do buffer
                                        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
                                        if (imageBuffer) {
                                            // Dimensões do frame
                                            size_t width = CVPixelBufferGetWidth(imageBuffer);
                                            size_t height = CVPixelBufferGetHeight(imageBuffer);
                                            frameInfo[@"width"] = @(width);
                                            frameInfo[@"height"] = @(height);
                                            
                                            logToFile([NSString stringWithFormat:@"Frame: %zux%zu", width, height]);
                                        }
                                        
                                        // Capturar informações de conexão
                                        if (connection) {
                                            if ([connection isVideoOrientationSupported]) {
                                                AVCaptureVideoOrientation orientation = connection.videoOrientation;
                                                frameInfo[@"videoOrientation"] = @(orientation);
                                                
                                                // Salvar orientação global
                                                g_videoOrientation = (int)orientation;
                                            }
                                            
                                            // Espelhamento
                                            frameInfo[@"videoMirrored"] = @(connection.isVideoMirrored);
                                        }
                                        
                                        // Adicionar ao diagnóstico
                                        addDiagnosticData(@"videoFrame", frameInfo);
                                    } @catch (NSException *exception) {
                                        logToFile([NSString stringWithFormat:@"Erro ao processar frame: %@", exception]);
                                    }
                                }
                            }
                            
                            // Chamar o método original
                            return original_method(self, @selector(captureOutput:didOutputSampleBuffer:fromConnection:), output, sampleBuffer, connection);
                        }), (IMP*)&original_method
                    );
                }
            }
        } @catch (NSException *exception) {
            logToFile([NSString stringWithFormat:@"Erro ao processar setSampleBufferDelegate: %@", exception]);
        }
    }
    
    %orig;
}

- (void)setVideoSettings:(NSDictionary<NSString *,id> *)videoSettings {
    // Detectar uso da câmera
    activateForCurrentApp();
    
    if (g_isTargetApp) {
        logToFile(@"AVCaptureVideoDataOutput setVideoSettings: chamado");
        
        @try {
            NSMutableDictionary *settingsInfo = [NSMutableDictionary dictionary];
            settingsInfo[@"fullSettings"] = videoSettings ?: @{};
            
            // Extrair dimensões e formato de pixel
            id widthValue = videoSettings[(id)kCVPixelBufferWidthKey];
            id heightValue = videoSettings[(id)kCVPixelBufferHeightKey];
            id formatValue = videoSettings[(id)kCVPixelBufferPixelFormatTypeKey];
            
            if (widthValue && heightValue) {
                settingsInfo[@"width"] = widthValue;
                settingsInfo[@"height"] = heightValue;
                
                logToFile([NSString stringWithFormat:@"Dimensões de saída: %@x%@", widthValue, heightValue]);
            }
            
            if (formatValue) {
                uint32_t pixelFormat = [formatValue unsignedIntValue];
                char formatStr[5] = {0};
                formatStr[0] = (pixelFormat >> 24) & 0xFF;
                formatStr[1] = (pixelFormat >> 16) & 0xFF;
                formatStr[2] = (pixelFormat >> 8) & 0xFF;
                formatStr[3] = pixelFormat & 0xFF;
                
                settingsInfo[@"pixelFormat"] = formatValue;
                settingsInfo[@"pixelFormatString"] = [NSString stringWithCString:formatStr encoding:NSASCIIStringEncoding];
                
                logToFile([NSString stringWithFormat:@"Formato de pixel: %s", formatStr]);
            }
            
            addDiagnosticData(@"videoSettings", settingsInfo);
        } @catch (NSException *exception) {
            logToFile([NSString stringWithFormat:@"Erro ao processar setVideoSettings: %@", exception]);
        }
    }
    
    %orig;
}

%end

// Hook para orientação de vídeo
%hook AVCaptureConnection

- (void)setVideoOrientation:(AVCaptureVideoOrientation)videoOrientation {
    // Detectar uso da câmera
    activateForCurrentApp();
    
    if (g_isTargetApp) {
        @try {
            logToFile([NSString stringWithFormat:@"AVCaptureConnection setVideoOrientation: %d", (int)videoOrientation]);
            
            // Salvar orientação global
            g_videoOrientation = (int)videoOrientation;
            
            // Criar informações para diagnóstico
            NSMutableDictionary *orientationInfo = [NSMutableDictionary dictionary];
            orientationInfo[@"orientation"] = @(videoOrientation);
            
            NSString *orientationString;
            switch (videoOrientation) {
                case AVCaptureVideoOrientationPortrait:
                    orientationString = @"Portrait";
                    break;
                case AVCaptureVideoOrientationPortraitUpsideDown:
                    orientationString = @"PortraitUpsideDown";
                    break;
                case AVCaptureVideoOrientationLandscapeRight:
                    orientationString = @"LandscapeRight";
                    break;
                case AVCaptureVideoOrientationLandscapeLeft:
                    orientationString = @"LandscapeLeft";
                    break;
                default:
                    orientationString = @"Unknown";
                    break;
            }
            orientationInfo[@"orientationString"] = orientationString;
            
            // Adicionar ao diagnóstico
            addDiagnosticData(@"orientation", orientationInfo);
        } @catch (NSException *exception) {
            logToFile([NSString stringWithFormat:@"Erro ao processar setVideoOrientation: %@", exception]);
        }
    }
    
    %orig;
}

- (void)setVideoMirrored:(BOOL)videoMirrored {
    // Detectar uso da câmera
    activateForCurrentApp();
    
    if (g_isTargetApp) {
        @try {
            logToFile([NSString stringWithFormat:@"AVCaptureConnection setVideoMirrored: %@", videoMirrored ? @"YES" : @"NO"]);
            
            addDiagnosticData(@"mirroring", @{
                @"videoMirrored": @(videoMirrored)
            });
        } @catch (NSException *exception) {
            logToFile([NSString stringWithFormat:@"Erro ao processar setVideoMirrored: %@", exception]);
        }
    }
    
    %orig;
}

%end

// Hook para captura de fotos
%hook AVCapturePhotoOutput

- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    // Detectar uso da câmera
    activateForCurrentApp();
    
    if (g_isTargetApp) {
        @try {
            logToFile(@"AVCapturePhotoOutput capturePhotoWithSettings: chamado");
            
            // Registrar que estamos capturando uma foto
            g_isCapturingPhoto = YES;
            
            // Extrair informações das configurações
            NSMutableDictionary *photoInfo = [NSMutableDictionary dictionary];
            photoInfo[@"delegateClass"] = NSStringFromClass([delegate class]) ?: @"nil";
            
            if (settings) {
                // Formato de preview
                NSDictionary *previewFormat = settings.previewPhotoFormat;
                if (previewFormat) {
                    photoInfo[@"previewFormat"] = previewFormat;
                    
                    // Extrair dimensões se disponíveis
                    id width = previewFormat[(NSString *)kCVPixelBufferWidthKey];
                    id height = previewFormat[(NSString *)kCVPixelBufferHeightKey];
                    if (width && height) {
                        photoInfo[@"previewWidth"] = width;
                        photoInfo[@"previewHeight"] = height;
                    }
                }
                
                // Formatos disponíveis
                NSArray *availableFormats = settings.availablePreviewPhotoPixelFormatTypes;
                if (availableFormats.count > 0) {
                    NSMutableArray *formatsArray = [NSMutableArray array];
                    for (NSNumber *format in availableFormats) {
                        uint32_t pixelFormat = [format unsignedIntValue];
                        char formatStr[5] = {0};
                        formatStr[0] = (pixelFormat >> 24) & 0xFF;
                        formatStr[1] = (pixelFormat >> 16) & 0xFF;
                        formatStr[2] = (pixelFormat >> 8) & 0xFF;
                        formatStr[3] = pixelFormat & 0xFF;
                        
                        [formatsArray addObject:@{
                            @"format": format,
                            @"formatString": [NSString stringWithCString:formatStr encoding:NSASCIIStringEncoding]
                        }];
                    }
                    photoInfo[@"availableFormats"] = formatsArray;
                }
                
                // Flash mode
                if ([settings respondsToSelector:@selector(flashMode)]) {
                    photoInfo[@"flashMode"] = @(settings.flashMode);
                }
            }
            
            // Adicionar ao diagnóstico
            addDiagnosticData(@"photoCapture", photoInfo);
            
            // Hook adicional para o delegate da foto - inspirado no VCamWebRTC
            if (delegate != nil) {
                static NSMutableArray *hookedPhotoCaptureDelegates = nil;
                static dispatch_once_t onceToken;
                
                dispatch_once(&onceToken, ^{
                    hookedPhotoCaptureDelegates = [NSMutableArray new];
                });
                
                NSString *className = NSStringFromClass([delegate class]);
                
                // Se esta classe ainda não foi hooked
                if (![hookedPhotoCaptureDelegates containsObject:className]) {
                    [hookedPhotoCaptureDelegates addObject:className];
                    
                    logToFile([NSString stringWithFormat:@"Hooking photo capture delegate: %@", className]);
                    
                    // Hook para o método que recebe a foto capturada
                    if ([delegate respondsToSelector:@selector(captureOutput:didFinishProcessingPhotoSampleBuffer:previewPhotoSampleBuffer:resolvedSettings:bracketSettings:error:)]) {
                        __block void (*original_photo_method)(id self, SEL _cmd, AVCapturePhotoOutput *captureOutput, CMSampleBufferRef photoSampleBuffer, CMSampleBufferRef previewPhotoSampleBuffer, AVCaptureResolvedPhotoSettings *resolvedSettings, AVCaptureBracketedStillImageSettings *bracketSettings, NSError *error) = nil;
                        
                        MSHookMessageEx(
                            [delegate class],
                            @selector(captureOutput:didFinishProcessingPhotoSampleBuffer:previewPhotoSampleBuffer:resolvedSettings:bracketSettings:error:),
                            imp_implementationWithBlock(^(id self, AVCapturePhotoOutput *captureOutput, CMSampleBufferRef photoSampleBuffer, CMSampleBufferRef previewPhotoSampleBuffer, AVCaptureResolvedPhotoSettings *resolvedSettings, AVCaptureBracketedStillImageSettings *bracketSettings, NSError *error) {
                                
                                logToFile(@"Foto processada");
                                
                                if (g_isTargetApp && photoSampleBuffer) {
                                    @try {
                                        NSMutableDictionary *photoInfo = [NSMutableDictionary dictionary];
                                        
                                        // Extrair dimensões do photoSampleBuffer
                                        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(photoSampleBuffer);
                                        if (imageBuffer) {
                                            size_t width = CVPixelBufferGetWidth(imageBuffer);
                                            size_t height = CVPixelBufferGetHeight(imageBuffer);
                                            photoInfo[@"width"] = @(width);
                                            photoInfo[@"height"] = @(height);
                                            
                                            logToFile([NSString stringWithFormat:@"Foto capturada: %zux%zu", width, height]);
                                        }
                                        
                                        // Adicionar ao diagnóstico
                                        addDiagnosticData(@"photoProcessed", photoInfo);
                                    } @catch (NSException *exception) {
                                        logToFile([NSString stringWithFormat:@"Erro ao processar foto: %@", exception]);
                                    }
                                }
                                
                                g_isCapturingPhoto = NO;
                                
                                // Chamar o método original
                                return original_photo_method(self, @selector(captureOutput:didFinishProcessingPhotoSampleBuffer:previewPhotoSampleBuffer:resolvedSettings:bracketSettings:error:), captureOutput, photoSampleBuffer, previewPhotoSampleBuffer, resolvedSettings, bracketSettings, error);
                            }),
                            (IMP*)&original_photo_method
                        );
                    }
                    // Método alternativo para iOS mais recentes
                    else if ([delegate respondsToSelector:@selector(captureOutput:didFinishProcessingPhoto:error:)]) {
                        __block void (*original_photo_method2)(id self, SEL _cmd, AVCapturePhotoOutput *captureOutput, AVCapturePhoto *photo, NSError *error) = nil;
                        
                        MSHookMessageEx(
                            [delegate class],
                            @selector(captureOutput:didFinishProcessingPhoto:error:),
                            imp_implementationWithBlock(^(id self, AVCapturePhotoOutput *captureOutput, AVCapturePhoto *photo, NSError *error) {
                                
                                logToFile(@"Foto processada (método moderno)");
                                
                                if (g_isTargetApp && photo) {
                                    @try {
                                        NSMutableDictionary *photoInfo = [NSMutableDictionary dictionary];
                                        
                                        // Obter dimensões usando CGImageRepresentation
                                        CGImageRef cgImage = [photo CGImageRepresentation];
                                        if (cgImage) {
                                            size_t width = CGImageGetWidth(cgImage);
                                            size_t height = CGImageGetHeight(cgImage);
                                            photoInfo[@"width"] = @(width);
                                            photoInfo[@"height"] = @(height);
                                            
                                            logToFile([NSString stringWithFormat:@"Foto capturada: %zux%zu", width, height]);
                                        }
                                        
                                        // Adicionar ao diagnóstico
                                        addDiagnosticData(@"photoProcessedModern", photoInfo);
                                    } @catch (NSException *exception) {
                                        logToFile([NSString stringWithFormat:@"Erro ao processar foto: %@", exception]);
                                    }
                                }
                                
                                g_isCapturingPhoto = NO;
                                
                                // Chamar o método original
                                return original_photo_method2(self, @selector(captureOutput:didFinishProcessingPhoto:error:), captureOutput, photo, error);
                            }),
                            (IMP*)&original_photo_method2
                        );
                    }
                }
            }
        } @catch (NSException *exception) {
            logToFile([NSString stringWithFormat:@"Erro ao processar capturePhotoWithSettings: %@", exception]);
        }
    }
    
    %orig;
}

%end

// Capturar redimensionamento de view (importante para problemas de layout)
%hook UIView

- (void)setFrame:(CGRect)frame {
    %orig; // Chama o método original primeiro para evitar problemas

    if (!g_isTargetApp) {
        return;
    }
    
    @try {
        static NSSet *relevantClassNames = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            relevantClassNames = [NSSet setWithArray:@[
                @"UIImageView", @"AVCaptureVideoPreviewLayer", @"CALayer",
                @"PreviewView", @"CameraView", @"VideoPreviewView",
                @"CAMVideoPreviewView", @"CAMPreviewView", @"CAMPanoramaPreviewView"
            ]];
        });
        
        NSString *className = NSStringFromClass([self class]);
        BOOL isRelevantView = NO;
        
        // Verificar se o nome da classe contém alguma das palavras-chave
        for (NSString *relevantName in relevantClassNames) {
            if ([className containsString:relevantName]) {
                isRelevantView = YES;
                break;
            }
        }
        
        // Se for uma view relevante para a câmera, registrar a mudança de frame
        if (isRelevantView) {
            logToFile([NSString stringWithFormat:@"View %@ frame alterada para: {{%.1f, %.1f}, {%.1f, %.1f}}",
                      className, frame.origin.x, frame.origin.y, frame.size.width, frame.size.height]);
            
            addDiagnosticData(@"viewFrameChange", @{
                @"viewClass": className,
                @"x": @(frame.origin.x),
                @"y": @(frame.origin.y),
                @"width": @(frame.size.width),
                @"height": @(frame.size.height)
            });
        }
    } @catch (NSException *exception) {
        // Não registramos o erro aqui para evitar logs excessivos
    }
}

%end

// Capturar alterações de bounds e layout (similar ao método no VCamWebRTC)
%hook UIWindow

- (void)layoutSubviews {
    %orig;
    
    if (!g_isTargetApp) {
        return;
    }
    
    @try {
        // Registrar informações de layout da janela principal
        CGRect bounds = self.bounds;
        CGRect frame = self.frame;
        
        logToFile([NSString stringWithFormat:@"UIWindow layout: bounds={{%.1f, %.1f}, {%.1f, %.1f}}, frame={{%.1f, %.1f}, {%.1f, %.1f}}",
                  bounds.origin.x, bounds.origin.y, bounds.size.width, bounds.size.height,
                  frame.origin.x, frame.origin.y, frame.size.width, frame.size.height]);
        
        addDiagnosticData(@"windowLayout", @{
            @"boundsX": @(bounds.origin.x),
            @"boundsY": @(bounds.origin.y),
            @"boundsWidth": @(bounds.size.width),
            @"boundsHeight": @(bounds.size.height),
            @"frameX": @(frame.origin.x),
            @"frameY": @(frame.origin.y),
            @"frameWidth": @(frame.size.width),
            @"frameHeight": @(frame.size.height)
        });
    } @catch (NSException *exception) {
        logToFile([NSString stringWithFormat:@"Erro ao processar layoutSubviews: %@", exception]);
    }
}

%end

// Hook para webviews (para capturar uso da câmera em sites)
%hook WKWebView

// Detecção de acesso a câmera via web
- (void)loadRequest:(NSURLRequest *)request {
    %orig;
    
    @try {
        // Procura por strings que indiquem uso da câmera
        if ([request.URL.absoluteString containsString:@"getUserMedia"] ||
            [request.URL.absoluteString containsString:@"camera"] ||
            [request.URL.absoluteString containsString:@"webcam"]) {
            
            logToFile([NSString stringWithFormat:@"Possível requisição de câmera via Web: %@", request.URL]);
            
            // Ativar monitoramento para este app
            activateForCurrentApp();
        }
    } @catch (NSException *exception) {
        logToFile([NSString stringWithFormat:@"Erro ao analisar requisição web: %@", exception]);
    }
}

%end

// Hook adicional para WKWebView para iOS 15+
%hook WKWebView

// Este método é chamado quando sites solicitam acesso a câmera/microfone
- (void)_requestMediaCapturePermissionForOrigin:(id)origin mainFrameURL:(NSURL *)mainFrameURL decisionHandler:(void (^)(int))decisionHandler {
    logToFile(@"Permissão para captura de mídia solicitada via WebKit");
    
    // Ativar monitoramento para este app
    activateForCurrentApp();
    
    if (g_isTargetApp) {
        addDiagnosticData(@"webkitCameraPermission", @{
            @"mainFrameURL": mainFrameURL.absoluteString ?: @"unknown"
        });
    }
    
    %orig;
}

%end

// Inicialização do tweak - muito parecido com VCamWebRTC
%ctor {
    @autoreleasepool {
        // Log de inicialização básico (independente se é app alvo)
        NSString *processName = [NSProcessInfo processInfo].processName;
        NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
        
        // Criar diretório de logs
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *logDir = @"/var/tmp/CameraDiagnostic";
        if (![fileManager fileExistsAtPath:logDir]) {
            [fileManager createDirectoryAtPath:logDir
                  withIntermediateDirectories:YES
                                   attributes:nil
                                        error:nil];
        }
        
        // Verificar se este processo deve ser monitorado imediatamente
        if (isAppSuitableForDiagnostic()) {
            // Verificar se o processo atual é um aplicativo que usa câmera
            if ([bundleId containsString:@"camera"] ||
                [bundleId containsString:@"facetime"] ||
                [bundleId containsString:@"instagram"] ||
                [bundleId containsString:@"snapchat"] ||
                [bundleId containsString:@"tiktok"] ||
                [bundleId containsString:@"whatsapp"] ||
                [bundleId containsString:@"telegram"] ||
                [processName containsString:@"Camera"]) {
                
                // Ativar monitoramento imediatamente para aplicativos conhecidos
                activateForCurrentApp();
            }
        }
        
        // Log inicial
        logToFile([NSString stringWithFormat:@"CameraDiagnostic iniciado em: %@ (%@), monitoramento: %@",
                  processName, bundleId, g_isTargetApp ? @"ATIVO" : @"INATIVO (pendente detecção)"]);
        
        // Inicializar todos os hooks
        %init;
    }
}

// Finalização do tweak
%dtor {
    @try {
        // Salvar dados antes de descarregar apenas se for app alvo
        if (g_isTargetApp) {
            logToFile(@"CameraDiagnostic sendo descarregado");
            saveDiagnosticData();
            finalizeDiagnosticSession();
        }
    } @catch (NSException *exception) {
        logToFile([NSString stringWithFormat:@"Erro na finalização: %@", exception]);
    }
}
