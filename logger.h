#ifndef LOGGER_H
#define LOGGER_H

#import <Foundation/Foundation.h>

// Define níveis de log
typedef NS_ENUM(NSInteger, LogLevel) {
    LogLevelDebug,
    LogLevelInfo,
    LogLevelWarning,
    LogLevelError
};

// Interface de Logger
@interface Logger : NSObject

+ (instancetype)sharedInstance;

// Métodos principais de logging
- (void)logDebug:(NSString *)format, ...;
- (void)logInfo:(NSString *)format, ...;
- (void)logWarning:(NSString *)format, ...;
- (void)logError:(NSString *)format, ...;

// Configuração
- (void)setLogToConsole:(BOOL)logToConsole;
- (void)setLogToFile:(BOOL)logToFile;
- (void)setLogFilePath:(NSString *)filePath;
- (void)setMinimumLogLevel:(LogLevel)level;

// Utilitários
- (NSString *)getLogFilePath;
- (void)clearLogFile;

@end

// Macros convenientes
#define LOG_DEBUG(fmt, ...) [[Logger sharedInstance] logDebug:fmt, ##__VA_ARGS__]
#define LOG_INFO(fmt, ...) [[Logger sharedInstance] logInfo:fmt, ##__VA_ARGS__]
#define LOG_WARNING(fmt, ...) [[Logger sharedInstance] logWarning:fmt, ##__VA_ARGS__]
#define LOG_ERROR(fmt, ...) [[Logger sharedInstance] logError:fmt, ##__VA_ARGS__]

#endif /* LOGGER_H */
