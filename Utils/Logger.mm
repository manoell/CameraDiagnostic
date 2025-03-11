#import "Logger.h"
#import <UIKit/UIKit.h> // Adicionado para acessar UIDevice

// Nome dos arquivos e diretórios
static NSString *const kDefaultLogDirectory = @"/var/tmp/CameraDiagnostic";
static NSString *const kLogFilePrefix = @"camera_diagnostic_";
static NSString *const kLogFileExtension = @".json";
static NSString *const kSessionDataFile = @"current_session.json";

// Utilidade para obter string da categoria
static NSString *categoryToString(LogCategory category) {
    static NSDictionary *categoryStrings = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        categoryStrings = @{
            @(LogCategorySession): @"SESSION",
            @(LogCategoryDevice): @"DEVICE",
            @(LogCategoryVideo): @"VIDEO",
            @(LogCategoryPhoto): @"PHOTO",
            @(LogCategoryOrientation): @"ORIENTATION",
            @(LogCategoryFormat): @"FORMAT",
            @(LogCategoryMetadata): @"METADATA",
            @(LogCategoryTransform): @"TRANSFORM",
            @(LogCategoryGeneral): @"GENERAL"
        };
    });
    
    return categoryStrings[@(category)] ?: @"UNKNOWN";
}

// Utilidade para obter string do nível de log
static NSString *levelToString(LogLevel level) {
    static NSDictionary *levelStrings = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        levelStrings = @{
            @(LogLevelError): @"ERROR",
            @(LogLevelWarning): @"WARNING",
            @(LogLevelInfo): @"INFO",
            @(LogLevelDebug): @"DEBUG",
            @(LogLevelVerbose): @"VERBOSE"
        };
    });
    
    return levelStrings[@(level)] ?: @"UNKNOWN";
}

@implementation DiagnosticLogger {
    NSFileHandle *_currentFileHandle;
    LogLevel _logLevel;
    NSString *_logDirectory;
    NSString *_currentSessionFile;
    NSMutableDictionary *_sessionData;
    NSLock *_sessionLock;
    dispatch_queue_t _logQueue;
    BOOL _hasWrittenToCurrentFile;
}

+ (instancetype)sharedInstance {
    static DiagnosticLogger *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        _logLevel = LogLevelDebug;
        _logDirectory = kDefaultLogDirectory;
        _sessionData = [NSMutableDictionary dictionary];
        _sessionLock = [[NSLock alloc] init];
        _logQueue = dispatch_queue_create("com.diagnostic.camera.log", DISPATCH_QUEUE_SERIAL);
        _hasWrittenToCurrentFile = NO;
        
        // Criar diretório de logs se não existir
        [self createLogDirectoryIfNeeded];
        
        // Iniciar uma nova sessão
        [self startNewSession];
    }
    return self;
}

#pragma mark - Configuração

- (void)setLogLevel:(LogLevel)level {
    _logLevel = level;
}

- (void)setLogDirectory:(NSString *)directory {
    if (directory) {
        _logDirectory = [directory copy];
        [self createLogDirectoryIfNeeded];
    }
}

- (NSString *)currentLogFile {
    return _currentSessionFile;
}

- (void)createLogDirectoryIfNeeded {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if (![fileManager fileExistsAtPath:_logDirectory]) {
        NSError *error = nil;
        if (![fileManager createDirectoryAtPath:_logDirectory
                    withIntermediateDirectories:YES
                                     attributes:nil
                                          error:&error]) {
            NSLog(@"[CameraDiagnostic] Erro ao criar diretório de logs: %@", error);
        }
    }
}

#pragma mark - Métodos de Log

