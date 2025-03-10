#import "Tweak.h"

// Grupo para hooks relacionados à câmera
%group CameraHooks

// Função auxiliar para garantir que a resolução da câmera está atualizada
static void updateCurrentCameraResolution() {
    // Atualizar a resolução atual com base na câmera em uso
    if (CGSizeEqualToSize(g_originalFrontCameraResolution, CGSizeZero) ||
        CGSizeEqualToSize(g_originalBackCameraResolution, CGSizeZero)) {
        return;
    }
    
    g_originalCameraResolution = g_usingFrontCamera ? g_originalFrontCameraResolution : g_originalBackCameraResolution;
    
    // Log para depuração
    writeLog(@"[HOOK] Resolução atual da câmera atualizada para %.0f x %.0f (Câmera %@)",
             g_originalCameraResolution.width, g_originalCameraResolution.height,
             g_usingFrontCamera ? @"Frontal" : @"Traseira");
    
    // Registrar esta troca no diagnóstico
    [[DiagnosticCollector sharedInstance] recordCameraSwitch:g_usingFrontCamera
                                              withResolution:g_originalCameraResolution];
}

// Hook para AVCaptureSession para monitorar quando a câmera é iniciada
%hook AVCaptureSession

- (void)startRunning {
    writeLog(@"[HOOK] AVCaptureSession startRunning foi chamado");
    
    // Coletar informações de diagnóstico antes da chamada original
    NSArray *inputs = [self inputs];
    NSArray *outputs = [self outputs];
    
    NSMutableArray *inputsInfo = [NSMutableArray array];
    NSMutableArray *outputsInfo = [NSMutableArray array];
    
    for (AVCaptureInput *input in inputs) {
        [inputsInfo addObject:@{
            @"class": NSStringFromClass([input class]),
            @"ports": @(input.ports.count)
        }];
    }
    
    for (AVCaptureOutput *output in outputs) {
        NSMutableDictionary *outputInfo = [NSMutableDictionary dictionary];
        outputInfo[@"class"] = NSStringFromClass([output class]);
        
        if ([output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
            AVCaptureVideoDataOutput *videoOutput = (AVCaptureVideoDataOutput *)output;
            outputInfo[@"videoSettings"] = videoOutput.videoSettings ?: @{};
            
            id<AVCaptureVideoDataOutputSampleBufferDelegate> delegate = [videoOutput sampleBufferDelegate];
            if (delegate) {
                outputInfo[@"delegateClass"] = NSStringFromClass([delegate class]);
            }
        }
        else if ([output isKindOfClass:[AVCapturePhotoOutput class]]) {
            // Para saída de foto
            outputInfo[@"type"] = @"photo";
        }
        
        [outputsInfo addObject:outputInfo];
    }
    
    // Registrar dados da sessão
    [[DiagnosticCollector sharedInstance] recordSessionStart:@{
        @"inputs": inputsInfo,
        @"outputs": outputsInfo,
        @"sessionPreset": [self sessionPreset] ?: @"unknown"
    }];
    
    // Registrar delegados conhecidos
    logDelegates();
    
    g_isCaptureActive = YES;
    
    // Chamar o método original
    %orig;
    
    // Coletar informações pós-inicialização
    [[DiagnosticCollector sharedInstance] recordSessionInfo:@{
        @"isRunning": @([self isRunning]),
        @"isInterrupted": @([self isInterrupted])
    }];
}

- (void)stopRunning {
    writeLog(@"[HOOK] AVCaptureSession stopRunning foi chamado");
    
    // Coletar diagnóstico
    [[DiagnosticCollector sharedInstance] recordSessionStop:@{
        @"wasRunning": @([self isRunning]),
        @"wasInterrupted": @([self isInterrupted])
    }];
    
    g_isCaptureActive = NO;
    
    %orig;
}

// Monitorar adição de entrada para detectar tipos de câmera
- (BOOL)addInput:(AVCaptureInput *)input {
    BOOL result = %orig;
    
    if (result && [input isKindOfClass:[AVCaptureDeviceInput class]]) {
        AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
        AVCaptureDevice *device = deviceInput.device;
        
        if ([device hasMediaType:AVMediaTypeVideo]) {
            // Determinar se é câmera frontal ou traseira
            BOOL isFrontCamera = (device.position == AVCaptureDevicePositionFront);
            g_usingFrontCamera = isFrontCamera;
            
            writeLog(@"[HOOK] Adicionada entrada de câmera: %@", isFrontCamera ? @"Frontal" : @"Traseira");
            
            // Adicionar ao diagnóstico
            [[DiagnosticCollector sharedInstance] recordInputAdded:@{
                @"deviceType": @"camera",
                @"position": isFrontCamera ? @"front" : @"back",
                @"deviceId": device.uniqueID ?: @"unknown",
                @"modelID": device.modelID ?: @"unknown",
                @"localizedName": device.localizedName ?: @"unknown"
            }];
            
            // Atualizar resolução
            updateCurrentCameraResolution();
        }
        else if ([device hasMediaType:AVMediaTypeAudio]) {
            writeLog(@"[HOOK] Adicionada entrada de áudio: %@", device.localizedName);
            
            [[DiagnosticCollector sharedInstance] recordInputAdded:@{
                @"deviceType": @"microphone",
                @"deviceId": device.uniqueID ?: @"unknown",
                @"localizedName": device.localizedName ?: @"unknown"
            }];
        }
    }
    
    return result;
}

// Monitorar adição de saída para entender o pipeline de processamento
- (BOOL)addOutput:(AVCaptureOutput *)output {
    BOOL result = %orig;
    
    if (result) {
        NSString *outputClass = NSStringFromClass([output class]);
        writeLog(@"[HOOK] Adicionada saída: %@", outputClass);
        
        NSMutableDictionary *outputInfo = [NSMutableDictionary dictionary];
        outputInfo[@"class"] = outputClass;
        
        if ([output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
            AVCaptureVideoDataOutput *videoOutput = (AVCaptureVideoDataOutput *)output;
            outputInfo[@"videoSettings"] = videoOutput.videoSettings ?: @{};
            
            id<AVCaptureVideoDataOutputSampleBufferDelegate> delegate = [videoOutput sampleBufferDelegate];
            if (delegate) {
                outputInfo[@"delegateClass"] = NSStringFromClass([delegate class]);
            }
            
            outputInfo[@"type"] = @"video";
        }
        else if ([output isKindOfClass:[AVCaptureAudioDataOutput class]]) {
            outputInfo[@"type"] = @"audio";
        }
        else if ([output isKindOfClass:[AVCapturePhotoOutput class]]) {
            outputInfo[@"type"] = @"photo";
            
            // Configurações específicas para foto
            if (@available(iOS 11.0, *)) {
                AVCapturePhotoOutput *photoOutput = (AVCapturePhotoOutput *)output;
                // Corrigido - não pode boxear um NSArray
                outputInfo[@"supportedFlashModes"] = @(photoOutput.supportedFlashModes.count);
                outputInfo[@"maxBracketedCapturePhotoCount"] = @(photoOutput.maxBracketedCapturePhotoCount);
                outputInfo[@"availablePhotoCodecTypes"] = photoOutput.availablePhotoCodecTypes ?: @[];
            }
        }
        
        [[DiagnosticCollector sharedInstance] recordOutputAdded:outputInfo];
    }
    
    return result;
}

%end

// Hook para AVCaptureConnection para entender seu funcionamento
%hook AVCaptureConnection

- (void)setVideoOrientation:(AVCaptureVideoOrientation)videoOrientation {
    writeLog(@"[HOOK] setVideoOrientation: %d (Anterior: %d)", (int)videoOrientation, g_videoOrientation);
    g_isVideoOrientationSet = YES;
    g_videoOrientation = (int)videoOrientation;
    
    // Log detalhado
    NSString *orientationDesc;
    switch ((int)videoOrientation) {
        case 1: orientationDesc = @"Portrait"; break;
        case 2: orientationDesc = @"Portrait Upside Down"; break;
        case 3: orientationDesc = @"Landscape Right"; break;
        case 4: orientationDesc = @"Landscape Left"; break;
        default: orientationDesc = @"Desconhecido"; break;
    }
    
    writeLog(@"[HOOK] Orientação definida para: %@ (%d)", orientationDesc, (int)videoOrientation);
    
    // Registrar no diagnóstico
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[@"orientation"] = @(videoOrientation);
    info[@"orientationName"] = orientationDesc;
    
    // Verificar se há portas de entrada e corrigir acesso
    if (self.inputPorts.count > 0) {
        AVCaptureInputPort *firstPort = self.inputPorts.firstObject;
        info[@"connectionInputPortMediaType"] = firstPort.mediaType ?: @"unknown";
    } else {
        info[@"connectionInputPortMediaType"] = @"unknown";
    }
    
    info[@"connectionOutputClass"] = NSStringFromClass([self.output class]);
    
    [[DiagnosticCollector sharedInstance] recordVideoOrientation:info];
    
    %orig;
}

// Monitorar outras propriedades de conexão importantes
- (void)setVideoMinFrameDuration:(CMTime)frameDuration {
    %orig;
    
    float fps = frameDuration.value > 0 ? (float)frameDuration.timescale / frameDuration.value : 0;
    writeLog(@"[HOOK] setVideoMinFrameDuration: %f FPS", fps);
    
    [[DiagnosticCollector sharedInstance] recordConnectionProperty:@{
        @"property": @"videoMinFrameDuration",
        @"fps": @(fps),
        @"timescale": @(frameDuration.timescale),
        @"timeValue": @(frameDuration.value)  // Renomeado para evitar chave duplicada
    }];
}

- (void)setVideoMaxFrameDuration:(CMTime)frameDuration {
    %orig;
    
    float fps = frameDuration.value > 0 ? (float)frameDuration.timescale / frameDuration.value : 0;
    writeLog(@"[HOOK] setVideoMaxFrameDuration: %f FPS", fps);
    
    [[DiagnosticCollector sharedInstance] recordConnectionProperty:@{
        @"property": @"videoMaxFrameDuration",
        @"fps": @(fps),
        @"timescale": @(frameDuration.timescale),
        @"timeValue": @(frameDuration.value)  // Renomeado para evitar chave duplicada
    }];
}

- (void)setAutomaticallyAdjustsVideoMirroring:(BOOL)automaticallyAdjustsVideoMirroring {
    %orig;
    
    writeLog(@"[HOOK] setAutomaticallyAdjustsVideoMirroring: %d", automaticallyAdjustsVideoMirroring);
    
    [[DiagnosticCollector sharedInstance] recordConnectionProperty:@{
        @"property": @"automaticallyAdjustsVideoMirroring",
        @"value": @(automaticallyAdjustsVideoMirroring)
    }];
}

- (void)setVideoMirrored:(BOOL)videoMirrored {
    %orig;
    
    writeLog(@"[HOOK] setVideoMirrored: %d", videoMirrored);
    
    [[DiagnosticCollector sharedInstance] recordConnectionProperty:@{
        @"property": @"videoMirrored",
        @"value": @(videoMirrored)
    }];
}

%end

// Hook para AVCaptureDevice para obter a resolução real da câmera
%hook AVCaptureDevice

+ (AVCaptureDevice *)defaultDeviceWithMediaType:(NSString *)mediaType {
    AVCaptureDevice *device = %orig;
    
    if ([mediaType isEqualToString:AVMediaTypeVideo] && device) {
        // Obter a resolução da câmera real
        AVCaptureDeviceFormat *format = device.activeFormat;
        if (format) {
            CMVideoFormatDescriptionRef formatDescription = format.formatDescription;
            if (formatDescription) {
                CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
                
                // Determinar se é câmera frontal ou traseira
                BOOL isFrontCamera = (device.position == AVCaptureDevicePositionFront);
                g_usingFrontCamera = isFrontCamera;
                
                if (isFrontCamera) {
                    g_originalFrontCameraResolution = CGSizeMake(dimensions.width, dimensions.height);
                    writeLog(@"[HOOK] Resolução da câmera frontal detectada: %.0f x %.0f",
                            g_originalFrontCameraResolution.width, g_originalFrontCameraResolution.height);
                } else {
                    g_originalBackCameraResolution = CGSizeMake(dimensions.width, dimensions.height);
                    writeLog(@"[HOOK] Resolução da câmera traseira detectada: %.0f x %.0f",
                            g_originalBackCameraResolution.width, g_originalBackCameraResolution.height);
                }
                
                // Definir a resolução atual com base na câmera em uso
                g_originalCameraResolution = isFrontCamera ? g_originalFrontCameraResolution : g_originalBackCameraResolution;
                
                // Diagnóstico detalhado do formato da câmera
                [[DiagnosticCollector sharedInstance] recordCameraFormat:@{
                    @"position": isFrontCamera ? @"front" : @"back",
                    @"resolution": @{
                        @"width": @(dimensions.width),
                        @"height": @(dimensions.height)
                    },
                    @"deviceType": device.deviceType ?: @"unknown",
                    @"uniqueID": device.uniqueID ?: @"unknown",
                    @"modelID": device.modelID ?: @"unknown",
                    @"formatMaxFrameRate": @(format.videoSupportedFrameRateRanges.firstObject.maxFrameRate),
                    @"formatMinFrameRate": @(format.videoSupportedFrameRateRanges.firstObject.minFrameRate),
                    @"formatMediaSubType": @(CMFormatDescriptionGetMediaSubType(formatDescription)),
                    @"exposureMode": @(device.exposureMode),  // Corrigido
                    @"focusMode": @(device.focusMode)         // Corrigido
                }];
            }
        }
    }
    
    return device;
}

// Método adicional para detectar a posição da câmera
- (void)_setPosition:(int)position {
    %orig;
    
    // 1 = traseira, 2 = frontal
    BOOL isFrontCamera = (position == 2);
    g_usingFrontCamera = isFrontCamera;
    
    // Usar a função de atualização em vez do código direto
    updateCurrentCameraResolution();
    
    writeLog(@"[HOOK] Mudança de câmera detectada: %@", isFrontCamera ? @"Frontal" : @"Traseira");
}

// Coletar informações sobre mudanças de configuração da câmera
- (BOOL)lockForConfiguration:(NSError **)outError {
    BOOL result = %orig;
    
    if (result) {
        writeLog(@"[HOOK] lockForConfiguration sucesso para dispositivo: %@", self.localizedName);
        
        [[DiagnosticCollector sharedInstance] recordDeviceOperation:@{
            @"operation": @"lockForConfiguration",
            @"success": @YES,
            @"deviceType": self.deviceType ?: @"unknown",
            @"uniqueID": self.uniqueID ?: @"unknown"
        }];
    } else if (outError && *outError) {
        writeLog(@"[HOOK] lockForConfiguration falhou: %@", [*outError localizedDescription]);
        
        [[DiagnosticCollector sharedInstance] recordDeviceOperation:@{
            @"operation": @"lockForConfiguration",
            @"success": @NO,
            @"errorCode": @((*outError).code),
            @"errorDomain": (*outError).domain ?: @"unknown"
        }];
    }
    
    return result;
}

- (void)unlockForConfiguration {
    writeLog(@"[HOOK] unlockForConfiguration para dispositivo: %@", self.localizedName);
    
    [[DiagnosticCollector sharedInstance] recordDeviceOperation:@{
        @"operation": @"unlockForConfiguration",
        @"deviceType": self.deviceType ?: @"unknown",
        @"uniqueID": self.uniqueID ?: @"unknown"
    }];
    
    %orig;
}

// Monitorar mudanças de formato
- (void)setActiveFormat:(AVCaptureDeviceFormat *)format {
    %orig;
    
    if (format) {
        CMVideoFormatDescriptionRef formatDescription = format.formatDescription;
        if (formatDescription) {
            CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
            writeLog(@"[HOOK] setActiveFormat: %d x %d", dimensions.width, dimensions.height);
            
            // Diagnosticar
            [[DiagnosticCollector sharedInstance] recordDeviceFormatChange:@{
                @"width": @(dimensions.width),
                @"height": @(dimensions.height),
                @"mediaSubType": @(CMFormatDescriptionGetMediaSubType(formatDescription)),
                @"maxFrameRate": @(format.videoSupportedFrameRateRanges.firstObject.maxFrameRate),
                @"minFrameRate": @(format.videoSupportedFrameRateRanges.firstObject.minFrameRate)
            }];
        }
    }
}

%end

// Hook para AVCaptureVideoDataOutput para monitorar captura
%hook AVCaptureVideoDataOutput

- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    writeLog(@"[HOOK] AVCaptureVideoDataOutput setSampleBufferDelegate: %@",
             NSStringFromClass([sampleBufferDelegate class]));
    
    // Diagnóstico sobre o delegate
    NSMutableDictionary *delegateInfo = [NSMutableDictionary dictionary];
    if (sampleBufferDelegate) {
        delegateInfo[@"delegateClass"] = NSStringFromClass([sampleBufferDelegate class]);
        delegateInfo[@"delegateRespondsToSelector"] = @([sampleBufferDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]);
        
        if (sampleBufferCallbackQueue) {
            const char *queueLabel = dispatch_queue_get_label(sampleBufferCallbackQueue);
            if (queueLabel) {
                delegateInfo[@"queueLabel"] = [NSString stringWithUTF8String:queueLabel];
            }
        }
    }
    
    [[DiagnosticCollector sharedInstance] recordVideoOutputDelegate:delegateInfo];
    
    %orig;
}

// Monitorar configurações de vídeo
- (void)setVideoSettings:(NSDictionary<NSString *,id> *)videoSettings {
    %orig;
    
    writeLog(@"[HOOK] setVideoSettings: %@", videoSettings);
    
    [[DiagnosticCollector sharedInstance] recordVideoSettings:videoSettings];
}

%end

// Hook para AVCaptureAudioDataOutput
%hook AVCaptureAudioDataOutput

- (void)setSampleBufferDelegate:(id<AVCaptureAudioDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    writeLog(@"[HOOK] AVCaptureAudioDataOutput setSampleBufferDelegate: %@",
             NSStringFromClass([sampleBufferDelegate class]));
    
    // Diagnóstico sobre o delegate de áudio
    NSMutableDictionary *delegateInfo = [NSMutableDictionary dictionary];
    if (sampleBufferDelegate) {
        delegateInfo[@"delegateClass"] = NSStringFromClass([sampleBufferDelegate class]);
        delegateInfo[@"delegateRespondsToSelector"] = @([sampleBufferDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]);
        
        if (sampleBufferCallbackQueue) {
            const char *queueLabel = dispatch_queue_get_label(sampleBufferCallbackQueue);
            if (queueLabel) {
                delegateInfo[@"queueLabel"] = [NSString stringWithUTF8String:queueLabel];
            }
        }
    }
    
    [[DiagnosticCollector sharedInstance] recordAudioOutputDelegate:delegateInfo];
    
    %orig;
}

%end

// Hook para AVCapturePhotoOutput para entender a captura de fotos
%hook AVCapturePhotoOutput

- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    writeLog(@"[HOOK] capturePhotoWithSettings:delegate: chamado");
    
    // Coletar informações sobre configurações de foto
    NSMutableDictionary *photoSettings = [NSMutableDictionary dictionary];
    
    if (settings) {
        // Corrigido - uniqueID é um inteiro, não um objeto
        photoSettings[@"uniqueID"] = settings.uniqueID ? @(settings.uniqueID) : @"unknown";
        photoSettings[@"flashMode"] = @(settings.flashMode);
        
        // Coletar informações sobre formato de foto
        if (@available(iOS 11.0, *)) {
            photoSettings[@"isDepthDataDeliveryEnabled"] = @(settings.isDepthDataDeliveryEnabled);
            
            // Remover método obsoleto
            if (@available(iOS 13.0, *)) {
                photoSettings[@"photoQualityPrioritization"] = @(settings.photoQualityPrioritization);
            } else {
                // Para iOS 11-12, ainda podemos usar o método obsoleto
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Wdeprecated-declarations"
                photoSettings[@"isAutoStillImageStabilizationEnabled"] = @(settings.isAutoStillImageStabilizationEnabled);
                #pragma clang diagnostic pop
            }
            
            photoSettings[@"isHighResolutionPhotoEnabled"] = @(settings.isHighResolutionPhotoEnabled);
            
            if (settings.availablePreviewPhotoPixelFormatTypes.count > 0) {
                photoSettings[@"hasPreviewFormat"] = @YES;
                photoSettings[@"previewPixelFormatTypes"] = settings.availablePreviewPhotoPixelFormatTypes;
                
                NSDictionary *previewFormat = settings.previewPhotoFormat;
                if (previewFormat) {
                    photoSettings[@"previewFormat"] = previewFormat;
                }
            }
            
            photoSettings[@"processedFileType"] = settings.processedFileType;
        }
        
        if (@available(iOS 10.0, *)) {
            photoSettings[@"livePhotoMovieFileURL"] = settings.livePhotoMovieFileURL.absoluteString ?: @"none";
            photoSettings[@"isLivePhotoEnabled"] = @(settings.livePhotoMovieFileURL != nil);
        }
    }
    
    // Informações sobre o delegate
    NSMutableDictionary *delegateInfo = [NSMutableDictionary dictionary];
    if (delegate) {
        delegateInfo[@"class"] = NSStringFromClass([delegate class]);
        delegateInfo[@"respondsToCapture"] = @([delegate respondsToSelector:@selector(captureOutput:didFinishProcessingPhoto:error:)]);
        delegateInfo[@"respondsToPhotoSampleBuffer"] = @([delegate respondsToSelector:@selector(captureOutput:didFinishProcessingPhotoSampleBuffer:previewPhotoSampleBuffer:resolvedSettings:bracketSettings:error:)]);
    }
    
    // Registrar no diagnóstico
    [[DiagnosticCollector sharedInstance] recordPhotoCapture:@{
        @"settings": photoSettings,
        @"delegate": delegateInfo,
        @"isFrontCamera": @(g_usingFrontCamera),
        @"resolution": @{
            @"width": @(g_originalCameraResolution.width),
            @"height": @(g_originalCameraResolution.height)
        },
        @"videoOrientation": @(g_videoOrientation)
    }];
    
    %orig;
}

