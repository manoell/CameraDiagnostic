// CameraDiagnosticFramework.m

#import "CameraDiagnosticFramework.h"
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import "IOSurface.h"
#import "logger.h"

@interface CameraDiagnosticFramework ()

@property (nonatomic, strong) NSFileHandle *logFileHandle;
@property (nonatomic, assign) CameraDiagnosticLogLevel logLevel;
@property (nonatomic, assign) BOOL isLoggingToFile;
@property (nonatomic, strong) NSString *logFilePath;
@property (nonatomic, strong) NSMutableArray *activeCaptureSessions;
@property (nonatomic, strong) NSMutableDictionary *methodSwizzleOriginals;
@property (nonatomic, strong) NSMutableArray *detectedVideoOutputDelegates;
@property (nonatomic, strong) NSMutableDictionary *delegateMethodCallStats;
@property (nonatomic, strong) NSMutableDictionary *sessionConfigurations;
@property (nonatomic, strong) NSMutableDictionary *criticalPoints;
@property (nonatomic, strong) NSDate *startTime;

@end

@implementation CameraDiagnosticFramework

#pragma mark - Singleton

+ (instancetype)sharedInstance {
    static CameraDiagnosticFramework *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _logLevel = CameraDiagnosticLogLevelInfo;
        _isLoggingToFile = NO;
        _activeCaptureSessions = [NSMutableArray new];
        _methodSwizzleOriginals = [NSMutableDictionary new];
        _detectedVideoOutputDelegates = [NSMutableArray new];
        _delegateMethodCallStats = [NSMutableDictionary new];
        _sessionConfigurations = [NSMutableDictionary new];
        _criticalPoints = [NSMutableDictionary new];
        
        // Preparar diretório de logs
        NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        _logFilePath = [documentsPath stringByAppendingPathComponent:@"camera_diagnostic.log"];
        _startTime = [NSDate date];
    }
    return self;
}

#pragma mark - Configuração

- (void)startDiagnosticWithLogLevel:(CameraDiagnosticLogLevel)level {
    self.logLevel = level;
    
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"CameraDiagnosticFramework iniciado em %@", [NSDate date]];
    
    // Se estiver logando para arquivo, abrir arquivo
    if (self.isLoggingToFile) {
        [self setupLogFile];
    }
    
    // Iniciar o monitoramento
    [self hookCameraAPIs];
    
    // Analisar a configuração atual
    [self dumpCameraConfiguration];
    
    // Observar notificações
    [self setupNotificationObservers];
    
    // Definir timer para análise periódica
    [NSTimer scheduledTimerWithTimeInterval:10.0
                                     target:self
                                   selector:@selector(periodicAnalysis)
                                   userInfo:nil
                                    repeats:YES];
}

- (void)periodicAnalysis {
    // Análise periódica de todos os dados coletados
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"Executando análise periódica..."];
    
    // Analisar sessões ativas
    [self analyzeActiveCaptureSessions];
    
    // Analisar delegados detectados
    [self analyzeVideoDataOutputs];
    
    // Identificar pontos críticos
    [self identifyCriticalInterceptionPoints];
}

- (void)stopDiagnostic {
    // Remover observadores
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // Fechar arquivo se necessário
    if (self.logFileHandle) {
        [self.logFileHandle closeFile];
        self.logFileHandle = nil;
    }
    
    // Criar relatório final
    [self generateFinalReport];
    
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"CameraDiagnosticFramework finalizado. Duração total: %f segundos",
                       [[NSDate date] timeIntervalSinceDate:self.startTime]];
}

- (void)generateFinalReport {
    NSMutableString *report = [NSMutableString string];
    
    [report appendString:@"====== RELATÓRIO DE DIAGNÓSTICO DE CÂMERA ======\n\n"];
    [report appendFormat:@"Horário de início: %@\n", self.startTime];
    [report appendFormat:@"Aplicativo: %@\n", [[NSBundle mainBundle] bundleIdentifier]];
    [report appendFormat:@"iOS: %@\n", [UIDevice currentDevice].systemVersion];
    [report appendFormat:@"Dispositivo: %@\n\n", [UIDevice currentDevice].model];
    
    // Resumo das sessões detectadas
    [report appendFormat:@"Sessões de câmera detectadas: %lu\n", (unsigned long)self.activeCaptureSessions.count];
    [report appendFormat:@"Delegados detectados: %lu\n\n", (unsigned long)self.detectedVideoOutputDelegates.count];
    
    // Pontos críticos para interceptação
    [report appendString:@"=== PONTOS CRÍTICOS PARA INTERCEPTAÇÃO ===\n"];
    NSArray *pointKeys = [self.criticalPoints.allKeys sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        NSNumber *score1 = self.criticalPoints[obj1][@"score"];
        NSNumber *score2 = self.criticalPoints[obj2][@"score"];
        return [score2 compare:score1]; // Ordem decrescente
    }];
    
    for (NSString *key in pointKeys) {
        NSDictionary *point = self.criticalPoints[key];
        [report appendFormat:@"- PONTO: %@\n", key];
        [report appendFormat:@"  Pontuação: %@\n", point[@"score"]];
        [report appendFormat:@"  Razão: %@\n", point[@"reason"]];
        [report appendFormat:@"  Notas: %@\n\n", point[@"notes"]];
    }
    
    // Estatísticas de delegados
    [report appendString:@"=== ESTATÍSTICAS DE DELEGADOS ===\n"];
    for (NSString *delegateClass in self.delegateMethodCallStats) {
        NSDictionary *stats = self.delegateMethodCallStats[delegateClass];
        [report appendFormat:@"- Delegado: %@\n", delegateClass];
        
        for (NSString *method in stats) {
            NSNumber *callCount = stats[method];
            [report appendFormat:@"  - %@: %@ chamadas\n", method, callCount];
        }
        [report appendString:@"\n"];
    }
    
    // Configurações de sessão
    [report appendString:@"=== CONFIGURAÇÕES DE SESSÃO ===\n"];
    for (NSString *sessionKey in self.sessionConfigurations) {
        NSDictionary *config = self.sessionConfigurations[sessionKey];
        [report appendFormat:@"- Sessão: %@\n", sessionKey];
        
        // Inputs
        NSArray *inputs = config[@"inputs"];
        if (inputs) {
            [report appendFormat:@"  Inputs: %lu\n", (unsigned long)inputs.count];
            for (NSDictionary *input in inputs) {
                [report appendFormat:@"   - %@\n", input[@"description"]];
            }
        }
        
        // Outputs
        NSArray *outputs = config[@"outputs"];
        if (outputs) {
            [report appendFormat:@"  Outputs: %lu\n", (unsigned long)outputs.count];
            for (NSDictionary *output in outputs) {
                [report appendFormat:@"   - %@\n", output[@"description"]];
                
                // Delegados de saída de vídeo - CRÍTICO para identificar ponto de interceptação
                if (output[@"delegate"]) {
                    [report appendFormat:@"     Delegate: %@\n", output[@"delegate"]];
                    
                    if ([output[@"hasIOSurface"] boolValue]) {
                        [report appendFormat:@"     ⭐️ USA IOSURFACE - PONTO IDEAL PARA INTERCEPTAÇÃO ⭐️\n"];
                    }
                }
            }
        }
    }
    
    // Salvar relatório em arquivo
    NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *reportPath = [documentsPath stringByAppendingPathComponent:@"camera_diagnostic_report.txt"];
    [report writeToFile:reportPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"Relatório final gerado em: %@", reportPath];
}

