// CameraFeedSubstitutionSource.m

#import "CameraFeedSubstitutionSource.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <ImageIO/ImageIO.h>

@interface CameraFeedSubstitutionSource ()

// Para reprodução de vídeo
@property (nonatomic, strong, nullable) AVAssetReader *assetReader;
@property (nonatomic, strong, nullable) AVAssetReaderTrackOutput *videoTrackOutput;
@property (nonatomic, assign) CMTime lastVideoTimestamp;
@property (nonatomic, assign) BOOL needsVideoReset;
@property (nonatomic, strong, nullable) dispatch_queue_t videoProcessingQueue;

// Propriedades de referência para manter compatibilidade
@property (nonatomic, assign) CGSize referenceBufferSize;
@property (nonatomic, assign) OSType referencePixelFormat;
@property (nonatomic, assign) CMVideoCodecType referenceCodecType;

// Estatísticas e diagnóstico
@property (nonatomic, assign) NSUInteger framesProcessed;
@property (nonatomic, assign) NSUInteger framesSubstituted;
@property (nonatomic, assign) NSUInteger substitutionFailures;
@property (nonatomic, strong) NSDate *startTime;

@end

@implementation CameraFeedSubstitutionSource

#pragma mark - Lifecycle

- (instancetype)init {
    return [self initWithSubstitutionType:CameraFeedSubstitutionTypeNone];
}

- (instancetype)initWithSubstitutionType:(CameraFeedSubstitutionType)type {
    self = [super init];
    if (self) {
        _substitutionType = type;
        _videoProcessingQueue = dispatch_queue_create("com.camera.substitution.videoprocessing", DISPATCH_QUEUE_SERIAL);
        _needsVideoReset = YES;
        _startTime = [NSDate date];
        
        // Registre para notificações em caso de transição em segundo plano
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationDidEnterBackground:)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
        
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationWillEnterForeground:)
                                                     name:UIApplicationWillEnterForegroundNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self teardownVideoPlayback];
}

#pragma mark - Public Methods

- (BOOL)enableSubstitution {
    BOOL validConfiguration = [self validateConfiguration];
    if (!validConfiguration) {
        NSLog(@"Configuração de substituição inválida");
        return NO;
    }
    
    // Registra-se no interceptor
    CameraBufferSubstitutionInterceptor *interceptor = [CameraBufferSubstitutionInterceptor sharedInterceptor];
    interceptor.substitutionSource = self;
    interceptor.enabled = YES;
    
    // Se estivermos usando vídeo, prepare-o
    if (self.substitutionType == CameraFeedSubstitutionTypeVideoFile && self.substitutionVideoURL) {
        [self prepareVideoPlayback];
    }
    
    NSLog(@"Substituição de feed de câmera ativada (tipo: %ld)", (long)self.substitutionType);
    return YES;
}

- (void)disableSubstitution {
    // Remove-se do interceptor
    CameraBufferSubstitutionInterceptor *interceptor = [CameraBufferSubstitutionInterceptor sharedInterceptor];
    
    if (interceptor.substitutionSource == self) {
        interceptor.substitutionSource = nil;
        interceptor.enabled = NO;
    }
    
    // Libera recursos de vídeo
    [self teardownVideoPlayback];
    
    NSLog(@"Substituição de feed de câmera desativada");
}

- (void)updateWithReferenceBuffer:(CMSampleBufferRef)buffer {
    if (!buffer) return;
    
    // Extrai propriedades do buffer para referência
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(buffer);
    if (imageBuffer) {
        self.referenceBufferSize = CGSizeMake(
            CVPixelBufferGetWidth(imageBuffer),
            CVPixelBufferGetHeight(imageBuffer)
        );
        self.referencePixelFormat = CVPixelBufferGetPixelFormatType(imageBuffer);
    }
    
    // Extrai o tipo de codec do buffer
    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(buffer);
    if (formatDescription) {
        self.referenceCodecType = CMFormatDescriptionGetMediaSubType(formatDescription);
    }
}

- (void)setSubstitutionType:(CameraFeedSubstitutionType)substitutionType {
    if (_substitutionType == substitutionType) return;
    
    // Limpa os recursos anteriores
    if (_substitutionType == CameraFeedSubstitutionTypeVideoFile) {
        [self teardownVideoPlayback];
    }
    
    _substitutionType = substitutionType;
    
    // Inicializa recursos para o novo tipo se necessário
    if (substitutionType == CameraFeedSubstitutionTypeVideoFile && self.substitutionVideoURL) {
        [self prepareVideoPlayback];
    }
}

#pragma mark - CameraBufferSubstitutionSource Protocol

