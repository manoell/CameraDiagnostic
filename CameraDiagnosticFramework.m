// CameraDiagnosticFramework.m

#import "CameraDiagnosticFramework.h"
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>

@interface CameraDiagnosticFramework ()

@property (nonatomic, strong) NSFileHandle *logFileHandle;
@property (nonatomic, assign) CameraDiagnosticLogLevel logLevel;
@property (nonatomic, assign) BOOL isLoggingToFile;
@property (nonatomic, strong) NSString *logFilePath;
@property (nonatomic, strong) NSMutableArray *activeCaptureSessions;
@property (nonatomic, strong) NSMutableDictionary *methodSwizzleOriginals;
@property (nonatomic, strong) NSMutableArray *detectedVideoOutputDelegates;
@property (nonatomic, strong) NSDate *startTime;

@end

@implementation CameraDiagnosticFramework

#pragma mark - Singleton

+ (instancetype)sharedInstance {
    static CameraDiagnosticFramework *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[CameraDiagnosticFramework alloc] init];
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
        
        // Preparar diretório de logs
        NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        _logFilePath = [documentsPath stringByAppendingPathComponent:@"camera_diagnostic.log"];
    }
    return self;
}

#pragma mark - Configuração

- (void)startDiagnosticWithLogLevel:(CameraDiagnosticLogLevel)level {
    self.logLevel = level;
    self.startTime = [NSDate date];
    
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"CameraDiagnosticFramework iniciado em %@", self.startTime];
    
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
}

- (void)stopDiagnostic {
    // Remover observadores
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // Fechar arquivo se necessário
    if (self.logFileHandle) {
        [self.logFileHandle closeFile];
        self.logFileHandle = nil;
    }
    
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"CameraDiagnosticFramework finalizado. Duração total: %f segundos",
                       [[NSDate date] timeIntervalSinceDate:self.startTime]];
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
    // Usar a variável para evitar o erro de 'unused variable'
    AVCaptureSession *session = notification.object;
    NSError *error = notification.userInfo[AVCaptureSessionErrorKey];
    
    [self logMessageWithLevel:CameraDiagnosticLogLevelError
                       format:@"AVCaptureSession runtime error: %@ (Session: %p)", error, session];
    [self analyzeActiveCaptureSessions];
}

- (void)captureSessionDidStartRunning:(NSNotification *)notification {
    // Usar a variável para evitar o erro de 'unused variable'
    AVCaptureSession *session = notification.object;
    
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"AVCaptureSession started running: %p", session];
    
    if (![self.activeCaptureSessions containsObject:session]) {
        [self.activeCaptureSessions addObject:session];
    }
    
    [self analyzeActiveCaptureSessions];
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
}

- (void)captureSessionInterruptionEnded:(NSNotification *)notification {
    // Usar a sessão para evitar erro de variável não utilizada
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
                       format:@"Iniciando hooks nas APIs de câmera..."];
    
    [self hookAVCaptureSession];
    [self hookAVCaptureVideoDataOutput];
    [self hookUIImagePickerController];
    [self hookCoreMedia];
}

- (void)hookAVCaptureSession {
    [self logMessageWithLevel:CameraDiagnosticLogLevelDebug
                       format:@"Instalando hook em AVCaptureSession..."];
    
    // Método de inicialização
    [self swizzleMethodForClass:[AVCaptureSession class]
                    originalSel:@selector(init)
                     swizzledSel:@selector(diagnosticInit)];
    
    // Métodos importantes de AVCaptureSession
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
    
    [self swizzleMethodForClass:[AVCaptureSession class]
                    originalSel:@selector(removeInput:)
                     swizzledSel:@selector(diagnosticRemoveInput:)];
    
    [self swizzleMethodForClass:[AVCaptureSession class]
                    originalSel:@selector(removeOutput:)
                     swizzledSel:@selector(diagnosticRemoveOutput:)];
    
    [self swizzleMethodForClass:[AVCaptureSession class]
                    originalSel:@selector(beginConfiguration)
                     swizzledSel:@selector(diagnosticBeginConfiguration)];
    
    [self swizzleMethodForClass:[AVCaptureSession class]
                    originalSel:@selector(commitConfiguration)
                     swizzledSel:@selector(diagnosticCommitConfiguration)];
}

