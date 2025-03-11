#import "../DiagnosticTweak.h"

// Grupo para hooks relacionados à saída de vídeo
%group VideoOutputHooks

// Hook para AVCaptureVideoDataOutput
%hook AVCaptureVideoDataOutput

// Monitorar configuração de delegate para output de vídeo
- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    %orig;
    
    if (sampleBufferDelegate) {
        // Registrar classe do delegate
        NSString *delegateClass = NSStringFromClass([sampleBufferDelegate class]);
        
        logJSONWithDescription(@{
            @"delegateClass": delegateClass ?: @"unknown",
            @"hasQueue": sampleBufferCallbackQueue ? @YES : @NO,
            @"timestamp": [NSDate date].description
        }, LogCategoryVideo, @"Video data output delegate configurado");
        
        // Registrar classe do delegate na sessão
        logSessionInfo(@"videoOutputDelegateClass", delegateClass);
    }
}

// Verificar configurações de qualidade de vídeo
- (void)setVideoSettings:(NSDictionary<NSString *,id> *)videoSettings {
    %orig;
    
    if (videoSettings) {
        // Extrair informações do dicionário de configurações
        NSMutableDictionary *settingsInfo = [NSMutableDictionary dictionary];
        
        // Dimensões
        if (videoSettings[(id)kCVPixelBufferWidthKey]) {
            settingsInfo[@"width"] = videoSettings[(id)kCVPixelBufferWidthKey];
        }
        
        if (videoSettings[(id)kCVPixelBufferHeightKey]) {
            settingsInfo[@"height"] = videoSettings[(id)kCVPixelBufferHeightKey];
        }
        
        // Formato de pixel
        id pixelFormatObj = videoSettings[(id)kCVPixelBufferPixelFormatTypeKey];
        if (pixelFormatObj) {
            uint32_t pixelFormat = [pixelFormatObj unsignedIntValue];
            char formatStr[5] = {0};
            formatStr[0] = (pixelFormat >> 24) & 0xFF;
            formatStr[1] = (pixelFormat >> 16) & 0xFF;
            formatStr[2] = (pixelFormat >> 8) & 0xFF;
            formatStr[3] = pixelFormat & 0xFF;
            
            settingsInfo[@"pixelFormat"] = @(pixelFormat);
            settingsInfo[@"pixelFormatString"] = [NSString stringWithCString:formatStr encoding:NSASCIIStringEncoding];
        }
        
        // Outras configurações
        for (NSString *key in videoSettings) {
            if (![key isEqual:(id)kCVPixelBufferWidthKey] &&
                ![key isEqual:(id)kCVPixelBufferHeightKey] &&
                ![key isEqual:(id)kCVPixelBufferPixelFormatTypeKey]) {
                settingsInfo[key] = videoSettings[key];
            }
        }
        
        logJSONWithDescription(settingsInfo, LogCategoryVideo, @"Configurações de saída de vídeo definidas");
        
        // Registrar na sessão
        if (settingsInfo[@"width"] && settingsInfo[@"height"]) {
            NSString *resolution = [NSString stringWithFormat:@"%@x%@",
                                   settingsInfo[@"width"], settingsInfo[@"height"]];
            logSessionInfo(@"videoOutputResolution", resolution);
        }
        
        if (settingsInfo[@"pixelFormatString"]) {
            logSessionInfo(@"videoOutputPixelFormat", settingsInfo[@"pixelFormatString"]);
        }
    }
}

%end

// Hook para AVCaptureAudioDataOutput
%hook AVCaptureAudioDataOutput

// Monitorar configuração de delegate para output de áudio
- (void)setSampleBufferDelegate:(id<AVCaptureAudioDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    %orig;
    
    if (sampleBufferDelegate) {
        // Registrar classe do delegate
        NSString *delegateClass = NSStringFromClass([sampleBufferDelegate class]);
        
        logJSONWithDescription(@{
            @"delegateClass": delegateClass ?: @"unknown",
            @"hasQueue": sampleBufferCallbackQueue ? @YES : @NO,
            @"timestamp": [NSDate date].description
        }, LogCategoryVideo, @"Audio data output delegate configurado");
        
        // Registrar classe do delegate na sessão
        logSessionInfo(@"audioOutputDelegateClass", delegateClass);
    }
}

