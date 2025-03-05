#ifndef LOGGER_H
#define LOGGER_H

#import <Foundation/Foundation.h>

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

#ifdef __cplusplus
}
#endif

#endif
