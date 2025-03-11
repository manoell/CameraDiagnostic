#import "../DiagnosticTweak.h"

// Grupo para hooks relacionados à orientação
%group OrientationHooks

// Hook para AVCaptureConnection para monitorar orientação do vídeo
%hook AVCaptureConnection

- (void)setVideoOrientation:(AVCaptureVideoOrientation)videoOrientation {
    %orig;
    
    // Armazenar orientação para uso posterior
    g_videoOrientation = (int)videoOrientation;
    
    // Obter descrição legível da orientação
    NSString *orientationDesc;
    switch ((int)videoOrientation) {
        case AVCaptureVideoOrientationPortrait:
            orientationDesc = @"Portrait";
            break;
        case AVCaptureVideoOrientationPortraitUpsideDown:
            orientationDesc = @"Portrait Upside Down";
            break;
        case AVCaptureVideoOrientationLandscapeRight:
            orientationDesc = @"Landscape Right";
            break;
        case AVCaptureVideoOrientationLandscapeLeft:
            orientationDesc = @"Landscape Left";
            break;
        default:
            orientationDesc = @"Desconhecido";
            break;
    }
    
    // Registrar no log
    logJSONWithDescription(@{
        @"videoOrientation": @(videoOrientation),
        @"orientationDescription": orientationDesc,
        @"timestamp": [NSDate date].description
    }, LogCategoryOrientation, @"Orientação de vídeo configurada");
    
    // Atualizar metadados de sessão
    logSessionInfo(@"videoOrientation", @(videoOrientation));
    logSessionInfo(@"videoOrientationString", orientationDesc);
}

// Hook para monitorar espelhamento de vídeo
- (void)setVideoMirrored:(BOOL)videoMirrored {
    %orig;
    
    logJSONWithDescription(@{
        @"videoMirrored": @(videoMirrored),
        @"timestamp": [NSDate date].description
    }, LogCategoryOrientation, @"Espelhamento de vídeo configurado");
}

// Hook para monitorar estabilização de vídeo
- (void)setPreferredVideoStabilizationMode:(AVCaptureVideoStabilizationMode)preferredVideoStabilizationMode {
    %orig;
    
    // Mapear modo para string legível
    NSString *stabModeString;
    switch (preferredVideoStabilizationMode) {
        case AVCaptureVideoStabilizationModeOff:
            stabModeString = @"Off";
            break;
        case AVCaptureVideoStabilizationModeStandard:
            stabModeString = @"Standard";
            break;
        case AVCaptureVideoStabilizationModeCinematic:
            stabModeString = @"Cinematic";
            break;
        case AVCaptureVideoStabilizationModeAuto:
            stabModeString = @"Auto";
            break;
        default:
            stabModeString = @"Unknown";
            break;
    }
    
    logJSONWithDescription(@{
        @"stabilizationMode": @(preferredVideoStabilizationMode),
        @"stabilizationModeString": stabModeString,
        @"timestamp": [NSDate date].description
    }, LogCategoryOrientation, @"Modo de estabilização configurado");
}

// Monitorar propriedades de transformação
- (void)setVideoTransform:(CGAffineTransform)videoTransform {
    %orig;
    
    // Extrair componentes da matriz de transformação
    logJSONWithDescription(@{
        @"transform": @{
            @"a": @(videoTransform.a),  // escala x
            @"b": @(videoTransform.b),  // cisalhamento y
            @"c": @(videoTransform.c),  // cisalhamento x
            @"d": @(videoTransform.d),  // escala y
            @"tx": @(videoTransform.tx), // translação x
            @"ty": @(videoTransform.ty)  // translação y
        },
        @"timestamp": [NSDate date].description
    }, LogCategoryTransform, @"Transformação de vídeo configurada");
}

%end

// Hook para UIDevice para monitorar orientação do dispositivo
%hook UIDevice

- (void)setOrientation:(UIDeviceOrientation)orientation {
    %orig;
    
    // Mapear orientação para string legível
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
    
    // Verificar se a orientação é válida antes de registrar
    if (orientation != UIDeviceOrientationUnknown) {
        logJSONWithDescription(@{
            @"deviceOrientation": @(orientation),
            @"orientationString": orientationString,
            @"timestamp": [NSDate date].description
        }, LogCategoryOrientation, @"Orientação do dispositivo alterada");
        
        // Atualizar metadados de sessão
        logSessionInfo(@"deviceOrientation", @(orientation));
        logSessionInfo(@"deviceOrientationString", orientationString);
    }
}

%end

// Hook para UIApplication para monitorar orientação da interface
%hook UIApplication

- (void)_setStatusBarOrientation:(UIInterfaceOrientation)orientation animated:(BOOL)animated {
    %orig;
    
    // Mapear orientação para string legível
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
    
    logJSONWithDescription(@{
        @"interfaceOrientation": @(orientation),
        @"orientationString": orientationString,
        @"animated": @(animated),
        @"timestamp": [NSDate date].description
    }, LogCategoryOrientation, @"Orientação da interface alterada");
    
    // Atualizar metadados de sessão
    logSessionInfo(@"interfaceOrientation", @(orientation));
    logSessionInfo(@"interfaceOrientationString", orientationString);
}

%end

%end // grupo OrientationHooks

// Constructor específico deste arquivo
%ctor {
    %init(OrientationHooks);
}
