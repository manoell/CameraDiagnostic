#import "../DiagnosticTweak.h"

// Grupo para hooks relacionados à captura de fotos
%group PhotoOutputHooks

// Hook para AVCapturePhotoOutput para iOS 10+
%hook AVCapturePhotoOutput

// Monitorar configurações de captura de foto
- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    logMessage(@"capturePhotoWithSettings:delegate: chamado", LogLevelInfo, LogCategoryPhoto);
    
    // Registrar que estamos capturando uma foto
    g_isCapturingPhoto = YES;
    
    // Extrair informações das configurações de foto
    if (settings) {
        // Usar o auxiliar para obter informações detalhadas
        NSDictionary *photoSettings = [MetadataExtractor photoFormatInfoFromSettings:settings];
        
        // Adicionar informações sobre o delegate
        NSMutableDictionary *captureInfo = [NSMutableDictionary dictionaryWithDictionary:photoSettings];
        captureInfo[@"delegateClass"] = NSStringFromClass([delegate class]) ?: @"unknown";
        captureInfo[@"timestamp"] = [NSDate date].description;
        
        // Registrar informações no log
        logJSON(captureInfo, LogCategoryPhoto, @"Captura de foto iniciada");
        
        // Registrar na sessão de diagnóstico
        logSessionInfo(@"photoCapturing", @YES);
        logSessionInfo(@"photoCaptureStartTime", [NSDate date].description);
        
        // Registrar configurações importantes
        if (photoSettings[@"previewWidth"] && photoSettings[@"previewHeight"]) {
            NSString *previewResolution = [NSString stringWithFormat:@"%@x%@",
                                         photoSettings[@"previewWidth"],
                                         photoSettings[@"previewHeight"]];
            logSessionInfo(@"photoPreviewResolution", previewResolution);
        }
        
        // Verificar formato de pixel
        NSArray *availableFormats = photoSettings[@"availablePreviewFormats"];
        if (availableFormats && [availableFormats count] > 0) {
            logSessionInfo(@"photoAvailableFormats", availableFormats);
        }
    }
    
    %orig;
}

%end

// Hook para AVCapturePhoto para iOS 11+
%hook AVCapturePhoto

- (CGImageRef)CGImageRepresentation {
    CGImageRef originalImage = %orig;
    
    if (g_isCapturingPhoto) {
        // Extrair informações da imagem
        if (originalImage) {
            NSMutableDictionary *imageInfo = [NSMutableDictionary dictionary];
            imageInfo[@"width"] = @(CGImageGetWidth(originalImage));
            imageInfo[@"height"] = @(CGImageGetHeight(originalImage));
            imageInfo[@"bitsPerComponent"] = @(CGImageGetBitsPerComponent(originalImage));
            imageInfo[@"bitsPerPixel"] = @(CGImageGetBitsPerPixel(originalImage));
            imageInfo[@"bytesPerRow"] = @(CGImageGetBytesPerRow(originalImage));
            
            // Registrar informações no log
            logJSON(imageInfo, LogCategoryPhoto, @"CGImageRepresentation chamado para foto");
            
            // Registrar dimensões da foto na sessão
            NSString *photoResolution = [NSString stringWithFormat:@"%@ x %@",
                                      imageInfo[@"width"], imageInfo[@"height"]];
            logSessionInfo(@"photoCaptureResolution", photoResolution);
        }
    }
    
    return originalImage;
}

- (CVPixelBufferRef)pixelBuffer {
    CVPixelBufferRef buffer = %orig;
    
    if (g_isCapturingPhoto && buffer) {
        // Extrair informações do buffer
        NSDictionary *bufferInfo = [MetadataExtractor pixelBufferInfoFromBuffer:buffer];
        
        // Registrar informações no log
        logJSON(bufferInfo, LogCategoryPhoto, @"pixelBuffer chamado para foto");
        
        // Registrar formato de pixel na sessão
        if (bufferInfo[@"pixelFormat"]) {
            logSessionInfo(@"photoCapturePixelFormat", bufferInfo[@"pixelFormat"]);
        }
    }
    
    return buffer;
}

