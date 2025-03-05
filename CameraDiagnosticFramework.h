// CameraDiagnosticFramework.h

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Níveis de log para o framework de diagnóstico
 */
typedef NS_ENUM(NSInteger, CameraDiagnosticLogLevel) {
    CameraDiagnosticLogLevelInfo,    // Informações gerais
    CameraDiagnosticLogLevelDebug,   // Detalhes de debug
    CameraDiagnosticLogLevelWarning, // Avisos
    CameraDiagnosticLogLevelError    // Erros
};

/**
 * Framework para diagnóstico completo do sistema de câmera
 * Foca em encontrar pontos universais para substituição do feed
 */
@interface CameraDiagnosticFramework : NSObject

/**
 * Obtém a instância singleton do framework
 */
+ (instancetype)sharedInstance;

// MARK: - Configuração

/**
 * Inicia o diagnóstico com um determinado nível de log
 * @param level Nível de log desejado
 */
- (void)startDiagnosticWithLogLevel:(CameraDiagnosticLogLevel)level;

/**
 * Encerra o diagnóstico e gera relatório final
 */
- (void)stopDiagnostic;

/**
 * Configura o log para arquivo
 * @param logToFile YES para habilitar log em arquivo
 */
- (void)setLogToFile:(BOOL)logToFile;

/**
 * Define o caminho do arquivo de log
 * @param path Caminho completo para o arquivo de log
 */
- (void)setLogFilePath:(NSString *)path;

// MARK: - Hook para swizzling de métodos

/**
 * Instala hooks específicos para APIs de câmera
 * Foca apenas nos métodos críticos para o diagnóstico
 */
- (void)hookCameraAPIs;

/**
 * Hook em AVCaptureSession para monitorar sessões de câmera
 */
- (void)hookAVCaptureSession;

/**
 * Hook em AVCaptureVideoDataOutput para monitorar processamento de buffers
 */
- (void)hookAVCaptureVideoDataOutput;

// MARK: - Diagnóstico específico

/**
 * Gera um snapshot da configuração atual da câmera
 */
- (void)dumpCameraConfiguration;

/**
 * Analisa todas as sessões de captura ativas
 */
- (void)analyzeActiveCaptureSessions;

/**
 * Analisa uma sessão específica em busca de pontos de interceptação
 * @param session A sessão a ser analisada
 */
- (void)analyzeSession:(AVCaptureSession *)session;

/**
 * Analisa delegados de saída de vídeo
 * Identifica quem processa os buffers da câmera
 */
- (void)analyzeVideoDataOutputs;

/**
 * Analisa buffer de câmera para identificar características importantes
 * @param sampleBuffer O buffer a analisar
 * @param output O output que gerou o buffer
 * @param connection A conexão associada ao buffer
 */
- (void)analyzeBuffer:(CMSampleBufferRef)sampleBuffer
          fromOutput:(AVCaptureOutput *)output
          connection:(AVCaptureConnection *)connection;

/**
 * Analisa o pipeline de renderização da visualização da câmera
 * Identifica camadas e visualizações relacionadas à câmera
 */
- (void)analyzeRenderPipeline;

/**
 * Detecta quais aplicativos estão usando a câmera
 */
- (void)detectApplicationUsingCamera;

/**
 * Identifica pontos críticos para interceptação do feed da câmera
 * Avalia todos os componentes analisados e identifica os melhores pontos para substituição
 */
- (void)identifyCriticalInterceptionPoints;

/**
 * Executa análise periódica do sistema
 * Chamada por timer para atualizar informações em tempo real
 */
- (void)periodicAnalysis;

/**
 * Gera relatório final com todos os pontos de interceptação identificados
 * Detalha os componentes envolvidos e as estratégias recomendadas
 */
- (void)generateFinalReport;

// MARK: - Utilitários

/**
 * Registra uma mensagem de log com um determinado nível
 * @param level Nível da mensagem
 * @param format String de formatação
 * @param ... Argumentos para a formatação
 */
- (void)logMessageWithLevel:(CameraDiagnosticLogLevel)level
                     format:(NSString *)format, ...;

/**
 * Obtém descrição detalhada de um buffer de sample
 * @param sampleBuffer Buffer a descrever
 * @return String com descrição detalhada do buffer
 */
- (NSString *)descriptionForCMSampleBuffer:(CMSampleBufferRef)sampleBuffer;

/**
 * Obtém descrição detalhada de uma conexão de captura
 * @param connection Conexão a descrever
 * @return String com descrição detalhada da conexão
 */
- (NSString *)descriptionForAVCaptureConnection:(AVCaptureConnection *)connection;

/**
 * Obtém descrição detalhada de uma saída de dados de vídeo
 * @param output Saída a descrever
 * @return String com descrição detalhada da saída
 */
- (NSString *)descriptionForAVCaptureVideoDataOutput:(AVCaptureVideoDataOutput *)output;

/**
 * Obtém descrição detalhada de um buffer de pixels
 * @param pixelBuffer Buffer a descrever
 * @return String com descrição detalhada do buffer
 */
- (NSString *)descriptionForPixelBuffer:(CVPixelBufferRef)pixelBuffer;

@end

NS_ASSUME_NONNULL_END
