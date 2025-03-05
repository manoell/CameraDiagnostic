#import "BufferContentInspector.h"
#import "logger.h"

@implementation BufferContentInspector {
    NSMutableArray *_capturedBufferInfo;
    NSUInteger _bufferCounter;
    dispatch_queue_t _processingQueue;
    NSMutableDictionary *_bufferFingerprints;  // Para detectar padrões recorrentes
    NSMutableDictionary *_patternStats;        // Estatísticas de padrões
}

+ (instancetype)sharedInstance {
    static BufferContentInspector *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _captureEnabled = YES;
        _analyzeContent = YES;
        _captureInterval = 300; // Valor aumentado para reduzir volume de amostras
        _maxCapturedSamples = 50;
        _capturedBufferInfo = [NSMutableArray array];
        _bufferFingerprints = [NSMutableDictionary dictionary];
        _patternStats = [NSMutableDictionary dictionary];
        _bufferCounter = 0;
        _processingQueue = dispatch_queue_create("com.camera.buffer.inspection", DISPATCH_QUEUE_SERIAL);
        
        // Configurar diretório de saída
        NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        _outputDirectory = [documentsPath stringByAppendingPathComponent:@"BufferSamples"];
        
        // Criar diretório se não existir
        if (![[NSFileManager defaultManager] fileExistsAtPath:_outputDirectory]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:_outputDirectory
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:nil];
        }
        
        LOG_INFO(@"BufferContentInspector inicializado. Diretório de amostras: %@", _outputDirectory);
    }
    return self;
}

#pragma mark - Captura de Amostras