- (void)hookAVCaptureVideoDataOutput {
    [self logMessageWithLevel:CameraDiagnosticLogLevelDebug
                       format:@"Instalando hook em AVCaptureVideoDataOutput..."];
    
    // Hook para setSampleBufferDelegate
    [self swizzleMethodForClass:[AVCaptureVideoDataOutput class]
                    originalSel:@selector(setSampleBufferDelegate:queue:)
                     swizzledSel:@selector(diagnosticSetSampleBufferDelegate:queue:)];
    
    // Hook para delegate callback - esse é tricky e pode precisar de abordagem alternativa
    Protocol *protocolObj = @protocol(AVCaptureVideoDataOutputSampleBufferDelegate);
    if (protocolObj) {
        [self logMessageWithLevel:CameraDiagnosticLogLevelDebug
                           format:@"Encontrado protocolo AVCaptureVideoDataOutputSampleBufferDelegate"];
        
        // Precisamos encontrar todas as classes que implementam este protocolo
        // Esta é uma abordagem parcial - idealmente precisaríamos iterar em todas as classes carregadas
        unsigned int count;
        Class *classes = objc_copyClassList(&count);
        
        for (unsigned int i = 0; i < count; i++) {
            if (class_conformsToProtocol(classes[i], protocolObj)) {
                [self logMessageWithLevel:CameraDiagnosticLogLevelDebug
                                   format:@"Classe %s implementa AVCaptureVideoDataOutputSampleBufferDelegate",
                 class_getName(classes[i])];
                
                // Hook o método captureOutput:didOutputSampleBuffer:fromConnection:
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

- (void)hookUIImagePickerController {
    [self logMessageWithLevel:CameraDiagnosticLogLevelDebug
                       format:@"Instalando hook em UIImagePickerController..."];
    
    // Hook nos métodos de UIImagePickerController
    [self swizzleMethodForClass:[UIImagePickerController class]
                    originalSel:@selector(init)
                     swizzledSel:@selector(diagnosticImagePickerInit)];
    
    [self swizzleMethodForClass:[UIImagePickerController class]
                    originalSel:@selector(setSourceType:)
                     swizzledSel:@selector(diagnosticSetSourceType:)];
    
    [self swizzleMethodForClass:[UIImagePickerController class]
                    originalSel:@selector(setDelegate:)
                     swizzledSel:@selector(diagnosticSetDelegate:)];
}

- (void)hookCoreMedia {
    [self logMessageWithLevel:CameraDiagnosticLogLevelDebug
                       format:@"Tentando hook em funções do CoreMedia/CoreVideo..."];
    
    // Isso é complexo e pode precisar de uma abordagem diferente com fishhook ou similar
    // Para funções C, precisaríamos interceptar ao nível de dylib
    
    // Exemplo de como seria se usássemos fishhook, mas aqui só registramos
    [self logMessageWithLevel:CameraDiagnosticLogLevelDebug
                       format:@"Funções a serem consideradas para hook: CMSampleBufferGetImageBuffer, CVPixelBufferLockBaseAddress, etc."];
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
                       format:@"Iniciando dump de configuração da câmera..."];
    
    // Dispositivos disponíveis
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"Dispositivos de câmera disponíveis: %lu", (unsigned long)devices.count];
    
    for (AVCaptureDevice *device in devices) {
        [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                           format:@"Dispositivo: %@, Posição: %ld, Fornece formatos: %lu",
         device.localizedName, (long)device.position, (unsigned long)device.formats.count];
        
        // Log detalhado de formatos suportados
        for (AVCaptureDeviceFormat *format in device.formats) {
            CMFormatDescriptionRef formatDescription = format.formatDescription;
            CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
            
            FourCharCode fourCharCode = CMFormatDescriptionGetMediaSubType(formatDescription);
            char fourCC[5] = {0};
            fourCC[0] = (fourCharCode >> 24) & 0xFF;
            fourCC[1] = (fourCharCode >> 16) & 0xFF;
            fourCC[2] = (fourCharCode >> 8) & 0xFF;
            fourCC[3] = fourCharCode & 0xFF;
            
            [self logMessageWithLevel:CameraDiagnosticLogLevelDebug
                               format:@"  Formato: %dx%d, FourCC: %s, FPS: %@",
             dimensions.width, dimensions.height, fourCC, format.videoSupportedFrameRateRanges];
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
        // Dispositivos
        [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                           format:@"Sessão: %p, Preset: %@, Em execução: %d",
         session, session.sessionPreset, session.isRunning];
        
        // Inputs
        [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                           format:@"Inputs: %lu", (unsigned long)session.inputs.count];
        
        for (AVCaptureInput *input in session.inputs) {
            if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
                AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
                [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                                   format:@"  Device Input: %@ (Posição: %ld)",
                 deviceInput.device.localizedName, (long)deviceInput.device.position];
            } else {
                [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                                   format:@"  Input: %@", [input class]];
            }
        }
        
        // Outputs
        [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                           format:@"Outputs: %lu", (unsigned long)session.outputs.count];
        
        for (AVCaptureOutput *output in session.outputs) {
            if ([output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
                // Realmente use a variável videoOutput ao invés de apenas declará-la
                AVCaptureVideoDataOutput *videoOutput = (AVCaptureVideoDataOutput *)output;
                [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                                  format:@"  Video Data Output: %@", [self descriptionForAVCaptureVideoDataOutput:videoOutput]];
                
                // Essa é uma boa oportunidade para examinar os delegados
                id<AVCaptureVideoDataOutputSampleBufferDelegate> delegate = videoOutput.sampleBufferDelegate;
                if (delegate && ![self.detectedVideoOutputDelegates containsObject:delegate]) {
                    [self.detectedVideoOutputDelegates addObject:delegate];
                    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                                       format:@"    Delegate: %@ (%@)", delegate, [delegate class]];
                }
            } else if ([output isKindOfClass:[AVCaptureMovieFileOutput class]]) {
                AVCaptureMovieFileOutput *movieOutput = (AVCaptureMovieFileOutput *)output;
                [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                                   format:@"  Movie File Output: %@", movieOutput];
            } else if ([output isKindOfClass:[AVCaptureStillImageOutput class]]) {
                AVCaptureStillImageOutput *stillImageOutput = (AVCaptureStillImageOutput *)output;
                [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                                   format:@"  Still Image Output: %@", stillImageOutput];
            } else {
                [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                                   format:@"  Output: %@", [output class]];
            }
        }
        
        // Conexões
        [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                           format:@"Conexões de saída:"];
        
        for (AVCaptureOutput *output in session.outputs) {
            for (AVCaptureConnection *connection in output.connections) {
                [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                                   format:@"  %@", [self descriptionForAVCaptureConnection:connection]];
            }
        }
    }
}

- (void)analyzeVideoDataOutputs {
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"Analisando delegados de saída de vídeo detectados: %lu",
     (unsigned long)self.detectedVideoOutputDelegates.count];
    
    for (id<AVCaptureVideoDataOutputSampleBufferDelegate> delegate in self.detectedVideoOutputDelegates) {
        [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                           format:@"Delegate: %@ (%@)", delegate, [delegate class]];
        
        // Analisar a hierarquia de classes
        Class currentClass = [delegate class];
        NSMutableString *classHierarchy = [NSMutableString string];
        
        while (currentClass) {
            [classHierarchy appendFormat:@"%@ -> ", NSStringFromClass(currentClass)];
            currentClass = class_getSuperclass(currentClass);
        }
        
        [classHierarchy appendString:@"nil"];
        [self logMessageWithLevel:CameraDiagnosticLogLevelDebug
                           format:@"  Hierarquia de classes: %@", classHierarchy];
        
        // Verificar métodos relevantes
        BOOL implementsDidOutputSampleBuffer = [delegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)];
        BOOL implementsDidDropSampleBuffer = [delegate respondsToSelector:@selector(captureOutput:didDropSampleBuffer:fromConnection:)];
        
        [self logMessageWithLevel:CameraDiagnosticLogLevelDebug
                           format:@"  Implementa didOutputSampleBuffer: %d", implementsDidOutputSampleBuffer];
        [self logMessageWithLevel:CameraDiagnosticLogLevelDebug
                           format:@"  Implementa didDropSampleBuffer: %d", implementsDidDropSampleBuffer];
        
        // Aqui poderíamos usar mais runtime introspection para examinar o delegate em detalhe
    }
}