- (nullable CMSampleBufferRef)provideSubstitutionBufferForOriginalBuffer:(CMSampleBufferRef)originalBuffer
                                                             atTimestamp:(CMTime)timestamp {
    self.framesProcessed++;
    
    // Atualiza as propriedades de referência a partir do buffer original
    [self updateWithReferenceBuffer:originalBuffer];
    
    // Verifica se temos configuração válida
    if (!originalBuffer || self.substitutionType == CameraFeedSubstitutionTypeNone) {
        return NULL; // Sem substituição
    }
    
    // Gera o buffer substituto com base no tipo de substituição
    CMSampleBufferRef substitutionBuffer = NULL;
    
    switch (self.substitutionType) {
        case CameraFeedSubstitutionTypeStaticImage:
            substitutionBuffer = [self createStaticImageBuffer:originalBuffer timestamp:timestamp];
            break;
            
        case CameraFeedSubstitutionTypeVideoFile:
            substitutionBuffer = [self createVideoFrameBuffer:originalBuffer timestamp:timestamp];
            break;
            
        case CameraFeedSubstitutionTypeCustomBuffer:
            substitutionBuffer = [self createCustomBuffer:originalBuffer timestamp:timestamp];
            break;
            
        case CameraFeedSubstitutionTypeFilteredLive:
            substitutionBuffer = [self createFilteredBuffer:originalBuffer timestamp:timestamp];
            break;
            
        default:
            return NULL;
    }
    
    // Registra o resultado
    if (substitutionBuffer) {
        self.framesSubstituted++;
        return substitutionBuffer;
    } else {
        self.substitutionFailures++;
        return NULL;
    }
}

- (void)substitutionBufferWasApplied:(CMSampleBufferRef)buffer {
    // Nada a fazer por padrão
}

- (void)substitutionFailedForBuffer:(CMSampleBufferRef)originalBuffer error:(NSError *)error {
    NSLog(@"Falha na substituição de buffer: %@", error.localizedDescription);
    self.substitutionFailures++;
}

#pragma mark - Buffer Creation Methods

- (CMSampleBufferRef)createStaticImageBuffer:(CMSampleBufferRef)originalBuffer timestamp:(CMTime)timestamp {
    if (!self.substitutionImage) {
        return NULL;
    }
    
    // Usa a utilidade do interceptor para criar um buffer a partir da imagem
    return [CameraBufferSubstitutionInterceptor createSampleBufferFromUIImage:self.substitutionImage
                                                         withReferenceBuffer:originalBuffer];
}

- (CMSampleBufferRef)createVideoFrameBuffer:(CMSampleBufferRef)originalBuffer timestamp:(CMTime)timestamp {
    if (!self.assetReader || !self.videoTrackOutput) {
        if (self.needsVideoReset && self.substitutionVideoURL) {
            [self prepareVideoPlayback];
        }
        
        if (!self.assetReader || !self.videoTrackOutput) {
            return NULL;
        }
    }
    
    // Captura o próximo frame do vídeo de maneira thread-safe
    __block CMSampleBufferRef videoFrame = NULL;
    
    dispatch_sync(self.videoProcessingQueue, ^{
        // Verifica se o asset reader está em estado de leitura
        if (self.assetReader.status != AVAssetReaderStatusReading) {
            // Tenta reiniciar o leitor se necessário
            if (self.assetReader.status == AVAssetReaderStatusCompleted) {
                [self prepareVideoPlayback]; // Isso reinicia o vídeo do início
            } else {
                return; // Erro, não podemos ler
            }
        }
        
        // Lê o próximo sample buffer
        CMSampleBufferRef nextFrame = [self.videoTrackOutput copyNextSampleBuffer];
        if (!nextFrame) {
            // Fim do vídeo, reinicie
            [self prepareVideoPlayback];
            nextFrame = [self.videoTrackOutput copyNextSampleBuffer];
        }
        
        if (nextFrame) {
            videoFrame = nextFrame;
            
            // Substitui o timestamp pelo da câmera para sincronização
            CMSampleTimingInfo timing = {
                .duration = CMSampleBufferGetDuration(nextFrame),
                .presentationTimeStamp = timestamp,
                .decodeTimeStamp = timestamp
            };
            
            // Cria um novo buffer com as propriedades de timing ajustadas
            CMSampleBufferRef adjustedBuffer = NULL;
            CMSampleBufferCreateCopyWithNewTiming(
                kCFAllocatorDefault,
                nextFrame,
                1, // timingArrayEntryCount
                &timing,
                &adjustedBuffer
            );
            
            if (adjustedBuffer) {
                CFRelease(nextFrame);
                videoFrame = adjustedBuffer;
            }
        }
    });
    
    return videoFrame;
}

- (CMSampleBufferRef)createCustomBuffer:(CMSampleBufferRef)originalBuffer timestamp:(CMTime)timestamp {
    // Se temos um bloco de filtro personalizado, execute-o
    if (self.customBufferFilterBlock) {
        return self.customBufferFilterBlock(originalBuffer);
    }
    
    return NULL;
}