- (void)identifyCriticalInterceptionPoints {
    // Identificar e pontuar possíveis pontos de interceptação
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"Identificando pontos críticos para interceptação..."];
    
    // 1. Delegados de AVCaptureVideoDataOutput
    for (id delegate in self.detectedVideoOutputDelegates) {
        NSString *delegateClass = NSStringFromClass([delegate class]);
        NSString *key = [NSString stringWithFormat:@"Delegate_%@", delegateClass];
        
        // Verificar se este delegado é usado com frequência
        NSDictionary *stats = self.delegateMethodCallStats[delegateClass];
        NSInteger callCount = [[stats objectForKey:@"captureOutput:didOutputSampleBuffer:fromConnection:"] integerValue];
        
        if (callCount > 0) {
            NSMutableDictionary *pointInfo = [NSMutableDictionary dictionary];
            pointInfo[@"type"] = @"AVCaptureVideoDataOutputSampleBufferDelegate";
            pointInfo[@"class"] = delegateClass;
            pointInfo[@"callCount"] = @(callCount);
            
            // Pontuação baseada em frequência de uso e padrões detectados
            float score = 0.7f; // Base score para delegados
            
            // Ajuste baseado em frequência de chamadas
            if (callCount > 100) score += 0.1f;
            if (callCount > 500) score += 0.1f;
            
            // Ajuste baseado em associação com IOSurface
            BOOL usesIOSurface = NO;
            for (NSString *sessionKey in self.sessionConfigurations) {
                NSDictionary *config = self.sessionConfigurations[sessionKey];
                NSArray *outputs = config[@"outputs"];
                for (NSDictionary *output in outputs) {
                    if ([output[@"delegate"] isEqualToString:delegateClass] &&
                        [output[@"hasIOSurface"] boolValue]) {
                        usesIOSurface = YES;
                        break;
                    }
                }
                if (usesIOSurface) break;
            }
            
            if (usesIOSurface) {
                score += 0.3f;
                pointInfo[@"usesIOSurface"] = @YES;
                pointInfo[@"reason"] = @"Delegado de buffer que utiliza IOSurface";
                pointInfo[@"notes"] = @"Este delegado processa buffers com IOSurface, altamente promissor para substituição universal";
            } else {
                pointInfo[@"usesIOSurface"] = @NO;
                pointInfo[@"reason"] = @"Delegado frequente de buffer de câmera";
                pointInfo[@"notes"] = @"Ponto potencial de interceptação, mas não utiliza IOSurface diretamente";
            }
            
            pointInfo[@"score"] = @(score);
            
            self.criticalPoints[key] = pointInfo;
            
            [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                               format:@"Ponto crítico identificado: %@ (Score: %.2f)", key, score];
        }
    }
    
    // 2. Identificar pontos de criação de buffer (CVPixelBufferPool)
    BOOL foundPixelBufferPool = NO;
    for (NSString *sessionKey in self.sessionConfigurations) {
        NSDictionary *config = self.sessionConfigurations[sessionKey];
        if ([config[@"usesPixelBufferPool"] boolValue]) {
            foundPixelBufferPool = YES;
            break;
        }
    }
    
    if (foundPixelBufferPool) {
        NSString *key = @"CVPixelBufferPoolCreatePixelBuffer";
        NSMutableDictionary *pointInfo = [NSMutableDictionary dictionary];
        pointInfo[@"type"] = @"CoreVideo API";
        pointInfo[@"function"] = key;
        pointInfo[@"reason"] = @"Ponto central de criação de buffers via pool";
        pointInfo[@"notes"] = @"Hook em CVPixelBufferPoolCreatePixelBuffer permitiria substituição em nível de API - altamente universal";
        pointInfo[@"score"] = @(0.95f); // Score alto por ser universal
        
        self.criticalPoints[key] = pointInfo;
        
        [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                           format:@"Ponto crítico identificado: %@ (Score: 0.95)", key];
    }
    
    // 3. IOSurface como mecanismo de transferência
    BOOL foundIOSurface = NO;
    for (NSString *sessionKey in self.sessionConfigurations) {
        NSDictionary *config = self.sessionConfigurations[sessionKey];
        NSArray *outputs = config[@"outputs"];
        for (NSDictionary *output in outputs) {
            if ([output[@"hasIOSurface"] boolValue]) {
                foundIOSurface = YES;
                break;
            }
        }
        if (foundIOSurface) break;
    }
    
    if (foundIOSurface) {
        NSString *key = @"CVPixelBufferCreateWithIOSurface";
        NSMutableDictionary *pointInfo = [NSMutableDictionary dictionary];
        pointInfo[@"type"] = @"CoreVideo API";
        pointInfo[@"function"] = key;
        pointInfo[@"reason"] = @"Ponto crítico para transferência entre processos via IOSurface";
        pointInfo[@"notes"] = @"Hook em CVPixelBufferCreateWithIOSurface oferece substituição universal em nível de sistema";
        pointInfo[@"score"] = @(0.98f); // Score muito alto - possivelmente o melhor ponto
        
        self.criticalPoints[key] = pointInfo;
        
        [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                           format:@"Ponto crítico identificado: %@ (Score: 0.98)", key];
    }
}

- (void)setLogToFile:(BOOL)logToFile {
    self.isLoggingToFile = logToFile;
    
    if (logToFile && !self.logFileHandle) {
        [self setupLogFile];
    }
}

- (void)setLogFilePath:(NSString *)path {
    self.logFilePath = path;
    
    // Se já estiver logando, reconfigurar o arquivo
    if (self.isLoggingToFile) {
        if (self.logFileHandle) {
            [self.logFileHandle closeFile];
            self.logFileHandle = nil;
        }
        [self setupLogFile];
    }
}