- (void)analyzeBufferProcessingChain {
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"Analisando cadeia de processamento de buffers..."];
    
    // Aqui acompanhamos o fluxo de um buffer de amostra através do sistema
    // Esta é uma análise que depende dos hooks capturarem dados em tempo real
    
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"Hooks instalados nos pontos da pipeline. Aguardando dados de captura para análise."];
    
    // A maioria dos dados será coletada pelos hooks de método
}

- (void)analyzeRenderingPipeline {
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"Analisando pipeline de renderização..."];
    
    // Análise das camadas de renderização nas visualizações ativas da câmera
    UIWindow *keyWindow = nil;
    
    // Obter a janela principal (compatível com iOS 13+)
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
    // Cria uma string de indentação para formatação
    NSMutableString *indentString = [NSMutableString string];
    for (int i = 0; i < indent; i++) {
        [indentString appendString:@"  "];
    }
    
    // Registra informações sobre a visualização
    [self logMessageWithLevel:CameraDiagnosticLogLevelDebug
                       format:@"%@View: %@ (Frame: %@, Hidden: %d)",
     indentString, [view class], NSStringFromCGRect(view.frame), view.isHidden];
    
    // Verifica se esta visualização pode estar relacionada à câmera
    if ([view isKindOfClass:NSClassFromString(@"AVCaptureVideoPreviewLayer")] ||
        [view isKindOfClass:NSClassFromString(@"PLCameraView")] ||
        [view isKindOfClass:NSClassFromString(@"PLPreviewView")] ||
        [view isKindOfClass:NSClassFromString(@"CAMPreviewView")]) {
        
        [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                           format:@"%@Visualização relacionada à câmera encontrada: %@",
         indentString, [view class]];
        
        // Analisa as camadas (CALayer)
        CALayer *layer = view.layer;
        [self inspectLayerHierarchy:layer indent:indent + 1];
    }
    
    // Recursivamente inspeciona subviews
    for (UIView *subview in view.subviews) {
        [self inspectViewHierarchy:subview indent:indent + 1];
    }
}

