#import "MetadataExtractor.h"
#import <ImageIO/ImageIO.h>

// Funções auxiliares para converter tipos de dados específicos
static NSString *FourCCToString(FourCharCode code) {
    char string[5] = {0};
    string[0] = (code >> 24) & 0xFF;
    string[1] = (code >> 16) & 0xFF;
    string[2] = (code >> 8) & 0xFF;
    string[3] = code & 0xFF;
    return [NSString stringWithCString:string encoding:NSASCIIStringEncoding];
}

@implementation MetadataExtractor

#pragma mark - Sample Buffer Metadata

+ (NSDictionary *)metadataFromSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if (!sampleBuffer || !CMSampleBufferIsValid(sampleBuffer)) {
        return @{@"error": @"Invalid sample buffer"};
    }
    
    NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
    
    // Informações básicas do buffer
    CMTime presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    CMTime duration = CMSampleBufferGetDuration(sampleBuffer);
    
    metadata[@"presentationTime"] = @(CMTimeGetSeconds(presentationTime));
    metadata[@"duration"] = @(CMTimeGetSeconds(duration));
    metadata[@"numSamples"] = @(CMSampleBufferGetNumSamples(sampleBuffer));
    
    // Informações do formato
    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
    if (formatDescription) {
        [metadata addEntriesFromDictionary:[self videoFormatInfoFromDescription:formatDescription]];
    }
    
    return metadata;
}

#pragma mark - Capture Photo Metadata

+ (NSDictionary *)metadataFromCapturePhoto:(AVCapturePhoto *)photo {
    if (!photo) {
        return @{@"error": @"Invalid capture photo"};
    }
    
    NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
    
    // Informações de dimensões
    CGImageRef cgImage = [photo CGImageRepresentation];
    if (cgImage) {
        metadata[@"width"] = @(CGImageGetWidth(cgImage));
        metadata[@"height"] = @(CGImageGetHeight(cgImage));
        metadata[@"bitsPerComponent"] = @(CGImageGetBitsPerComponent(cgImage));
        metadata[@"bitsPerPixel"] = @(CGImageGetBitsPerPixel(cgImage));
        metadata[@"bytesPerRow"] = @(CGImageGetBytesPerRow(cgImage));
    }
    
    // Formato de arquivo
    if ([photo fileDataRepresentation]) {
        metadata[@"fileFormat"] = @"JPEG";
        metadata[@"fileSize"] = @([photo fileDataRepresentation].length);
    }
    
    return metadata;
}

#pragma mark - Helper Methods

+ (NSString *)stringForColorSpace:(CGColorSpaceRef)colorSpace {
    if (!colorSpace) return @"Unknown";
    
    CGColorSpaceModel model = CGColorSpaceGetModel(colorSpace);
    switch (model) {
        case kCGColorSpaceModelUnknown: return @"Unknown";
        case kCGColorSpaceModelMonochrome: return @"Monochrome";
        case kCGColorSpaceModelRGB: return @"RGB";
        case kCGColorSpaceModelCMYK: return @"CMYK";
        case kCGColorSpaceModelLab: return @"Lab";
        case kCGColorSpaceModelDeviceN: return @"DeviceN";
        case kCGColorSpaceModelIndexed: return @"Indexed";
        case kCGColorSpaceModelPattern: return @"Pattern";
        default: return [NSString stringWithFormat:@"Other (%ld)", (long)model];
    }
}

#pragma mark - EXIF Metadata

+ (NSDictionary *)exifMetadataFromData:(NSData *)imageData {
    if (!imageData || imageData.length == 0) {
        return @{@"error": @"Invalid image data"};
    }
    
    CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)imageData, NULL);
    if (!imageSource) {
        return @{@"error": @"Could not create image source"};
    }
    
    NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
    
    // Obter metadados da imagem
    CFDictionaryRef imageProperties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL);
    if (imageProperties) {
        NSDictionary *props = (__bridge_transfer NSDictionary *)imageProperties;
        
        // EXIF
        NSDictionary *exif = props[(NSString *)kCGImagePropertyExifDictionary];
        if (exif) {
            metadata[@"exif"] = exif;
        }
        
        // GPS
        NSDictionary *gps = props[(NSString *)kCGImagePropertyGPSDictionary];
        if (gps) {
            metadata[@"gps"] = gps;
        }
        
        // Outras propriedades básicas
        NSNumber *width = props[(NSString *)kCGImagePropertyPixelWidth];
        if (width) {
            metadata[@"width"] = width;
        }
        
        NSNumber *height = props[(NSString *)kCGImagePropertyPixelHeight];
        if (height) {
            metadata[@"height"] = height;
        }
    }
    
    CFRelease(imageSource);
    return metadata;
}