- (void)setupLogFile {
    // Apagar arquivo anterior se existir
    [[NSFileManager defaultManager] removeItemAtPath:self.logFilePath error:nil];
    
    // Criar novo arquivo
    [[NSFileManager defaultManager] createFileAtPath:self.logFilePath contents:nil attributes:nil];
    
    // Abrir para escrita
    self.logFileHandle = [NSFileHandle fileHandleForWritingAtPath:self.logFilePath];
}

- (void)setupNotificationObservers {
    // Notificações sobre sessões de captura
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(captureSessionRuntimeError:)
                                                 name:AVCaptureSessionRuntimeErrorNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(captureSessionDidStartRunning:)
                                                 name:AVCaptureSessionDidStartRunningNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(captureSessionDidStopRunning:)
                                                 name:AVCaptureSessionDidStopRunningNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(captureSessionWasInterrupted:)
                                                 name:AVCaptureSessionWasInterruptedNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(captureSessionInterruptionEnded:)
                                                 name:AVCaptureSessionInterruptionEndedNotification
                                               object:nil];
    
    // Notificações sobre aplicativo entrando em background/foreground
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive:)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive:)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
}

#pragma mark - Notification Handlers

- (void)captureSessionRuntimeError:(NSNotification *)notification {
    AVCaptureSession *session = notification.object;
    NSError *error = notification.userInfo[AVCaptureSessionErrorKey];
    
    [self logMessageWithLevel:CameraDiagnosticLogLevelError
                       format:@"AVCaptureSession runtime error: %@ (Session: %p)", error, session];
}

- (void)captureSessionDidStartRunning:(NSNotification *)notification {
    AVCaptureSession *session = notification.object;
    
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"⭐️ AVCaptureSession started running: %p", session];
    
    if (![self.activeCaptureSessions containsObject:session]) {
        [self.activeCaptureSessions addObject:session];
    }
    
    // Analisar a sessão em detalhes
    [self analyzeSession:session];
}

- (void)captureSessionDidStopRunning:(NSNotification *)notification {
    AVCaptureSession *session = notification.object;
    
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"AVCaptureSession stopped running: %p", session];
    
    [self.activeCaptureSessions removeObject:session];
}

- (void)captureSessionWasInterrupted:(NSNotification *)notification {
    AVCaptureSession *session = notification.object;
    AVCaptureSessionInterruptionReason reason = [notification.userInfo[AVCaptureSessionInterruptionReasonKey] integerValue];
    
    NSString *reasonStr = @"Unknown";
    if (reason == AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableInBackground) {
        reasonStr = @"Video device not available in background";
    } else if (reason == AVCaptureSessionInterruptionReasonAudioDeviceInUseByAnotherClient) {
        reasonStr = @"Audio device in use by another client";
    } else if (reason == AVCaptureSessionInterruptionReasonVideoDeviceInUseByAnotherClient) {
        reasonStr = @"Video device in use by another client";
    } else if (reason == AVCaptureSessionInterruptionReasonVideoDeviceNotAvailableWithMultipleForegroundApps) {
        reasonStr = @"Video device not available with multiple foreground apps";
    }
    
    [self logMessageWithLevel:CameraDiagnosticLogLevelWarning
                       format:@"AVCaptureSession %p was interrupted. Reason: %@", session, reasonStr];
    
    // Se for interrompido por outro cliente usando o dispositivo, isso é uma informação importante
    if (reason == AVCaptureSessionInterruptionReasonVideoDeviceInUseByAnotherClient) {
        [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                           format:@"⭐️ Possível ponto de observação: outro cliente usando o dispositivo de vídeo"];
    }
}

- (void)captureSessionInterruptionEnded:(NSNotification *)notification {
    AVCaptureSession *session = notification.object;
    
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"AVCaptureSession interruption ended for session: %p", session];
}

- (void)applicationWillResignActive:(NSNotification *)notification {
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"Application will resign active. Current active sessions: %lu",
     (unsigned long)self.activeCaptureSessions.count];
}

- (void)applicationDidBecomeActive:(NSNotification *)notification {
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"Application did become active. Current active sessions: %lu",
     (unsigned long)self.activeCaptureSessions.count];
    
    // Bom momento para analisar as sessões ativas
    [self analyzeActiveCaptureSessions];
    [self detectApplicationUsingCamera];
}

#pragma mark - Hook para swizzling de métodos

- (void)hookCameraAPIs {
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"Instalando hooks focados em diagnóstico de câmera..."];
    
    // Focamos apenas nos hooks mais críticos para o diagnóstico
    [self hookAVCaptureVideoDataOutput];
    [self hookAVCaptureSession];
}

- (void)hookAVCaptureSession {
    [self logMessageWithLevel:CameraDiagnosticLogLevelDebug
                       format:@"Instalando hook em AVCaptureSession..."];
    
    // Métodos mais importantes de AVCaptureSession
    [self swizzleMethodForClass:[AVCaptureSession class]
                    originalSel:@selector(startRunning)
                     swizzledSel:@selector(diagnosticStartRunning)];
    
    [self swizzleMethodForClass:[AVCaptureSession class]
                    originalSel:@selector(stopRunning)
                     swizzledSel:@selector(diagnosticStopRunning)];
    
    [self swizzleMethodForClass:[AVCaptureSession class]
                    originalSel:@selector(addInput:)
                     swizzledSel:@selector(diagnosticAddInput:)];
    
    [self swizzleMethodForClass:[AVCaptureSession class]
                    originalSel:@selector(addOutput:)
                     swizzledSel:@selector(diagnosticAddOutput:)];
}

- (void)hookAVCaptureVideoDataOutput {
    [self logMessageWithLevel:CameraDiagnosticLogLevelDebug
                       format:@"Instalando hook em AVCaptureVideoDataOutput..."];
    
    // Hook para setSampleBufferDelegate - CRÍTICO
    [self swizzleMethodForClass:[AVCaptureVideoDataOutput class]
                    originalSel:@selector(setSampleBufferDelegate:queue:)
                     swizzledSel:@selector(diagnosticSetSampleBufferDelegate:queue:)];
    
    // Analisar classes que implementam o protocolo
    Protocol *protocolObj = @protocol(AVCaptureVideoDataOutputSampleBufferDelegate);
    if (protocolObj) {
        [self logMessageWithLevel:CameraDiagnosticLogLevelDebug
                           format:@"Identificando classes que implementam AVCaptureVideoDataOutputSampleBufferDelegate"];
        
        unsigned int count;
        Class *classes = objc_copyClassList(&count);
        
        for (unsigned int i = 0; i < count; i++) {
            if (class_conformsToProtocol(classes[i], protocolObj)) {
                [self logMessageWithLevel:CameraDiagnosticLogLevelDebug
                                   format:@"Classe %s implementa AVCaptureVideoDataOutputSampleBufferDelegate",
                 class_getName(classes[i])];
                
                // Hook do método didOutputSampleBuffer - crucial para interceptação
                if (class_getInstanceMethod(classes[i], @selector(captureOutput:didOutputSampleBuffer:fromConnection:))) {
                    [self swizzleMethodForClass:classes[i]
                                    originalSel:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)
                                     swizzledSel:@selector(diagnosticCaptureOutput:didOutputSampleBuffer:fromConnection:)];
                }
            }
        }
        
        free(classes);
    }
}

