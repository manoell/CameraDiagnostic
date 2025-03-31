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
uint64_t g_frameCounter = 0;

// Utilitário para converter formato de pixel para string legível
NSString *pixelFormatToString(OSType format) {
    char formatStr[5] = {0};
    formatStr[0] = (format >> 24) & 0xFF;
    formatStr[1] = (format >> 16) & 0xFF;
    formatStr[2] = (format >> 8) & 0xFF;
    formatStr[3] = format & 0xFF;
    
    return [NSString stringWithCString:formatStr encoding:NSASCIIStringEncoding] ?: @"unknown";
}

// Função para iniciar uma nova sessão de diagnóstico
void startNewDiagnosticSession(void) {
    @try {
        // Gerar novo ID de sessão
        g_sessionId = [[NSUUID UUID] UUIDString];
        
        // Obter informações do processo atual
        g_appName = [NSProcessInfo processInfo].processName;
        g_bundleId = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
        
        // Inicializar variáveis de estado
        g_frameCounter = 0;
        g_cameraResolution = CGSizeZero;
        g_frontCameraResolution = CGSizeZero;
        g_backCameraResolution = CGSizeZero;
        g_videoOrientation = 0;
        g_isCapturingPhoto = NO;
        g_isRecordingVideo = NO;
        g_usingFrontCamera = NO;
        
        // Registrar informações no log
        NSLog(@"[CameraDiagnostic] Nova sessão de diagnóstico iniciada para %@ (%@)",
              g_appName, g_bundleId);
        
    } @catch (NSException *exception) {
        // Usar NSLog que é mais seguro em caso de falhas
        NSLog(@"[CameraDiagnostic] Erro ao iniciar sessão: %@", exception);
    }
}

// Função para finalizar e salvar o diagnóstico
void finalizeDiagnosticSession(void) {
    @try {
        // Adicionar resumo final
        NSMutableDictionary *summary = [NSMutableDictionary dictionary];
        
        // Adicionar informações sobre a câmera
        if (!CGSizeEqualToSize(g_frontCameraResolution, CGSizeZero)) {
            summary[@"frontCameraResolution"] = NSStringFromCGSize(g_frontCameraResolution);
        }
        
        if (!CGSizeEqualToSize(g_backCameraResolution, CGSizeZero)) {
            summary[@"backCameraResolution"] = NSStringFromCGSize(g_backCameraResolution);
        }
        
        // Adicionar informações sobre orientação
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
        
        // Adicionar informações sobre frames
        if (g_frameCounter > 0) {
            summary[@"totalFramesProcessed"] = @(g_frameCounter);
        }
        
        NSLog(@"[CameraDiagnostic] Sessão de diagnóstico finalizada");
    } @catch (NSException *exception) {
        NSLog(@"[CameraDiagnostic] Erro ao finalizar sessão: %@", exception);
    }
}