%end

// Para todos os iOS - processamento de vídeo
%hook NSObject

// Para a captura de frames de vídeo
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    // Verificar se somos um delegate de amostra de buffer
    if (![self respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
        return %orig;
    }
    
    // Limitar a quantidade de logs para evitar sobrecarga
    static int frameCount = 0;
    static NSTimeInterval lastLogTime = 0;
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    
    if (++frameCount % 100 == 0 || currentTime - lastLogTime > 5.0) {
        lastLogTime = currentTime;
        writeLog(@"[FRAME] Frame #%d recebido por classe %@", frameCount, NSStringFromClass([self class]));
        
        // Extrair e diagnosticar informações do buffer apenas periodicamente
        if (sampleBuffer && CMSampleBufferIsValid(sampleBuffer)) {
            @try {
                // Informações sobre o formato do frame
                CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
                if (!formatDescription) {
                    %orig;
                    return;
                }
                
                FourCharCode mediaSubType = CMFormatDescriptionGetMediaSubType(formatDescription);
                
                // Extrair dimensões
                CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
                size_t width = 0;
                size_t height = 0;
                size_t bytesPerRow = 0;
                if (imageBuffer) {
                    width = CVPixelBufferGetWidth(imageBuffer);
                    height = CVPixelBufferGetHeight(imageBuffer);
                    bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
                }
                
                // Informações de timing
                CMTime presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
                CMTime decodeTime = CMSampleBufferGetDecodeTimeStamp(sampleBuffer);
                
                // Descobrir formato como string
                char mediaSubTypeStr[5] = {0};
                mediaSubTypeStr[0] = (char)((mediaSubType >> 24) & 0xFF);
                mediaSubTypeStr[1] = (char)((mediaSubType >> 16) & 0xFF);
                mediaSubTypeStr[2] = (char)((mediaSubType >> 8) & 0xFF);
                mediaSubTypeStr[3] = (char)(mediaSubType & 0xFF);
                
                // Informações de timestamp
                float presentationSeconds = (float)presentationTime.value / presentationTime.timescale;
                
                // Coletar dados sobre o output
                NSString *outputClass = NSStringFromClass([output class]);
                
                // Capturar informações de orientação da conexão
                int videoOrientation = (connection && [connection isKindOfClass:[AVCaptureConnection class]]) ?
                                      (int)[connection videoOrientation] : -1;
                
                // Capturar informações de espelhamento
                BOOL isMirrored = (connection && [connection isKindOfClass:[AVCaptureConnection class]]) ?
                                 [connection isVideoMirrored] : NO;
                
                // Coleta de metadados (limitada para evitar dados excessivos)
                NSMutableDictionary *metadataInfo = [NSMutableDictionary dictionary];
                CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true);
                if (attachments && CFArrayGetCount(attachments) > 0) {
                    CFDictionaryRef attachmentDict = (CFDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
                    if (attachmentDict) {
                        // Verificar se o frame é keyframe (I-frame)
                        bool keyFrame = !CFDictionaryContainsKey(attachmentDict, kCMSampleAttachmentKey_NotSync);
                        metadataInfo[@"isKeyFrame"] = @(keyFrame);
                        
                        // Outros metadados importantes
                        if (CFDictionaryContainsKey(attachmentDict, kCMSampleAttachmentKey_DependsOnOthers)) {
                            CFTypeRef valueRef = CFDictionaryGetValue(attachmentDict, kCMSampleAttachmentKey_DependsOnOthers);
                            if (valueRef && CFGetTypeID(valueRef) == CFBooleanGetTypeID()) {
                                bool boolValue = CFBooleanGetValue((CFBooleanRef)valueRef);
                                metadataInfo[@"dependsOnOthers"] = @(boolValue);
                            }
                        }
                    }
                }
                
                // Registrar diagnóstico do frame
                [[DiagnosticCollector sharedInstance] recordSampleBufferInfo:@{
                    @"delegateClass": NSStringFromClass([self class]),
                    @"outputClass": outputClass,
                    @"width": @(width),
                    @"height": @(height),
                    @"bytesPerRow": @(bytesPerRow),
                    @"mediaSubType": [NSString stringWithUTF8String:mediaSubTypeStr],
                    @"mediaSubTypeValue": @(mediaSubType),
                    @"presentationTime": @(presentationSeconds),
                    @"isPresentationTimeValid": @(CMTIME_IS_VALID(presentationTime)),
                    @"isDecodeTimeValid": @(CMTIME_IS_VALID(decodeTime)),
                    @"videoOrientation": @(videoOrientation),
                    @"isMirrored": @(isMirrored),
                    @"metadata": metadataInfo
                }];
            } @catch (NSException *exception) {
                writeLog(@"[ERROR] Erro ao diagnosticar sampleBuffer: %@", exception);
            }
        }
    }
    
    %orig;
}