- (void)captureSampleFromBuffer:(CMSampleBufferRef)sampleBuffer withContext:(NSString *)context {
    if (!_captureEnabled || !sampleBuffer) return;
    
    _bufferCounter++;
    
    // Verificar se deve capturar esta amostra
    if (_bufferCounter % _captureInterval != 0) return;
    
    // Verificar se já atingiu o limite de amostras
    if (_capturedBufferInfo.count >= _maxCapturedSamples) return;
    
    // Processar em fila assíncrona para não bloquear o fluxo principal
    dispatch_async(_processingQueue, ^{
        // Capturar informações básicas do buffer
        NSMutableDictionary *bufferInfo = [NSMutableDictionary dictionary];
        
        // ID e timestamp
        NSString *timestamp = [NSString stringWithFormat:@"%lld", (long long)([[NSDate date] timeIntervalSince1970] * 1000)];
        NSString *sampleID = [NSString stringWithFormat:@"sample_%llu_%@", (unsigned long long)self->_bufferCounter, timestamp];
        bufferInfo[@"sampleID"] = sampleID;
        bufferInfo[@"timestamp"] = timestamp;
        bufferInfo[@"context"] = context ?: @"unknown";
        
        // Informações do aplicativo
        bufferInfo[@"app"] = [[NSBundle mainBundle] bundleIdentifier];
        
        // Formato e dimensões
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        if (imageBuffer) {
            size_t width = CVPixelBufferGetWidth(imageBuffer);
            size_t height = CVPixelBufferGetHeight(imageBuffer);
            OSType pixelFormat = CVPixelBufferGetPixelFormatType(imageBuffer);
            
            bufferInfo[@"width"] = @(width);
            bufferInfo[@"height"] = @(height);
            bufferInfo[@"pixelFormat"] = @(pixelFormat);
            
            char formatStr[5] = {0};
            formatStr[0] = (pixelFormat >> 24) & 0xFF;
            formatStr[1] = (pixelFormat >> 16) & 0xFF;
            formatStr[2] = (pixelFormat >> 8) & 0xFF;
            formatStr[3] = pixelFormat & 0xFF;
            bufferInfo[@"formatString"] = [NSString stringWithUTF8String:formatStr];
            
            // CRÍTICO: Verificar se tem IOSurface associada
            IOSurfaceRef surface = CVPixelBufferGetIOSurface(imageBuffer);
            if (surface) {
                uint32_t surfaceID = IOSurfaceGetID(surface);
                bufferInfo[@"hasIOSurface"] = @YES;
                bufferInfo[@"IOSurfaceID"] = @(surfaceID);
                
                LOG_INFO(@"🔍 Buffer com IOSurface detectado! ID: %u, Contexto: %@", surfaceID, context);
                
                // Verificar propriedades da IOSurface - CRUCIAL para análise
                NSDictionary *surfaceProps = (__bridge_transfer NSDictionary *)IOSurfaceCopyAllValues(surface);
                if (surfaceProps) {
                    bufferInfo[@"IOSurfaceProperties"] = surfaceProps;
                    
                    // Destacar propriedades relevantes da IOSurface
                    for (NSString *key in surfaceProps) {
                        if ([key containsString:@"Camera"] ||
                            [key containsString:@"Video"] ||
                            [key containsString:@"Capture"]) {
                            LOG_INFO(@"⭐️ Propriedade IOSurface relevante: %@=%@", key, surfaceProps[key]);
                        }
                    }
                }
            } else {
                bufferInfo[@"hasIOSurface"] = @NO;
            }
            
            // Extrair uma imagem do buffer (frequência reduzida)
            if (_bufferCounter % (_captureInterval * 3) == 0) {
                NSString *imagePath = [self saveImageFromBuffer:imageBuffer withID:sampleID];
                if (imagePath) {
                    bufferInfo[@"imagePath"] = imagePath;
                }
            }
            
            // Analisar conteúdo se habilitado
            if (_analyzeContent) {
                NSDictionary *contentAnalysis = [self analyzeBufferContent:sampleBuffer];
                if (contentAnalysis) {
                    bufferInfo[@"analysis"] = contentAnalysis;
                    
                    // Verificar se é potencialmente de câmera real
                    if ([contentAnalysis[@"isSyntheticContent"] boolValue] == NO &&
                        [contentAnalysis[@"syntheticContentLikelihood"] floatValue] < 0.3) {
                        LOG_INFO(@"🎯 Buffer parece ser de câmera real! Contexto: %@", context);
                    }
                }
            }
            
            // Verificar se o buffer tem algum fingerprint conhecido
            NSString *fingerprint = [self generateFingerprintForBuffer:imageBuffer];
            if (fingerprint) {
                bufferInfo[@"fingerprint"] = fingerprint;
                
                // Registrar estatísticas do padrão
                NSNumber *count = _patternStats[fingerprint];
                if (!count) count = @0;
                _patternStats[fingerprint] = @([count integerValue] + 1);
                
                // Verificar se este padrão já foi visto anteriormente
                NSString *existingContext = _bufferFingerprints[fingerprint];
                if (existingContext) {
                    bufferInfo[@"patternMatchedWith"] = existingContext;
                    
                    if (![existingContext isEqualToString:context]) {
                        LOG_INFO(@"⚠️ Padrão recorrente detectado entre '%@' e '%@' - Possível pipeline compartilhado!",
                                existingContext, context);
                    }
                } else {
                    _bufferFingerprints[fingerprint] = context;
                }
            }
        }
        
        // Salvar metadados em JSON
        NSString *metadataPath = [self->_outputDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_metadata.json", sampleID]];
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:bufferInfo options:NSJSONWritingPretty error:nil];
        [jsonData writeToFile:metadataPath atomically:YES];
        
        // Adicionar ao array de informações capturadas
        [self->_capturedBufferInfo addObject:bufferInfo];
        self->_samplesSaved++;
        
        LOG_INFO(@"📸 Capturada amostra de buffer: %@", sampleID);
    });
}

