// CameraBufferSubstitutionInterceptor.h

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Protocolo para fornecer quadros substitutos para a câmera
 */
@protocol CameraBufferSubstitutionSource <NSObject>

/**
 * Solicita um quadro substituto para um determinado momento
 *
 * @param originalBuffer O buffer original da câmera (pode ser usado como referência)
 * @param timestamp O timestamp de apresentação do quadro
 * @return Um novo buffer para substituir o buffer original, ou nil para não substituir
 */
- (nullable CMSampleBufferRef)provideSubstitutionBufferForOriginalBuffer:(CMSampleBufferRef)originalBuffer
                                                             atTimestamp:(CMTime)timestamp;

@optional
/**
 * Notifica quando um buffer substituto foi aplicado com sucesso
 */
- (void)substitutionBufferWasApplied:(CMSampleBufferRef)buffer;

/**
 * Notifica quando uma substituição falhou
 */
- (void)substitutionFailedForBuffer:(CMSampleBufferRef)originalBuffer error:(NSError *)error;

@end

/**
 * Interceptor que permite substituir buffers da câmera em runtime
 */
@interface CameraBufferSubstitutionInterceptor : NSObject

/**
 * Singleton para acesso global
 */
+ (instancetype)sharedInterceptor;

/**
 * Define a fonte de substitução
 */
@property (nonatomic, weak, nullable) id<CameraBufferSubstitutionSource> substitutionSource;

/**
 * Ativa ou desativa a substituição
 */
@property (nonatomic, assign, getter=isEnabled) BOOL enabled;

/**
 * Define uma estratégia de intercepção
 * Valores possíveis: "swizzle", "proxy", "direct"
 */
@property (nonatomic, copy) NSString *interceptionStrategy;

/**
 * Instala os hooks necessários para interceptar os buffers da câmera
 */
- (void)installHooks;

/**
 * Desinstala os hooks
 */
- (void)uninstallHooks;

/**
 * Intercepta e potencialmente substitui um buffer
 */
- (CMSampleBufferRef)interceptAndPotentiallyReplaceBuffer:(CMSampleBufferRef)buffer fromOutput:(AVCaptureOutput *)output;

/**
 * Cria um buffer a partir de uma UIImage
 */
+ (nullable CMSampleBufferRef)createSampleBufferFromUIImage:(UIImage *)image
                                         withReferenceBuffer:(CMSampleBufferRef)referenceBuffer;

/**
 * Cria um buffer a partir de dados de pixel
 */
+ (nullable CMSampleBufferRef)createSampleBufferFromPixelData:(uint8_t *)pixelData
                                                        width:(size_t)width
                                                       height:(size_t)height
                                                 pixelFormat:(OSType)pixelFormat
                                       withPresentationTime:(CMTime)presentationTime;

@end

NS_ASSUME_NONNULL_END