- (void)inspectLayerHierarchy:(CALayer *)layer indent:(int)indent {
    // Cria uma string de indentação para formatação
    NSMutableString *indentString = [NSMutableString string];
    for (int i = 0; i < indent; i++) {
        [indentString appendString:@"  "];
    }
    
    // Registra informações sobre a camada
    [self logMessageWithLevel:CameraDiagnosticLogLevelDebug
                       format:@"%@Layer: %@ (Frame: %@, Hidden: %d)",
     indentString, [layer class], NSStringFromCGRect(layer.frame), layer.isHidden];
    
    // Verifica se esta camada está relacionada à câmera
    if ([layer isKindOfClass:NSClassFromString(@"AVCaptureVideoPreviewLayer")]) {
        AVCaptureVideoPreviewLayer *previewLayer = (AVCaptureVideoPreviewLayer *)layer;
        [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                           format:@"%@AVCaptureVideoPreviewLayer encontrada! Sessão: %@, Orientation: %ld, Mirror: %d",
         indentString, previewLayer.session, (long)previewLayer.connection.videoOrientation, previewLayer.connection.isVideoMirrored];
    }
    
    // Recursivamente inspeciona sublayers
    for (CALayer *sublayer in layer.sublayers) {
        [self inspectLayerHierarchy:sublayer indent:indent + 1];
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
                       format:@"Aplicativo principal: %@ (%@)", appName, mainBundleID];
    
    // Verificar se há extensões ou outros processos
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"Binários carregados que podem estar relacionados à câmera:"];
    
    uint32_t count = _dyld_image_count();
    for (uint32_t i = 0; i < count; i++) {
        const char *imageName = _dyld_get_image_name(i);
        if (imageName) {
            NSString *name = [NSString stringWithUTF8String:imageName];
            
            // Filtrar apenas os binários relevantes para a câmera
            if ([name containsString:@"Camera"] ||
                [name containsString:@"AVCapture"] ||
                [name containsString:@"CoreMedia"] ||
                [name containsString:@"VideoToolbox"]) {
                
                [self logMessageWithLevel:CameraDiagnosticLogLevelDebug
                                   format:@"  Imagem: %@", name];
            }
        }
    }
}

- (void)traceBufferLifecycle {
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"Iniciando rastreamento do ciclo de vida do buffer..."];
    
    // Este método será usado para rastrear um buffer específico ao longo da pipeline
    // Será preenchido principalmente pelos callbacks dos hooks
    
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"Aguardando captura de buffer para análise..."];
}

#pragma mark - Swizzled Methods (AVCaptureSession)

- (id)diagnosticInit {
    // Chama o método original
    id instance = [self diagnosticInit]; // Isso vai chamar o método original devido ao swizzling
    
    CameraDiagnosticFramework *diagnostic = [CameraDiagnosticFramework sharedInstance];
    [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelDebug
                             format:@"AVCaptureSession inicializada: %@", instance];
    
    return instance;
}

- (void)diagnosticStartRunning {
    CameraDiagnosticFramework *diagnostic = [CameraDiagnosticFramework sharedInstance];
    [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelInfo
                             format:@"AVCaptureSession startRunning chamado: %@", self];
    
    // Chama o método original
    [self diagnosticStartRunning];
    
    [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelDebug
                             format:@"AVCaptureSession startRunning concluído: %@", self];
    
    // Adicionar à lista de sessões ativas se ainda não estiver nela
    if (![diagnostic.activeCaptureSessions containsObject:self]) {
        [diagnostic.activeCaptureSessions addObject:self];
    }
}

- (void)diagnosticStopRunning {
    CameraDiagnosticFramework *diagnostic = [CameraDiagnosticFramework sharedInstance];
    [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelInfo
                             format:@"AVCaptureSession stopRunning chamado: %@", self];
    
    // Chama o método original
    [self diagnosticStopRunning];
    
    [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelDebug
                             format:@"AVCaptureSession stopRunning concluído: %@", self];
    
    // Remover da lista de sessões ativas
    [diagnostic.activeCaptureSessions removeObject:self];
}

- (void)diagnosticBeginConfiguration {
    CameraDiagnosticFramework *diagnostic = [CameraDiagnosticFramework sharedInstance];
    [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelDebug
                             format:@"AVCaptureSession beginConfiguration chamado: %@", self];
    
    // Chama o método original
    [self diagnosticBeginConfiguration];
}