- (NSString *)generateFingerprintForBuffer:(CVImageBufferRef)imageBuffer {
    if (!imageBuffer) return nil;
    
    // Criamos um fingerprint simplificado baseado em algumas características-chave do buffer
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    OSType format = CVPixelBufferGetPixelFormatType(imageBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    
    // Verificar se tem IOSurface
    IOSurfaceRef surface = CVPixelBufferGetIOSurface(imageBuffer);
    uint32_t surfaceID = 0;
    if (surface) {
        surfaceID = IOSurfaceGetID(surface);
    }
    
    // Simplificado: Apenas características básicas estruturais
    return [NSString stringWithFormat:@"%zux%zu-%u-%zu-%u",
            width, height, format, bytesPerRow, surfaceID];
}

- (NSString *)saveImageFromBuffer:(CVImageBufferRef)imageBuffer withID:(NSString *)sampleID {
    if (!imageBuffer) return nil;
    
    @try {
        // Verificar o formato e converter para UIImage
        OSType pixelFormat = CVPixelBufferGetPixelFormatType(imageBuffer);
        size_t width = CVPixelBufferGetWidth(imageBuffer);
        size_t height = CVPixelBufferGetHeight(imageBuffer);
        
        // Caminho do arquivo
        NSString *imagePath = [_outputDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.png", sampleID]];
        
        // Lock do buffer para acesso
        CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
        
        UIImage *image = nil;
        
        // Processar com base no formato
        if (pixelFormat == kCVPixelFormatType_32BGRA ||
            pixelFormat == kCVPixelFormatType_32RGBA) {
            
            CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
            uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer);
            size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
            
            CGBitmapInfo bitmapInfo;
            if (pixelFormat == kCVPixelFormatType_32BGRA) {
                bitmapInfo = kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst;
            } else { // 32RGBA
                bitmapInfo = kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast;
            }
            
            CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8, bytesPerRow, colorSpace, bitmapInfo);
            
            if (context) {
                CGImageRef cgImage = CGBitmapContextCreateImage(context);
                if (cgImage) {
                    image = [UIImage imageWithCGImage:cgImage];
                    CGImageRelease(cgImage);
                }
                CGContextRelease(context);
            }
            CGColorSpaceRelease(colorSpace);
        }
        // Formatos YUV
        else if (pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
                 pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            
            // Criar um CIImage do buffer
            CIImage *ciImage = [CIImage imageWithCVPixelBuffer:imageBuffer];
            
            // Converter para UIImage via contexto
            CIContext *context = [CIContext contextWithOptions:nil];
            CGImageRef cgImage = [context createCGImage:ciImage fromRect:CGRectMake(0, 0, width, height)];
            
            if (cgImage) {
                image = [UIImage imageWithCGImage:cgImage];
                CGImageRelease(cgImage);
            }
        }
        
        CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
        
        // Salvar a imagem como PNG
        if (image) {
            NSData *pngData = UIImagePNGRepresentation(image);
            [pngData writeToFile:imagePath atomically:YES];
            return imagePath;
        }
        
    } @catch (NSException *exception) {
        LOG_ERROR(@"Erro ao converter buffer para imagem: %@", exception);
    }
    
    return nil;
}

#pragma mark - Análise de Conteúdo