- (void)logMessage:(NSString *)message level:(LogLevel)level category:(LogCategory)category {
    if (level > _logLevel) return;
    
    // Timestamp atual
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *timestamp = [dateFormatter stringFromDate:[NSDate date]];
    
    // Formato do log
    NSString *formattedMessage = [NSString stringWithFormat:@"[%@] [%@] [%@] %@",
                                 timestamp, levelToString(level), categoryToString(category), message];
    
    // Log para console
    NSLog(@"%@", formattedMessage);
    
    // Adicionar ao arquivo JSON atual
    dispatch_async(_logQueue, ^{
        NSDictionary *logEntry = @{
            @"timestamp": timestamp,
            @"level": levelToString(level),
            @"category": categoryToString(category),
            @"message": message
        };
        
        [self appendToSessionData:@{@"logs": @[logEntry]}];
    });
}

- (void)logFormat:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *formattedString = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    [self logMessage:formattedString level:LogLevelInfo category:LogCategoryGeneral];
}

- (void)logError:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *formattedString = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    [self logMessage:formattedString level:LogLevelError category:LogCategoryGeneral];
}

- (void)logWarning:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *formattedString = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    [self logMessage:formattedString level:LogLevelWarning category:LogCategoryGeneral];
}

- (void)logInfo:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *formattedString = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    [self logMessage:formattedString level:LogLevelInfo category:LogCategoryGeneral];
}

- (void)logDebug:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *formattedString = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    [self logMessage:formattedString level:LogLevelDebug category:LogCategoryGeneral];
}

- (void)logVerbose:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *formattedString = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    [self logMessage:formattedString level:LogLevelVerbose category:LogCategoryGeneral];
}

#pragma mark - JSON Logging

- (void)logJSONData:(NSDictionary *)jsonData forCategory:(LogCategory)category {
    [self logJSONData:jsonData forCategory:category withDescription:nil];
}

- (void)logJSONData:(NSDictionary *)jsonData forCategory:(LogCategory)category withDescription:(NSString *)description {
    if (!jsonData) return;
    
    NSString *categoryString = categoryToString(category);
    
    // Log para console
    if (description) {
        NSLog(@"[CameraDiagnostic] [%@] %@: %@", categoryString, description, jsonData);
    } else {
        NSLog(@"[CameraDiagnostic] [%@] JSON Data: %@", categoryString, jsonData);
    }
    
    // Adicionar à estrutura de dados da sessão
    dispatch_async(_logQueue, ^{
        NSString *key = [categoryString lowercaseString];
        
        [self appendToSessionData:@{key: jsonData}];
    });
}

#pragma mark - Gerenciamento de Sessão

- (void)startNewSession {
    [_sessionLock lock];
    
    // Finalizar sessão anterior se existir
    if (_hasWrittenToCurrentFile) {
        [self saveCurrentSessionData];
    }
    
    // Criar novo arquivo de sessão
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateFormat:@"yyyyMMdd_HHmmss"];
    NSString *timestamp = [dateFormatter stringFromDate:[NSDate date]];
    
    _currentSessionFile = [NSString stringWithFormat:@"%@/%@%@%@",
                          _logDirectory, kLogFilePrefix, timestamp, kLogFileExtension];
    
    // Adicionar informações básicas da sessão
    _sessionData = [NSMutableDictionary dictionary];
    NSString *processName = [NSProcessInfo processInfo].processName;
    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
    
    _sessionData[@"sessionInfo"] = @{
        @"id": [[NSUUID UUID] UUIDString],
        @"startTime": [NSDate date].description,
        @"appName": processName,
        @"bundleId": bundleId,
        @"iosVersion": [[UIDevice currentDevice] systemVersion],
        @"deviceModel": [[UIDevice currentDevice] model]
    };
    
    _hasWrittenToCurrentFile = NO;
    
    [_sessionLock unlock];
    
    [self logInfo:@"Nova sessão iniciada para %@ (%@)", processName, bundleId];
}

