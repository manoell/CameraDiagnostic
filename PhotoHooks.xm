#import "Tweak.h"

// Grupo para hooks relacionados à captura de fotos
%group PhotoHooks

// Hook para AVCapturePhoto para examinar as propriedades das fotos capturadas
%hook AVCapturePhoto

- (CGImageRef)CGImageRepresentation {
    CGImageRef result = %orig;
    
    if (result) {
        size_t width = CGImageGetWidth(result);
        size_t height = CGImageGetHeight(result);
        size_t bitsPerComponent = CGImageGetBitsPerComponent(result);
        size_t bytesPerRow = CGImageGetBytesPerRow(result);
        size_t bitsPerPixel = CGImageGetBitsPerPixel(result);
        
        writeLog(@"[PHOTO] CGImageRepresentation: %zu x %zu, BPC: %zu, BPP: %zu, BPR: %zu",
                width, height, bitsPerComponent, bitsPerPixel, bytesPerRow);
        
        [[DiagnosticCollector sharedInstance] recordPhotoImageInfo:@{
            @"type": @"CGImageRepresentation",
            @"width": @(width),
            @"height": @(height),
            @"bitsPerComponent": @(bitsPerComponent),
            @"bitsPerPixel": @(bitsPerPixel),
            @"bytesPerRow": @(bytesPerRow),
            @"originalMethod": @"CGImageRepresentation"
        }];
    } else {
        writeLog(@"[PHOTO] CGImageRepresentation retornou NULL");
        
        [[DiagnosticCollector sharedInstance] recordPhotoImageInfo:@{
            @"type": @"CGImageRepresentation",
            @"error": @"Retornou NULL",
            @"originalMethod": @"CGImageRepresentation"
        }];
    }
    
    return result;
}

- (CVPixelBufferRef)pixelBuffer {
    CVPixelBufferRef result = %orig;
    
    if (result) {
        size_t width = CVPixelBufferGetWidth(result);
        size_t height = CVPixelBufferGetHeight(result);
        OSType pixelFormat = CVPixelBufferGetPixelFormatType(result);
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(result);
        
        // Converter formato para string legível
        char formatString[5] = {0};
        formatString[0] = (char)((pixelFormat >> 24) & 0xFF);
        formatString[1] = (char)((pixelFormat >> 16) & 0xFF);
        formatString[2] = (char)((pixelFormat >> 8) & 0xFF);
        formatString[3] = (char)(pixelFormat & 0xFF);
        
        writeLog(@"[PHOTO] pixelBuffer: %zu x %zu, Formato: %s, BPR: %zu",
                width, height, formatString, bytesPerRow);
        
        [[DiagnosticCollector sharedInstance] recordPhotoImageInfo:@{
            @"type": @"pixelBuffer",
            @"width": @(width),
            @"height": @(height),
            @"pixelFormat": @(pixelFormat),
            @"pixelFormatString": [NSString stringWithUTF8String:formatString],
            @"bytesPerRow": @(bytesPerRow),
            @"originalMethod": @"pixelBuffer"
        }];
    } else {
        writeLog(@"[PHOTO] pixelBuffer retornou NULL");
        
        [[DiagnosticCollector sharedInstance] recordPhotoImageInfo:@{
            @"type": @"pixelBuffer",
            @"error": @"Retornou NULL",
            @"originalMethod": @"pixelBuffer"
        }];
    }
    
    return result;
}