- (NSDictionary *)analyzeBufferContent:(CMSampleBufferRef)sampleBuffer {
    if (!sampleBuffer) return nil;
    
    NSMutableDictionary *analysis = [NSMutableDictionary dictionary];
    _samplesAnalyzed++;
    
    @try {
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        if (!imageBuffer) return nil;
        
        // Bloqueio para acesso
        CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
        
        // 1. Calcular média e desvio padrão de luminosidade
        float avgBrightness = 0.0f;
        float stdDevBrightness = 0.0f;
        [self calculateBrightnessStats:imageBuffer average:&avgBrightness stdDev:&stdDevBrightness];
        
        analysis[@"avgBrightness"] = @(avgBrightness);
        analysis[@"stdDevBrightness"] = @(stdDevBrightness);
        
        // 2. Detecção de características visuais básicas
        NSDictionary *visualFeatures = [self extractVisualFeatures:sampleBuffer];
        if (visualFeatures) {
            [analysis addEntriesFromDictionary:visualFeatures];
        }
        
        // 3. Verificar se parece conteúdo sintético
        CGFloat confidence = 0.0f;
        BOOL isSynthetic = [self isLikelySyntheticContent:sampleBuffer confidence:&confidence];
        analysis[@"syntheticContentLikelihood"] = @(confidence);
        analysis[@"isSyntheticContent"] = @(isSynthetic);
        
        // 4. CRÍTICO: Verificar metadados específicos de câmera
        CFDictionaryRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, false);
        if (attachments && CFArrayGetCount(attachments) > 0) {
            CFDictionaryRef attachmentDict = (CFDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
            if (attachmentDict) {
                NSDictionary *attachs = (__bridge NSDictionary *)attachmentDict;
                
                // Verificar atributos específicos de câmera
                NSMutableDictionary *cameraAttachments = [NSMutableDictionary dictionary];
                for (NSString *key in attachs) {
                    if ([key containsString:@"Camera"] ||
                        [key containsString:@"Video"] ||
                        [key containsString:@"Capture"] ||
                        [key containsString:@"Source"]) {
                        
                        cameraAttachments[key] = attachs[key];
                        LOG_INFO(@"🔍 Attachment relevante detectado: %@ = %@", key, attachs[key]);
                    }
                }
                
                if (cameraAttachments.count > 0) {
                    analysis[@"cameraMetadata"] = cameraAttachments;
                }
            }
        }
        
        // 5. Verificar formato e descrição
        CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
        if (formatDesc) {
            // Obter extensões do formato
            CFDictionaryRef extensions = CMFormatDescriptionGetExtensions(formatDesc);
            if (extensions) {
                NSDictionary *extDict = (__bridge NSDictionary *)extensions;
                
                // Filtrar extensões relevantes
                NSMutableDictionary *relevantExtensions = [NSMutableDictionary dictionary];
                for (NSString *key in extDict) {
                    if ([key containsString:@"Camera"] ||
                        [key containsString:@"Video"] ||
                        [key containsString:@"Codec"] ||
                        [key containsString:@"Surface"]) {
                        
                        relevantExtensions[key] = extDict[key];
                        LOG_INFO(@"🔍 Extensão de formato relevante: %@ = %@", key, extDict[key]);
                    }
                }
                
                if (relevantExtensions.count > 0) {
                    analysis[@"formatExtensions"] = relevantExtensions;
                }
            }
            
            // Obter tipo de mídia
            CMMediaType mediaType = CMFormatDescriptionGetMediaType(formatDesc);
            FourCharCode mediaSubType = CMFormatDescriptionGetMediaSubType(formatDesc);
            
            char mediaTypeStr[5] = {0};
            mediaTypeStr[0] = (mediaType >> 24) & 0xFF;
            mediaTypeStr[1] = (mediaType >> 16) & 0xFF;
            mediaTypeStr[2] = (mediaType >> 8) & 0xFF;
            mediaTypeStr[3] = mediaType & 0xFF;
            
            char mediaSubTypeStr[5] = {0};
            mediaSubTypeStr[0] = (mediaSubType >> 24) & 0xFF;
            mediaSubTypeStr[1] = (mediaSubType >> 16) & 0xFF;
            mediaSubTypeStr[2] = (mediaSubType >> 8) & 0xFF;
            mediaSubTypeStr[3] = mediaSubType & 0xFF;
            
            analysis[@"mediaType"] = [NSString stringWithUTF8String:mediaTypeStr];
            analysis[@"mediaSubType"] = [NSString stringWithUTF8String:mediaSubTypeStr];
        }
        
        // Desbloquear buffer
        CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
        
    } @catch (NSException *exception) {
        LOG_ERROR(@"Erro na análise do buffer: %@", exception);
    }
    
    return analysis;
}