- (void)setSessionValue:(id)value forKey:(NSString *)key {
    if (!key || !value) return;
    
    dispatch_async(_logQueue, ^{
        [_sessionLock lock];
        
        NSMutableDictionary *sessionInfo = [_sessionData[@"sessionInfo"] mutableCopy] ?: [NSMutableDictionary dictionary];
        sessionInfo[key] = value;
        _sessionData[@"sessionInfo"] = sessionInfo;
        
        [_sessionLock unlock];
    });
}

- (NSDictionary *)currentSessionData {
    [_sessionLock lock];
    NSDictionary *copy = [_sessionData copy];
    [_sessionLock unlock];
    
    return copy;
}

- (void)finalizeSessionWithCompletion:(void(^)(NSURL *fileURL, NSError *error))completion {
    dispatch_async(_logQueue, ^{
        [self saveCurrentSessionData];
        
        if (completion) {
            NSURL *fileURL = [NSURL fileURLWithPath:self->_currentSessionFile];
            completion(fileURL, nil);
        }
    });
}

#pragma mark - Helpers

- (void)appendToSessionData:(NSDictionary *)data {
    [_sessionLock lock];
    
    for (NSString *key in data) {
        id existingValue = _sessionData[key];
        
        // Se a chave já existe e é um array, acrescentar ao array
        if ([existingValue isKindOfClass:[NSArray class]] && [data[key] isKindOfClass:[NSArray class]]) {
            NSMutableArray *combined = [existingValue mutableCopy];
            [combined addObjectsFromArray:data[key]];
            _sessionData[key] = combined;
        }
        // Se a chave já existe e é um dicionário, mesclar os dicionários
        else if ([existingValue isKindOfClass:[NSDictionary class]] && [data[key] isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *combined = [existingValue mutableCopy];
            [combined addEntriesFromDictionary:data[key]];
            _sessionData[key] = combined;
        }
        // Caso contrário, substituir o valor existente
        else {
            _sessionData[key] = data[key];
        }
    }
    
    _hasWrittenToCurrentFile = YES;
    
    [_sessionLock unlock];
}

- (void)saveCurrentSessionData {
    if (!_hasWrittenToCurrentFile) return;
    
    [_sessionLock lock];
    
    // Adicionar timestamp de finalização
    NSMutableDictionary *sessionInfo = [_sessionData[@"sessionInfo"] mutableCopy];
    sessionInfo[@"endTime"] = [NSDate date].description;
    _sessionData[@"sessionInfo"] = sessionInfo;
    
    // Converter para JSON e salvar
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:_sessionData
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:&error];
    
    if (error) {
        NSLog(@"[CameraDiagnostic] Erro ao converter sessão para JSON: %@", error);
    } else {
        [jsonData writeToFile:_currentSessionFile options:NSDataWritingAtomic error:&error];
        if (error) {
            NSLog(@"[CameraDiagnostic] Erro ao salvar arquivo de sessão: %@", error);
        } else {
            NSLog(@"[CameraDiagnostic] Sessão salva em: %@", _currentSessionFile);
            _hasWrittenToCurrentFile = NO;
        }
    }
    
    [_sessionLock unlock];
}

@end

#pragma mark - Funções C
void logMessage(NSString *message, LogLevel level, LogCategory category) {
    [[DiagnosticLogger sharedInstance] logMessage:message level:level category:category];
}

void logJSON(NSDictionary *jsonData, LogCategory category) {
    [[DiagnosticLogger sharedInstance] logJSONData:jsonData forCategory:category];
}

void logJSONWithDescription(NSDictionary *jsonData, LogCategory category, NSString *description) {
    [[DiagnosticLogger sharedInstance] logJSONData:jsonData forCategory:category withDescription:description];
}

void startNewLogSession(void) {
    [[DiagnosticLogger sharedInstance] startNewSession];
}

void finalizeLogSession(void) {
    [[DiagnosticLogger sharedInstance] finalizeSessionWithCompletion:nil];
}

void setLogSessionValue(NSString *key, id value) {
    [[DiagnosticLogger sharedInstance] setSessionValue:value forKey:key];
}
