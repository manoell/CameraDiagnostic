#import "Tweak.h"

// Inicialização das variáveis globais
NSString *g_processName = nil;
NSString *g_processID = nil;
NSString *g_sessionID = nil;
BOOL g_isVideoOrientationSet = NO;
int g_videoOrientation = 1; // Default orientation (portrait)
CGSize g_originalCameraResolution = CGSizeZero;
CGSize g_originalFrontCameraResolution = CGSizeZero;
CGSize g_originalBackCameraResolution = CGSizeZero;
BOOL g_usingFrontCamera = NO;
BOOL g_isCaptureActive = NO;

// Função para registrar informações de delegados ativos relacionados à câmera
void logDelegates() {
    writeLog(@"[INFO] Buscando delegados de câmera ativos...");
    
    // Lista de classes potenciais para monitorar
    NSArray *activeDelegateClasses = @[
        @"CAMCaptureEngine",
        @"PLCameraController",
        @"PLCaptureSession",
        @"SCCapture",
        @"TGCameraController",
        @"AVCaptureSession",
        @"MTCameraController", // Para FaceTime/iMessage
        @"UIImagePickerController" // Para seletores nativos
    ];
    
    NSMutableDictionary *delegateInfo = [NSMutableDictionary dictionary];
    
    for (NSString *className in activeDelegateClasses) {
        Class delegateClass = NSClassFromString(className);
        if (delegateClass) {
            writeLog(@"[DELEGATE] Encontrado delegado potencial: %@", className);
            
            // Coletar informações sobre a classe para diagnóstico
            unsigned int methodCount = 0;
            class_copyMethodList(delegateClass, &methodCount);
            
            NSDictionary *classInfo = @{
                @"exists": @YES,
                @"methodCount": @(methodCount),
                @"className": className
            };
            
            delegateInfo[className] = classInfo;
        }
    }
    
    // Salvar informações coletadas usando DiagnosticCollector
    [[DiagnosticCollector sharedInstance] saveDelegateInfo:delegateInfo];
}

// Função para detectar dimensões das câmeras
void detectCameraResolutions() {
    // Resolução padrão caso falhe a detecção automática
    g_originalFrontCameraResolution = CGSizeMake(0, 0);
    g_originalBackCameraResolution = CGSizeMake(0, 0);
    
    writeLog(@"[INIT] Configurando detecção de resoluções de câmera");
    
    // A detecção real ocorre via hooks em AVCaptureDevice no CameraHooks.xm
}

// Constructor - roda quando o tweak é carregado
%ctor {
    @autoreleasepool {
        setLogLevel(5); // Nível DEBUG para máximo de detalhes
        
        // Inicializar dados de identificação da sessão
        g_processName = [NSProcessInfo processInfo].processName;
        g_processID = [NSString stringWithFormat:@"%d", [NSProcessInfo processInfo].processIdentifier];
        
        // Criar ID único para esta sessão (timestamp + random)
        NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970];
        int randomVal = arc4random_uniform(10000);
        g_sessionID = [NSString stringWithFormat:@"%@-%0.0f-%d", g_processName, timestamp, randomVal];
        
        writeLog(@"[INIT] CameraDiagnostic carregado em processo: %@ (PID: %@)", g_processName, g_processID);
        writeLog(@"[INIT] ID da sessão: %@", g_sessionID);
        
        // Inicializar o DiagnosticCollector singleton
        DiagnosticCollector *collector = [DiagnosticCollector sharedInstance];
        [collector setSessionInfo:@{
            @"processName": g_processName,
            @"processID": g_processID,
            @"sessionID": g_sessionID,
            @"timestamp": @(timestamp),
            @"iosVersion": [[UIDevice currentDevice] systemVersion]
        }];
        
        // Inicializar resoluções da câmera
        detectCameraResolutions();
        
        // Verificar se estamos em um aplicativo que usa a câmera
        BOOL isCameraApp =
            ([g_processName isEqualToString:@"Camera"] ||
             [g_processName containsString:@"camera"] ||
             [g_processName isEqualToString:@"Telegram"] ||
             [g_processName isEqualToString:@"Instagram"] ||
             [g_processName isEqualToString:@"com.burbn.instagram"] ||
             [g_processName isEqualToString:@"WhatsApp"] ||
             [g_processName isEqualToString:@"net.whatsapp.WhatsApp"] ||
             [g_processName isEqualToString:@"Facetime"] ||
             [g_processName containsString:@"facetime"] ||
             [g_processName isEqualToString:@"MobileSlideShow"] ||
             [g_processName isEqualToString:@"com.facebook.Facebook"] ||
             [g_processName isEqualToString:@"com.atebits.Tweetie2"] ||
             [g_processName isEqualToString:@"ph.telegra.Telegraph"] ||
             [g_processName isEqualToString:@"com.google.ios.youtube"] ||
             [g_processName isEqualToString:@"com.apple.mobileslideshow"] ||
             [g_processName isEqualToString:@"com.skype.skype"]);
            
        if (isCameraApp) {
            writeLog(@"[INIT] Detectado aplicativo que usa câmera: %@", g_processName);
            [collector addAppCategory:@"camera_app"];
        } else {
            writeLog(@"[INIT] Aplicativo sem uso de câmera conhecido: %@", g_processName);
            [collector addAppCategory:@"other_app"];
        }
        
        // Registrar classes importantes
        logDelegates();
        
        // Inicializar os grupos padrão - sem hooks específicos neste arquivo
        %init(_ungrouped);
        
        // Forçar um salvamento inicial de diagnóstico após inicialização
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            writeLog(@"[INIT] Forçando salvamento inicial de diagnóstico");
            [[DiagnosticCollector sharedInstance] forceSaveDiagnostic];
        });
    }
}
