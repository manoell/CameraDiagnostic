#import "../DiagnosticTweak.h"

// Grupo para hooks relacionados à sessão de captura
%group CaptureSessionHooks

// Hook para AVCaptureSession para monitorar início e configuração
%hook AVCaptureSession

// Monitorar quando a sessão é iniciada
- (void)startRunning {
    // Chamar o método original primeiro
    %orig;
    
    logMessage(@"AVCaptureSession startRunning foi chamado", LogLevelInfo, LogCategorySession);
    
    // Registrar na sessão de diagnóstico
    logSessionInfo(@"captureSessionActive", @YES);
    logSessionInfo(@"captureSessionStartTime", [NSDate date].description);
    
    // Extrair informações sobre a sessão
    NSMutableDictionary *sessionInfo = [NSMutableDictionary dictionary];
    sessionInfo[@"timestamp"] = [NSDate date].description;
    
    // Verificar preset da sessão
    if ([self respondsToSelector:@selector(sessionPreset)]) {
        NSString *preset = [self sessionPreset];
        sessionInfo[@"sessionPreset"] = preset ?: @"unknown";
        logSessionInfo(@"sessionPreset", preset);
    }
    
    // Verificar inputs
    if ([self respondsToSelector:@selector(inputs)]) {
        NSArray *inputs = [self inputs];
        NSMutableArray *inputsInfo = [NSMutableArray array];
        
        for (AVCaptureInput *input in inputs) {
            NSMutableDictionary *inputDict = [NSMutableDictionary dictionary];
            inputDict[@"class"] = NSStringFromClass([input class]);
            
            // Se for um AVCaptureDeviceInput, extrair informações do dispositivo
            if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
                AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
                AVCaptureDevice *device = deviceInput.device;
                
                if (device) {
                    inputDict[@"deviceName"] = device.localizedName ?: @"unknown";
                    inputDict[@"uniqueID"] = device.uniqueID ?: @"unknown";
                    inputDict[@"manufacturer"] = device.manufacturer ?: @"unknown";
                    inputDict[@"modelID"] = device.modelID ?: @"unknown";
                    
                    // Tipo de mídia
                    if ([device hasMediaType:AVMediaTypeVideo]) {
                        inputDict[@"mediaType"] = @"video";
                        
                        // Posição da câmera
                        switch (device.position) {
                            case AVCaptureDevicePositionBack:
                                inputDict[@"position"] = @"back";
                                break;
                            case AVCaptureDevicePositionFront:
                                inputDict[@"position"] = @"front";
                                break;
                            default:
                                inputDict[@"position"] = @"unknown";
                                break;
                        }
                    } else if ([device hasMediaType:AVMediaTypeAudio]) {
                        inputDict[@"mediaType"] = @"audio";
                    } else {
                        inputDict[@"mediaType"] = @"other";
                    }
                }
            }
            
            [inputsInfo addObject:inputDict];
        }
        
        sessionInfo[@"inputs"] = inputsInfo;
    }
    
    // Verificar outputs
    if ([self respondsToSelector:@selector(outputs)]) {
        NSArray *outputs = [self outputs];
        NSMutableArray *outputsInfo = [NSMutableArray array];
        
        for (AVCaptureOutput *output in outputs) {
            NSMutableDictionary *outputDict = [NSMutableDictionary dictionary];
            outputDict[@"class"] = NSStringFromClass([output class]);
            
            // Verificar tipo específico de output
            if ([output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
                AVCaptureVideoDataOutput *videoOutput = (AVCaptureVideoDataOutput *)output;
                outputDict[@"type"] = @"videoData";
                outputDict[@"videoSettings"] = videoOutput.videoSettings ?: @{};
                outputDict[@"alwaysDiscardsLateVideoFrames"] = @(videoOutput.alwaysDiscardsLateVideoFrames);
            }
            else if ([output isKindOfClass:[AVCaptureAudioDataOutput class]]) {
                // Remover a variável não utilizada
                outputDict[@"type"] = @"audioData";
                outputDict[@"hasAudioSettings"] = @YES;
            }
            else if ([output isKindOfClass:[AVCaptureMovieFileOutput class]]) {
                AVCaptureMovieFileOutput *movieOutput = (AVCaptureMovieFileOutput *)output;
                outputDict[@"type"] = @"movieFile";
                outputDict[@"movieFragmentInterval"] = @(CMTimeGetSeconds(movieOutput.movieFragmentInterval));
                outputDict[@"maxRecordedDuration"] = @(CMTimeGetSeconds(movieOutput.maxRecordedDuration));
                outputDict[@"maxRecordedFileSize"] = @(movieOutput.maxRecordedFileSize);
            }
            else if ([output isKindOfClass:[AVCapturePhotoOutput class]]) {
                outputDict[@"type"] = @"photo";
                
                if (@available(iOS 10.0, *)) {
                    AVCapturePhotoOutput *photoOutput = (AVCapturePhotoOutput *)output;
                    // Remover a propriedade não existente
                    outputDict[@"isLivePhotoCaptureSupported"] = @(photoOutput.isLivePhotoCaptureSupported);
                    outputDict[@"isDepthDataDeliverySupported"] = @(photoOutput.isDepthDataDeliverySupported);
                    
                    NSMutableArray *availableFormats = [NSMutableArray array];
                    for (NSNumber *format in photoOutput.availablePhotoPixelFormatTypes) {
                        // Converter formato para string legível
                        uint32_t pixelFormat = [format unsignedIntValue];
                        char formatStr[5] = {0};
                        formatStr[0] = (pixelFormat >> 24) & 0xFF;
                        formatStr[1] = (pixelFormat >> 16) & 0xFF;
                        formatStr[2] = (pixelFormat >> 8) & 0xFF;
                        formatStr[3] = pixelFormat & 0xFF;
                        
                        [availableFormats addObject:@{
                            @"format": format,
                            @"formatString": [NSString stringWithCString:formatStr encoding:NSASCIIStringEncoding]
                        }];
                    }
                    outputDict[@"availablePhotoPixelFormatTypes"] = availableFormats;
                }
            }
            
            [outputsInfo addObject:outputDict];
        }
        
        sessionInfo[@"outputs"] = outputsInfo;
    }
    
    // Verificar conexões
    if ([self respondsToSelector:@selector(connections)]) {
        NSArray *connections = [self connections];
        NSMutableArray *connectionsInfo = [NSMutableArray array];
        
        for (AVCaptureConnection *connection in connections) {
            NSMutableDictionary *connectionDict = [NSMutableDictionary dictionary];
            
            // Informações básicas
            connectionDict[@"enabled"] = @(connection.enabled);
            
            // Verificar se é conexão de vídeo
            if ([connection isVideoOrientationSupported]) {
                connectionDict[@"isVideoConnection"] = @YES;
                connectionDict[@"videoOrientation"] = @(connection.videoOrientation);
                connectionDict[@"videoMirrored"] = @(connection.isVideoMirrored);
                
                // Converter para string legível
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
                connectionDict[@"videoOrientationString"] = orientationString;
            } else {
                connectionDict[@"isVideoConnection"] = @NO;
            }
            
            // Verificar portas de input
            NSArray *inputPorts = connection.inputPorts;
            NSMutableArray *portsInfo = [NSMutableArray array];
            
            for (AVCaptureInputPort *port in inputPorts) {
                [portsInfo addObject:@{
                    @"mediaType": port.mediaType ?: @"unknown",
                    @"sourceDeviceType": port.sourceDeviceType ?: @"unknown",
                    @"sourceDevicePosition": @(port.sourceDevicePosition)
                }];
            }
            
            connectionDict[@"inputPorts"] = portsInfo;
            [connectionsInfo addObject:connectionDict];
        }
        
        sessionInfo[@"connections"] = connectionsInfo;
    }
    
    // Registrar todas as informações no log
    logJSONWithDescription(sessionInfo, LogCategorySession, @"Configuração da AVCaptureSession");
}