- (CMSampleBufferRef)createFilteredBuffer:(CMSampleBufferRef)originalBuffer timestamp:(CMTime)timestamp {
    // Aplica filtros ao buffer ao vivo
    // Esta é uma implementação demonstrativa de aplicação de um filtro simples de cor
    
    // Obtém o CVPixelBuffer do CMSampleBuffer original
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(originalBuffer);
    if (!pixelBuffer) {
        return NULL;
    }
    
    // Bloqueamos o buffer para acesso direto
    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    
    // Obter informações do buffer
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    OSType pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
    void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    
    // Exemplo: Criar uma cópia do buffer e aplicar um filtro
    // Para um filtro real, você pode usar Core Image, Metal, ou OpenGL
    uint8_t *filteredData = malloc(bytesPerRow * height);
    if (!filteredData) {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        return NULL;
    }
    
    memcpy(filteredData, baseAddress, bytesPerRow * height);
    
    // Desbloqueia o buffer original
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    
    // Aplicamos um filtro simples (exemplo: canal vermelho invertido)
    // Esta operação depende do formato do pixel
    if (pixelFormat == kCVPixelFormatType_32BGRA) {
        for (size_t y = 0; y < height; y++) {
            for (size_t x = 0; x < width; x++) {
                size_t pixelOffset = y * bytesPerRow + x * 4;
                
                // BGRA: inverte o canal R (índice 2)
                filteredData[pixelOffset + 2] = 255 - filteredData[pixelOffset + 2];
            }
        }
    }
    
    // Cria um novo buffer de amostra com os dados filtrados
    CMSampleBufferRef filteredBuffer = [CameraBufferSubstitutionInterceptor createSampleBufferFromPixelData:filteredData
                                                                                                 width:width
                                                                                                height:height
                                                                                          pixelFormat:pixelFormat
                                                                                withPresentationTime:timestamp];
    
    // Libera a memória alocada
    free(filteredData);
    
    return filteredBuffer;
}

#pragma mark - Video Playback Helpers

- (void)prepareVideoPlayback {
    [self teardownVideoPlayback];
    
    if (!self.substitutionVideoURL) {
        return;
    }
    
    dispatch_sync(self.videoProcessingQueue, ^{
        NSError *error = nil;
        
        // Cria um asset para o vídeo
        AVAsset *asset = [AVAsset assetWithURL:self.substitutionVideoURL];
        
        // Cria um leitor para o asset
        self.assetReader = [AVAssetReader assetReaderWithAsset:asset error:&error];
        if (error) {
            NSLog(@"Erro ao criar asset reader: %@", error);
            self.assetReader = nil;
            return;
        }
        
        // Obtém a primeira trilha de vídeo
        AVAssetTrack *videoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
        if (!videoTrack) {
            NSLog(@"Não foi possível encontrar uma trilha de vídeo");
            self.assetReader = nil;
            return;
        }
        
        // Configura a saída de trilha
        NSDictionary *outputSettings = @{
            (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)
        };
        
        self.videoTrackOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:videoTrack
                                                                         outputSettings:outputSettings];
        
        if (![self.assetReader canAddOutput:self.videoTrackOutput]) {
            NSLog(@"Não foi possível adicionar a saída da trilha ao leitor");
            self.assetReader = nil;
            self.videoTrackOutput = nil;
            return;
        }
        
        [self.assetReader addOutput:self.videoTrackOutput];
        
        // Inicia a leitura
        if (![self.assetReader startReading]) {
            NSLog(@"Erro ao iniciar a leitura: %@", self.assetReader.error);
            self.assetReader = nil;
            self.videoTrackOutput = nil;
        }
    });
    
    self.needsVideoReset = NO;
}

- (void)teardownVideoPlayback {
    dispatch_sync(self.videoProcessingQueue, ^{
        if (self.assetReader) {
            [self.assetReader cancelReading];
            self.assetReader = nil;
            self.videoTrackOutput = nil;
        }
    });
}

#pragma mark - Application Lifecycle

- (void)applicationDidEnterBackground:(NSNotification *)notification {
    // Quando o app vai para o background, marcamos para resetar o vídeo
    self.needsVideoReset = YES;
}

- (void)applicationWillEnterForeground:(NSNotification *)notification {
    // Quando o app volta para o foreground, reinicializamos o vídeo se necessário
    if (self.needsVideoReset && self.substitutionType == CameraFeedSubstitutionTypeVideoFile) {
        [self prepareVideoPlayback];
    }
}

#pragma mark - Helpers

- (BOOL)validateConfiguration {
    switch (self.substitutionType) {
        case CameraFeedSubstitutionTypeNone:
            return YES; // Válido, mas não faz nada
            
        case CameraFeedSubstitutionTypeStaticImage:
            return self.substitutionImage != nil;
            
        case CameraFeedSubstitutionTypeVideoFile:
            return self.substitutionVideoURL != nil;
            
        case CameraFeedSubstitutionTypeCustomBuffer:
            return self.customBufferFilterBlock != nil;
            
        case CameraFeedSubstitutionTypeFilteredLive:
            return YES; // Sempre válido, aplica um filtro interno
    }
    
    return NO;
}

@end
