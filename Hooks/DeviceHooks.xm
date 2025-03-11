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
                AVFrameRateRange *frameRateRange = format.videoSupportedFrameRateRanges.firstObject;
                if (frameRateRange) {
                    formatDetails[@"minFrameRate"] = @(frameRateRange.minFrameRate);
                    formatDetails[@"maxFrameRate"] = @(frameRateRange.maxFrameRate);
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
                
                logJSONWithDescription(formatDetails, LogCategoryDevice, [NSString stringWithFormat:@"Características da câmera %@", isFrontCamera ? @"frontal" : @"traseira"]);
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
    
    logJSONWithDescription(@{
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
            logJSONWithDescription(formatInfo, LogCategoryFormat, @"Formato ativo alterado");
        }
    }
}

// Monitorar configurações de exposição
- (void)setExposureMode:(AVCaptureExposureMode)exposureMode {
    %orig;
    
    NSString *exposureModeString;
    switch (exposureMode) {
        case AVCaptureExposureModeLocked:
            exposureModeString = @"Locked";
            break;
        case AVCaptureExposureModeAutoExpose:
            exposureModeString = @"AutoExpose";
            break;
        case AVCaptureExposureModeContinuousAutoExposure:
            exposureModeString = @"ContinuousAutoExposure";
            break;
        case AVCaptureExposureModeCustom:
            exposureModeString = @"Custom";
            break;
        default:
            exposureModeString = @"Unknown";
            break;
    }
    
    logJSONWithDescription(@{
        @"exposureMode": @(exposureMode),
        @"exposureModeString": exposureModeString
    }, LogCategoryDevice, @"Configuração de exposição alterada");
}

// Monitorar configurações de foco
- (void)setFocusMode:(AVCaptureFocusMode)focusMode {
    %orig;
    
    NSString *focusModeString;
    switch (focusMode) {
        case AVCaptureFocusModeLocked:
            focusModeString = @"Locked";
            break;
        case AVCaptureFocusModeAutoFocus:
            focusModeString = @"AutoFocus";
            break;
        case AVCaptureFocusModeContinuousAutoFocus:
            focusModeString = @"ContinuousAutoFocus";
            break;
        default:
            focusModeString = @"Unknown";
            break;
    }
    
    logJSONWithDescription(@{
        @"focusMode": @(focusMode),
        @"focusModeString": focusModeString
    }, LogCategoryDevice, @"Configuração de foco alterada");
}

// Monitorar configurações de balanço de branco
- (void)setWhiteBalanceMode:(AVCaptureWhiteBalanceMode)whiteBalanceMode {
    %orig;
    
    NSString *whiteBalanceModeString;
    switch (whiteBalanceMode) {
        case AVCaptureWhiteBalanceModeLocked:
            whiteBalanceModeString = @"Locked";
            break;
        case AVCaptureWhiteBalanceModeAutoWhiteBalance:
            whiteBalanceModeString = @"AutoWhiteBalance";
            break;
        case AVCaptureWhiteBalanceModeContinuousAutoWhiteBalance:
            whiteBalanceModeString = @"ContinuousAutoWhiteBalance";
            break;
        default:
            whiteBalanceModeString = @"Unknown";
            break;
    }
    
    logJSONWithDescription(@{
        @"whiteBalanceMode": @(whiteBalanceMode),
        @"whiteBalanceModeString": whiteBalanceModeString
    }, LogCategoryDevice, @"Configuração de balanço de branco alterada");
}

// Monitorar configurações de flash
- (void)setFlashMode:(AVCaptureFlashMode)flashMode {
    %orig;
    
    NSString *flashModeString;
    switch (flashMode) {
        case AVCaptureFlashModeOff:
            flashModeString = @"Off";
            break;
        case AVCaptureFlashModeOn:
            flashModeString = @"On";
            break;
        case AVCaptureFlashModeAuto:
            flashModeString = @"Auto";
            break;
        default:
            flashModeString = @"Unknown";
            break;
    }
    
    logJSONWithDescription(@{
        @"flashMode": @(flashMode),
        @"flashModeString": flashModeString
    }, LogCategoryDevice, @"Configuração de flash alterada");
}

// Monitorar configurações de torchMode (luz auxiliar)
- (void)setTorchMode:(AVCaptureTorchMode)torchMode {
    %orig;
    
    NSString *torchModeString;
    switch (torchMode) {
        case AVCaptureTorchModeOff:
            torchModeString = @"Off";
            break;
        case AVCaptureTorchModeOn:
            torchModeString = @"On";
            break;
        case AVCaptureTorchModeAuto:
            torchModeString = @"Auto";
            break;
        default:
            torchModeString = @"Unknown";
            break;
    }
    
    logJSONWithDescription(@{
        @"torchMode": @(torchMode),
        @"torchModeString": torchModeString
    }, LogCategoryDevice, @"Configuração de luz auxiliar alterada");
}

%end

%end // grupo DeviceHooks

// Constructor específico deste arquivo
%ctor {
    %init(DeviceHooks);
}
