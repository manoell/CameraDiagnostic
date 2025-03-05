// BufferContentInspector.m

#import "BufferContentInspector.h"
#import "logger.h"

@implementation BufferContentInspector {
    NSMutableArray *_capturedBufferInfo;
    NSUInteger _bufferCounter;
    dispatch_queue_t _processingQueue;
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
        _captureInterval = 100; // Capturar 1 a cada 100 frames
        _maxCapturedSamples = 50; // Máximo de amostras para não ocupar muito espaço
        _capturedBufferInfo = [NSMutableArray array];
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
        NSString *sampleID = [NSString stringWithFormat:@"sample_%llu_%@", (unsigned long long)_bufferCounter, timestamp];
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
            
            // Extrair uma imagem do buffer
            NSString *imagePath = [self saveImageFromBuffer:imageBuffer withID:sampleID];
            if (imagePath) {
                bufferInfo[@"imagePath"] = imagePath;
            }
            
            // Analisar conteúdo se habilitado
            if (_analyzeContent) {
                NSDictionary *contentAnalysis = [self analyzeBufferContent:sampleBuffer];
                if (contentAnalysis) {
                    bufferInfo[@"analysis"] = contentAnalysis;
                }
            }
        }
        
        // Salvar metadados em JSON
        NSString *metadataPath = [_outputDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_metadata.json", sampleID]];
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:bufferInfo options:NSJSONWritingPretty error:nil];
        [jsonData writeToFile:metadataPath atomically:YES];
        
        // Adicionar ao array de informações capturadas
        [_capturedBufferInfo addObject:bufferInfo];
        _samplesSaved++;
        
        LOG_INFO(@"📸 Capturada amostra de buffer: %@", sampleID);
    });
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
        // Adicionar suporte para outros formatos comuns
        else if (pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
                 pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
            // Formatos YUV - precisa de conversão mais complexa
            // Esta é uma abordagem simplificada que não trata corretamente cores YUV
            // Em um ambiente de produção, use frameworks como GPUImage ou vImage
            
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
        
        // Desbloquear buffer
        CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
        
    } @catch (NSException *exception) {
        LOG_ERROR(@"Erro na análise do buffer: %@", exception);
    }
    
    return analysis;
}

- (void)calculateBrightnessStats:(CVImageBufferRef)imageBuffer average:(float *)avgOut stdDev:(float *)stdDevOut {
    // Implementação básica para BGRA
    OSType pixelFormat = CVPixelBufferGetPixelFormatType(imageBuffer);
    if (pixelFormat != kCVPixelFormatType_32BGRA) {
        // Simplificando - apenas um formato suportado neste exemplo
        *avgOut = 0.0f;
        *stdDevOut = 0.0f;
        return;
    }
    
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer);
    
    // Amostrar pixels em grade esparsa (evita processar todos os pixels)
    const size_t sampleStride = 16; // Analisa 1 a cada 16 pixels
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
        variance = MAX(0.0, variance); // Evitar erros de arredondamento
        
        *avgOut = (float)mean / 255.0f; // Normaliza para [0, 1]
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
    
    // Fatores que contribuem para a confiança (totalizando 1.0)
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
    
    // Considerar sintético se confiança > 0.7 (ajustável)
    return confidence > 0.7f;
}