%end

// Hook para AVCaptureMovieFileOutput
%hook AVCaptureMovieFileOutput

// Monitorar início de gravação
- (void)startRecordingToOutputFileURL:(NSURL *)outputFileURL recordingDelegate:(id<AVCaptureFileOutputRecordingDelegate>)delegate {
    %orig;
    
    g_isRecordingVideo = YES;
    
    logJSONWithDescription(@{
        @"outputFileURL": outputFileURL.absoluteString ?: @"unknown",
        @"delegateClass": NSStringFromClass([delegate class]) ?: @"unknown",
        @"timestamp": [NSDate date].description
    }, LogCategoryVideo, @"Gravação de vídeo iniciada");
    
    // Registrar estado na sessão
    logSessionInfo(@"isRecordingVideo", @YES);
    logSessionInfo(@"videoRecordingStartTime", [NSDate date].description);
}

// Monitorar fim de gravação
- (void)stopRecording {
    %orig;
    
    g_isRecordingVideo = NO;
    
    logJSONWithDescription(@{
        @"timestamp": [NSDate date].description
    }, LogCategoryVideo, @"Gravação de vídeo finalizada");
    
    // Registrar estado na sessão
    logSessionInfo(@"isRecordingVideo", @NO);
    logSessionInfo(@"videoRecordingEndTime", [NSDate date].description);
}

%end

// Hook para captura de frames
%hook NSObject

// Interceptar método de delegate para obter informações sobre os frames
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    // Verificar se somos um delegate de amostra de buffer
    if (![self respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
        %orig;
        return;
    }
    
    static int frameCounter = 0;
    frameCounter++;
    
    // Limitar logging para não sobrecarregar o sistema - apenas log a cada 100 frames
    if (frameCounter % 100 == 0) {
        // Extrair metadados detalhados do buffer de amostra
        NSDictionary *bufferInfo = [MetadataExtractor metadataFromSampleBuffer:sampleBuffer];
        
        // Extrair informações de transformação
        NSDictionary *transformInfo = [MetadataExtractor transformInfoFromVideoConnection:connection];
        
        // Combinar informações
        NSMutableDictionary *frameInfo = [NSMutableDictionary dictionary];
        [frameInfo addEntriesFromDictionary:bufferInfo];
        [frameInfo setObject:transformInfo forKey:@"transform"];
        [frameInfo setObject:@(frameCounter) forKey:@"frameCount"];
        
        // Determinar tipo de output
        NSString *outputType = @"unknown";
        if ([output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
            outputType = @"videoDataOutput";
        } else if ([output isKindOfClass:[AVCaptureAudioDataOutput class]]) {
            outputType = @"audioDataOutput";
        } else if ([output isKindOfClass:[AVCaptureMovieFileOutput class]]) {
            outputType = @"movieFileOutput";
        }
        [frameInfo setObject:outputType forKey:@"outputType"];
        
        // Analisar o pixel buffer e extrair informações
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        if (imageBuffer) {
            NSDictionary *pixelInfo = [MetadataExtractor pixelBufferInfoFromBuffer:imageBuffer];
            [frameInfo setObject:pixelInfo forKey:@"pixelBuffer"];
            
            // Adicionar dimensões do frame à sessão
            logSessionInfo(@"frameWidth", @(CVPixelBufferGetWidth(imageBuffer)));
            logSessionInfo(@"frameHeight", @(CVPixelBufferGetHeight(imageBuffer)));
        }
        
        logJSONWithDescription(frameInfo, LogCategoryVideo, [NSString stringWithFormat:@"Frame #%d capturado", frameCounter]);
    }
    
    %orig;
}

%end

%end // grupo VideoOutputHooks

// Constructor específico deste arquivo
%ctor {
    %init(VideoOutputHooks);
}