- (NSData *)fileDataRepresentation {
    NSData *result = %orig;
    
    if (result) {
        writeLog(@"[PHOTO] fileDataRepresentation: %zu bytes", result.length);
        
        // Detectar tipo de imagem analisando os primeiros bytes
        NSString *format = @"desconhecido";
        if (result.length > 4) {
            const unsigned char *bytes = (const unsigned char *)result.bytes;
            if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
                format = @"JPEG";
            } else if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
                format = @"PNG";
            } else if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
                format = @"GIF";
            } else if (bytes[0] == 0x48 && bytes[1] == 0x45 && bytes[2] == 0x49 && bytes[3] == 0x43) {
                format = @"HEIC";
            }
        }
        
        NSMutableDictionary *imageInfo = [NSMutableDictionary dictionary];
        imageInfo[@"type"] = @"fileDataRepresentation";
        imageInfo[@"size"] = @(result.length);
        imageInfo[@"format"] = format;
        imageInfo[@"originalMethod"] = @"fileDataRepresentation";
        
        [[DiagnosticCollector sharedInstance] recordPhotoImageInfo:imageInfo];
        
        // Não é necessário examinar todo o conteúdo, apenas os metadados importantes
        // Se o formato for JPEG, podemos tentar extrair informações EXIF
        if ([format isEqualToString:@"JPEG"]) {
            // Métodos para analisar os metadados JPEG
            NSMutableDictionary *exifInfo = [NSMutableDictionary dictionary];
            
            const unsigned char *bytes = (const unsigned char *)result.bytes;
            NSUInteger length = result.length;
            
            BOOL hasExif = NO;
            BOOL hasXMP = NO;
            BOOL hasJFIF = NO;
            BOOL hasICCProfile = NO;
            
            for (NSUInteger i = 0; i < length - 4; i++) {
                // EXIF marker (APP1): FF E1 xx xx 45 78 69 66 (Exif)
                if (bytes[i] == 0xFF && bytes[i+1] == 0xE1 &&
                    i+6 < length && bytes[i+4] == 0x45 && bytes[i+5] == 0x78 &&
                    bytes[i+6] == 0x69 && bytes[i+7] == 0x66) {
                    hasExif = YES;
                }
                
                // XMP marker (APP1): FF E1 xx xx 68 74 74 70 (http)
                else if (bytes[i] == 0xFF && bytes[i+1] == 0xE1 &&
                        i+6 < length && bytes[i+4] == 0x68 && bytes[i+5] == 0x74 &&
                        bytes[i+6] == 0x74 && bytes[i+7] == 0x70) {
                    hasXMP = YES;
                }
                
                // JFIF marker (APP0): FF E0 xx xx 4A 46 49 46 (JFIF)
                else if (bytes[i] == 0xFF && bytes[i+1] == 0xE0 &&
                        i+6 < length && bytes[i+4] == 0x4A && bytes[i+5] == 0x46 &&
                        bytes[i+6] == 0x49 && bytes[i+7] == 0x46) {
                    hasJFIF = YES;
                }
                
                // ICC_PROFILE marker (APP2): FF E2 xx xx 49 43 43 5F (ICC_)
                else if (bytes[i] == 0xFF && bytes[i+1] == 0xE2 &&
                        i+6 < length && bytes[i+4] == 0x49 && bytes[i+5] == 0x43 &&
                        bytes[i+6] == 0x43 && bytes[i+7] == 0x5F) {
                    hasICCProfile = YES;
                }
                
                // Se encontramos todos os tipos de marcadores, podemos parar
                if (hasExif && hasXMP && hasJFIF && hasICCProfile) {
                    break;
                }
            }
            
            exifInfo[@"hasEXIF"] = @(hasExif);
            exifInfo[@"hasXMP"] = @(hasXMP);
            exifInfo[@"hasJFIF"] = @(hasJFIF);
            exifInfo[@"hasICCProfile"] = @(hasICCProfile);
            
            [[DiagnosticCollector sharedInstance] recordPhotoMetadata:exifInfo];
        }
    } else {
        writeLog(@"[PHOTO] fileDataRepresentation retornou NULL");
        
        [[DiagnosticCollector sharedInstance] recordPhotoImageInfo:@{
            @"type": @"fileDataRepresentation",
            @"error": @"Retornou NULL",
            @"originalMethod": @"fileDataRepresentation"
        }];
    }
    
    return result;
}

- (NSData *)fileDataRepresentationWithCustomizer:(id)customizer {
    NSData *result = %orig;
    
    if (result) {
        writeLog(@"[PHOTO] fileDataRepresentationWithCustomizer: %zu bytes", result.length);
        
        // Verificar se temos um customizador
        NSString *customizerClass = customizer ? NSStringFromClass([customizer class]) : @"nil";
        
        [[DiagnosticCollector sharedInstance] recordPhotoImageInfo:@{
            @"type": @"fileDataRepresentationWithCustomizer",
            @"size": @(result.length),
            @"customizerClass": customizerClass,
            @"originalMethod": @"fileDataRepresentationWithCustomizer"
        }];
    } else {
        writeLog(@"[PHOTO] fileDataRepresentationWithCustomizer retornou NULL");
        
        [[DiagnosticCollector sharedInstance] recordPhotoImageInfo:@{
            @"type": @"fileDataRepresentationWithCustomizer",
            @"error": @"Retornou NULL",
            @"originalMethod": @"fileDataRepresentationWithCustomizer"
        }];
    }
    
    return result;
}

