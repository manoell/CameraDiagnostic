#ifndef LOGGER_H
#define LOGGER_H

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h> // Para CMSampleBufferRef, CMTime, etc.
#import <CoreVideo/CoreVideo.h> // Para CVPixelBufferRef

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Escreve uma mensagem de log com timestamp
 * @param format String de formato (estilo NSLog)
 * @param ... Argumentos variáveis
 */
void writeLog(NSString *format, ...);

/**
 * Configura o nível de log (0=desativado, 1=crítico, 2=erro, 3=aviso, 4=info, 5=debug)
 * @param level Nível desejado
 */
void setLogLevel(int level);

/**
 * Registra detalhes de um CMSampleBuffer
 * @param buffer Buffer de amostra
 * @param context Contexto da chamada
 */
void logBufferDetails(CMSampleBufferRef buffer, NSString *context);

/**
 * Registra detalhes de um CVPixelBuffer
 * @param buffer Buffer de pixel
 * @param context Contexto da chamada
 */
void logPixelBufferDetails(CVPixelBufferRef buffer, NSString *context);

#ifdef __cplusplus
}
#endif

#endif