- (void)calculateBrightnessStats:(CVImageBufferRef)imageBuffer average:(float *)avgOut stdDev:(float *)stdDevOut {
    // Simplificação: somente BGRA para este exemplo
    OSType pixelFormat = CVPixelBufferGetPixelFormatType(imageBuffer);
    if (pixelFormat != kCVPixelFormatType_32BGRA) {
        *avgOut = 0.0f;
        *stdDevOut = 0.0f;
        return;
    }
    
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer);
    
    // Amostragem mais esparsa para performance
    const size_t sampleStride = 32; // Análise mais esparsa
    size_t sampleCount = 0;
    double sum = 0.0;
    double sumSq = 0.0;
    
    for (size_t y = 0; y < height; y += sampleStride) {
        for (size_t x = 0; x < width; x += sampleStride) {
            if (y >= height || x >= width) continue;
            
            size_t pixelOffset = y * bytesPerRow + x * 4;
            uint8_t b = baseAddress[pixelOffset];
            uint8_t g = baseAddress[pixelOffset + 1];
            uint8_t r = baseAddress[pixelOffset + 2];
            
            // Fórmula ponderada para luminosidade
            double luma = 0.299 * r + 0.587 * g + 0.114 * b;
            
            sum += luma;
            sumSq += luma * luma;
            sampleCount++;
        }
    }
    
    if (sampleCount > 0) {
        double mean = sum / sampleCount;
        double variance = (sumSq / sampleCount) - (mean * mean);
        variance = MAX(0.0, variance);
        
        *avgOut = (float)mean / 255.0f;
        *stdDevOut = (float)sqrt(variance) / 255.0f;
    } else {
        *avgOut = 0.0f;
        *stdDevOut = 0.0f;
    }
}

- (BOOL)isLikelySyntheticContent:(CMSampleBufferRef)sampleBuffer confidence:(CGFloat *)confidenceOut {
    // Esta é uma implementação simplificada para detectar se um frame
    // parece ser conteúdo sintético, como uma imagem estática
    
    // Inicializar output
    if (confidenceOut) *confidenceOut = 0.0f;
    
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!imageBuffer) return NO;
    
    // Fatores que contribuem para a confiança
    CGFloat stdDevWeight = 0.5f;  // Desvio padrão baixo = mais uniforme = mais sintético
    CGFloat edgeWeight = 0.3f;    // Poucas bordas = mais sintético
    CGFloat noiseWeight = 0.2f;   // Pouco ruído = mais sintético
    
    // 1. Calcular uniformidade (baixo desvio padrão)
    float avgBrightness = 0.0f;
    float stdDevBrightness = 0.0f;
    [self calculateBrightnessStats:imageBuffer average:&avgBrightness stdDev:&stdDevBrightness];
    
    // Quanto menor o desvio padrão, mais uniforme (mais sintético)
    CGFloat uniformityScore = 1.0f - MIN(1.0f, stdDevBrightness * 5.0f);
    
    // 2. Detecção básica de bordas
    NSDictionary *features = [self extractVisualFeatures:sampleBuffer];
    CGFloat edgeScore = 0.0f;
    CGFloat noiseScore = 0.0f;
    
    if (features) {
        NSNumber *edgeDensity = features[@"edgeDensity"];
        if (edgeDensity) {
            // Baixa densidade de bordas = mais sintético
            edgeScore = 1.0f - MIN(1.0f, [edgeDensity floatValue] * 10.0f);
        }
        
        NSNumber *noiseLevel = features[@"noiseLevel"];
        if (noiseLevel) {
            // Baixo nível de ruído = mais sintético
            noiseScore = 1.0f - MIN(1.0f, [noiseLevel floatValue] * 5.0f);
        }
    }
    
    // Calcular confiança combinada
    CGFloat confidence = (uniformityScore * stdDevWeight) +
                         (edgeScore * edgeWeight) +
                         (noiseScore * noiseWeight);
    
    if (confidenceOut) *confidenceOut = confidence;
    
    return confidence > 0.7f;
}