// Hook para previewPhotoPixelBuffer para interceptar a miniatura
- (CVPixelBufferRef)previewPixelBuffer {
    CVPixelBufferRef result = %orig;
    
    if (result) {
        size_t width = CVPixelBufferGetWidth(result);
        size_t height = CVPixelBufferGetHeight(result);
        OSType pixelFormat = CVPixelBufferGetPixelFormatType(result);
        
        // Converter formato para string legível
        char formatString[5] = {0};
        formatString[0] = (char)((pixelFormat >> 24) & 0xFF);
        formatString[1] = (char)((pixelFormat >> 16) & 0xFF);
        formatString[2] = (char)((pixelFormat >> 8) & 0xFF);
        formatString[3] = (char)(pixelFormat & 0xFF);
        
        writeLog(@"[PHOTO] previewPixelBuffer: %zu x %zu, Formato: %s",
                width, height, formatString);
        
        [[DiagnosticCollector sharedInstance] recordPhotoImageInfo:@{
            @"type": @"previewPixelBuffer",
            @"width": @(width),
            @"height": @(height),
            @"pixelFormat": @(pixelFormat),
            @"pixelFormatString": [NSString stringWithUTF8String:formatString],
            @"isPreview": @YES,
            @"originalMethod": @"previewPixelBuffer"
        }];
    } else {
        writeLog(@"[PHOTO] previewPixelBuffer retornou NULL");
        
        [[DiagnosticCollector sharedInstance] recordPhotoImageInfo:@{
            @"type": @"previewPixelBuffer",
            @"error": @"Retornou NULL",
            @"originalMethod": @"previewPixelBuffer"
        }];
    }
    
    return result;
}

// Implementação para iOS 11+
- (NSDictionary *)metadata {
    NSDictionary *result = %orig;
    
    if (result) {
        writeLog(@"[PHOTO] metadata: %lu chaves", (unsigned long)result.count);
        
        // Extrair algumas chaves importantes mas omitir dados muito grandes
        NSMutableDictionary *filteredMetadata = [NSMutableDictionary dictionary];
        
        // Lista de chaves de metadados relevantes para extrair
        NSArray *relevantKeys = @[
            @"{Exif}", @"{TIFF}", @"{GPS}", @"Orientation",
            @"PixelWidth", @"PixelHeight", @"ColorModel",
            @"DPIWidth", @"DPIHeight", @"Depth"
        ];
        
        for (NSString *key in relevantKeys) {
            if (result[key]) {
                // Para dicionários aninhados, preservar apenas a existência
                if ([result[key] isKindOfClass:[NSDictionary class]]) {
                    filteredMetadata[key] = @{@"present": @YES, @"keyCount": @(((NSDictionary *)result[key]).count)};
                } else {
                    filteredMetadata[key] = result[key];
                }
            }
        }
        
        // Adicionar informações sobre tamanho e chaves existentes
        filteredMetadata[@"allKeys"] = result.allKeys;
        
        [[DiagnosticCollector sharedInstance] recordPhotoMetadata:filteredMetadata];
    } else {
        writeLog(@"[PHOTO] metadata retornou NULL");
        
        [[DiagnosticCollector sharedInstance] recordPhotoMetadata:@{
            @"error": @"Retornou NULL"
        }];
    }
    
    return result;
}

%end

// Hook para UIImagePickerController para entender quando as capturas ocorrem
%hook UIImagePickerController

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary<NSString *, id> *)info {
    writeLog(@"[PHOTO] didFinishPickingMediaWithInfo chamado");
    
    // Extrair informações relevantes sobre a mídia selecionada
    NSMutableDictionary *mediaInfo = [NSMutableDictionary dictionary];
    
    for (NSString *key in info) {
        // Registrar os tipos de dados, mas não os valores completos
        id value = info[key];
        if ([value isKindOfClass:[UIImage class]]) {
            UIImage *image = (UIImage *)value;
            mediaInfo[key] = [NSString stringWithFormat:@"UIImage: %.0f x %.0f", image.size.width, image.size.height];
        } else if ([value isKindOfClass:[NSURL class]]) {
            mediaInfo[key] = [NSString stringWithFormat:@"NSURL: %@", [(NSURL *)value lastPathComponent]];
        } else if ([value isKindOfClass:[NSData class]]) {
            mediaInfo[key] = [NSString stringWithFormat:@"NSData: %lu bytes", (unsigned long)[(NSData *)value length]];
        } else {
            mediaInfo[key] = NSStringFromClass([value class]);
        }
    }
    
    [[DiagnosticCollector sharedInstance] recordImagePickerInfo:mediaInfo];
    
    %orig;
}

%end

// Hook para UIImage para compreender como as imagens são geradas
%hook UIImage