- (void)swizzleMethodForClass:(Class)cls originalSel:(SEL)originalSel swizzledSel:(SEL)swizzledSel {
    Method originalMethod = class_getInstanceMethod(cls, originalSel);
    Method swizzledMethod = class_getInstanceMethod([self class], swizzledSel);
    
    if (!originalMethod || !swizzledMethod) {
        [self logMessageWithLevel:CameraDiagnosticLogLevelError
                           format:@"Falha ao swizzle %@ (%p) -> %@ (%p)",
         NSStringFromSelector(originalSel), originalMethod,
         NSStringFromSelector(swizzledSel), swizzledMethod];
        return;
    }
    
    // Armazena o método original para referência
    NSString *key = [NSString stringWithFormat:@"%@_%@",
                     NSStringFromClass(cls), NSStringFromSelector(originalSel)];
    [self.methodSwizzleOriginals setObject:[NSValue valueWithPointer:originalMethod] forKey:key];
    
    // Adiciona o método swizzled à classe original
    BOOL addedMethod = class_addMethod(cls,
                                       swizzledSel,
                                       method_getImplementation(swizzledMethod),
                                       method_getTypeEncoding(swizzledMethod));
    
    if (addedMethod) {
        // Se o método foi adicionado com sucesso, substitui o método original
        Method newMethod = class_getInstanceMethod(cls, swizzledSel);
        method_exchangeImplementations(originalMethod, newMethod);
        [self logMessageWithLevel:CameraDiagnosticLogLevelDebug
                           format:@"Método swizzled com sucesso: %@ em %@",
         NSStringFromSelector(originalSel), NSStringFromClass(cls)];
    } else {
        [self logMessageWithLevel:CameraDiagnosticLogLevelError
                           format:@"Falha ao adicionar método swizzled %@ para %@",
         NSStringFromSelector(swizzledSel), NSStringFromClass(cls)];
    }
}

#pragma mark - Diagnóstico específico

- (void)dumpCameraConfiguration {
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"Analisando configuração da câmera..."];
    
    // Dispositivos disponíveis
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"Dispositivos de câmera disponíveis: %lu", (unsigned long)devices.count];
    
    for (AVCaptureDevice *device in devices) {
        [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                           format:@"Dispositivo: %@, Posição: %ld, Fornece formatos: %lu",
         device.localizedName, (long)device.position, (unsigned long)device.formats.count];
        
        // Focar apenas nos formatos mais prováveis para serem usados
        for (AVCaptureDeviceFormat *format in device.formats) {
            CMFormatDescriptionRef formatDescription = format.formatDescription;
            CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
            
            // Verificar se este é um formato de resolução comum para câmera
            if ((dimensions.width == 1920 && dimensions.height == 1080) || // Full HD
                (dimensions.width == 1280 && dimensions.height == 720) ||  // HD
                (dimensions.width == 3840 && dimensions.height == 2160)) { // 4K
                
                FourCharCode fourCharCode = CMFormatDescriptionGetMediaSubType(formatDescription);
                char fourCC[5] = {0};
                fourCC[0] = (fourCharCode >> 24) & 0xFF;
                fourCC[1] = (fourCharCode >> 16) & 0xFF;
                fourCC[2] = (fourCharCode >> 8) & 0xFF;
                fourCC[3] = fourCharCode & 0xFF;
                
                [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                                   format:@"  Formato relevante: %dx%d, FourCC: %s",
                 dimensions.width, dimensions.height, fourCC];
                
                // Verificar extensões do formato que podem ser relevantes
                CFDictionaryRef extensions = CMFormatDescriptionGetExtensions(formatDescription);
                if (extensions) {
                    NSDictionary *extDict = (__bridge NSDictionary *)extensions;
                    for (NSString *key in extDict) {
                        if ([key containsString:@"IOSurface"] ||
                            [key containsString:@"PixelBuffer"] ||
                            [key containsString:@"Pool"]) {
                            [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                                               format:@"    🔍 Extensão relevante: %@ = %@", key, extDict[key]];
                        }
                    }
                }
            }
        }
    }
    
    // Verificar autorização
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    NSString *authStatusStr = @"Unknown";
    switch (authStatus) {
        case AVAuthorizationStatusAuthorized:
            authStatusStr = @"Authorized";
            break;
        case AVAuthorizationStatusDenied:
            authStatusStr = @"Denied";
            break;
        case AVAuthorizationStatusRestricted:
            authStatusStr = @"Restricted";
            break;
        case AVAuthorizationStatusNotDetermined:
            authStatusStr = @"NotDetermined";
            break;
    }
    
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"Status de autorização da câmera: %@", authStatusStr];
}

- (void)analyzeActiveCaptureSessions {
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"Analisando %lu sessões de captura ativas...",
     (unsigned long)self.activeCaptureSessions.count];
    
    for (AVCaptureSession *session in self.activeCaptureSessions) {
        [self analyzeSession:session];
    }
}

