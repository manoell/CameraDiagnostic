#import "DiagnosticTweak.h"

// Variáveis para registro de dados por aplicativo
static NSMutableDictionary *appDiagnosticData = nil;

// Declarações antecipadas de funções
static void saveDiagnosticData(void);

// Log para arquivo de texto
static void logToFile(NSString *message) {
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
    if (![fileManager fileExistsAtPath:logFile]) {
        [logMessage writeToFile:logFile atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:logFile];
        [fileHandle seekToEndOfFile];
        [fileHandle writeData:[logMessage dataUsingEncoding:NSUTF8StringEncoding]];
        [fileHandle closeFile];
    }
}

// Adicionar dados para o diagnóstico do aplicativo atual
static void addDiagnosticData(NSString *eventType, NSDictionary *eventData) {
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
}

// Salvar os dados coletados em um arquivo JSON por aplicativo
static void saveDiagnosticData(void) {
    if (!appDiagnosticData) return;
    
    NSString *logDir = @"/var/tmp/CameraDiagnostic";
    
    @synchronized(appDiagnosticData) {
        for (NSString *bundleId in appDiagnosticData) {
            NSDictionary *appData = appDiagnosticData[bundleId];
            NSString *appName = appData[@"appName"];
            
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
}

// Hook para AVCaptureSession - Início do fluxo da câmera
%hook AVCaptureSession

- (void)startRunning {
    logToFile(@"AVCaptureSession startRunning chamado");
    
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
    
    // Chamar o método original
    %orig;
}

- (void)stopRunning {
    logToFile(@"AVCaptureSession stopRunning chamado");
    addDiagnosticData(@"sessionStop", @{@"reason": @"stopRunning chamado"});
    %orig;
}

%end

// Hook para AVCaptureVideoDataOutput - Onde o feed de vídeo é processado
%hook AVCaptureVideoDataOutput

- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    logToFile(@"AVCaptureVideoDataOutput setSampleBufferDelegate: chamado");
    
    NSMutableDictionary *delegateInfo = [NSMutableDictionary dictionary];
    delegateInfo[@"delegateClass"] = NSStringFromClass([sampleBufferDelegate class]) ?: @"nil";
    delegateInfo[@"hasQueue"] = sampleBufferCallbackQueue ? @YES : @NO;
    
    addDiagnosticData(@"videoDelegate", delegateInfo);
    
    %orig;
}

- (void)setVideoSettings:(NSDictionary<NSString *,id> *)videoSettings {
    logToFile(@"AVCaptureVideoDataOutput setVideoSettings: chamado");
    
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
    
    %orig;
}

%end

// Hook para captura de frames - PONTO CRUCIAL onde o VCamMJPEG faz a substituição
%hook NSObject

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    // Verificar se somos o delegate correto
    if (![self respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
        %orig;
        return;
    }
    
    static int frameCounter = 0;
    frameCounter++;
    
    // Limitar logging para 1 a cada 100 frames
    if (frameCounter % 100 == 0) {
        logToFile([NSString stringWithFormat:@"Frame #%d capturado", frameCounter]);
        
        NSMutableDictionary *frameInfo = [NSMutableDictionary dictionary];
        frameInfo[@"frameNumber"] = @(frameCounter);
        frameInfo[@"delegateClass"] = NSStringFromClass([self class]);
        frameInfo[@"outputClass"] = NSStringFromClass([output class]);
        
        // Extrair informações do buffer
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        if (imageBuffer) {
            // Dimensões do frame
            size_t width = CVPixelBufferGetWidth(imageBuffer);
            size_t height = CVPixelBufferGetHeight(imageBuffer);
            frameInfo[@"width"] = @(width);
            frameInfo[@"height"] = @(height);
            
            // Formato do pixel
            OSType pixelFormat = CVPixelBufferGetPixelFormatType(imageBuffer);
            char formatStr[5] = {0};
            formatStr[0] = (pixelFormat >> 24) & 0xFF;
            formatStr[1] = (pixelFormat >> 16) & 0xFF;
            formatStr[2] = (pixelFormat >> 8) & 0xFF;
            formatStr[3] = pixelFormat & 0xFF;
            
            frameInfo[@"pixelFormat"] = @(pixelFormat);
            frameInfo[@"pixelFormatString"] = [NSString stringWithCString:formatStr encoding:NSASCIIStringEncoding];
            
            // Mais detalhes
            frameInfo[@"bytesPerRow"] = @(CVPixelBufferGetBytesPerRow(imageBuffer));
            frameInfo[@"dataSize"] = @(CVPixelBufferGetDataSize(imageBuffer));
            frameInfo[@"planeCount"] = @(CVPixelBufferGetPlaneCount(imageBuffer));
            
            logToFile([NSString stringWithFormat:@"Frame: %zux%zu, Formato: %s",
                       width, height, formatStr]);
        }
        
        // Extrair informações de metadados
        CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
        if (formatDesc) {
            frameInfo[@"hasFormatDescription"] = @YES;
            
            // Tipo de mídia
            CMMediaType mediaType = CMFormatDescriptionGetMediaType(formatDesc);
            FourCharCode mediaSubType = CMFormatDescriptionGetMediaSubType(formatDesc);
            
            char mediaTypeStr[5] = {0};
            char mediaSubTypeStr[5] = {0};
            
            mediaTypeStr[0] = (mediaType >> 24) & 0xFF;
            mediaTypeStr[1] = (mediaType >> 16) & 0xFF;
            mediaTypeStr[2] = (mediaType >> 8) & 0xFF;
            mediaTypeStr[3] = mediaType & 0xFF;
            
            mediaSubTypeStr[0] = (mediaSubType >> 24) & 0xFF;
            mediaSubTypeStr[1] = (mediaSubType >> 16) & 0xFF;
            mediaSubTypeStr[2] = (mediaSubType >> 8) & 0xFF;
            mediaSubTypeStr[3] = mediaSubType & 0xFF;
            
            frameInfo[@"mediaType"] = [NSString stringWithCString:mediaTypeStr encoding:NSASCIIStringEncoding];
            frameInfo[@"mediaSubType"] = [NSString stringWithCString:mediaSubTypeStr encoding:NSASCIIStringEncoding];
        }
        
        // Capturar informações de conexão
        if (connection) {
            NSMutableDictionary *connectionInfo = [NSMutableDictionary dictionary];
            
            // Orientação
            if ([connection isVideoOrientationSupported]) {
                AVCaptureVideoOrientation orientation = connection.videoOrientation;
                connectionInfo[@"videoOrientation"] = @(orientation);
                
                NSString *orientationString;
                switch (orientation) {
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
                connectionInfo[@"orientationString"] = orientationString;
                
                // Salvar orientação global
                g_videoOrientation = (int)orientation;
            }
            
            // Espelhamento
            connectionInfo[@"videoMirrored"] = @(connection.isVideoMirrored);
            
            // Estabilização
            if ([connection respondsToSelector:@selector(preferredVideoStabilizationMode)]) {
                connectionInfo[@"stabilizationMode"] = @(connection.preferredVideoStabilizationMode);
            }
            
            frameInfo[@"connection"] = connectionInfo;
        }
        
        // Adicionar ao diagnóstico
        addDiagnosticData(@"videoFrame", frameInfo);
    }
    
    // Chamar método original
    %orig;
}

%end

// Hook para orientação de vídeo
%hook AVCaptureConnection

- (void)setVideoOrientation:(AVCaptureVideoOrientation)videoOrientation {
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
    
    %orig;
}

- (void)setVideoMirrored:(BOOL)videoMirrored {
    logToFile([NSString stringWithFormat:@"AVCaptureConnection setVideoMirrored: %@", videoMirrored ? @"YES" : @"NO"]);
    
    addDiagnosticData(@"mirroring", @{
        @"videoMirrored": @(videoMirrored)
    });
    
    %orig;
}

%end

// Hook para captura de fotos
%hook AVCapturePhotoOutput

- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
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
    
    %orig;
}

%end

// Capturar redimensionamento de view (importante para problemas de layout)
%hook UIView

- (void)setFrame:(CGRect)frame {
    static NSSet *relevantClassNames = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        relevantClassNames = [NSSet setWithArray:@[
            @"UIImageView", @"AVCaptureVideoPreviewLayer", @"CALayer",
            @"PreviewView", @"CameraView", @"VideoPreviewView"
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
    
    %orig;
}

%end

// Capturar mudanças de orientação do dispositivo
%hook UIDevice

- (void)setOrientation:(UIDeviceOrientation)orientation {
    %orig;
    
    // Verificar se é uma orientação válida
    if (orientation != UIDeviceOrientationUnknown) {
        NSString *orientationString;
        switch (orientation) {
            case UIDeviceOrientationPortrait:
                orientationString = @"Portrait";
                break;
            case UIDeviceOrientationPortraitUpsideDown:
                orientationString = @"PortraitUpsideDown";
                break;
            case UIDeviceOrientationLandscapeLeft:
                orientationString = @"LandscapeLeft";
                break;
            case UIDeviceOrientationLandscapeRight:
                orientationString = @"LandscapeRight";
                break;
            case UIDeviceOrientationFaceUp:
                orientationString = @"FaceUp";
                break;
            case UIDeviceOrientationFaceDown:
                orientationString = @"FaceDown";
                break;
            default:
                orientationString = @"Unknown";
                break;
        }
        
        logToFile([NSString stringWithFormat:@"Orientação do dispositivo alterada para: %@", orientationString]);
        
        addDiagnosticData(@"deviceOrientation", @{
            @"orientation": @(orientation),
            @"orientationString": orientationString
        });
    }
}

%end

// Capturar mudanças na interface
%hook UIApplication

// Versão compatível com iOS 13+
- (void)_updateInterfaceOrientationIfNeeded {
    %orig;
    
    // Obter orientação atual da janela - forma segura para iOS 13+
    UIInterfaceOrientation orientation = UIInterfaceOrientationPortrait; // valor padrão
    
    // Usar a primeira janela disponível em vez de keyWindow (obsoleto)
    NSArray *windows = [UIApplication sharedApplication].windows;
    UIWindow *mainWindow = windows.count > 0 ? windows[0] : nil;
    
    if (@available(iOS 13.0, *)) {
        // Para iOS 13 ou superior, use a orientação da cena
        if (mainWindow && mainWindow.windowScene) {
            orientation = mainWindow.windowScene.interfaceOrientation;
        }
    }
    
    NSString *orientationString;
    switch (orientation) {
        case UIInterfaceOrientationPortrait:
            orientationString = @"Portrait";
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            orientationString = @"PortraitUpsideDown";
            break;
        case UIInterfaceOrientationLandscapeLeft:
            orientationString = @"LandscapeLeft";
            break;
        case UIInterfaceOrientationLandscapeRight:
            orientationString = @"LandscapeRight";
            break;
        default:
            orientationString = @"Unknown";
            break;
    }
    
    logToFile([NSString stringWithFormat:@"Orientação da interface alterada para: %@", orientationString]);
    
    addDiagnosticData(@"interfaceOrientation", @{
        @"orientation": @(orientation),
        @"orientationString": orientationString
    });
}

%end

// Capturar alterações de bounds e layout
%hook UIWindow

- (void)layoutSubviews {
    %orig;
    
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
}

%end

// Inicialização do tweak
%ctor {
    @autoreleasepool {
        // Criar diretório de logs
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSString *logDir = @"/var/tmp/CameraDiagnostic";
        if (![fileManager fileExistsAtPath:logDir]) {
            [fileManager createDirectoryAtPath:logDir
                  withIntermediateDirectories:YES
                                   attributes:nil
                                        error:nil];
        }
        
        // Log de inicialização
        NSString *processName = [NSProcessInfo processInfo].processName;
        NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
        logToFile([NSString stringWithFormat:@"CameraDiagnostic iniciado em: %@ (%@)", processName, bundleId]);
        
        // Inicializar dicionário de diagnóstico
        appDiagnosticData = [NSMutableDictionary dictionary];
        
        // Iniciar sessão de diagnóstico
        startNewDiagnosticSession();
        
        // Inicializar todos os hooks
        %init;
    }
}

// Finalização do tweak
%dtor {
    // Salvar dados antes de descarregar
    logToFile(@"CameraDiagnostic sendo descarregado");
    saveDiagnosticData();
    finalizeDiagnosticSession();
}
