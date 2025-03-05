// CameraFeedSubstitutionSource.h

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import "CameraBufferSubstitutionInterceptor.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Tipos de substituição de feed suportados
 */
typedef NS_ENUM(NSInteger, CameraFeedSubstitutionType) {
    CameraFeedSubstitutionTypeNone,           // Sem substituição
    CameraFeedSubstitutionTypeStaticImage,    // Imagem estática
    CameraFeedSubstitutionTypeVideoFile,      // Arquivo de vídeo em loop
    CameraFeedSubstitutionTypeCustomBuffer,   // Buffer customizado (avançado)
    CameraFeedSubstitutionTypeFilteredLive,   // Feed ao vivo com filtros aplicados
};

/**
 * Fonte de substituição de feed de câmera
 * Implementa o protocolo CameraBufferSubstitutionSource
 */
@interface CameraFeedSubstitutionSource : NSObject <CameraBufferSubstitutionSource>

/**
 * Inicia com o tipo de substituição especificado
 */
- (instancetype)initWithSubstitutionType:(CameraFeedSubstitutionType)type;

/**
 * Tipo de substituição
 */
@property (nonatomic, assign) CameraFeedSubstitutionType substitutionType;

/**
 * Imagem para substituição (quando type = StaticImage)
 */
@property (nonatomic, strong, nullable) UIImage *substitutionImage;

/**
 * URL para vídeo de substituição (quando type = VideoFile)
 */
@property (nonatomic, strong, nullable) NSURL *substitutionVideoURL;

/**
 * Define uma função de filtro personalizada
 * Recebe um buffer e retorna um buffer modificado
 */
@property (nonatomic, copy, nullable) CMSampleBufferRef (^customBufferFilterBlock)(CMSampleBufferRef buffer);

/**
 * Registra a fonte no interceptor e ativa a substituição
 */
- (BOOL)enableSubstitution;

/**
 * Desativa a substituição
 */
- (void)disableSubstitution;

/**
 * Atualiza parâmetros da fonte com base no buffer original
 * Útil para manter sincronização
 */
- (void)updateWithReferenceBuffer:(CMSampleBufferRef)buffer;

@end

NS_ASSUME_NONNULL_END