// Monitorar quando a sessão é parada
- (void)stopRunning {
    %orig;
    
    logMessage(@"AVCaptureSession stopRunning foi chamado", LogLevelInfo, LogCategorySession);
    
    // Registrar na sessão de diagnóstico
    logSessionInfo(@"captureSessionActive", @NO);
    logSessionInfo(@"captureSessionStopTime", [NSDate date].description);
    
    // Registrar informações no log
    NSDictionary *logData = @{
        @"timestamp": [NSDate date].description
    };
    logJSONWithDescription(logData, LogCategorySession, @"AVCaptureSession foi parada");
}

// Monitorar alterações de preset da sessão
- (void)setSessionPreset:(NSString *)sessionPreset {
    %orig;
    
    if (sessionPreset) {
        NSDictionary *logData = @{
            @"sessionPreset": sessionPreset,
            @"timestamp": [NSDate date].description
        };
        logJSONWithDescription(logData, LogCategorySession, @"Preset da sessão alterado");
        
        // Atualizar na sessão de diagnóstico
        logSessionInfo(@"sessionPreset", sessionPreset);
    }
}

// Monitorar adição de inputs
- (BOOL)addInput:(AVCaptureInput *)input {
    BOOL result = %orig;
    
    if (result && input) {
        NSMutableDictionary *inputInfo = [NSMutableDictionary dictionary];
        inputInfo[@"class"] = NSStringFromClass([input class]);
        
        // Se for um AVCaptureDeviceInput, extrair informações do dispositivo
        if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
            AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
            AVCaptureDevice *device = deviceInput.device;
            
            if (device) {
                inputInfo[@"deviceName"] = device.localizedName ?: @"unknown";
                inputInfo[@"uniqueID"] = device.uniqueID ?: @"unknown";
                
                // Tipo de mídia
                if ([device hasMediaType:AVMediaTypeVideo]) {
                    inputInfo[@"mediaType"] = @"video";
                    
                    // Posição da câmera
                    switch (device.position) {
                        case AVCaptureDevicePositionBack:
                            inputInfo[@"position"] = @"back";
                            break;
                        case AVCaptureDevicePositionFront:
                            inputInfo[@"position"] = @"front";
                            break;
                        default:
                            inputInfo[@"position"] = @"unknown";
                            break;
                    }
                } else if ([device hasMediaType:AVMediaTypeAudio]) {
                    inputInfo[@"mediaType"] = @"audio";
                } else {
                    inputInfo[@"mediaType"] = @"other";
                }
            }
        }
        
        logJSONWithDescription(inputInfo, LogCategorySession, @"Input adicionado à sessão");
    }
    
    return result;
}