// Monitorar a preparação de frames para display
- (void)enqueueSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if ([self isKindOfClass:[AVSampleBufferDisplayLayer class]]) {
        writeLog(@"[DISPLAY] SampleBuffer enfileirado para display em AVSampleBufferDisplayLayer");
        
        // Diagnosticar apenas se o buffer for válido
        if (sampleBuffer && CMSampleBufferIsValid(sampleBuffer)) {
            // Extrair informações básicas
            CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
            if (formatDesc) {
                FourCharCode mediaSubType = CMFormatDescriptionGetMediaSubType(formatDesc);
                
                // Diagnosticar
                [[DiagnosticCollector sharedInstance] recordDisplayLayerInfo:@{
                    @"action": @"enqueueSampleBuffer",
                    @"layerClass": NSStringFromClass([self class]),
                    @"mediaSubType": @(mediaSubType),
                    @"bufferValid": @YES
                }];
            }
        }
    }
    
    %orig;
}

- (void)flush {
    if ([self isKindOfClass:[AVSampleBufferDisplayLayer class]]) {
        writeLog(@"[DISPLAY] AVSampleBufferDisplayLayer flush chamado");
        
        [[DiagnosticCollector sharedInstance] recordDisplayLayerInfo:@{
            @"action": @"flush",
            @"layerClass": NSStringFromClass([self class])
        }];
    }
    
    %orig;
}

