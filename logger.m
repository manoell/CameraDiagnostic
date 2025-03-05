#import "logger.h"

@interface Logger ()

@property (nonatomic, assign) BOOL logToConsole;
@property (nonatomic, assign) BOOL logToFile;
@property (nonatomic, strong) NSString *logFilePath;
@property (nonatomic, assign) LogLevel minimumLogLevel;
@property (nonatomic, strong) dispatch_queue_t loggingQueue;
@property (nonatomic, strong) NSFileHandle *logFileHandle;
@property (nonatomic, strong) NSDateFormatter *dateFormatter;

@end

@implementation Logger

#pragma mark - Singleton

+ (instancetype)sharedInstance {
    static Logger *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

#pragma mark - Inicialização

- (instancetype)init {
    self = [super init];
    if (self) {
        // Configuração padrão
        _logToConsole = YES;
        _logToFile = YES;
        _minimumLogLevel = LogLevelInfo;
        
        // Cria fila para logging thread-safe
        _loggingQueue = dispatch_queue_create("com.camera.diagnostic.logging", DISPATCH_QUEUE_SERIAL);
        
        // Configura formatador de data
        _dateFormatter = [[NSDateFormatter alloc] init];
        [_dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
        
        // Configura caminho do arquivo
        NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        _logFilePath = [documentsPath stringByAppendingPathComponent:@"camera_diagnostic.log"];
        
        // Inicializa arquivo de log
        [self setupLogFile];
        
        // Log inicial
        [self logInfo:@"=== Logger inicializado ==="];
        [self logInfo:@"Caminho do Log: %@", _logFilePath];
    }
    return self;
}

- (void)dealloc {
    // Fecha o arquivo de log
    if (_logFileHandle) {
        [_logFileHandle closeFile];
        _logFileHandle = nil;
    }
}

#pragma mark - Configuração

- (void)setLogToConsole:(BOOL)logToConsole {
    _logToConsole = logToConsole;
}

- (void)setLogToFile:(BOOL)logToFile {
    _logToFile = logToFile;
    
    // Se acabamos de ativar o log para arquivo, configure o arquivo
    if (logToFile && !_logFileHandle) {
        [self setupLogFile];
    }
}

- (void)setLogFilePath:(NSString *)filePath {
    if ([_logFilePath isEqualToString:filePath]) {
        return;
    }
    
    _logFilePath = [filePath copy];
    
    // Reinicia o arquivo de log
    if (_logToFile) {
        [self setupLogFile];
    }
}

- (void)setMinimumLogLevel:(LogLevel)level {
    _minimumLogLevel = level;
}

- (NSString *)getLogFilePath {
    return _logFilePath;
}

- (void)clearLogFile {
    dispatch_sync(_loggingQueue, ^{
        // Fecha o arquivo existente
        if (_logFileHandle) {
            [_logFileHandle closeFile];
            _logFileHandle = nil;
        }
        
        // Sobrescreve com string vazia
        [@"" writeToFile:_logFilePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        
        // Reabre o arquivo
        [self setupLogFile];
        
        [self logInfo:@"=== Arquivo de log limpo ==="];
    });
}

#pragma mark - Log File Management

- (void)setupLogFile {
    dispatch_sync(_loggingQueue, ^{
        // Fecha o arquivo existente
        if (_logFileHandle) {
            [_logFileHandle closeFile];
            _logFileHandle = nil;
        }
        
        // Cria arquivo se não existir
        if (![[NSFileManager defaultManager] fileExistsAtPath:_logFilePath]) {
            [[NSFileManager defaultManager] createFileAtPath:_logFilePath contents:nil attributes:nil];
        }
        
        // Abre o arquivo para escrita
        NSError *error = nil;
        _logFileHandle = [NSFileHandle fileHandleForWritingToURL:[NSURL fileURLWithPath:_logFilePath] error:&error];
        
        if (!_logFileHandle) {
            NSLog(@"Erro ao abrir arquivo de log: %@", error);
        } else {
            [_logFileHandle seekToEndOfFile];
        }
    });
}

#pragma mark - Métodos de Log

- (void)logWithLevel:(LogLevel)level format:(NSString *)format args:(va_list)args {
    // Ignora se o nível for menor que o mínimo
    if (level < _minimumLogLevel) {
        return;
    }
    
    // Formata a mensagem
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    
    // String de nível
    NSString *levelString;
    switch (level) {
        case LogLevelDebug:
            levelString = @"[DEBUG]";
            break;
        case LogLevelInfo:
            levelString = @"[INFO]";
            break;
        case LogLevelWarning:
            levelString = @"[WARN]";
            break;
        case LogLevelError:
            levelString = @"[ERROR]";
            break;
        default:
            levelString = @"[LOG]";
            break;
    }
    
    // Data e hora
    NSString *timestamp = [_dateFormatter stringFromDate:[NSDate date]];
    
    // Cria linha completa
    NSString *logLine = [NSString stringWithFormat:@"%@ %@ %@\n", timestamp, levelString, message];
    
    // Envia para a fila de logging
    dispatch_async(_loggingQueue, ^{
        // Log para console
        if (_logToConsole) {
            NSLog(@"%@", logLine);
        }
        
        // Log para arquivo
        if (_logToFile && _logFileHandle) {
            NSData *logData = [logLine dataUsingEncoding:NSUTF8StringEncoding];
            [_logFileHandle writeData:logData];
            [_logFileHandle synchronizeFile];
        }
    });
}

- (void)logDebug:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    [self logWithLevel:LogLevelDebug format:format args:args];
    va_end(args);
}

- (void)logInfo:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    [self logWithLevel:LogLevelInfo format:format args:args];
    va_end(args);
}

- (void)logWarning:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    [self logWithLevel:LogLevelWarning format:format args:args];
    va_end(args);
}

- (void)logError:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    [self logWithLevel:LogLevelError format:format args:args];
    va_end(args);
}

@end
