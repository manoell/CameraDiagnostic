#import "logger.h"

static int gLogLevel = 3; // Valor padrão: aviso
static NSString *const kLogDirectory = @"CameraDiagnosticLogs";

void setLogLevel(int level) {
    gLogLevel = level;
}

void writeLog(NSString *format, ...) {
    // Se log estiver desativado, retorna imediatamente
    if (gLogLevel <= 0) return;
    
    @try {
        va_list args;
        va_start(args, format);
        NSString *formattedString = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);
        
        // Formatar a mensagem com timestamp
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
        NSString *timestamp = [dateFormatter stringFromDate:[NSDate date]];
        
        NSString *logMessage = [NSString stringWithFormat:@"[%@] %@\n", timestamp, formattedString];
        
        // Mostrar log no console (sempre)
        NSLog(@"[CameraDiagnostic] %@", formattedString);
        
        // Em modo debug ou superior, salvar em arquivo
        if (gLogLevel >= 4) {
            // Obter caminho para diretório de logs
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
            NSString *documentsDirectory = [paths firstObject];
            NSString *logsDirectory = [documentsDirectory stringByAppendingPathComponent:kLogDirectory];
            
            // Criar diretório se não existir
            NSFileManager *fileManager = [NSFileManager defaultManager];
            NSError *dirError;
            if (![fileManager fileExistsAtPath:logsDirectory]) {
                [fileManager createDirectoryAtPath:logsDirectory 
                       withIntermediateDirectories:YES 
                                        attributes:nil 
                                             error:&dirError];
                
                if (dirError) {
                    NSLog(@"[CameraDiagnostic] Erro ao criar diretório de logs: %@", [dirError localizedDescription]);
                    return;
                }
            }
            
            // Nome de arquivo com processo e data
            NSString *processName = [NSProcessInfo processInfo].processName;
            NSDateFormatter *fileDateFormatter = [[NSDateFormatter alloc] init];
            [fileDateFormatter setDateFormat:@"yyyyMMdd"];
            NSString *dateString = [fileDateFormatter stringFromDate:[NSDate date]];
            
            NSString *logFilename = [NSString stringWithFormat:@"%@_%@.log", processName, dateString];
            NSString *logPath = [logsDirectory stringByAppendingPathComponent:logFilename];
            
            // Escrever no arquivo (append)
            @try {
                NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
                
                if (!fileHandle) {
                    // Criar arquivo se não existir
                    NSError *fileError;
                    [logMessage writeToFile:logPath 
                                 atomically:YES 
                                   encoding:NSUTF8StringEncoding 
                                      error:&fileError];
                    
                    if (fileError) {
                        NSLog(@"[CameraDiagnostic] Erro ao criar arquivo de log: %@", [fileError localizedDescription]);
                    }
                } else {
                    // Adicionar ao arquivo existente
                    [fileHandle seekToEndOfFile];
                    [fileHandle writeData:[logMessage dataUsingEncoding:NSUTF8StringEncoding]];
                    [fileHandle closeFile];
                }
            } @catch (NSException *e) {
                NSLog(@"[CameraDiagnostic] Erro ao escrever log: %@", e);
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[CameraDiagnostic] ERRO NO LOGGER: %@", e);
    }
}