- (void)analyzeSession:(AVCaptureSession *)session {
    if (!session) return;
    
    NSString *sessionKey = [NSString stringWithFormat:@"%p", session];
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"Analisando sessão: %@", sessionKey];
    
    NSMutableDictionary *sessionConfig = [NSMutableDictionary dictionary];
    sessionConfig[@"preset"] = session.sessionPreset;
    sessionConfig[@"running"] = @(session.isRunning);
    
    // Inputs - focando em detalhes importantes
    NSMutableArray *inputConfigs = [NSMutableArray array];
    for (AVCaptureInput *input in session.inputs) {
        NSMutableDictionary *inputConfig = [NSMutableDictionary dictionary];
        
        if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
            AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
            AVCaptureDevice *device = deviceInput.device;
            
            inputConfig[@"deviceName"] = device.localizedName;
            inputConfig[@"position"] = @(device.position);
            inputConfig[@"uniqueID"] = device.uniqueID;
            
            // Verificar formato ativo para informações sobre pixel buffer
            AVCaptureDeviceFormat *activeFormat = device.activeFormat;
            CMFormatDescriptionRef formatDesc = activeFormat.formatDescription;
            if (formatDesc) {
                CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDesc);
                inputConfig[@"width"] = @(dimensions.width);
                inputConfig[@"height"] = @(dimensions.height);
                
                // Focar em extensões críticas
                CFDictionaryRef extensions = CMFormatDescriptionGetExtensions(formatDesc);
                if (extensions) {
                    NSDictionary *extDict = (__bridge NSDictionary *)extensions;
                    
                    // Verificar especificamente propriedades interessantes
                    id pixelBufferPool = extDict[@"kCMFormatDescriptionExtension_VerboseFormatDescription"];
                    if (pixelBufferPool) {
                        inputConfig[@"usesPixelBufferPool"] = @YES;
                        sessionConfig[@"usesPixelBufferPool"] = @YES;
                        [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                                           format:@"⭐️ Dispositivo usa pixel buffer pool: %@", device.localizedName];
                    }
                    
                    // Verificar outras extensões relevantes
                    for (NSString *key in extDict) {
                        if ([key containsString:@"IOSurface"] ||
                            [key containsString:@"PixelBuffer"]) {
                            inputConfig[[NSString stringWithFormat:@"extension_%@", key]] = extDict[key];
                        }
                    }
                }
            }
        }
        
        inputConfig[@"description"] = [input description];
        [inputConfigs addObject:inputConfig];
    }
    sessionConfig[@"inputs"] = inputConfigs;
    
    // Outputs - CRÍTICO para interceptação
    NSMutableArray *outputConfigs = [NSMutableArray array];
    for (AVCaptureOutput *output in session.outputs) {
        NSMutableDictionary *outputConfig = [NSMutableDictionary dictionary];
        outputConfig[@"type"] = NSStringFromClass([output class]);
        
        if ([output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
            AVCaptureVideoDataOutput *videoOutput = (AVCaptureVideoDataOutput *)output;
            
            // CRÍTICO: Delegado, configurações e conexões
            id<AVCaptureVideoDataOutputSampleBufferDelegate> delegate = videoOutput.sampleBufferDelegate;
            if (delegate) {
                NSString *delegateClass = NSStringFromClass([delegate class]);
                outputConfig[@"delegate"] = delegateClass;
                
                // Registrar o delegado para análise
                if (![self.detectedVideoOutputDelegates containsObject:delegate]) {
                    [self.detectedVideoOutputDelegates addObject:delegate];
                }
                
                [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                                   format:@"⭐️ Detectado delegado de saída de vídeo: %@", delegateClass];
            }
            
            // Configurações de vídeo
            NSDictionary *settings = videoOutput.videoSettings;
            if (settings) {
                outputConfig[@"videoSettings"] = settings;
                
                // Verificar uso de IOSurface
                id ioSurfaceProperties = settings[@"kCVPixelBufferIOSurfacePropertiesKey"];
                if (ioSurfaceProperties) {
                    outputConfig[@"hasIOSurface"] = @YES;
                    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                                       format:@"⭐️ Output usa IOSurface! Configurações: %@", ioSurfaceProperties];
                } else {
                    outputConfig[@"hasIOSurface"] = @NO;
                }
                
                // Verificar propriedades de pixel buffer
                id pixelBufferPoolOptions = settings[@"kCVPixelBufferPoolAllocationThresholdKey"];
                if (pixelBufferPoolOptions) {
                    outputConfig[@"usesPixelBufferPool"] = @YES;
                    sessionConfig[@"usesPixelBufferPool"] = @YES;
                }
            }
            
            // Conexões - pode revelar caminhos de fluxo de dados
            NSMutableArray *connectionConfigs = [NSMutableArray array];
            for (AVCaptureConnection *connection in videoOutput.connections) {
                NSMutableDictionary *connConfig = [NSMutableDictionary dictionary];
                connConfig[@"enabled"] = @(connection.enabled);
                
                if ([connection isVideoOrientationSupported]) {
                    connConfig[@"videoOrientation"] = @(connection.videoOrientation);
                }
                
                if ([connection isVideoMirroringSupported]) {
                    connConfig[@"videoMirrored"] = @(connection.isVideoMirrored);
                }
                
                // Entrada ligada a esta conexão (fonte de dados)
                NSMutableArray *inputPorts = [NSMutableArray array];
                for (AVCaptureInputPort *port in connection.inputPorts) {
                    [inputPorts addObject:@{
                        @"mediaType": port.mediaType ?: @"unknown",
                        @"sourceDevicePosition": @([port.input isKindOfClass:[AVCaptureDeviceInput class]] ?
                                                   ((AVCaptureDeviceInput*)port.input).device.position : -1)
                    }];
                }
                connConfig[@"inputPorts"] = inputPorts;
                
                [connectionConfigs addObject:connConfig];
            }
            outputConfig[@"connections"] = connectionConfigs;
        }
        
        outputConfig[@"description"] = [output description];
        [outputConfigs addObject:outputConfig];
    }
    sessionConfig[@"outputs"] = outputConfigs;
    
    // Armazenar configuração para análise posterior
    self.sessionConfigurations[sessionKey] = sessionConfig;
}

- (void)analyzeVideoDataOutputs {
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"Analisando delegados de saída de vídeo: %lu",
     (unsigned long)self.detectedVideoOutputDelegates.count];
    
    for (id<AVCaptureVideoDataOutputSampleBufferDelegate> delegate in self.detectedVideoOutputDelegates) {
        NSString *delegateClass = NSStringFromClass([delegate class]);
        
        BOOL implementsDidOutputSampleBuffer = [delegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)];
        BOOL implementsDidDropSampleBuffer = [delegate respondsToSelector:@selector(captureOutput:didDropSampleBuffer:fromConnection:)];
        
        [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                           format:@"Delegado: %@, implementa didOutputSampleBuffer: %d, didDropSampleBuffer: %d",
         delegateClass, implementsDidOutputSampleBuffer, implementsDidDropSampleBuffer];
        
        // Analisar a hierarquia de classes para entender funcionalidade
        NSMutableString *classHierarchy = [NSMutableString string];
        Class currentClass = [delegate class];
        while (currentClass) {
            [classHierarchy appendFormat:@"%s -> ", class_getName(currentClass)];
            currentClass = class_getSuperclass(currentClass);
        }
        [classHierarchy appendString:@"nil"];
        
        [self logMessageWithLevel:CameraDiagnosticLogLevelDebug
                           format:@"Hierarquia de classes: %@", classHierarchy];
        
        // Verificar para cada output se está usando este delegado
        for (NSString *sessionKey in self.sessionConfigurations) {
            NSDictionary *config = self.sessionConfigurations[sessionKey];
            NSArray *outputs = config[@"outputs"];
            
            for (NSDictionary *output in outputs) {
                if ([output[@"delegate"] isEqualToString:delegateClass]) {
                    BOOL usesIOSurface = [output[@"hasIOSurface"] boolValue];
                    
                    if (usesIOSurface) {
                        [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                                           format:@"⭐️ PONTO CRÍTICO: Delegado %@ usado com IOSurface", delegateClass];
                        
                        // Adicionar ao dicionário de pontos críticos
                        NSString *key = [NSString stringWithFormat:@"Delegate_%@", delegateClass];
                        if (!self.criticalPoints[key]) {
                            NSMutableDictionary *pointInfo = [NSMutableDictionary dictionary];
                            pointInfo[@"type"] = @"AVCaptureVideoDataOutputSampleBufferDelegate";
                            pointInfo[@"class"] = delegateClass;
                            pointInfo[@"usesIOSurface"] = @YES;
                            pointInfo[@"reason"] = @"Delegado de buffer associado a IOSurface";
                            pointInfo[@"notes"] = @"Ponto ideal para substituição universal através de IOSurface";
                            pointInfo[@"score"] = @(0.95f);
                            
                            self.criticalPoints[key] = pointInfo;
                        }
                    }
                }
            }
        }
    }
}