- (NSDictionary *)extractVisualFeatures:(CMSampleBufferRef)sampleBuffer {
    // Extrair características visuais básicas do buffer
    
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
    
    // Análise simplificada - estes são algoritmos muito básicos
    // Uma implementação real usaria bibliotecas como vImage ou OpenCV
    
    // 1. Calcular um histograma RGB simplificado (8 bins por canal)
    const int histogramBins = 8;
    int histogramR[histogramBins] = {0};
    int histogramG[histogramBins] = {0};
    int histogramB[histogramBins] = {0};
    
    // 2. Detecção simplificada de bordas e ruído
    int edgeCount = 0;
    float noiseSum = 0.0f;
    
    // Amostragem para histograma e características
    const size_t sampleStride = 8;
    
    for (size_t y = sampleStride; y < height - sampleStride; y += sampleStride) {
        for (size_t x = sampleStride; x < width - sampleStride; x += sampleStride) {
            size_t pixelOffset = y * bytesPerRow + x * 4;
            
            // Pixel atual
            uint8_t b = baseAddress[pixelOffset];
            uint8_t g = baseAddress[pixelOffset + 1];
            uint8_t r = baseAddress[pixelOffset + 2];
            
            // Histograma (agrupar em bins)
            histogramB[b * histogramBins / 256]++;
            histogramG[g * histogramBins / 256]++;
            histogramR[r * histogramBins / 256]++;
            
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
            if (gradient > 100) { // Valor arbitrário para o limiar
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
    
    // Histograma normalizado
    NSMutableArray *histogramData = [NSMutableArray array];
    for (int i = 0; i < histogramBins; i++) {
        [histogramData addObject:@{
            @"bin": @(i),
            @"r": @((float)histogramR[i] / ((width * height) / (sampleStride * sampleStride))),
            @"g": @((float)histogramG[i] / ((width * height) / (sampleStride * sampleStride))),
            @"b": @((float)histogramB[i] / ((width * height) / (sampleStride * sampleStride)))
        }];
    }
    
    features[@"histogram"] = histogramData;
    
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
    
    // Amostragem para comparação (não comparar todos os pixels)
    const size_t sampleStride = 8;
    
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
    // Detectar padrões específicos no conteúdo (implementação básica)
    NSMutableDictionary *patterns = [NSMutableDictionary dictionary];
    
    // Adicione aqui algoritmos para detectar padrões como:
    // - Teste de padrões (barras de cor, padrão de xadrez, etc.)
    // - Cenas estáticas vs. dinâmicas
    // - Presença de rosto
    // - Detecção de texto
    
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
        
        // Outras detecções com base no histograma
        NSArray *histogram = features[@"histogram"];
        if (histogram && [histogram count] > 0) {
            // Verificar se histograma mostra imagem muito brilhante
            float brightBins = 0;
            for (NSDictionary *bin in histogram) {
                NSInteger binIdx = [bin[@"bin"] integerValue];
                if (binIdx >= 6) { // 2 bins mais brilhantes (de 8)
                    brightBins += [bin[@"r"] floatValue] + [bin[@"g"] floatValue] + [bin[@"b"] floatValue];
                }
            }
            
            if (brightBins > 0.6) {
                patterns[@"likelyOverExposed"] = @YES;
            }
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
    }
    
    [report appendString:@"Estatísticas por aplicativo:\n"];
    for (NSString *app in statsByApp) {
        NSDictionary *appStats = statsByApp[app];
        NSInteger count = [appStats[@"count"] integerValue];
        NSInteger syntheticCount = [appStats[@"syntheticCount"] integerValue];
        
        [report appendFormat:@"- %@: %ld amostras, %.1f%% sintéticas\n", 
                 app, (long)count, (count > 0 ? (float)syntheticCount / count * 100 : 0)];
    }
    
    // Análise de formatos de pixel e dimensões
    [report appendString:@"\nAnálise de formatos:\n"];
    NSMutableDictionary *formatStats = [NSMutableDictionary dictionary];
    NSMutableDictionary *dimensionStats = [NSMutableDictionary dictionary];
    
    for (NSDictionary *sample in _capturedBufferInfo) {
        NSString *formatString = sample[@"formatString"];
        if (formatString) {
            NSNumber *count = formatStats[formatString];
            if (!count) count = @0;
            formatStats[formatString] = @([count integerValue] + 1);
        }
        
        NSNumber *width = sample[@"width"];
        NSNumber *height = sample[@"height"];
        if (width && height) {
            NSString *resolution = [NSString stringWithFormat:@"%@x%@", width, height];
            NSNumber *count = dimensionStats[resolution];
            if (!count) count = @0;
            dimensionStats[resolution] = @([count integerValue] + 1);
        }
    }
    
    // Mostrar formatos de pixel
    [report appendString:@"Formatos de pixel encontrados:\n"];
    for (NSString *format in formatStats) {
        NSNumber *count = formatStats[format];
        [report appendFormat:@"- '%@': %@ amostras (%.1f%%)\n", 
             format, count, (float)[count integerValue] / _samplesSaved * 100];
    }
    
    // Mostrar resoluções
    [report appendString:@"\nResoluções encontradas:\n"];
    for (NSString *resolution in dimensionStats) {
        NSNumber *count = dimensionStats[resolution];
        [report appendFormat:@"- %@: %@ amostras (%.1f%%)\n", 
             resolution, count, (float)[count integerValue] / _samplesSaved * 100];
    }
    
    // Resumo de características visuais
    float avgBrightness = 0.0f;
    float avgNoise = 0.0f;
    float avgEdges = 0.0f;
    NSInteger featuresCount = 0;
    
    for (NSDictionary *sample in _capturedBufferInfo) {
        NSDictionary *analysis = sample[@"analysis"];
        if (!analysis) continue;
        
        NSNumber *brightness = analysis[@"avgBrightness"];
        NSNumber *noiseLevel = analysis[@"noiseLevel"];
        NSNumber *edgeDensity = analysis[@"edgeDensity"];
        
        if (brightness && noiseLevel && edgeDensity) {
            avgBrightness += [brightness floatValue];
            avgNoise += [noiseLevel floatValue];
            avgEdges += [edgeDensity floatValue];
            featuresCount++;
        }
    }
    
    if (featuresCount > 0) {
        avgBrightness /= featuresCount;
        avgNoise /= featuresCount;
        avgEdges /= featuresCount;
        
        [report appendString:@"\nMédia das características visuais:\n"];
        [report appendFormat:@"- Brilho médio: %.2f\n", avgBrightness];
        [report appendFormat:@"- Nível de ruído médio: %.4f\n", avgNoise];
        [report appendFormat:@"- Densidade de bordas média: %.4f\n", avgEdges];
    }
    
    // Conclusões
    [report appendString:@"\nCONCLUSÕES E RECOMENDAÇÕES:\n"];
    
    // Verificar se há alta prevalência de conteúdo sintético
    NSInteger totalSyntheticSamples = 0;
    for (NSString *app in statsByApp) {
        NSDictionary *appStats = statsByApp[app];
        totalSyntheticSamples += [appStats[@"syntheticCount"] integerValue];
    }
    
    float syntheticPercentage = _samplesSaved > 0 ? (float)totalSyntheticSamples / _samplesSaved * 100 : 0;
    
    if (syntheticPercentage > 50) {
        [report appendString:@"- ALERTA: Alta prevalência de conteúdo sintético detectado (>50%).\n"];
        [report appendString:@"  Isso pode indicar que já há substituição de feed em andamento ou problemas no diagnóstico.\n"];
    }
    
    // Formato mais comum - possível alvo para implementação
    NSString *mostCommonFormat = nil;
    NSInteger maxFormatCount = 0;
    for (NSString *format in formatStats) {
        NSInteger count = [formatStats[format] integerValue];
        if (count > maxFormatCount) {
            maxFormatCount = count;
            mostCommonFormat = format;
        }
    }
    
    if (mostCommonFormat) {
        [report appendFormat:@"- Formato mais comum para interceptação: '%@' (%.1f%% das amostras).\n", 
             mostCommonFormat, (float)maxFormatCount / _samplesSaved * 100];
    }
    
    // Resolução mais comum
    NSString *mostCommonResolution = nil;
    NSInteger maxResCount = 0;
    for (NSString *resolution in dimensionStats) {
        NSInteger count = [dimensionStats[resolution] integerValue];
        if (count > maxResCount) {
            maxResCount = count;
            mostCommonResolution = resolution;
        }
    }
    
    if (mostCommonResolution) {
        [report appendFormat:@"- Resolução mais comum para substituição: %@ (%.1f%% das amostras).\n", 
             mostCommonResolution, (float)maxResCount / _samplesSaved * 100];
    }
    
    [report appendString:@"\n==== FIM DO RELATÓRIO ====\n"];
    
    return report;
}

@end