// Monitorar adição de outputs
- (BOOL)addOutput:(AVCaptureOutput *)output {
    BOOL result = %orig;
    
    if (result && output) {
        NSMutableDictionary *outputInfo = [NSMutableDictionary dictionary];
        outputInfo[@"class"] = NSStringFromClass([output class]);
        
        // Verificar tipo específico de output
        if ([output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
            outputInfo[@"type"] = @"videoData";
        }
        else if ([output isKindOfClass:[AVCaptureAudioDataOutput class]]) {
            outputInfo[@"type"] = @"audioData";
        }
        else if ([output isKindOfClass:[AVCaptureMovieFileOutput class]]) {
            outputInfo[@"type"] = @"movieFile";
        }
        else if ([output isKindOfClass:[AVCapturePhotoOutput class]]) {
            outputInfo[@"type"] = @"photo";
        }
        
        logJSONWithDescription(outputInfo, LogCategorySession, @"Output adicionado à sessão");
    }
    
    return result;
}

// Monitorar erros da sessão
- (void)_notifyAboutRuntimeError:(NSError *)error {
    %orig;
    
    if (error) {
        NSDictionary *errorInfo = @{
            @"code": @(error.code),
            @"domain": error.domain ?: @"unknown",
            @"description": error.localizedDescription ?: @"unknown",
            @"timestamp": [NSDate date].description
        };
        logJSONWithDescription(errorInfo, LogCategorySession, @"Erro na sessão de captura");
    }
}

// Monitorar interrupções na sessão
- (void)beginInterruption {
    %orig;
    
    NSDictionary *interruptionInfo = @{
        @"timestamp": [NSDate date].description
    };
    logJSONWithDescription(interruptionInfo, LogCategorySession, @"Interrupção iniciada na sessão");
    
    // Registrar na sessão de diagnóstico
    logSessionInfo(@"sessionInterrupted", @YES);
    logSessionInfo(@"sessionInterruptionTime", [NSDate date].description);
}

- (void)endInterruption {
    %orig;
    
    NSDictionary *interruptionInfo = @{
        @"timestamp": [NSDate date].description
    };
    logJSONWithDescription(interruptionInfo, LogCategorySession, @"Interrupção finalizada na sessão");
    
    // Registrar na sessão de diagnóstico
    logSessionInfo(@"sessionInterrupted", @NO);
    logSessionInfo(@"sessionInterruptionEndTime", [NSDate date].description);
}

%end

%end // grupo CaptureSessionHooks

// Constructor específico deste arquivo
%ctor {
    %init(CaptureSessionHooks);
}