- (void)diagnosticCommitConfiguration {
    CameraDiagnosticFramework *diagnostic = [CameraDiagnosticFramework sharedInstance];
    [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelDebug
                             format:@"AVCaptureSession commitConfiguration chamado: %@", self];
    
    // Chama o método original
    [self diagnosticCommitConfiguration];
    
    // Boa hora para analisar a configuração atualizada
    [diagnostic analyzeActiveCaptureSessions];
}

- (BOOL)diagnosticAddInput:(AVCaptureInput *)input {
    CameraDiagnosticFramework *diagnostic = [CameraDiagnosticFramework sharedInstance];
    
    NSString *deviceInfo = @"";
    if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
        AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
        deviceInfo = [NSString stringWithFormat:@" (Dispositivo: %@, Posição: %ld)",
                      deviceInput.device.localizedName,
                      (long)deviceInput.device.position];
    }
    
    [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelInfo
                             format:@"AVCaptureSession addInput chamado: %@%@", input, deviceInfo];
    
    // Chama o método original
    BOOL result = [self diagnosticAddInput:input];
    
    [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelDebug
                             format:@"AVCaptureSession addInput completado com resultado: %d", result];
    
    return result;
}

- (void)diagnosticRemoveInput:(AVCaptureInput *)input {
    CameraDiagnosticFramework *diagnostic = [CameraDiagnosticFramework sharedInstance];
    [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelInfo
                             format:@"AVCaptureSession removeInput chamado: %@", input];
    
    // Chama o método original
    [self diagnosticRemoveInput:input];
    
    [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelDebug
                             format:@"AVCaptureSession removeInput concluído"];
}

- (BOOL)diagnosticAddOutput:(AVCaptureOutput *)output {
    CameraDiagnosticFramework *diagnostic = [CameraDiagnosticFramework sharedInstance];
    
    NSString *outputInfo = @"";
    if ([output isKindOfClass:[AVCaptureVideoDataOutput class]]) {
        outputInfo = [NSString stringWithFormat:@" (VideoDataOutput)"];
    } else if ([output isKindOfClass:[AVCaptureMovieFileOutput class]]) {
        outputInfo = [NSString stringWithFormat:@" (MovieFileOutput)"];
    } else if ([output isKindOfClass:[AVCaptureStillImageOutput class]]) {
        outputInfo = [NSString stringWithFormat:@" (StillImageOutput)"];
    }
    
    [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelInfo
                             format:@"AVCaptureSession addOutput chamado: %@%@", output, outputInfo];
    
    // Chama o método original
    BOOL result = [self diagnosticAddOutput:output];
    
    [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelDebug
                             format:@"AVCaptureSession addOutput completado com resultado: %d", result];
    
    return result;
}

- (void)diagnosticRemoveOutput:(AVCaptureOutput *)output {
    CameraDiagnosticFramework *diagnostic = [CameraDiagnosticFramework sharedInstance];
    [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelInfo
                             format:@"AVCaptureSession removeOutput chamado: %@", output];
    
    // Chama o método original
    [self diagnosticRemoveOutput:output];
    
    [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelDebug
                             format:@"AVCaptureSession removeOutput concluído"];
}

#pragma mark - Swizzled Methods (AVCaptureVideoDataOutput)

- (void)diagnosticSetSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    CameraDiagnosticFramework *diagnostic = [CameraDiagnosticFramework sharedInstance];
    [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelInfo
                             format:@"AVCaptureVideoDataOutput setSampleBufferDelegate chamado. Delegate: %@, Queue: %@",
     sampleBufferDelegate, sampleBufferCallbackQueue];
    
    // Registra o delegate para análise
    if (sampleBufferDelegate && ![diagnostic.detectedVideoOutputDelegates containsObject:sampleBufferDelegate]) {
        [diagnostic.detectedVideoOutputDelegates addObject:sampleBufferDelegate];
    }
    
    // Chama o método original
    [self diagnosticSetSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
    
    [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelDebug
                             format:@"AVCaptureVideoDataOutput setSampleBufferDelegate concluído"];
}

#pragma mark - Swizzled Delegate Methods (AVCaptureVideoDataOutputSampleBufferDelegate)