- (void)analyzeRenderPipeline {
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"Analisando pipeline de renderização..."];
    
    // Obter janela principal
    UIWindow *keyWindow = nil;
    
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *scenes = [[UIApplication sharedApplication] connectedScenes];
        for (UIScene *scene in scenes) {
            if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
                UIWindowScene *windowScene = (UIWindowScene *)scene;
                for (UIWindow *window in windowScene.windows) {
                    if (window.isKeyWindow) {
                        keyWindow = window;
                        break;
                    }
                }
                if (keyWindow) break;
            }
        }
    } else {
        keyWindow = [UIApplication sharedApplication].keyWindow;
    }
    
    if (!keyWindow) {
        [self logMessageWithLevel:CameraDiagnosticLogLevelWarning
                           format:@"Não foi possível encontrar a janela principal"];
        return;
    }
    
    // Procurar por visualizações relacionadas à câmera
    [self inspectViewHierarchy:keyWindow indent:0];
}

- (void)inspectViewHierarchy:(UIView *)view indent:(int)indent {
    NSMutableString *indentString = [NSMutableString string];
    for (int i = 0; i < indent; i++) {
        [indentString appendString:@"  "];
    }
    
    if ([view isKindOfClass:NSClassFromString(@"AVCaptureVideoPreviewLayer")] ||
        [view isKindOfClass:NSClassFromString(@"PLCameraView")] ||
        [view isKindOfClass:NSClassFromString(@"PLPreviewView")] ||
        [view isKindOfClass:NSClassFromString(@"CAMPreviewView")]) {
        
        [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                           format:@"%@⭐️ Visualização relacionada à câmera: %@",
         indentString, [view class]];
        
        // Analisar as camadas (CALayer)
        CALayer *layer = view.layer;
        [self inspectLayerHierarchy:layer indent:indent + 1];
    }
    
    // Recursivamente inspeciona subviews - apenas para alguns níveis para evitar log excessivo
    if (indent < 5) {
        for (UIView *subview in view.subviews) {
            [self inspectViewHierarchy:subview indent:indent + 1];
        }
    }
}

- (void)inspectLayerHierarchy:(CALayer *)layer indent:(int)indent {
    NSMutableString *indentString = [NSMutableString string];
    for (int i = 0; i < indent; i++) {
        [indentString appendString:@"  "];
    }
    
    if ([layer isKindOfClass:NSClassFromString(@"AVCaptureVideoPreviewLayer")]) {
        AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)layer;
        [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                           format:@"%@⭐️ AVCaptureVideoPreviewLayer: Sessão: %p, Orientação: %ld",
         indentString, previewLayer.session, (long)previewLayer.connection.videoOrientation];
        
        // Verificar a sessão associada
        if (previewLayer.session) {
            [self analyzeSession:previewLayer.session];
            
            // Se esta sessão não estiver na lista de sessões ativas, adicione-a
            if (![self.activeCaptureSessions containsObject:previewLayer.session]) {
                [self.activeCaptureSessions addObject:previewLayer.session];
            }
        }
    }
    
    // Recursivamente inspeciona apenas algumas camadas para evitar log excessivo
    if (indent < 7) {
        for (CALayer *sublayer in layer.sublayers) {
            [self inspectLayerHierarchy:sublayer indent:indent + 1];
        }
    }
}

- (void)detectApplicationUsingCamera {
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"Detectando aplicativo usando a câmera..."];
    
    // Obter o nome do aplicativo principal
    NSString *mainBundleID = [[NSBundle mainBundle] bundleIdentifier];
    NSString *appName = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?:
                        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
    
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"Aplicativo: %@ (%@)", appName, mainBundleID];
    
    // Verificar binários relacionados à câmera
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *imageName = _dyld_get_image_name(i);
        if (imageName) {
            NSString *name = [NSString stringWithUTF8String:imageName];
            
            // Filtrar apenas os binários relevantes
            if ([name containsString:@"Camera"] ||
                [name containsString:@"AVCapture"] ||
                [name containsString:@"CoreMedia"] ||
                [name containsString:@"VideoToolbox"]) {
                
                [self logMessageWithLevel:CameraDiagnosticLogLevelDebug
                                   format:@"Binário relevante: %@", name];
            }
        }
    }
}

#pragma mark - Análise de Buffer