+ (UIImage *)imageWithCGImage:(CGImageRef)cgImage scale:(CGFloat)scale orientation:(UIImageOrientation)orientation {
    UIImage *result = %orig;
    
    // Registrar apenas um subconjunto de chamadas para evitar sobrecarga
    static int callCount = 0;
    if (++callCount % 20 == 0 && cgImage) {
        writeLog(@"[IMAGE] imageWithCGImage - scale: %.2f, orientation: %d, size: %zu x %zu",
                scale, (int)orientation, CGImageGetWidth(cgImage), CGImageGetHeight(cgImage));
        
        NSString *orientationName;
        switch (orientation) {
            case UIImageOrientationUp: orientationName = @"Up"; break;
            case UIImageOrientationDown: orientationName = @"Down"; break;
            case UIImageOrientationLeft: orientationName = @"Left"; break;
            case UIImageOrientationRight: orientationName = @"Right"; break;
            case UIImageOrientationUpMirrored: orientationName = @"UpMirrored"; break;
            case UIImageOrientationDownMirrored: orientationName = @"DownMirrored"; break;
            case UIImageOrientationLeftMirrored: orientationName = @"LeftMirrored"; break;
            case UIImageOrientationRightMirrored: orientationName = @"RightMirrored"; break;
            default: orientationName = @"Unknown"; break;
        }
        
        // Coletar informações sobre o CGImage
        size_t width = CGImageGetWidth(cgImage);
        size_t height = CGImageGetHeight(cgImage);
        size_t bitsPerComponent = CGImageGetBitsPerComponent(cgImage);
        size_t bitsPerPixel = CGImageGetBitsPerPixel(cgImage);
        CGColorSpaceRef colorSpace = CGImageGetColorSpace(cgImage);
        
        NSString *colorSpaceModel = @"Unknown";
        if (colorSpace) {
            CGColorSpaceModel model = CGColorSpaceGetModel(colorSpace);
            switch (model) {
                case kCGColorSpaceModelRGB: colorSpaceModel = @"RGB"; break;
                case kCGColorSpaceModelCMYK: colorSpaceModel = @"CMYK"; break;
                case kCGColorSpaceModelMonochrome: colorSpaceModel = @"Monochrome"; break;
                case kCGColorSpaceModelLab: colorSpaceModel = @"Lab"; break;
                case kCGColorSpaceModelPattern: colorSpaceModel = @"Pattern"; break;
                case kCGColorSpaceModelIndexed: colorSpaceModel = @"Indexed"; break;
                default: colorSpaceModel = [NSString stringWithFormat:@"Other(%d)", (int)model]; break;
            }
        }
        
        [[DiagnosticCollector sharedInstance] recordUIImageCreation:@{
            @"method": @"imageWithCGImage",
            @"scale": @(scale),
            @"orientation": @(orientation),
            @"orientationName": orientationName,
            @"width": @(width),
            @"height": @(height),
            @"bitsPerComponent": @(bitsPerComponent),
            @"bitsPerPixel": @(bitsPerPixel),
            @"colorSpaceModel": colorSpaceModel,
            @"hasAlpha": @(CGImageGetAlphaInfo(cgImage) != kCGImageAlphaNone),
            @"resultClass": NSStringFromClass([result class])
        }];
    }
    
    return result;
}

+ (UIImage *)imageWithData:(NSData *)data {
    UIImage *result = %orig;
    
    // Registrar apenas um subconjunto de chamadas para evitar sobrecarga
    static int callCount = 0;
    if (++callCount % 20 == 0 && data.length > 0) {
        writeLog(@"[IMAGE] imageWithData - size: %zu bytes", data.length);
        
        // Detectar formato da imagem
        NSString *format = @"Desconhecido";
        if (data.length > 4) {
            const unsigned char *bytes = (const unsigned char *)data.bytes;
            if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
                format = @"JPEG";
            } else if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
                format = @"PNG";
            } else if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
                format = @"GIF";
            } else if (bytes[0] == 0x48 && bytes[1] == 0x45 && bytes[2] == 0x49 && bytes[3] == 0x43) {
                format = @"HEIC";
            }
        }
        
        // Registrar informações sobre a imagem resultante
        NSMutableDictionary *imageInfo = [NSMutableDictionary dictionary];
        imageInfo[@"method"] = @"imageWithData";
        imageInfo[@"dataSize"] = @(data.length);
        imageInfo[@"format"] = format;
        
        if (result) {
            imageInfo[@"resultWidth"] = @(result.size.width);
            imageInfo[@"resultHeight"] = @(result.size.height);
            imageInfo[@"resultScale"] = @(result.scale);
            imageInfo[@"resultOrientation"] = @(result.imageOrientation);
        } else {
            imageInfo[@"error"] = @"Failed to create image";
        }
        
        [[DiagnosticCollector sharedInstance] recordUIImageCreation:imageInfo];
    }
    
    return result;
}