- (void)diagnosticCaptureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    CameraDiagnosticFramework *diagnostic = [CameraDiagnosticFramework sharedInstance];
    
    static NSInteger bufferCounter = 0;
    bufferCounter++;
    
    // Só logamos a cada N frames para não sobrecarregar
    if (bufferCounter % 30 == 0) {  // A cada 30 frames (aprox. 1 segundo a 30 FPS)
        [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelDebug
                                 format:@"captureOutput:didOutputSampleBuffer chamado. Buffer: %@",
         [diagnostic descriptionForCMSampleBuffer:sampleBuffer]];
    }
    
    // Chama o método original
    [self diagnosticCaptureOutput:output didOutputSampleBuffer:sampleBuffer fromConnection:connection];
    
    // Ocasionalmente analisamos em detalhes (a cada 300 frames ~ 10 segundos a 30 FPS)
    if (bufferCounter % 300 == 0) {
        // Analisamos o buffer em detalhes
        [diagnostic analyzeBufferInDetail:sampleBuffer fromOutput:output connection:connection];
    }
}

#pragma mark - Swizzled Methods (UIImagePickerController)

- (id)diagnosticImagePickerInit {
    // Chama o método original
    id instance = [self diagnosticImagePickerInit];
    
    CameraDiagnosticFramework *diagnostic = [CameraDiagnosticFramework sharedInstance];
    [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelInfo
                             format:@"UIImagePickerController inicializado: %@", instance];
    
    return instance;
}

- (void)diagnosticSetSourceType:(UIImagePickerControllerSourceType)sourceType {
    CameraDiagnosticFramework *diagnostic = [CameraDiagnosticFramework sharedInstance];
    
    NSString *sourceTypeStr = @"Unknown";
    switch (sourceType) {
        case UIImagePickerControllerSourceTypePhotoLibrary:
            sourceTypeStr = @"PhotoLibrary";
            break;
        case UIImagePickerControllerSourceTypeCamera:
            sourceTypeStr = @"Camera";
            break;
        case UIImagePickerControllerSourceTypeSavedPhotosAlbum:
            sourceTypeStr = @"SavedPhotosAlbum";
            break;
    }
    
    [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelInfo
                             format:@"UIImagePickerController setSourceType chamado: %@", sourceTypeStr];
    
    // Chama o método original
    [self diagnosticSetSourceType:sourceType];
    
    // Se for modo câmera, podemos capturar mais informações
    if (sourceType == UIImagePickerControllerSourceTypeCamera) {
        [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelInfo
                                 format:@"UIImagePickerController configurado para usar a câmera"];
    }
}

- (void)diagnosticSetDelegate:(id<UIImagePickerControllerDelegate>)delegate {
    CameraDiagnosticFramework *diagnostic = [CameraDiagnosticFramework sharedInstance];
    [diagnostic logMessageWithLevel:CameraDiagnosticLogLevelInfo
                             format:@"UIImagePickerController setDelegate chamado: %@", delegate];
    
    // Chama o método original
    [self diagnosticSetDelegate:delegate];
}

#pragma mark - Análise Detalhada de Buffer