- (NSData *)fileDataRepresentation {
    NSData *fileData = %orig;
    
    if (g_isCapturingPhoto && fileData) {
        // Extrair metadados EXIF da imagem
        NSDictionary *exifInfo = [MetadataExtractor exifMetadataFromData:fileData];
        
        // Registrar tamanho do arquivo
        NSMutableDictionary *fileInfo = [NSMutableDictionary dictionary];
        fileInfo[@"fileSize"] = @(fileData.length);
        fileInfo[@"fileSizeFormatted"] = [NSByteCountFormatter stringFromByteCount:fileData.length 
                                                                        countStyle:NSByteCountFormatterCountStyleFile];
        
        // Adicionar metadados EXIF
        if (exifInfo) {
            fileInfo[@"exifMetadata"] = exifInfo;
        }
        
        // Registrar informações no log
        logJSON(fileInfo, LogCategoryPhoto, @"fileDataRepresentation chamado para foto");
        
        // Registrar tamanho do arquivo na sessão
        logSessionInfo(@"photoCaptureFileSize", fileInfo[@"fileSizeFormatted"]);
        
        // Armazenar metadados para uso posterior
        g_lastPhotoMetadata = exifInfo;
    }
    
    return fileData;
}

- (NSDictionary *)metadata {
    NSDictionary *metadata = %orig;
    
    if (g_isCapturingPhoto && metadata) {
        // Registrar informações no log
        logJSON(metadata, LogCategoryMetadata, @"Metadados de foto capturados");
    }
    
    return metadata;
}

%end

// Hook para AVCapturePhotoCaptureDelegate usando o método @protocol
%hook NSObject

// iOS 10+
- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhotoSampleBuffer:(CMSampleBufferRef)photoSampleBuffer previewPhotoSampleBuffer:(CMSampleBufferRef)previewPhotoSampleBuffer resolvedSettings:(AVCaptureResolvedPhotoSettings *)resolvedSettings bracketSettings:(AVCaptureBracketedStillImageSettings *)bracketSettings error:(NSError *)error {
    // Verificar se somos um delegate de photo capture
    if (![self respondsToSelector:@selector(captureOutput:didFinishProcessingPhotoSampleBuffer:previewPhotoSampleBuffer:resolvedSettings:bracketSettings:error:)]) {
        %orig;
        return;
    }
    
    // Extrair informações do sample buffer
    if (photoSampleBuffer && CMSampleBufferIsValid(photoSampleBuffer)) {
        NSDictionary *bufferInfo = [MetadataExtractor metadataFromSampleBuffer:photoSampleBuffer];
        
        logJSON(bufferInfo, LogCategoryPhoto, @"Processamento de foto finalizado (iOS 10)");
    }
    
    // Verificar se houve erro
    if (error) {
        logJSON(@{
            @"code": @(error.code),
            @"domain": error.domain ?: @"unknown",
            @"description": error.localizedDescription ?: @"unknown",
            @"timestamp": [NSDate date].description
        }, LogCategoryPhoto, @"Erro na captura de foto");
    }
    
    // Registrar finalização da captura
    g_isCapturingPhoto = NO;
    logSessionInfo(@"photoCapturing", @NO);
    logSessionInfo(@"photoCaptureEndTime", [NSDate date].description);
    
    %orig;
}

// iOS 11+
- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(NSError *)error {
    // Verificar se somos um delegate de photo capture
    if (![self respondsToSelector:@selector(captureOutput:didFinishProcessingPhoto:error:)]) {
        %orig;
        return;
    }
    
    // Extrair informações da foto
    if (photo) {
        NSDictionary *photoInfo = [MetadataExtractor metadataFromCapturePhoto:photo];
        
        logJSON(photoInfo, LogCategoryPhoto, @"Processamento de foto finalizado (iOS 11+)");
        
        // Verificar se temos informações de dimensões
        if (photoInfo[@"width"] && photoInfo[@"height"]) {
            NSString *resolution = [NSString stringWithFormat:@"%@ x %@", 
                                   photoInfo[@"width"], photoInfo[@"height"]];
            logSessionInfo(@"photoFinalResolution", resolution);
        }
    }
    
    // Verificar se houve erro
    if (error) {
        logJSON(@{
            @"code": @(error.code),
            @"domain": error.domain ?: @"unknown",
            @"description": error.localizedDescription ?: @"unknown",
            @"timestamp": [NSDate date].description
        }, LogCategoryPhoto, @"Erro na captura de foto");
    }
    
    // Registrar finalização da captura
    g_isCapturingPhoto = NO;
    logSessionInfo(@"photoCapturing", @NO);
    logSessionInfo(@"photoCaptureEndTime", [NSDate date].description);
    
    %orig;
}

%end

%end // grupo PhotoOutputHooks

// Constructor específico deste arquivo
%ctor {
    %init(PhotoOutputHooks);
}