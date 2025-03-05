// LowLevelCameraInterceptor.h

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <IOKit/IOKitLib.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Interceptor de baixo nível para captura de dados da câmera
 * Vai além do AVFoundation para capturar interações em nível de driver
 */
@interface LowLevelCameraInterceptor : NSObject

// Singleton
+ (instancetype)sharedInstance;

// Iniciar monitoramento de baixo nível
- (void)startMonitoring;

// Parar monitoramento
- (void)stopMonitoring;

// Configurar nível de detalhamento da captura
@property (nonatomic, assign) BOOL captureBufferContent;       // Salvar amostras de conteúdo dos buffers
@property (nonatomic, assign) BOOL traceCoreMediaAPIs;         // Rastrear APIs do CoreMedia
@property (nonatomic, assign) BOOL traceIOServices;            // Rastrear serviços de IO
@property (nonatomic, assign) BOOL tracePrivateCameraAPIs;     // Rastrear APIs privadas de câmera

// Configurar diretório para amostras de buffer
@property (nonatomic, copy) NSString *bufferSamplesDirectory;

@end


/**
 * Monitor para frameworks privados da Apple
 * Detecta e faz hook em classes relacionadas à câmera em frameworks proprietários
 */
@interface PrivateFrameworksMonitor : NSObject

// Iniciar monitoramento de frameworks privados
+ (void)startMonitoring;

// Processos escaneados
+ (NSArray<NSString *> *)scannedFrameworks;

// Classes detectadas relacionadas à câmera
+ (NSArray<NSString *> *)detectedCameraRelatedClasses;

@end

NS_ASSUME_NONNULL_END