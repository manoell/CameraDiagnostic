#import "../DiagnosticTweak.h"

// Grupo para hooks relacionados à câmera
%group DeviceHooks

// Hook para AVCaptureDevice para obter características da câmera
%hook AVCaptureDevice

// Hook para obter dispositivo padrão
+ (AVCaptureDevice *)defaultDeviceWithMediaType:(NSString *)mediaType {
    AVCaptureDevice *device = %orig;
    
    if ([mediaType isEqualToString:AVMediaTypeVideo] && device) {
        // Obter a resolução real da câmera
        AVCaptureDeviceFormat *format = device.activeFormat;
        if (format) {
            CMFormatDescriptionRef formatDescription = format.formatDescription;
            if (formatDescription) {
                CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
                
                // Extrair características detalhadas do formato
                NSMutableDictionary *formatDetails = [NSMutableDictionary dictionary];
                formatDetails[@"width"] = @(dimensions.width);
                formatDetails[@"height"] = @(dimensions.height);
                
                // Obter metadados de formato
                NSDictionary *formatInfo = [MetadataExtractor videoFormatInfoFromDescription:formatDescription];
                if (formatInfo) {
                    [formatDetails addEntriesFromDictionary:formatInfo];
                }
                
                // Adicionar mais informações
                formatDetails[@"fieldOfView"] = @(format.videoFieldOfView);
                formatDetails[@"isVideoHDRSupported"] = @(format.isVideoHDRSupported);
                formatDetails[@"maxISO"] = @(device.activeFormat.maxISO);
                formatDetails[@"minISO"] = @(device.activeFormat.minISO);
                
                // Obter range de frame rate
                CMTimeRange frameRateRange = format.videoSupportedFrameRateRanges.firstObject.minFrameDuration;
                if (frameRateRange.duration.timescale > 0) {
                    double minFrameRate = 1.0 / CMTimeGetSeconds(frameRateRange.duration);
                    formatDetails[@"minFrameRate"] = @(minFrameRate);
                }
                
                frameRateRange = format.videoSupportedFrameRateRanges.firstObject.maxFrameDuration;
                if (frameRateRange.duration.timescale > 0) {
                    double maxFrameRate = 1.0 / CMTimeGetSeconds(frameRateRange.duration);
                    formatDetails[@"maxFrameRate"] = @(maxFrameRate);
                }
                
                // Determinar se é câmera frontal ou traseira
                BOOL isFrontCamera = (device.position == AVCaptureDevicePositionFront);
                g_usingFrontCamera = isFrontCamera;
                
                // Salvar resolução
                CGSize resolution = CGSizeMake(dimensions.width, dimensions.height);
                if (isFrontCamera) {
                    g_frontCameraResolution = resolution;
                    logSessionInfo(@"frontCameraResolution", NSStringFromCGSize(resolution));
                } else {
                    g_backCameraResolution = resolution;
                    logSessionInfo(@"backCameraResolution", NSStringFromCGSize(resolution));
                }
                
                g_cameraResolution = resolution;
                
                // Log detalhado
                formatDetails[@"position"] = isFrontCamera ? @"front" : @"back";
                formatDetails[@"deviceType"] = device.localizedName ?: @"unknown";
                formatDetails[@"uniqueID"] = device.uniqueID ?: @"unknown";
                
                logJSON(formatDetails, LogCategoryDevice, [NSString stringWithFormat:@"Características da câmera %@", isFrontCamera ? @"frontal" : @"traseira"]);
            }
        }
    }
    
    return device;
}

// Método para detectar a posição da câmera
- (void)_setPosition:(int)position {
    %orig;
    
    // 1 = traseira, 2 = frontal
    BOOL isFrontCamera = (position == 2);
    g_usingFrontCamera = isFrontCamera;
    
    // Atualizar a resolução atual com base na câmera em uso
    g_cameraResolution = isFrontCamera ? g_frontCameraResolution : g_backCameraResolution;
    
    logJSON(@{
        @"cameraPosition": @(position),
        @"isFrontCamera": @(isFrontCamera),
        @"resolution": NSStringFromCGSize(g_cameraResolution)
    }, LogCategoryDevice, @"Mudança de câmera detectada");
}

