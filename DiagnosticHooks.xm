#import "DiagnosticTweak.h"

// Variáveis para registro de dados por aplicativo
static NSMutableDictionary *appDiagnosticData = nil;

// Flag para controlar se o app atual está sendo monitorado
static BOOL g_isTargetApp = NO;

// Variáveis para medição de FPS e latência
static NSTimeInterval g_lastFrameTime = 0;
static NSMutableArray *g_frameTimes = nil;

// Declarações antecipadas de funções
static void saveDiagnosticData(void);
static void logToFile(NSString *message);

// Ativar diagnóstico para o app atual - sem nenhuma filtragem
static void activateForCurrentApp() {
    if (g_isTargetApp) return; // Já ativado
    
    // Ativar para qualquer aplicativo, sem restrições
    g_isTargetApp = YES;
    
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
    NSString *appName = [NSProcessInfo processInfo].processName;
    
    // Inicializar dicionário de diagnóstico
    if (!appDiagnosticData) {
        appDiagnosticData = [NSMutableDictionary dictionary];
    }
    
    // Inicializar variáveis de controle de frames
    g_lastFrameTime = 0;
    g_frameTimes = [NSMutableArray array];
    g_frameCounter = 0;
    
    // Registrar ativação
    logToFile([NSString stringWithFormat:@"Ativando diagnóstico para: %@ (%@)", appName, bundleId]);
    
    // Iniciar sessão de diagnóstico
    startNewDiagnosticSession();
}

// Log para arquivo de texto simplificado
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
        
        // Criar arquivo ou adicionar ao existente
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
        static NSSet *importantEventTypes = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            importantEventTypes = [NSSet setWithArray:@[
                @"sessionStart", @"sessionStop", @"photoCapture",
                @"videoFrame", @"cameraRequest", @"orientation",
                @"fpsStats", @"mirroring"
            ]];
        });
        
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
            
            // Só logar mensagem para eventos importantes
            if ([importantEventTypes containsObject:eventType]) {
                logToFile([NSString stringWithFormat:@"Evento registrado: %@", eventType]);
                // Salvar dados atualizados
                saveDiagnosticData();
            }
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
                } else {
                    logToFile([NSString stringWithFormat:@"Erro ao salvar diagnóstico: %@", error.localizedDescription]);
                }
            }
        }
    } @catch (NSException *exception) {
        logToFile([NSString stringWithFormat:@"Erro ao salvar dados de diagnóstico: %@", exception]);
    }
}

// ----- INÍCIO DOS HOOKS DE DIAGNÓSTICO -----

// Hook para AVCaptureDevice
%hook AVCaptureDevice