- (void)analyzeBuffer:(CMSampleBufferRef)sampleBuffer fromOutput:(AVCaptureOutput *)output connection:(AVCaptureConnection *)connection {
    // Verificar o buffer para propriedades críticas de substituição
    if (!sampleBuffer || !CMSampleBufferIsValid(sampleBuffer)) {
        return;
    }
    
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"Analisando buffer da câmera..."];
    
    // 1. Verificar IOSurface - CRÍTICO para substituição
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (imageBuffer) {
        // Lock do buffer para acesso
        CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
        
        // Verificar IOSurface
        IOSurfaceRef surface = CVPixelBufferGetIOSurface(imageBuffer);
        if (surface) {
            uint32_t surfaceID = IOSurfaceGetID(surface);
            
            [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                               format:@"⭐️ Buffer usa IOSurface! ID: %u", surfaceID];
            
            // Verificar propriedades da IOSurface
            NSDictionary *props = (__bridge_transfer NSDictionary *)IOSurfaceCopyAllValues(surface);
            if (props) {
                for (NSString *key in props) {
                    if ([key containsString:@"Camera"] ||
                        [key containsString:@"VideoProcessing"]) {
                        [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                                           format:@"  Propriedade importante: %@ = %@", key, props[key]];
                    }
                }
            }
            
            // Registrar este ponto crítico
            NSString *key = @"CVPixelBufferCreateWithIOSurface";
            if (!self.criticalPoints[key]) {
                NSMutableDictionary *pointInfo = [NSMutableDictionary dictionary];
                pointInfo[@"type"] = @"CoreVideo API";
                pointInfo[@"function"] = key;
                pointInfo[@"reason"] = @"Ponto crítico para transferência entre processos via IOSurface";
                pointInfo[@"notes"] = @"Hook em CVPixelBufferCreateWithIOSurface oferece substituição universal em nível de sistema";
                pointInfo[@"score"] = @(0.98f);
                
                self.criticalPoints[key] = pointInfo;
            }
        }
        
        // Unlock do buffer
        CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
    }
    
    // 2. Verificar attachments do buffer
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, false);
    if (attachments && CFArrayGetCount(attachments) > 0) {
        CFDictionaryRef attachmentDict = (CFDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
        if (attachmentDict) {
            NSDictionary *attachs = (__bridge NSDictionary *)attachmentDict;
            
            // Verificar se há metadados relevantes
            for (NSString *key in attachs) {
                if ([key containsString:@"Camera"] ||
                    [key containsString:@"Source"] ||
                    [key containsString:@"Capture"]) {
                    
                    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                                       format:@"  Metadata relevante: %@ = %@", key, attachs[key]];
                }
            }
        }
    }
    
    // 3. Verificar formato
    CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
    if (formatDesc) {
        // Verificar extensões relevantes
        CFDictionaryRef extensions = CMFormatDescriptionGetExtensions(formatDesc);
        if (extensions) {
            NSDictionary *extDict = (__bridge NSDictionary *)extensions;
            
            for (NSString *key in extDict) {
                if ([key containsString:@"IOSurface"] ||
                    [key containsString:@"PixelBuffer"] ||
                    [key containsString:@"Pool"]) {
                    
                    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                                       format:@"  Extensão crítica: %@ = %@", key, extDict[key]];
                    
                    // Se usa pixel buffer pool, registre como ponto crítico
                    if ([key isEqualToString:@"PixelBufferPool"] ||
                        [key containsString:@"PixelBufferPool"]) {
                        
                        NSString *criticalKey = @"CVPixelBufferPoolCreatePixelBuffer";
                        if (!self.criticalPoints[criticalKey]) {
                            NSMutableDictionary *pointInfo = [NSMutableDictionary dictionary];
                            pointInfo[@"type"] = @"CoreVideo API";
                            pointInfo[@"function"] = criticalKey;
                            pointInfo[@"reason"] = @"Ponto central de criação de buffers via pool";
                            pointInfo[@"notes"] = @"Hook em CVPixelBufferPoolCreatePixelBuffer permitiria substituição em nível de API - altamente universal";
                            pointInfo[@"score"] = @(0.95f);
                            
                            self.criticalPoints[criticalKey] = pointInfo;
                        }
                    }
                }
            }
        }
    }
}

#pragma mark - Métodos Swizzled

- (void)diagnosticStartRunning {
    CameraDiagnosticFramework *diagnostic = [CameraDiagnosticFramework sharedInstance];
    [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelInfo
                             format:@"AVCaptureSession startRunning chamado: %@", self];
    
    // Chama o método original
    SEL originalSelector = @selector(startRunning);
    IMP originalImp = [diagnostic.methodSwizzleOriginals[[NSString stringWithFormat:@"%@_%@",
                                                          NSStringFromClass([self class]),
                                                          NSStringFromSelector(originalSelector)]] pointerValue];
    if (originalImp) {
        ((void(*)(id, SEL))originalImp)(self, originalSelector);
    }
    
    // Analisar a sessão
    [diagnostic analyzeSession:(AVCaptureSession *)self];
    
    // Incluir na lista de sessões ativas
    if (![diagnostic.activeCaptureSessions containsObject:self]) {
        [diagnostic.activeCaptureSessions addObject:self];
    }
}

- (void)diagnosticStopRunning {
    CameraDiagnosticFramework *diagnostic = [CameraDiagnosticFramework sharedInstance];
    [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelInfo
                             format:@"AVCaptureSession stopRunning chamado: %@", self];
    
    // Chama o método original
    SEL originalSelector = @selector(stopRunning);
    IMP originalImp = [diagnostic.methodSwizzleOriginals[[NSString stringWithFormat:@"%@_%@",
                                                          NSStringFromClass([self class]),
                                                          NSStringFromSelector(originalSelector)]] pointerValue];
    if (originalImp) {
        ((void(*)(id, SEL))originalImp)(self, originalSelector);
    }
    
    // Remover da lista de sessões ativas
    [diagnostic.activeCaptureSessions removeObject:self];
}

- (BOOL)diagnosticAddInput:(AVCaptureInput *)input {
    CameraDiagnosticFramework *diagnostic = [CameraDiagnosticFramework sharedInstance];
    
    NSString *deviceInfo = @"";
    if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
        AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
        deviceInfo = [NSString stringWithFormat:@" (Dispositivo: %@, Posição: %ld)",
                      deviceInput.device.localizedName, (long)deviceInput.device.position];
    }
    
    [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelInfo
                             format:@"AVCaptureSession addInput chamado: %@%@", input, deviceInfo];
    
    // Chama o método original
    SEL originalSelector = @selector(addInput:);
    IMP originalImp = [diagnostic.methodSwizzleOriginals[[NSString stringWithFormat:@"%@_%@",
                                                          NSStringFromClass([self class]),
                                                          NSStringFromSelector(originalSelector)]] pointerValue];
    BOOL result = NO;
    if (originalImp) {
        result = ((BOOL(*)(id, SEL, AVCaptureInput *))originalImp)(self, originalSelector, input);
    }
    
    // Atualizar configuração da sessão
    [diagnostic analyzeSession:(AVCaptureSession *)self];
    
    return result;
}