// Hook para captureOutput:didOutputMetadataObjects:fromConnection para monitorar metadados
- (void)captureOutput:(AVCaptureOutput *)output didOutputMetadataObjects:(NSArray *)metadataObjects fromConnection:(AVCaptureConnection *)connection {
    if (![self respondsToSelector:@selector(captureOutput:didOutputMetadataObjects:fromConnection:)]) {
        return %orig;
    }
    
    writeLog(@"[METADATA] Recebidos %lu objetos de metadados", (unsigned long)metadataObjects.count);
    
    NSMutableArray *metadataInfo = [NSMutableArray array];
    for (AVMetadataObject *metadata in metadataObjects) {
        [metadataInfo addObject:@{
            @"type": NSStringFromClass([metadata class]),
            @"time": @(CMTimeGetSeconds(metadata.time))
        }];
    }
    
    [[DiagnosticCollector sharedInstance] recordMetadataObjects:@{
        @"count": @(metadataObjects.count),
        @"delegateClass": NSStringFromClass([self class]),
        @"outputClass": NSStringFromClass([output class]),
        @"objects": metadataInfo
    }];
    
    %orig;
}

// Hook para processamento de erro
- (void)captureOutput:(AVCaptureOutput *)output didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (![self respondsToSelector:@selector(captureOutput:didDropSampleBuffer:fromConnection:)]) {
        return %orig;
    }
    
    writeLog(@"[ERROR] Frame descartado detectado");
    
    [[DiagnosticCollector sharedInstance] recordDroppedFrame:@{
        @"delegateClass": NSStringFromClass([self class]),
        @"outputClass": NSStringFromClass([output class])
    }];
    
    %orig;
}

%end

%end // grupo CameraHooks

// Constructor específico deste arquivo
%ctor {
    %init(CameraHooks);
}