- (void)analyzeBufferInDetail:(CMSampleBufferRef)sampleBuffer fromOutput:(AVCaptureOutput *)output connection:(AVCaptureConnection *)connection {
    // Analisa detalhadamente um buffer de amostra
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"Análise detalhada de buffer:"];
    
    // Verifica se o buffer é válido
    if (!CMSampleBufferIsValid(sampleBuffer)) {
        [self logMessageWithLevel:CameraDiagnosticLogLevelWarning
                           format:@"  Buffer inválido"];
        return;
    }
    
    // Obtém o formato do buffer
    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
    if (formatDescription) {
        CMMediaType mediaType = CMFormatDescriptionGetMediaType(formatDescription);
        FourCharCode mediaSubType = CMFormatDescriptionGetMediaSubType(formatDescription);
        
        char mediaTypeStr[5] = {0};
        mediaTypeStr[0] = (mediaType >> 24) & 0xFF;
        mediaTypeStr[1] = (mediaType >> 16) & 0xFF;
        mediaTypeStr[2] = (mediaType >> 8) & 0xFF;
        mediaTypeStr[3] = mediaType & 0xFF;
        
        char mediaSubTypeStr[5] = {0};
        mediaSubTypeStr[0] = (mediaSubType >> 24) & 0xFF;
        mediaSubTypeStr[1] = (mediaSubType >> 16) & 0xFF;
        mediaSubTypeStr[2] = (mediaSubType >> 8) & 0xFF;
        mediaSubTypeStr[3] = mediaSubType & 0xFF;
        
        [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                           format:@"  Media Type: %s, Media SubType: %s", mediaTypeStr, mediaSubTypeStr];
        
        if (mediaType == kCMMediaType_Video) {
            CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
            [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                               format:@"  Dimensões: %dx%d", dimensions.width, dimensions.height];
            
            // Obtém informações sobre a codificação
            CFDictionaryRef extensions = CMFormatDescriptionGetExtensions(formatDescription);
            if (extensions) {
                CFStringRef codecKey = kCMFormatDescriptionExtension_FormatName;
                CFStringRef codecValue = NULL;
                
                if (CFDictionaryGetValueIfPresent(extensions, codecKey, (const void **)&codecValue) && codecValue) {
                    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                                       format:@"  Codec: %@", codecValue];
                }
            }
        }
    }
    
    // Obtém o buffer de pixel para vídeo
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (imageBuffer) {
        [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                           format:@"  ImageBuffer: %@", [self descriptionForPixelBuffer:imageBuffer]];
    }
    
    // Informações de tempo
    CMTime presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    CMTime decodeTimeStamp = CMSampleBufferGetDecodeTimeStamp(sampleBuffer);
    CMTime duration = CMSampleBufferGetDuration(sampleBuffer);
    
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"  PTS: %.3fs, DTS: %.3fs, Duration: %.3fs",
     CMTimeGetSeconds(presentationTimeStamp),
     CMTimeGetSeconds(decodeTimeStamp),
     CMTimeGetSeconds(duration)];
    
    // Informações da conexão
    [self logMessageWithLevel:CameraDiagnosticLogLevelInfo
                       format:@"  Conexão: %@", [self descriptionForAVCaptureConnection:connection]];
    
    // Metadados (se disponíveis)
    CFArrayRef attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, false);
    if (attachments && CFArrayGetCount(attachments) > 0) {
        CFDictionaryRef attachmentDict = (CFDictionaryRef)CFArrayGetValueAtIndex(attachments, 0);
        if (attachmentDict) {
            [self logMessageWithLevel:CameraDiagnosticLogLevelDebug
                               format:@"  Tem %lu attachments", CFDictionaryGetCount(attachmentDict)];
            
            // Verificar alguns metadados comuns
            CFTypeRef value;
            
            if (CFDictionaryGetValueIfPresent(attachmentDict, kCMSampleAttachmentKey_DisplayImmediately, &value)) {
                [self logMessageWithLevel:CameraDiagnosticLogLevelDebug
                                   format:@"    DisplayImmediately: %@", value];
            }
            
            if (CFDictionaryGetValueIfPresent(attachmentDict, kCMSampleAttachmentKey_NotSync, &value)) {
                [self logMessageWithLevel:CameraDiagnosticLogLevelDebug
                                   format:@"    NotSync: %@", value];
            }
        }
    }
}

#pragma mark - Utilitários

- (void)logMessageWithLevel:(CameraDiagnosticLogLevel)level format:(NSString *)format, ... {
    // Só processa se o nível for igual ou superior ao nível configurado
    if (level < self.logLevel) {
        return;
    }
    
    // Prefixo baseado no nível
    NSString *levelPrefix = @"";
    switch (level) {
        case CameraDiagnosticLogLevelInfo:
            levelPrefix = @"[INFO]";
            break;
        case CameraDiagnosticLogLevelDebug:
            levelPrefix = @"[DEBUG]";
            break;
        case CameraDiagnosticLogLevelWarning:
            levelPrefix = @"[WARN]";
            break;
        case CameraDiagnosticLogLevelError:
            levelPrefix = @"[ERROR]";
            break;
    }
    
    // Formata a mensagem
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    // Adiciona timestamp
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
    NSString *timestamp = [dateFormatter stringFromDate:[NSDate date]];
    
    // Mensagem final
    NSString *finalMessage = [NSString stringWithFormat:@"%@ %@ %@", timestamp, levelPrefix, message];
    
    // Log para o console
    NSLog(@"%@", finalMessage);
    
    // Log para arquivo se necessário
    if (self.isLoggingToFile && self.logFileHandle) {
        NSString *fileMessage = [finalMessage stringByAppendingString:@"\n"];
        NSData *data = [fileMessage dataUsingEncoding:NSUTF8StringEncoding];
        [self.logFileHandle writeData:data];
    }
}

- (NSString *)descriptionForCMSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if (!sampleBuffer) {
        return @"<NULL>";
    }
    
    NSMutableString *description = [NSMutableString string];
    [description appendFormat:@"<CMSampleBuffer:%p", sampleBuffer];
    
    // Verifica se é válido
    [description appendFormat:@", valid:%d", CMSampleBufferIsValid(sampleBuffer)];
    
    // Timestamp
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    [description appendFormat:@", pts:%.3fs", CMTimeGetSeconds(pts)];
    
    // Número de amostras
    CMItemCount count = CMSampleBufferGetNumSamples(sampleBuffer);
    [description appendFormat:@", samples:%ld", (long)count];
    
    // Tipo de mídia
    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
    if (formatDescription) {
        CMMediaType mediaType = CMFormatDescriptionGetMediaType(formatDescription);
        char mediaTypeStr[5] = {0};
        mediaTypeStr[0] = (mediaType >> 24) & 0xFF;
        mediaTypeStr[1] = (mediaType >> 16) & 0xFF;
        mediaTypeStr[2] = (mediaType >> 8) & 0xFF;
        mediaTypeStr[3] = mediaType & 0xFF;
        
        [description appendFormat:@", mediaType:%s", mediaTypeStr];
        
        // Para vídeo, adiciona dimensões
        if (mediaType == kCMMediaType_Video) {
            CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDescription);
            [description appendFormat:@", dimensions:%dx%d", dimensions.width, dimensions.height];
        }
    }
    
    // Buffer de imagem para vídeo
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (imageBuffer) {
        [description appendFormat:@", hasImageBuffer:YES"];
    }
    
    [description appendString:@">"];
    return description;
}

