// BufferContentInspector.h

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <ImageIO/ImageIO.h>

/**
 * Classe utilitária para capturar e analisar o conteúdo dos buffers de vídeo
 * Permite salvar amostras e verificar padrões nos frames da câmera
 */
@interface BufferContentInspector : NSObject

// Configuração
@property (nonatomic, assign) BOOL captureEnabled;
@property (nonatomic, assign) BOOL analyzeContent;
@property (nonatomic, assign) uint32_t captureInterval;
@property (nonatomic, assign) NSInteger maxCapturedSamples;
@property (nonatomic, copy) NSString *outputDirectory;

// Estatísticas
@property (nonatomic, readonly) NSUInteger samplesAnalyzed;
@property (nonatomic, readonly) NSUInteger samplesSaved;

// Singleton
+ (instancetype)sharedInstance;

// Capturar uma amostra de um buffer
- (void)captureSampleFromBuffer:(CMSampleBufferRef)sampleBuffer 
                    withContext:(NSString *)context;

// Analisar o conteúdo de um buffer
- (NSDictionary *)analyzeBufferContent:(CMSampleBufferRef)sampleBuffer;

// Comparar dois buffers para detectar diferenças
- (CGFloat)compareBuffer:(CMSampleBufferRef)buffer1 
              withBuffer:(CMSampleBufferRef)buffer2;

// Verificar se um buffer contém uma imagem sintética/estática
- (BOOL)isLikelySyntheticContent:(CMSampleBufferRef)sampleBuffer 
                     confidence:(CGFloat *)confidenceOut;

// Detectar padrões específicos no conteúdo do buffer
- (NSDictionary *)detectContentPatterns:(CMSampleBufferRef)sampleBuffer;

// Extrair características visuais (histograma, bordas, etc.)
- (NSDictionary *)extractVisualFeatures:(CMSampleBufferRef)sampleBuffer;

// Gerar relatório sobre os buffers analisados
- (NSString *)generateReport;

@end