#pragma mark - Video Format Information

+ (NSDictionary *)videoFormatInfoFromDescription:(CMFormatDescriptionRef)formatDescription {
    if (!formatDescription) {
        return @{@"error": @"Invalid format description"};
    }
    
    NSMutableDictionary *formatInfo = [NSMutableDictionary dictionary];
    
    // Tipo de mídia
    CMMediaType mediaType = CMFormatDescriptionGetMediaType(formatDescription);
    formatInfo[@"mediaType"] = FourCCToString(mediaType);
    
    // Subtipo de mídia
    FourCharCode mediaSubtype = CMFormatDescriptionGetMediaSubType(formatDescription);
    formatInfo[@"mediaSubtype"] = FourCCToString(mediaSubtype);
    
    // Informações específicas de vídeo
    if (mediaType == kCMMediaType_Video) {
        CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
        formatInfo[@"width"] = @(dimensions.width);
        formatInfo[@"height"] = @(dimensions.height);
    }
    // Informações específicas de áudio
    else if (mediaType == kCMMediaType_Audio) {
        const AudioStreamBasicDescription *audioDesc = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription);
        if (audioDesc) {
            formatInfo[@"sampleRate"] = @(audioDesc->mSampleRate);
            formatInfo[@"channelsPerFrame"] = @(audioDesc->mChannelsPerFrame);
        }
    }
    
    return formatInfo;
}

#pragma mark - Photo Format Information

+ (NSDictionary *)photoFormatInfoFromSettings:(AVCapturePhotoSettings *)settings {
    if (!settings) {
        return @{@"error": @"Invalid photo settings"};
    }
    
    NSMutableDictionary *formatInfo = [NSMutableDictionary dictionary];
    
    // Dicionário de formato de preview
    NSDictionary *previewFormat = settings.previewPhotoFormat;
    if (previewFormat) {
        formatInfo[@"previewFormat"] = previewFormat;
        
        // Extrair dimensões se disponíveis
        NSNumber *width = previewFormat[(NSString *)kCVPixelBufferWidthKey] ?: previewFormat[@"Width"];
        NSNumber *height = previewFormat[(NSString *)kCVPixelBufferHeightKey] ?: previewFormat[@"Height"];
        
        if (width && height) {
            formatInfo[@"previewWidth"] = width;
            formatInfo[@"previewHeight"] = height;
        }
    }
    
    // Verificar formatos de pixel disponíveis
    NSArray *availablePreviewFormats = settings.availablePreviewPhotoPixelFormatTypes;
    if (availablePreviewFormats.count > 0) {
        NSMutableArray *formatsArray = [NSMutableArray array];
        for (NSNumber *format in availablePreviewFormats) {
            [formatsArray addObject:FourCCToString([format unsignedIntValue])];
        }
        formatInfo[@"availablePreviewFormats"] = formatsArray;
    }
    
    return formatInfo;
}

#pragma mark - Pixel Buffer Information

+ (NSDictionary *)pixelBufferInfoFromBuffer:(CVPixelBufferRef)pixelBuffer {
    if (!pixelBuffer) {
        return @{@"error": @"Invalid pixel buffer"};
    }
    
    NSMutableDictionary *bufferInfo = [NSMutableDictionary dictionary];
    
    // Dimensões
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    bufferInfo[@"width"] = @(width);
    bufferInfo[@"height"] = @(height);
    
    // Formato de pixel
    OSType pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
    bufferInfo[@"pixelFormat"] = FourCCToString(pixelFormat);
    
    // Outras propriedades
    bufferInfo[@"bytesPerRow"] = @(CVPixelBufferGetBytesPerRow(pixelBuffer));
    bufferInfo[@"dataSize"] = @(CVPixelBufferGetDataSize(pixelBuffer));
    bufferInfo[@"planeCount"] = @(CVPixelBufferGetPlaneCount(pixelBuffer));
    
    return bufferInfo;
}

#pragma mark - Transform Information

+ (NSDictionary *)transformInfoFromVideoConnection:(AVCaptureConnection *)connection {
    if (!connection) {
        return @{@"error": @"Invalid video connection"};
    }
    
    NSMutableDictionary *transformInfo = [NSMutableDictionary dictionary];
    
    // Orientação de vídeo
    transformInfo[@"videoOrientation"] = @(connection.videoOrientation);
    
    // Converter orientação para string legível
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
    transformInfo[@"videoOrientationString"] = orientationString;
    
    // Espelhamento
    transformInfo[@"videoMirrored"] = @(connection.isVideoMirrored);
    
    return transformInfo;
}

@end