- (NSDictionary *)extractVisualFeatures:(CMSampleBufferRef)sampleBuffer {
    // Versão simplificada focada apenas em características essenciais
    NSMutableDictionary *features = [NSMutableDictionary dictionary];
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!imageBuffer) return nil;
    
    OSType pixelFormat = CVPixelBufferGetPixelFormatType(imageBuffer);
    if (pixelFormat != kCVPixelFormatType_32BGRA) {
        // Simplificando - apenas um formato suportado
        return nil;
    }
    
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer);
    
    // Verificações básicas
    if (width < 16 || height < 16) return nil;
    
    // Amostragem para histograma e características mais esparsa
    const size_t sampleStride = 16;
    
    // 1. Detecção simplificada de bordas e ruído
    int edgeCount = 0;
    float noiseSum = 0.0f;
    
    for (size_t y = sampleStride; y < height - sampleStride; y += sampleStride) {
        for (size_t x = sampleStride; x < width - sampleStride; x += sampleStride) {
            size_t pixelOffset = y * bytesPerRow + x * 4;
            
            // Detecção simples de bordas (diferenças com pixels vizinhos)
            size_t leftOffset = y * bytesPerRow + (x - sampleStride) * 4;
            size_t rightOffset = y * bytesPerRow + (x + sampleStride) * 4;
            size_t topOffset = (y - sampleStride) * bytesPerRow + x * 4;
            size_t bottomOffset = (y + sampleStride) * bytesPerRow + x * 4;
            
            // Calcular gradientes horizontais e verticais
            int gradientH = abs((int)baseAddress[leftOffset + 2] - (int)baseAddress[rightOffset + 2]) +
                           abs((int)baseAddress[leftOffset + 1] - (int)baseAddress[rightOffset + 1]) +
                           abs((int)baseAddress[leftOffset] - (int)baseAddress[rightOffset]);
            
            int gradientV = abs((int)baseAddress[topOffset + 2] - (int)baseAddress[bottomOffset + 2]) +
                           abs((int)baseAddress[topOffset + 1] - (int)baseAddress[bottomOffset + 1]) +
                           abs((int)baseAddress[topOffset] - (int)baseAddress[bottomOffset]);
            
            // Limiar para considerar uma borda
            int gradient = gradientH + gradientV;
            if (gradient > 100) { // Limiar ajustado
                edgeCount++;
            }
            
            // Estimativa de ruído (variação local)
            noiseSum += gradient / 6.0f; // Média das diferenças absolutas
        }
    }
    
    // Normalizar contagem de bordas pelo tamanho da imagem
    float edgeDensity = (float)edgeCount / ((width * height) / (sampleStride * sampleStride));
    features[@"edgeDensity"] = @(edgeDensity);
    
    // Normalizar estimativa de ruído
    float noiseLevel = noiseSum / ((width * height) / (sampleStride * sampleStride)) / 255.0f;
    features[@"noiseLevel"] = @(noiseLevel);
    
    return features;
}

- (CGFloat)compareBuffer:(CMSampleBufferRef)buffer1 withBuffer:(CMSampleBufferRef)buffer2 {
    if (!buffer1 || !buffer2) return 1.0; // Diferentes se algum é NULL
    
    CVImageBufferRef imageBuffer1 = CMSampleBufferGetImageBuffer(buffer1);
    CVImageBufferRef imageBuffer2 = CMSampleBufferGetImageBuffer(buffer2);
    
    if (!imageBuffer1 || !imageBuffer2) return 1.0;
    
    // Verificar dimensões
    size_t width1 = CVPixelBufferGetWidth(imageBuffer1);
    size_t height1 = CVPixelBufferGetHeight(imageBuffer1);
    size_t width2 = CVPixelBufferGetWidth(imageBuffer2);
    size_t height2 = CVPixelBufferGetHeight(imageBuffer2);
    
    if (width1 != width2 || height1 != height2) return 1.0; // Dimensões diferentes
    
    // Verificar formato
    OSType format1 = CVPixelBufferGetPixelFormatType(imageBuffer1);
    OSType format2 = CVPixelBufferGetPixelFormatType(imageBuffer2);
    
    if (format1 != format2) return 1.0; // Formatos diferentes
    
    // Simplificação: suportar apenas BGRA
    if (format1 != kCVPixelFormatType_32BGRA) return 1.0;
    
    // Bloquear buffers
    CVPixelBufferLockBaseAddress(imageBuffer1, kCVPixelBufferLock_ReadOnly);
    CVPixelBufferLockBaseAddress(imageBuffer2, kCVPixelBufferLock_ReadOnly);
    
    uint8_t *baseAddress1 = (uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer1);
    uint8_t *baseAddress2 = (uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer2);
    size_t bytesPerRow1 = CVPixelBufferGetBytesPerRow(imageBuffer1);
    size_t bytesPerRow2 = CVPixelBufferGetBytesPerRow(imageBuffer2);
    
    // Diferença média
    double totalDiff = 0.0;
    int sampleCount = 0;
    
    // Amostragem para comparação (stride aumentado)
    const size_t sampleStride = 16;
    
    for (size_t y = 0; y < height1; y += sampleStride) {
        for (size_t x = 0; x < width1; x += sampleStride) {
            size_t offset1 = y * bytesPerRow1 + x * 4;
            size_t offset2 = y * bytesPerRow2 + x * 4;
            
            // Diferença por canal
            int diffB = abs((int)baseAddress1[offset1] - (int)baseAddress2[offset2]);
            int diffG = abs((int)baseAddress1[offset1 + 1] - (int)baseAddress2[offset2 + 1]);
            int diffR = abs((int)baseAddress1[offset1 + 2] - (int)baseAddress2[offset2 + 2]);
            
            // Diferença média normalizada para este pixel
            double pixelDiff = (diffR + diffG + diffB) / (3.0 * 255.0);
            totalDiff += pixelDiff;
            sampleCount++;
        }
    }
    
    // Desbloquear buffers
    CVPixelBufferUnlockBaseAddress(imageBuffer1, kCVPixelBufferLock_ReadOnly);
    CVPixelBufferUnlockBaseAddress(imageBuffer2, kCVPixelBufferLock_ReadOnly);
    
    // Calcular diferença média normalizada
    double avgDiff = sampleCount > 0 ? totalDiff / sampleCount : 1.0;
    
    return (CGFloat)avgDiff;
}