- (BOOL)diagnosticAddOutput:(AVCaptureOutput *)output {
    CameraDiagnosticFramework *diagnostic = [CameraDiagnosticFramework sharedInstance];
    
    NSString *outputInfo = @"";
    if ([output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
        outputInfo = @" (VideoDataOutput)";
    } else if ([output isKindOfClass:[AVCaptureMovieFileOutput class]]) {
        outputInfo = @" (MovieFileOutput)";
    } else if ([output isKindOfClass:[AVCaptureStillImageOutput class]]) {
        outputInfo = @" (StillImageOutput)";
    }
    
    [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelInfo
                             format:@"AVCaptureSession addOutput chamado: %@%@", output, outputInfo];
    
    // Chama o método original
    SEL originalSelector = @selector(addOutput:);
    IMP originalImp = [diagnostic.methodSwizzleOriginals[[NSString stringWithFormat:@"%@_%@",
                                                          NSStringFromClass([self class]),
                                                          NSStringFromSelector(originalSelector)]] pointerValue];
    BOOL result = NO;
    if (originalImp) {
        result = ((BOOL(*)(id, SEL, AVCaptureOutput *))originalImp)(self, originalSelector, output);
    }
    
    // Se for videoDataOutput, registre para análise detalhada
    if ([output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
        AVCaptureVideoDataOutput *videoOutput = (AVCaptureVideoDataOutput *)output;
        
        // Verificar configurações para IOSurface
        NSDictionary *settings = videoOutput.videoSettings;
        if (settings && settings[(NSString*)kCVPixelBufferIOSurfacePropertiesKey]) {
            [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelInfo
                                   format:@"⭐️ VideoDataOutput adicionado com suporte a IOSurface: %@", settings];
        }
    }
    
    // Atualizar configuração da sessão
    [diagnostic analyzeSession:(AVCaptureSession *)self];
    
    return result;
}

- (void)diagnosticSetSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    CameraDiagnosticFramework *diagnostic = [CameraDiagnosticFramework sharedInstance];
    [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelInfo
                             format:@"⭐️ AVCaptureVideoDataOutput setSampleBufferDelegate chamado: %@, classe: %@",
     sampleBufferDelegate, [sampleBufferDelegate class]];
    
    // Registrar o delegado para análise posterior
    if (sampleBufferDelegate && [sampleBufferDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
        // Adicionar à lista de delegados detectados
        if (![diagnostic.detectedVideoOutputDelegates containsObject:sampleBufferDelegate]) {
            [diagnostic.detectedVideoOutputDelegates addObject:sampleBufferDelegate];
        }
        
        // Atualizar estatísticas de chamadas de métodos
        NSString *delegateClass = NSStringFromClass([sampleBufferDelegate class]);
        NSMutableDictionary *stats = diagnostic.delegateMethodCallStats[delegateClass];
        if (!stats) {
            stats = [NSMutableDictionary dictionary];
            diagnostic.delegateMethodCallStats[delegateClass] = stats;
        }
        
        // Inicializar contadores de métodos
        if (!stats[@"captureOutput:didOutputSampleBuffer:fromConnection:"]) {
            stats[@"captureOutput:didOutputSampleBuffer:fromConnection:"] = @0;
        }
    }
    
    // Chamar método original
    SEL originalSelector = @selector(setSampleBufferDelegate:queue:);
    IMP originalImp = [diagnostic.methodSwizzleOriginals[[NSString stringWithFormat:@"%@_%@",
                                                          NSStringFromClass([self class]),
                                                          NSStringFromSelector(originalSelector)]] pointerValue];
    if (originalImp) {
        ((void(*)(id, SEL, id<AVCaptureVideoDataOutputSampleBufferDelegate>, dispatch_queue_t))originalImp)(
            self, originalSelector, sampleBufferDelegate, sampleBufferCallbackQueue);
    }
}

- (void)diagnosticCaptureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    CameraDiagnosticFramework *diagnostic = [CameraDiagnosticFramework sharedInstance];
    
    // Evitar logging excessivo
    static uint64_t bufferCounter = 0;
    bufferCounter++;
    
    // Atualizar estatísticas de chamada de método
    NSString *delegateClass = NSStringFromClass([self class]);
    NSMutableDictionary *stats = diagnostic.delegateMethodCallStats[delegateClass];
    if (stats) {
        NSInteger currentCount = [stats[@"captureOutput:didOutputSampleBuffer:fromConnection:"] integerValue];
        stats[@"captureOutput:didOutputSampleBuffer:fromConnection:"] = @(currentCount + 1);
    }
    
    // Log periódico para não sobrecarregar
    if (bufferCounter % 300 == 0) {
        [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelInfo
                                format:@"Buffer #%llu processado por %@", bufferCounter, delegateClass];
        
        // Analisar o buffer periodicamente
        [diagnostic analyzeBuffer:sampleBuffer fromOutput:output connection:connection];
    }
    
    // Chamar método original
    SEL originalSelector = @selector(captureOutput:didOutputSampleBuffer:fromConnection:);
    IMP originalImp = [diagnostic.methodSwizzleOriginals[[NSString stringWithFormat:@"%@_%@",
                                                          NSStringFromClass([self class]),
                                                          NSStringFromSelector(originalSelector)]] pointerValue];
    if (originalImp) {
        ((void(*)(id, SEL, AVCaptureOutput *, CMSampleBufferRef, AVCaptureConnection *))originalImp)(
            self, originalSelector, output, sampleBuffer, connection);
    }
}

#pragma mark - Utilitário de Logging

- (void)logMessageWithLevel:(CameraDiagnosticLogLevel)level format:(NSString *)format, ... {
    // Verificar nível mínimo de log
    if (level < self.logLevel) {
        return;
    }
    
    // Obter string formatada
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    // Prefixo de nível de log
    NSString *levelPrefix;
    switch (level) {
        case CameraDiagnosticLogLevelDebug:
            levelPrefix = @"[DEBUG]";
            break;
        case CameraDiagnosticLogLevelInfo:
            levelPrefix = @"[INFO]";
            break;
        case CameraDiagnosticLogLevelWarning:
            levelPrefix = @"[WARN]";
            break;
        case CameraDiagnosticLogLevelError:
            levelPrefix = @"[ERROR]";
            break;
        default:
            levelPrefix = @"[LOG]";
            break;
    }
    
    // Timestamp
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *timestamp = [formatter stringFromDate:[NSDate date]];
    
    // String completa
    NSString *fullMessage = [NSString stringWithFormat:@"%@ %@ %@", timestamp, levelPrefix, message];
    
    // Log para console
    NSLog(@"%@", fullMessage);
    
    // Log para arquivo se configurado
    if (self.isLoggingToFile && self.logFileHandle) {
        @try {
            NSString *lineMessage = [fullMessage stringByAppendingString:@"\n"];
            NSData *data = [lineMessage dataUsingEncoding:NSUTF8StringEncoding];
            [self.logFileHandle writeData:data];
        } @catch (NSException *exception) {
            NSLog(@"Erro ao escrever no arquivo de log: %@", exception);
        }
    }
}

@end
