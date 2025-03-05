// BufferContentInspector.h

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <ImageIO/ImageIO.h>
#import "IOSurface.h"

/**
 * Classe utilitária para capturar e analisar o conteúdo dos buffers de vídeo
 * Permite identificar características e padrões para diagnóstico do feed da câmera
 */
@interface BufferContentInspector : NSObject

// Configuração
@property (nonatomic, assign) BOOL captureEnabled;         // Habilitar captura de amostras
@property (nonatomic, assign) BOOL analyzeContent;         // Habilitar análise de conteúdo
@property (nonatomic, assign) uint32_t captureInterval;    // Intervalo de captura (1 em cada N frames)
@property (nonatomic, assign) NSInteger maxCapturedSamples;// Limite de amostras para guardar
@property (nonatomic, copy) NSString *outputDirectory;     // Diretório para salvar amostras

// Estatísticas
@property (nonatomic, readonly) NSUInteger samplesAnalyzed;
@property (nonatomic, readonly) NSUInteger samplesSaved;

// Singleton
+ (instancetype)sharedInstance;

/**
 * Captura e analisa uma amostra de um buffer de vídeo
 * @param sampleBuffer O buffer a ser analisado
 * @param context Contexto da captura (ex: nome do componente que está processando o buffer)
 */
- (void)captureSampleFromBuffer:(CMSampleBufferRef)sampleBuffer
                    withContext:(NSString *)context;

/**
 * Analisa o conteúdo de um buffer para extrair características
 * @param sampleBuffer O buffer a ser analisado
 * @return Dicionário com resultados da análise
 */
- (NSDictionary *)analyzeBufferContent:(CMSampleBufferRef)sampleBuffer;

/**
 * Compara dois buffers para detectar diferenças
 * @param buffer1 Primeiro buffer
 * @param buffer2 Segundo buffer
 * @return Valor entre 0 e 1 indicando a diferença (0 = idênticos, 1 = completamente diferentes)
 */
- (CGFloat)compareBuffer:(CMSampleBufferRef)buffer1
              withBuffer:(CMSampleBufferRef)buffer2;

/**
 * Verifica se um buffer contém conteúdo sintético (não proveniente de câmera real)
 * @param sampleBuffer O buffer a verificar
 * @param confidenceOut Nível de confiança da detecção (0-1)
 * @return YES se for provavelmente conteúdo sintético
 */
- (BOOL)isLikelySyntheticContent:(CMSampleBufferRef)sampleBuffer
                     confidence:(CGFloat *)confidenceOut;

/**
 * Detecta padrões específicos no conteúdo do buffer
 * @param sampleBuffer O buffer a analisar
 * @return Dicionário com os padrões detectados
 */
- (NSDictionary *)detectContentPatterns:(CMSampleBufferRef)sampleBuffer;

/**
 * Extrai características visuais do buffer (histograma, bordas, etc.)
 * @param sampleBuffer O buffer a analisar
 * @return Dicionário com as características extraídas
 */
- (NSDictionary *)extractVisualFeatures:(CMSampleBufferRef)sampleBuffer;

/**
 * Gera um relatório detalhado sobre os buffers analisados
 * Identifica pontos potenciais para substituição do feed da câmera
 * @return Relatório em formato de texto
 */
- (NSString *)generateReport;

/**
 * Gera uma impressão digital única para o buffer
 * Útil para detectar padrões recorrentes
 * @param imageBuffer O buffer a analisar
 * @return String representando a impressão digital do buffer
 */
- (NSString *)generateFingerprintForBuffer:(CVImageBufferRef)imageBuffer;

@end
