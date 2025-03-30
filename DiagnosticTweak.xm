#import "DiagnosticTweak.h"

// Inicialização das variáveis globais
NSString *g_sessionId = nil;
NSString *g_appName = nil;
NSString *g_bundleId = nil;
CGSize g_cameraResolution = CGSizeZero;
CGSize g_frontCameraResolution = CGSizeZero;
CGSize g_backCameraResolution = CGSizeZero;
int g_videoOrientation = 0;
BOOL g_isCapturingPhoto = NO;
BOOL g_isRecordingVideo = NO;
BOOL g_usingFrontCamera = NO;
NSDictionary *g_lastPhotoMetadata = nil;
NSMutableDictionary *g_sessionInfo = nil;

// Função para iniciar uma nova sessão de diagnóstico com tratamento de erros
void startNewDiagnosticSession(void) {
    @try {
        // Gerar novo ID de sessão
        g_sessionId = [[NSUUID UUID] UUIDString];
        g_sessionInfo = [NSMutableDictionary dictionary];
        
        // Obter informações do processo atual
        g_appName = [NSProcessInfo processInfo].processName;
        g_bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
        
        // Configurar o logger e iniciar nova sessão
        startNewLogSession();
        
        // Registrar informações básicas da sessão
        setLogSessionValue(@"sessionId", g_sessionId);
        setLogSessionValue(@"appName", g_appName);
        setLogSessionValue(@"bundleId", g_bundleId);
        setLogSessionValue(@"deviceModel", [[UIDevice currentDevice] model]);
        setLogSessionValue(@"iosVersion", [[UIDevice currentDevice] systemVersion]);
        
        logMessage([NSString stringWithFormat:@"Nova sessão de diagnóstico iniciada para %@ (%@)",
                    g_appName, g_bundleId], LogLevelInfo, LogCategorySession);
    } @catch (NSException *exception) {
        // Usar NSLog que é mais seguro em caso de falhas
        NSLog(@"[CameraDiagnostic] Erro ao iniciar sessão: %@", exception);
    }
}

// Função para registrar informações da sessão com tratamento de erros
void logSessionInfo(NSString *key, id value) {
    if (!key || !value) return;
    
    @try {
        // Adicionar ao dicionário da sessão
        g_sessionInfo[key] = value;
        
        // Registrar no log
        setLogSessionValue(key, value);
        
        // Log para console
        logMessage([NSString stringWithFormat:@"Sessão %@: %@ = %@",
                    g_sessionId, key, value], LogLevelDebug, LogCategorySession);
    } @catch (NSException *exception) {
        NSLog(@"[CameraDiagnostic] Erro ao registrar informação de sessão: %@", exception);
    }
}

// Função para finalizar e salvar o diagnóstico com tratamento de erros
void finalizeDiagnosticSession(void) {
    @try {
        // Adicionar resumo final
        NSMutableDictionary *summary = [NSMutableDictionary dictionary];
        
        if (!CGSizeEqualToSize(g_frontCameraResolution, CGSizeZero)) {
            summary[@"frontCameraResolution"] = NSStringFromCGSize(g_frontCameraResolution);
        }
        
        if (!CGSizeEqualToSize(g_backCameraResolution, CGSizeZero)) {
            summary[@"backCameraResolution"] = NSStringFromCGSize(g_backCameraResolution);
        }
        
        if (g_videoOrientation > 0) {
            summary[@"lastVideoOrientation"] = @(g_videoOrientation);
            
            NSString *orientationString;
            switch (g_videoOrientation) {
                case 1: orientationString = @"Portrait"; break;
                case 2: orientationString = @"PortraitUpsideDown"; break;
                case 3: orientationString = @"LandscapeRight"; break;
                case 4: orientationString = @"LandscapeLeft"; break;
                default: orientationString = @"Unknown"; break;
            }
            summary[@"lastVideoOrientationString"] = orientationString;
        }
        
        // Combinar com informações de sessão existentes
        if (g_sessionInfo) {
            [g_sessionInfo addEntriesFromDictionary:summary];
            
            // Adicionar ao log
            logJSONWithDescription(g_sessionInfo, LogCategorySession, @"Resumo de diagnóstico");
            
            // Finalizar sessão
            finalizeLogSession();
        }
        
        // Log para console
        logMessage(@"Sessão de diagnóstico finalizada", LogLevelInfo, LogCategorySession);
    } @catch (NSException *exception) {
        NSLog(@"[CameraDiagnostic] Erro ao finalizar sessão: %@", exception);
    }
}