+ (AVCaptureDevice *)defaultDeviceWithMediaType:(NSString *)mediaType {
    AVCaptureDevice *device = %orig;
    
    @try {
        if ([mediaType isEqualToString:AVMediaTypeVideo]) {
            // Quando um app solicita a câmera, marcamos como app de interesse
            activateForCurrentApp();
            
            if (g_isTargetApp && device) {
                logToFile([NSString stringWithFormat:@"Câmera solicitada: %@ (posição: %d)",
                          device.localizedName ?: @"unknown", (int)device.position]);
                
                NSMutableDictionary *deviceInfo = [NSMutableDictionary dictionary];
                deviceInfo[@"deviceName"] = device.localizedName ?: @"unknown";
                deviceInfo[@"devicePosition"] = @(device.position);
                deviceInfo[@"uniqueID"] = device.uniqueID ?: @"unknown";
                
                // Extrair informações detalhadas de formato para WebRTC
                AVCaptureDeviceFormat *format = device.activeFormat;
                if (format) {
                    NSMutableDictionary *formatInfo = [NSMutableDictionary dictionary];
                    
                    // Dimensões do formato
                    CMFormatDescriptionRef formatDesc = format.formatDescription;
                    if (formatDesc) {
                        CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDesc);
                        formatInfo[@"width"] = @(dimensions.width);
                        formatInfo[@"height"] = @(dimensions.height);
                    }
                    
                    // Ranges de FPS suportados
                    NSMutableArray *fpsRanges = [NSMutableArray array];
                    for (AVFrameRateRange *range in format.videoSupportedFrameRateRanges) {
                        [fpsRanges addObject:@{
                            @"minFrameRate": @(range.minFrameRate),
                            @"maxFrameRate": @(range.maxFrameRate),
                            @"defaultFrameRate": @(range.maxFrameDuration.timescale / range.maxFrameDuration.value)
                        }];
                    }
                    formatInfo[@"supportedFrameRates"] = fpsRanges;
                    
                    // Formato de pixel
                    if (formatDesc) {
                        FourCharCode subType = CMFormatDescriptionGetMediaSubType(formatDesc);
                        formatInfo[@"pixelFormat"] = @(subType);
                        formatInfo[@"pixelFormatString"] = pixelFormatToString(subType);
                    }
                    
                    deviceInfo[@"activeFormat"] = formatInfo;
                }
                
                addDiagnosticData(@"cameraRequest", deviceInfo);
            }
        }
    } @catch (NSException *exception) {
        logToFile([NSString stringWithFormat:@"Erro ao processar defaultDeviceWithMediaType: %@", exception]);
    }
    
    return device;
}

%end

// Hook para AVCaptureSession
%hook AVCaptureSession