- (NSDictionary *)detectContentPatterns:(CMSampleBufferRef)sampleBuffer {
    // Detectar padrões específicos no conteúdo (implementação simplificada)
    NSMutableDictionary *patterns = [NSMutableDictionary dictionary];
    
    // Simplificação: usar apenas informações já calculadas
    CGFloat confidence = 0.0f;
    BOOL isSynthetic = [self isLikelySyntheticContent:sampleBuffer confidence:&confidence];
    
    patterns[@"likelySynthetic"] = @(isSynthetic);
    patterns[@"syntheticConfidence"] = @(confidence);
    
    // Extrair características
    NSDictionary *features = [self extractVisualFeatures:sampleBuffer];
    if (features) {
        NSNumber *edgeDensity = features[@"edgeDensity"];
        if (edgeDensity && [edgeDensity floatValue] < 0.01) {
            patterns[@"likelyBlankScreen"] = @YES;
        } else if (edgeDensity && [edgeDensity floatValue] > 0.2) {
            patterns[@"likelyHighDetail"] = @YES;
        }
    }
    
    return patterns;
}

- (NSString *)generateReport {
    NSMutableString *report = [NSMutableString string];
    
    [report appendString:@"===== RELATÓRIO DE INSPEÇÃO DE BUFFER =====\n\n"];
    [report appendFormat:@"Amostras analisadas: %lu\n", (unsigned long)_samplesAnalyzed];
    [report appendFormat:@"Amostras salvas: %lu\n", (unsigned long)_samplesSaved];
    [report appendFormat:@"Diretório de amostras: %@\n\n", _outputDirectory];
    
    // Padrões detectados
    [report appendString:@"=== PADRÕES DE BUFFER DETECTADOS ===\n"];
    NSArray *sortedPatterns = [_patternStats keysSortedByValueUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        return [obj2 compare:obj1]; // Ordem decrescente
    }];
    
    for (NSString *pattern in sortedPatterns) {
        NSNumber *count = _patternStats[pattern];
        NSString *context = _bufferFingerprints[pattern];
        [report appendFormat:@"Padrão: %@ - Ocorrências: %@, Contexto: %@\n",
             pattern, count, context];
    }
    
    // Estatísticas por aplicativo
    NSMutableDictionary *statsByApp = [NSMutableDictionary dictionary];
    
    for (NSDictionary *sample in _capturedBufferInfo) {
        NSString *app = sample[@"app"];
        if (!app) continue;
        
        NSMutableDictionary *appStats = statsByApp[app];
        if (!appStats) {
            appStats = [NSMutableDictionary dictionary];
            appStats[@"count"] = @0;
            appStats[@"syntheticCount"] = @0;
            appStats[@"iosurfaceCount"] = @0;
            statsByApp[app] = appStats;
        }
        
        NSNumber *count = appStats[@"count"];
        appStats[@"count"] = @([count integerValue] + 1);
        
        // Verificar se sintético
        NSDictionary *analysis = sample[@"analysis"];
        if (analysis && [analysis[@"isSyntheticContent"] boolValue]) {
            NSNumber *syntheticCount = appStats[@"syntheticCount"];
            appStats[@"syntheticCount"] = @([syntheticCount integerValue] + 1);
        }
        
        // Verificar IOSurface
        if ([sample[@"hasIOSurface"] boolValue]) {
            NSNumber *ioSurfaceCount = appStats[@"iosurfaceCount"];
            appStats[@"iosurfaceCount"] = @([ioSurfaceCount integerValue] + 1);
        }
    }
    
    [report appendString:@"\nEstatísticas por aplicativo:\n"];
    for (NSString *app in statsByApp) {
        NSDictionary *appStats = statsByApp[app];
        NSInteger count = [appStats[@"count"] integerValue];
        NSInteger syntheticCount = [appStats[@"syntheticCount"] integerValue];
        NSInteger ioSurfaceCount = [appStats[@"iosurfaceCount"] integerValue];
        
        [report appendFormat:@"- %@: %ld amostras\n", app, (long)count];
        [report appendFormat:@"  - %.1f%% sintéticas\n", (count > 0 ? (float)syntheticCount / count * 100 : 0)];
        [report appendFormat:@"  - %.1f%% com IOSurface\n", (count > 0 ? (float)ioSurfaceCount / count * 100 : 0)];
    }
    
    // CRÍTICO: Identificar pontos prováveis para substituição
    [report appendString:@"\n=== PONTOS POTENCIAIS PARA SUBSTITUIÇÃO ===\n"];
    
    // Buffers com IOSurface são candidatos principais
    NSMutableArray *ioSurfaceSamples = [NSMutableArray array];
    for (NSDictionary *sample in _capturedBufferInfo) {
        if ([sample[@"hasIOSurface"] boolValue]) {
            [ioSurfaceSamples addObject:sample];
        }
    }
    
    if (ioSurfaceSamples.count > 0) {
        [report appendFormat:@"Detectados %lu buffers com IOSurface:\n", (unsigned long)ioSurfaceSamples.count];
        
        // Agrupar por ID de IOSurface
        NSMutableDictionary *surfaceGroups = [NSMutableDictionary dictionary];
        for (NSDictionary *sample in ioSurfaceSamples) {
            NSNumber *surfaceID = sample[@"IOSurfaceID"];
            if (!surfaceID) continue;
            
            NSMutableArray *group = surfaceGroups[surfaceID];
            if (!group) {
                group = [NSMutableArray array];
                surfaceGroups[surfaceID] = group;
            }
            [group addObject:sample];
        }
        
        // Listar IOSurfaces compartilhadas (mais interessantes)
        for (NSNumber *surfaceID in surfaceGroups) {
            NSArray *group = surfaceGroups[surfaceID];
            if (group.count > 1) {
                [report appendFormat:@"- IOSurface %@: %lu referências\n", surfaceID, (unsigned long)group.count];
                
                NSMutableSet *contexts = [NSMutableSet set];
                for (NSDictionary *sample in group) {
                    [contexts addObject:sample[@"context"]];
                }
                
                [report appendFormat:@"  Contextos: %@\n", contexts];
                
                // Esta é uma IOSurface compartilhada - PONTO CRÍTICO para substituição universal
                [report appendFormat:@"  ⭐️ PONTO CRÍTICO PARA SUBSTITUIÇÃO UNIVERSAL ⭐️\n"];
            }
        }
    }
    
    [report appendString:@"\n==== FIM DO RELATÓRIO ====\n"];
    
    return report;
}

@end