- (NSString *)descriptionForAVCaptureConnection:(AVCaptureConnection *)connection {
    if (!connection) {
        return @"<NULL>";
    }
    
    NSMutableString *description = [NSMutableString string];
    [description appendFormat:@"<AVCaptureConnection:%p", connection];
    
    // Verifica se está ativo
    [description appendFormat:@", enabled:%d", connection.enabled];
    
    // Inputs e outputs
    [description appendFormat:@", inputPorts:%lu", (unsigned long)connection.inputPorts.count];
    [description appendFormat:@", output:%@", connection.output];
    
    // Informações específicas de vídeo
    if ([connection isVideoOrientationSupported]) {
        [description appendFormat:@", videoOrientation:%ld", (long)connection.videoOrientation];
    }
    
    if ([connection isVideoMirroringSupported]) {
        [description appendFormat:@", videoMirrored:%d", connection.isVideoMirrored];
    }
    
    if ([connection isVideoStabilizationSupported]) {
        [description appendFormat:@", videoStabilizationEnabled:%d", (int)connection.preferredVideoStabilizationMode];
    }
    
    [description appendString:@">"];
    return description;
}

// Implementações dos métodos faltantes
- (NSString *)descriptionForAVCaptureVideoDataOutput:(AVCaptureVideoDataOutput *)output {
    if (!output) {
        return @"<NULL>";
    }
    
    NSMutableString *description = [NSMutableString string];
    [description appendFormat:@"<AVCaptureVideoDataOutput:%p", output];
    
    // Configurações de vídeo
    [description appendFormat:@", videoSettings:%@", output.videoSettings];
    
    // Delegate
    id<AVCaptureVideoDataOutputSampleBufferDelegate> delegate = output.sampleBufferDelegate;
    if (delegate) {
        [description appendFormat:@", delegate:%@ (%@)", delegate, [delegate class]];
        
        // Verifica se implementa métodos específicos
        BOOL implementsDidOutputSampleBuffer = [delegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)];
        BOOL implementsDidDropSampleBuffer = [delegate respondsToSelector:@selector(captureOutput:didDropSampleBuffer:fromConnection:)];
        
        [description appendFormat:@", implementsDidOutputSampleBuffer:%d", implementsDidOutputSampleBuffer];
        [description appendFormat:@", implementsDidDropSampleBuffer:%d", implementsDidDropSampleBuffer];
    }
    
    // Queue
    [description appendFormat:@", callbackQueue:%@", output.sampleBufferCallbackQueue];
    
    // Outras configurações
    [description appendFormat:@", alwaysDiscardsLateVideoFrames:%d", output.alwaysDiscardsLateVideoFrames];
    
    [description appendString:@">"];
    return description;
}

- (NSString *)descriptionForPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (!pixelBuffer) {
        return @"<NULL>";
    }
    
    NSMutableString *description = [NSMutableString string];
    [description appendFormat:@"<CVPixelBuffer:%p", pixelBuffer];
    
    // Dimensões
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    [description appendFormat:@", dimensions:%zux%zu", width, height];
    
    // Formato
    OSType pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
    char formatStr[5] = {0};
    formatStr[0] = (pixelFormat >> 24) & 0xFF;
    formatStr[1] = (pixelFormat >> 16) & 0xFF;
    formatStr[2] = (pixelFormat >> 8) & 0xFF;
    formatStr[3] = pixelFormat & 0xFF;
    [description appendFormat:@", format:'%s'", formatStr];
    
    // Outras propriedades
    [description appendFormat:@", bytesPerRow:%zu", CVPixelBufferGetBytesPerRow(pixelBuffer)];
    [description appendFormat:@", dataSize:%zu", CVPixelBufferGetDataSize(pixelBuffer)];
    
    // Planar vs. não-planar
    size_t planeCount = CVPixelBufferGetPlaneCount(pixelBuffer);
    if (planeCount > 0) {
        [description appendFormat:@", planeCount:%zu", planeCount];
    } else {
        [description appendString:@", planar:NO"];
    }
    
    [description appendString:@">"];
    return description;
}

@end