- (void)startRunning {
    // Detectar uso da câmera
    activateForCurrentApp();
    
    if (g_isTargetApp) {
        logToFile(@"AVCaptureSession startRunning chamado");
        
        @try {
            // Salvar informações essenciais da sessão
            NSMutableDictionary *sessionInfo = [NSMutableDictionary dictionary];
            
            // Capturar preset da sessão
            if ([self respondsToSelector:@selector(sessionPreset)]) {
                sessionInfo[@"sessionPreset"] = [self sessionPreset] ?: @"unknown";
            }
            
            // Capturar resolução e posição da câmera (frontal/traseira)
            BOOL foundCameraInfo = NO;
            
            if ([self respondsToSelector:@selector(inputs)]) {
                NSArray *inputs = [self inputs];
                
                for (AVCaptureInput *input in inputs) {
                    if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
                        AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
                        AVCaptureDevice *device = deviceInput.device;
                        
                        if (device) {
                            sessionInfo[@"deviceName"] = device.localizedName ?: @"unknown";
                            sessionInfo[@"uniqueID"] = device.uniqueID ?: @"unknown";
                            
                            // Câmera frontal/traseira
                            BOOL isFrontCamera = (device.position == AVCaptureDevicePositionFront);
                            g_usingFrontCamera = isFrontCamera;
                            sessionInfo[@"isFrontCamera"] = @(isFrontCamera);
                            
                            // Formato da câmera (importante para virtual cam)
                            AVCaptureDeviceFormat *format = device.activeFormat;
                            if (format) {
                                CMFormatDescriptionRef formatDesc = format.formatDescription;
                                if (formatDesc) {
                                    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDesc);
                                    sessionInfo[@"width"] = @(dimensions.width);
                                    sessionInfo[@"height"] = @(dimensions.height);
                                    
                                    // Salvar resolução global
                                    CGSize resolution = CGSizeMake(dimensions.width, dimensions.height);
                                    if (isFrontCamera) {
                                        g_frontCameraResolution = resolution;
                                    } else {
                                        g_backCameraResolution = resolution;
                                    }
                                    g_cameraResolution = resolution;
                                    
                                    // Adicionar format mediaSubtype
                                    FourCharCode subType = CMFormatDescriptionGetMediaSubType(formatDesc);
                                    sessionInfo[@"formatSubType"] = @(subType);
                                    sessionInfo[@"formatSubTypeString"] = pixelFormatToString(subType);
                                    
                                    // Adicionar dimensões ao log
                                    logToFile([NSString stringWithFormat:@"Resolução da câmera: %dx%d",
                                              (int)dimensions.width, (int)dimensions.height]);
                                    
                                    foundCameraInfo = YES;
                                }
                            }
                            
                            // Adicionar faixas de FPS suportadas
                            if (format) {
                                NSMutableArray *fpsRanges = [NSMutableArray array];
                                for (AVFrameRateRange *range in format.videoSupportedFrameRateRanges) {
                                    [fpsRanges addObject:@{
                                        @"minFrameRate": @(range.minFrameRate),
                                        @"maxFrameRate": @(range.maxFrameRate),
                                        @"defaultFrameRate": @(range.maxFrameDuration.timescale / range.maxFrameDuration.value)
                                    }];
                                }
                                sessionInfo[@"supportedFrameRates"] = fpsRanges;
                            }
                            
                            break; // Só precisamos de uma câmera
                        }
                    }
                }
            }
            
            // Se não encontrou informações de resolução, verificar outputs
            if (!foundCameraInfo && [self respondsToSelector:@selector(outputs)]) {
                NSArray *outputs = [self outputs];
                
                for (AVCaptureOutput *output in outputs) {
                    if ([output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
                        AVCaptureVideoDataOutput *videoOutput = (AVCaptureVideoDataOutput *)output;
                        
                        if (videoOutput.videoSettings) {
                            id widthValue = videoOutput.videoSettings[(id)kCVPixelBufferWidthKey];
                            id heightValue = videoOutput.videoSettings[(id)kCVPixelBufferHeightKey];
                            
                            if (widthValue && heightValue) {
                                sessionInfo[@"width"] = widthValue;
                                sessionInfo[@"height"] = heightValue;
                                
                                // Salvar formato de pixel
                                id formatValue = videoOutput.videoSettings[(id)kCVPixelBufferPixelFormatTypeKey];
                                if (formatValue) {
                                    uint32_t pixelFormat = [formatValue unsignedIntValue];
                                    sessionInfo[@"pixelFormat"] = formatValue;
                                    sessionInfo[@"pixelFormatString"] = pixelFormatToString(pixelFormat);
                                }
                                
                                logToFile([NSString stringWithFormat:@"Dimensões de saída: %@x%@, formato: %@",
                                          widthValue, heightValue, sessionInfo[@"pixelFormatString"] ?: @"unknown"]);
                                
                                foundCameraInfo = YES;
                                break;
                            }
                        }
                    }
                }
            }
            
            // Adicionar ao diagnóstico do app apenas se encontrou informações úteis
            if (sessionInfo.count > 1) {
                addDiagnosticData(@"sessionStart", sessionInfo);
            }
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
        
        // Registrar estatísticas de FPS ao final da sessão
        if (g_frameTimes.count > 0) {
            NSMutableDictionary *fpsStats = [NSMutableDictionary dictionary];
            
            // Calcular FPS médio
            double avgInterval = 0;
            for (NSNumber *interval in g_frameTimes) {
                avgInterval += [interval doubleValue];
            }
            avgInterval /= g_frameTimes.count;
            double avgFPS = 1.0 / avgInterval;
            
            fpsStats[@"averageFPS"] = @(avgFPS);
            fpsStats[@"totalFrames"] = @(g_frameCounter);
            fpsStats[@"sampledFrames"] = @(g_frameTimes.count);
            
            // Adicionar ao diagnóstico
            addDiagnosticData(@"fpsStats", fpsStats);
            
            // Reset para próxima sessão
            g_lastFrameTime = 0;
            [g_frameTimes removeAllObjects];
        }
        
        addDiagnosticData(@"sessionStop", @{@"reason": @"stopRunning chamado"});
    }
    %orig;
}

%end

// Hook para AVCaptureVideoDataOutput - capturar detalhes importantes dos frames
%hook AVCaptureVideoDataOutput

- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    // Detectar uso da câmera
    activateForCurrentApp();
    
    if (g_isTargetApp) {
        logToFile(@"AVCaptureVideoDataOutput setSampleBufferDelegate: chamado");
        
        @try {
            // Definir intervalo de frame (a cada 500 frames)
            static int frameLogInterval = 500;
            
            // Hook dinâmico para o método de delegado
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
                                g_frameCounter++;
                                
                                // Medição de FPS e latência
                                NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
                                if (g_lastFrameTime > 0) {
                                    // Calcular intervalo de frame
                                    NSTimeInterval frameInterval = currentTime - g_lastFrameTime;
                                    
                                    // Manter histórico para média de FPS
                                    [g_frameTimes addObject:@(frameInterval)];
                                    
                                    // Manter apenas os últimos 60 frames para média
                                    if (g_frameTimes.count > 60) {
                                        [g_frameTimes removeObjectAtIndex:0];
                                    }
                                }
                                g_lastFrameTime = currentTime;
                                
                                // Limitar logging para apenas 1 a cada N frames
                                if (g_frameCounter % frameLogInterval == 0) {
                                    @try {
                                        NSMutableDictionary *frameInfo = [NSMutableDictionary dictionary];
                                        frameInfo[@"frameNumber"] = @(g_frameCounter);
                                        
                                        // Calcular FPS atual baseado no histórico
                                        if (g_frameTimes.count > 0) {
                                            double avgInterval = 0;
                                            for (NSNumber *interval in g_frameTimes) {
                                                avgInterval += [interval doubleValue];
                                            }
                                            avgInterval /= g_frameTimes.count;
                                            double avgFPS = 1.0 / avgInterval;
                                            
                                            frameInfo[@"currentFPS"] = @(avgFPS);
                                            frameInfo[@"lastFrameInterval"] = @(((NSNumber *)g_frameTimes.lastObject).doubleValue * 1000); // em ms
                                        }
                                        
                                        // Extrair informações detalhadas do buffer para WebRTC
                                        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
                                        if (imageBuffer) {
                                            // Dimensões do frame
                                            size_t width = CVPixelBufferGetWidth(imageBuffer);
                                            size_t height = CVPixelBufferGetHeight(imageBuffer);
                                            frameInfo[@"width"] = @(width);
                                            frameInfo[@"height"] = @(height);
                                            
                                            // Formato de pixel
                                            OSType pixelFormat = CVPixelBufferGetPixelFormatType(imageBuffer);
                                            frameInfo[@"pixelFormat"] = pixelFormatToString(pixelFormat);
                                            
                                            // Informações de buffer avançadas para WebRTC
                                            frameInfo[@"bytesPerRow"] = @(CVPixelBufferGetBytesPerRow(imageBuffer));
                                            frameInfo[@"planeCount"] = @(CVPixelBufferGetPlaneCount(imageBuffer));
                                            frameInfo[@"dataSize"] = @(CVPixelBufferGetDataSize(imageBuffer));
                                            
                                            logToFile([NSString stringWithFormat:@"Frame #%llu: %zux%zu, formato: %@",
                                                    g_frameCounter, width, height, frameInfo[@"pixelFormat"]]);
                                        }
                                        
                                        // Informações de tempo do buffer (para sincronização WebRTC)
                                        CMTime presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
                                        CMTime duration = CMSampleBufferGetDuration(sampleBuffer);
                                        
                                        frameInfo[@"presentationTimeSeconds"] = @(CMTimeGetSeconds(presentationTime));
                                        frameInfo[@"durationSeconds"] = @(CMTimeGetSeconds(duration));
                                        
                                        // Informações de conexão
                                        if (connection) {
                                            NSMutableDictionary *connectionInfo = [NSMutableDictionary dictionary];
                                            
                                            // Orientação
                                            if ([connection isVideoOrientationSupported]) {
                                                connectionInfo[@"videoOrientation"] = @(connection.videoOrientation);
                                                
                                                // Salvar orientação global
                                                g_videoOrientation = (int)connection.videoOrientation;
                                            }
                                            
                                            // Espelhamento
                                            connectionInfo[@"videoMirrored"] = @(connection.isVideoMirrored);
                                            
                                            // Portas de entrada
                                            NSMutableArray *inputPorts = [NSMutableArray array];
                                            for (AVCaptureInputPort *port in connection.inputPorts) {
                                                [inputPorts addObject:@{
                                                    @"mediaType": port.mediaType ?: @"unknown",
                                                    @"sourcePosition": @(port.sourceDevicePosition)
                                                }];
                                            }
                                            connectionInfo[@"inputPorts"] = inputPorts;
                                            
                                            // Estabilização
                                            if ([connection respondsToSelector:@selector(isVideoStabilizationEnabled)]) {
                                                connectionInfo[@"videoStabilizationEnabled"] = @([connection isVideoStabilizationEnabled]);
                                                
                                                if ([connection respondsToSelector:@selector(activeVideoStabilizationMode)]) {
                                                    connectionInfo[@"videoStabilizationMode"] = @([connection activeVideoStabilizationMode]);
                                                }
                                            }
                                            
                                            frameInfo[@"connection"] = connectionInfo;
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
                settingsInfo[@"pixelFormat"] = formatValue;
                settingsInfo[@"pixelFormatString"] = pixelFormatToString(pixelFormat);
                
                logToFile([NSString stringWithFormat:@"Formato de pixel: %@", settingsInfo[@"pixelFormatString"]]);
            }
            
            addDiagnosticData(@"videoSettings", settingsInfo);
        } @catch (NSException *exception) {
            logToFile([NSString stringWithFormat:@"Erro ao processar setVideoSettings: %@", exception]);
        }
    }
    
    %orig;
}

%end

// Hook para orientação de vídeo - importante para câmera virtual
%hook AVCaptureConnection

- (void)setVideoOrientation:(AVCaptureVideoOrientation)videoOrientation {
    // Detectar uso da câmera
    activateForCurrentApp();
    
    if (g_isTargetApp) {
        @try {
            // Salvar orientação global
            g_videoOrientation = (int)videoOrientation;
            
            // Converter para string legível
            NSString *orientationString;
            switch (videoOrientation) {
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
            
            logToFile([NSString stringWithFormat:@"Orientação do vídeo alterada para: %@", orientationString]);
            
            // Adicionar ao diagnóstico
            addDiagnosticData(@"orientation", @{
                @"orientation": @(videoOrientation),
                @"orientationString": orientationString
            });
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
            logToFile([NSString stringWithFormat:@"Espelhamento de vídeo: %@", videoMirrored ? @"SIM" : @"NÃO"]);
            
            addDiagnosticData(@"mirroring", @{
                @"videoMirrored": @(videoMirrored)
            });
        } @catch (NSException *exception) {
            logToFile([NSString stringWithFormat:@"Erro ao processar setVideoMirrored: %@", exception]);
        }
    }
    
    %orig;
}

// Para WebRTC: estabilização de vídeo
- (void)setEnablesVideoStabilizationWhenAvailable:(BOOL)enablesVideoStabilization {
    if (g_isTargetApp) {
        @try {
            logToFile([NSString stringWithFormat:@"Estabilização de vídeo: %@", enablesVideoStabilization ? @"SIM" : @"NÃO"]);
            
            addDiagnosticData(@"stabilization", @{
                @"videoStabilizationEnabled": @(enablesVideoStabilization)
            });
        } @catch (NSException *exception) {
            logToFile([NSString stringWithFormat:@"Erro ao processar setEnablesVideoStabilizationWhenAvailable: %@", exception]);
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
            logToFile(@"Foto sendo capturada");
            
            // Registrar que estamos capturando uma foto
            g_isCapturingPhoto = YES;
            
            // Extrair informações essenciais
            NSMutableDictionary *photoInfo = [NSMutableDictionary dictionary];
            photoInfo[@"delegateClass"] = NSStringFromClass([delegate class]) ?: @"nil";
            
            if (settings) {
                // Formato de preview
                NSDictionary *previewFormat = settings.previewPhotoFormat;
                if (previewFormat) {
                    // Extrair dimensões se disponíveis
                    id width = previewFormat[(NSString *)kCVPixelBufferWidthKey];
                    id height = previewFormat[(NSString *)kCVPixelBufferHeightKey];
                    if (width && height) {
                        photoInfo[@"previewWidth"] = width;
                        photoInfo[@"previewHeight"] = height;
                        
                        logToFile([NSString stringWithFormat:@"Dimensões de preview: %@x%@", width, height]);
                    }
                    
                    // Adicionar formato completo de preview
                    photoInfo[@"previewFormat"] = previewFormat;
                }
                
                // Formatos disponíveis
                NSArray *availableFormats = settings.availablePreviewPhotoPixelFormatTypes;
                if (availableFormats.count > 0) {
                    NSMutableArray *formatsArray = [NSMutableArray array];
                    for (NSNumber *format in availableFormats) {
                        uint32_t pixelFormat = [format unsignedIntValue];
                        [formatsArray addObject:pixelFormatToString(pixelFormat)];
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
            
            // Hook para o delegate da captura de foto
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
                    
                    // Hook para o método que recebe a foto capturada (iOS 10-11)
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
                    // Método alternativo para iOS 12+
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

// Capturar mudanças de frame em views da câmera
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
                @"AVCaptureVideoPreviewLayer", @"CAMPreviewView", @"CAMVideoPreviewView",
                @"CAMPanoramaPreviewView", @"TGCameraPreviewView"
            ]];
        });
        
        NSString *className = NSStringFromClass([self class]);
        BOOL isRelevantView = NO;
        
        // Verificar se o nome da classe está na lista de relevantes
        for (NSString *relevantName in relevantClassNames) {
            if ([className isEqualToString:relevantName] || [className containsString:relevantName]) {
                isRelevantView = YES;
                break;
            }
        }
        
        // Se for uma view relevante para a câmera, registrar a mudança de frame
        if (isRelevantView) {
            logToFile([NSString stringWithFormat:@"View da câmera alterada: {{%.1f, %.1f}, {%.1f, %.1f}}",
                      frame.origin.x, frame.origin.y, frame.size.width, frame.size.height]);
            
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

// Inicialização do tweak - versão universal, sem filtragem
%ctor {
    @autoreleasepool {
        // Inicializar todos os hooks
        %init;
    }
}

// Finalização do tweak
%dtor {
    @try {
        // Salvar dados antes de descarregar apenas se for app alvo
        if (g_isTargetApp) {
            // Registrar estatísticas finais de FPS se houver frames capturados
            if (g_frameTimes.count > 0) {
                NSMutableDictionary *fpsStats = [NSMutableDictionary dictionary];
                
                // Calcular FPS médio
                double avgInterval = 0;
                for (NSNumber *interval in g_frameTimes) {
                    avgInterval += [interval doubleValue];
                }
                avgInterval /= g_frameTimes.count;
                double avgFPS = 1.0 / avgInterval;
                
                fpsStats[@"averageFPS"] = @(avgFPS);
                fpsStats[@"totalFrames"] = @(g_frameCounter);
                fpsStats[@"sampledFrames"] = @(g_frameTimes.count);
                
                // Adicionar ao diagnóstico
                addDiagnosticData(@"finalFpsStats", fpsStats);
            }
            
            logToFile(@"CameraDiagnostic sendo descarregado");
            saveDiagnosticData();
            finalizeDiagnosticSession();
        }
    } @catch (NSException *exception) {
        logToFile([NSString stringWithFormat:@"Erro na finalização: %@", exception]);
    }
}
