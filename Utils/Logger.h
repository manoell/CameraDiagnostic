#ifndef LOGGER_H
#define LOGGER_H

#import <Foundation/Foundation.h>

// Níveis de log
typedef NS_ENUM(NSInteger, LogLevel) {
    LogLevelError = 0,
    LogLevelWarning = 1,
    LogLevelInfo = 2,
    LogLevelDebug = 3,
    LogLevelVerbose = 4
};

// Categorias de log
typedef NS_ENUM(NSInteger, LogCategory) {
    LogCategorySession = 0,
    LogCategoryDevice = 1,
    LogCategoryVideo = 2,
    LogCategoryPhoto = 3,
    LogCategoryOrientation = 4,
    LogCategoryFormat = 5,
    LogCategoryMetadata = 6,
    LogCategoryTransform = 7,
    LogCategoryGeneral = 8
};

// Interface principal do logger
@interface DiagnosticLogger : NSObject

+ (instancetype)sharedInstance;

// Configuração
- (void)setLogLevel:(LogLevel)level;
- (void)setLogDirectory:(NSString *)directory;
- (NSString *)currentLogFile;

// Métodos de log
- (void)logMessage:(NSString *)message level:(LogLevel)level category:(LogCategory)category;
- (void)logFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
- (void)logError:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
- (void)logWarning:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
- (void)logInfo:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
- (void)logDebug:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
- (void)logVerbose:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

// JSON Logging
- (void)logJSONData:(NSDictionary *)jsonData forCategory:(LogCategory)category;
- (void)logJSONData:(NSDictionary *)jsonData forCategory:(LogCategory)category withDescription:(NSString *)description;

// Diagnóstico
- (void)startNewSession;
- (void)setSessionValue:(id)value forKey:(NSString *)key;
- (NSDictionary *)currentSessionData;
- (void)finalizeSessionWithCompletion:(void(^)(NSURL *fileURL, NSError *error))completion;

@end

// Funções C para facilitar o uso em hooks
#ifdef __cplusplus
extern "C" {
#endif

void logMessage(NSString *message, LogLevel level, LogCategory category);
void logJSON(NSDictionary *jsonData, LogCategory category);
void logJSONWithDescription(NSDictionary *jsonData, LogCategory category, NSString *description);
void startNewLogSession(void);
void finalizeLogSession(void);
void setLogSessionValue(NSString *key, id value);

#ifdef __cplusplus
}
#endif

#endif /* LOGGER_H */