+ (UIImage *)imageWithContentsOfFile:(NSString *)path {
    UIImage *result = %orig;
    
    // Registrar apenas um subconjunto de chamadas para evitar sobrecarga
    static int callCount = 0;
    if (++callCount % 10 == 0) {
        writeLog(@"[IMAGE] imageWithContentsOfFile - path: %@", [path lastPathComponent]);
        
        NSMutableDictionary *imageInfo = [NSMutableDictionary dictionary];
        imageInfo[@"method"] = @"imageWithContentsOfFile";
        imageInfo[@"filename"] = [path lastPathComponent] ?: @"unknown";
        
        if (result) {
            imageInfo[@"resultWidth"] = @(result.size.width);
            imageInfo[@"resultHeight"] = @(result.size.height);
            imageInfo[@"resultScale"] = @(result.scale);
            imageInfo[@"resultOrientation"] = @(result.imageOrientation);
        } else {
            imageInfo[@"error"] = @"Failed to create image";
        }
        
        [[DiagnosticCollector sharedInstance] recordUIImageCreation:imageInfo];
    }
    
    return result;
}

// Hook para imageWithCIImage para entender as conversões
+ (UIImage *)imageWithCIImage:(CIImage *)ciImage {
    UIImage *result = %orig;
    
    if (ciImage) {
        // Extrair tamanho da imagem
        CGRect extent = ciImage.extent;
        
        writeLog(@"[IMAGE] imageWithCIImage - size: %.0f x %.0f",
                extent.size.width, extent.size.height);
        
        NSMutableDictionary *imageInfo = [NSMutableDictionary dictionary];
        imageInfo[@"method"] = @"imageWithCIImage";
        imageInfo[@"ciImageWidth"] = @(extent.size.width);
        imageInfo[@"ciImageHeight"] = @(extent.size.height);
        
        if (result) {
            imageInfo[@"resultWidth"] = @(result.size.width);
            imageInfo[@"resultHeight"] = @(result.size.height);
            imageInfo[@"resultScale"] = @(result.scale);
        } else {
            imageInfo[@"error"] = @"Failed to create image";
        }
        
        [[DiagnosticCollector sharedInstance] recordUIImageCreation:imageInfo];
    }
    
    return result;
}

// Hook para imageWithCIImage:scale:orientation para entender como a orientação e escala afetam a imagem
+ (UIImage *)imageWithCIImage:(CIImage *)ciImage scale:(CGFloat)scale orientation:(UIImageOrientation)orientation {
    UIImage *result = %orig;
    
    if (ciImage) {
        // Extrair tamanho da imagem
        CGRect extent = ciImage.extent;
        
        writeLog(@"[IMAGE] imageWithCIImage:scale:orientation - size: %.0f x %.0f, scale: %.2f, orientation: %d",
                extent.size.width, extent.size.height, scale, (int)orientation);
        
        NSString *orientationName;
        switch (orientation) {
            case UIImageOrientationUp: orientationName = @"Up"; break;
            case UIImageOrientationDown: orientationName = @"Down"; break;
            case UIImageOrientationLeft: orientationName = @"Left"; break;
            case UIImageOrientationRight: orientationName = @"Right"; break;
            case UIImageOrientationUpMirrored: orientationName = @"UpMirrored"; break;
            case UIImageOrientationDownMirrored: orientationName = @"DownMirrored"; break;
            case UIImageOrientationLeftMirrored: orientationName = @"LeftMirrored"; break;
            case UIImageOrientationRightMirrored: orientationName = @"RightMirrored"; break;
            default: orientationName = @"Unknown"; break;
        }
        
        NSMutableDictionary *imageInfo = [NSMutableDictionary dictionary];
        imageInfo[@"method"] = @"imageWithCIImage:scale:orientation";
        imageInfo[@"ciImageWidth"] = @(extent.size.width);
        imageInfo[@"ciImageHeight"] = @(extent.size.height);
        imageInfo[@"scale"] = @(scale);
        imageInfo[@"orientation"] = @(orientation);
        imageInfo[@"orientationName"] = orientationName;
        
        if (result) {
            imageInfo[@"resultWidth"] = @(result.size.width);
            imageInfo[@"resultHeight"] = @(result.size.height);
            imageInfo[@"resultScale"] = @(result.scale);
        } else {
            imageInfo[@"error"] = @"Failed to create image";
        }
        
        [[DiagnosticCollector sharedInstance] recordUIImageCreation:imageInfo];
    }
    
    return result;
}

%end

%end // grupo PhotoHooks

// Constructor específico deste arquivo
%ctor {
    %init(PhotoHooks);
}