// Monitorar mudanças de formato ativo
- (void)setActiveFormat:(AVCaptureDeviceFormat *)format {
    %orig;
    
    if (!format) return;
    
    CMFormatDescriptionRef formatDescription = format.formatDescription;
    if (formatDescription) {
        // Extrair informações detalhadas do formato
        NSDictionary *formatInfo = [MetadataExtractor videoFormatInfoFromDescription:formatDescription];
        if (formatInfo) {
            logJSON(formatInfo, LogCategoryFormat, @"Formato ativo alterado");
        }
    }
}

// Monitorar configurações de exposição
- (void)setExposureMode:(AVCaptureExposureMode)exposureMode {
    %orig;
    
    logJSON(@{
        @"exposureMode": @(exposureMode),
        @"exposureModeString": [self stringForExposureMode:exposureMode]
    }, LogCategoryDevice, @"Configuração de exposição alterada");
}

// Monitorar configurações de foco
- (void)setFocusMode:(AVCaptureFocusMode)focusMode {
    %orig;
    
    logJSON(@{
        @"focusMode": @(focusMode),
        @"focusModeString": [self stringForFocusMode:focusMode]
    }, LogCategoryDevice, @"Configuração de foco alterada");
}

// Monitorar configurações de balanço de branco
- (void)setWhiteBalanceMode:(AVCaptureWhiteBalanceMode)whiteBalanceMode {
    %orig;
    
    logJSON(@{
        @"whiteBalanceMode": @(whiteBalanceMode),
        @"whiteBalanceModeString": [self stringForWhiteBalanceMode:whiteBalanceMode]
    }, LogCategoryDevice, @"Configuração de balanço de branco alterada");
}

// Monitorar configurações de flash
- (void)setFlashMode:(AVCaptureFlashMode)flashMode {
    %orig;
    
    logJSON(@{
        @"flashMode": @(flashMode),
        @"flashModeString": [self stringForFlashMode:flashMode]
    }, LogCategoryDevice, @"Configuração de flash alterada");
}

// Monitorar configurações de torchMode (luz auxiliar)
- (void)setTorchMode:(AVCaptureTorchMode)torchMode {
    %orig;
    
    logJSON(@{
        @"torchMode": @(torchMode),
        @"torchModeString": [self stringForTorchMode:torchMode]
    }, LogCategoryDevice, @"Configuração de luz auxiliar alterada");
}

// Métodos auxiliares para obter string descritiva para cada modo
%new
- (NSString *)stringForExposureMode:(AVCaptureExposureMode)mode {
    switch (mode) {
        case AVCaptureExposureModeLocked: return @"Locked";
        case AVCaptureExposureModeAutoExpose: return @"AutoExpose";
        case AVCaptureExposureModeContinuousAutoExposure: return @"ContinuousAutoExposure";
        case AVCaptureExposureModeCustom: return @"Custom";
        default: return @"Unknown";
    }
}

%new
- (NSString *)stringForFocusMode:(AVCaptureFocusMode)mode {
    switch (mode) {
        case AVCaptureFocusModeLocked: return @"Locked";
        case AVCaptureFocusModeAutoFocus: return @"AutoFocus";
        case AVCaptureFocusModeContinuousAutoFocus: return @"ContinuousAutoFocus";
        default: return @"Unknown";
    }
}

%new
- (NSString *)stringForWhiteBalanceMode:(AVCaptureWhiteBalanceMode)mode {
    switch (mode) {
        case AVCaptureWhiteBalanceModeLocked: return @"Locked";
        case AVCaptureWhiteBalanceModeAutoWhiteBalance: return @"AutoWhiteBalance";
        case AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance: return @"ContinuousAutoWhiteBalance";
        default: return @"Unknown";
    }
}

%new
- (NSString *)stringForFlashMode:(AVCaptureFlashMode)mode {
    switch (mode) {
        case AVCaptureFlashModeOff: return @"Off";
        case AVCaptureFlashModeOn: return @"On";
        case AVCaptureFlashModeAuto: return @"Auto";
        default: return @"Unknown";
    }
}

%new
- (NSString *)stringForTorchMode:(AVCaptureTorchMode)mode {
    switch (mode) {
        case AVCaptureTorchModeOff: return @"Off";
        case AVCaptureTorchModeOn: return @"On";
        case AVCaptureTorchModeAuto: return @"Auto";
        default: return @"Unknown";
    }
}

%end

%end // grupo DeviceHooks

// Constructor específico deste arquivo
%ctor {
    %init(DeviceHooks);
}