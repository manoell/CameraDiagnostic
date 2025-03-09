#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreImage/CoreImage.h>
#import <Metal/Metal.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "logger.h"

// Estado de monitoramento
static BOOL cameraIsActive = NO;

// Hooks AVFoundation
%hook AVCaptureSession
-(id)init {
    id result = %orig;
    writeLog(@"[INIT] AVCaptureSession: %@ em bundle: %@", result, [[NSBundle mainBundle] bundleIdentifier]);
    return result;
}

-(void)startRunning {
    writeLog(@"[SESSION] AVCaptureSession startRunning - Preset: %@ - App: %@",
             self.sessionPreset, [[NSBundle mainBundle] bundleIdentifier]);
    cameraIsActive = YES;
    %orig;
}

-(void)stopRunning {
    writeLog(@"[SESSION] AVCaptureSession stopRunning - App: %@",
             [[NSBundle mainBundle] bundleIdentifier]);
    cameraIsActive = NO;
    %orig;
}

-(BOOL)addInput:(AVCaptureInput *)input {
    BOOL result = %orig;
    writeLog(@"[SESSION] addInput: %@ - Resultado: %d - App: %@",
             input, result, [[NSBundle mainBundle] bundleIdentifier]);
    if ([input isKindOfClass:[AVCaptureDeviceInput class]]) {
        AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
        writeLog(@"[DEVICE_INPUT] Dispositivo: %@, posição: %ld, uniqueID: %@",
                 deviceInput.device.localizedName,
                 (long)deviceInput.device.position,
                 deviceInput.device.uniqueID);
        
        if ([deviceInput.device hasMediaType:AVMediaTypeVideo]) {
            cameraIsActive = YES;
        }
    }
    return result;
}

-(BOOL)addOutput:(AVCaptureOutput *)output {
    BOOL result = %orig;
    writeLog(@"[SESSION] addOutput: %@ - Resultado: %d - App: %@",
             output, result, [[NSBundle mainBundle] bundleIdentifier]);
    return result;
}
%end

%hook AVCaptureDevice
+(NSArray *)devices {
    NSArray *result = %orig;
    writeLog(@"[DEVICE] AVCaptureDevice devices: %@ - App: %@",
             result, [[NSBundle mainBundle] bundleIdentifier]);
    return result;
}

+(NSArray *)devicesWithMediaType:(NSString *)mediaType {
    NSArray *result = %orig;
    writeLog(@"[DEVICE] AVCaptureDevice devicesWithMediaType: %@ - Resultado: %@ - App: %@",
             mediaType, result, [[NSBundle mainBundle] bundleIdentifier]);
    
    if ([mediaType isEqualToString:AVMediaTypeVideo]) {
        writeLog(@"[CAMERA_QUERY] Aplicativo está consultando dispositivos de câmera - App: %@",
                [[NSBundle mainBundle] bundleIdentifier]);
    }
    return result;
}

+(AVCaptureDevice *)defaultDeviceWithMediaType:(NSString *)mediaType {
    AVCaptureDevice *result = %orig;
    writeLog(@"[DEVICE] AVCaptureDevice defaultDeviceWithMediaType: %@ - Resultado: %@ - App: %@",
             mediaType, result, [[NSBundle mainBundle] bundleIdentifier]);
    
    if ([mediaType isEqualToString:AVMediaTypeVideo]) {
        writeLog(@"[CAMERA_QUERY] Aplicativo está solicitando câmera padrão - App: %@",
                [[NSBundle mainBundle] bundleIdentifier]);
    }
    return result;
}

-(BOOL)lockForConfiguration:(NSError **)error {
    BOOL result = %orig;
    writeLog(@"[DEVICE] lockForConfiguration - Result: %d - App: %@",
             result, [[NSBundle mainBundle] bundleIdentifier]);
    return result;
}
%end

%hook AVCaptureDeviceInput
+(AVCaptureDeviceInput *)deviceInputWithDevice:(AVCaptureDevice *)device error:(NSError **)outError {
    AVCaptureDeviceInput *result = %orig;
    writeLog(@"[DEVICE_INPUT] deviceInputWithDevice: %@ - Resultado: %@ - App: %@",
             device, result, [[NSBundle mainBundle] bundleIdentifier]);
    return result;
}

-(id)initWithDevice:(AVCaptureDevice *)device error:(NSError **)outError {
    id result = %orig;
    writeLog(@"[DEVICE_INPUT] initWithDevice: %@ - Resultado: %@ - App: %@",
             device, result, [[NSBundle mainBundle] bundleIdentifier]);
    return result;
}
%end

%hook AVCaptureVideoDataOutput
-(void)setSampleBufferDelegate:(id)delegate queue:(dispatch_queue_t)queue {
    writeLog(@"[OUTPUT] AVCaptureVideoDataOutput setSampleBufferDelegate - Delegate: %@, Queue: %@ - App: %@",
             delegate, queue, [[NSBundle mainBundle] bundleIdentifier]);
    %orig;
}

-(id)sampleBufferDelegate {
    id result = %orig;
    writeLog(@"[OUTPUT] AVCaptureVideoDataOutput sampleBufferDelegate accessed: %@ - App: %@",
             result, [[NSBundle mainBundle] bundleIdentifier]);
    return result;
}
%end

%hook AVCaptureConnection
-(void)setVideoOrientation:(AVCaptureVideoOrientation)videoOrientation {
    writeLog(@"[CONNECTION] setVideoOrientation: %ld - App: %@",
             (long)videoOrientation, [[NSBundle mainBundle] bundleIdentifier]);
    %orig;
}

-(void)setVideoMirrored:(BOOL)videoMirrored {
    writeLog(@"[CONNECTION] setVideoMirrored: %d - App: %@",
             videoMirrored, [[NSBundle mainBundle] bundleIdentifier]);
    %orig;
}
%end

// Hooks para processamento de imagem
%hook CIContext
-(void)render:(CIImage *)image toCVPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    writeLog(@"[IMAGE_PROCESSING] CIContext render:toCVPixelBuffer - App: %@",
             [[NSBundle mainBundle] bundleIdentifier]);
    %orig;
    logPixelBufferDetails(pixelBuffer, @"CIContext render:toCVPixelBuffer output");
}
%end

%hook CIImage
-(id)initWithCVPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    id result = %orig;
    writeLog(@"[IMAGE_PROCESSING] CIImage initWithCVPixelBuffer - App: %@",
             [[NSBundle mainBundle] bundleIdentifier]);
    logPixelBufferDetails(pixelBuffer, @"CIImage initWithCVPixelBuffer input");
    return result;
}

-(id)initWithCVPixelBuffer:(CVPixelBufferRef)pixelBuffer options:(NSDictionary *)options {
    id result = %orig;
    writeLog(@"[IMAGE_PROCESSING] CIImage initWithCVPixelBuffer:options - App: %@",
             [[NSBundle mainBundle] bundleIdentifier]);
    logPixelBufferDetails(pixelBuffer, @"CIImage initWithCVPixelBuffer:options input");
    return result;
}
%end

// Hooks para visualização da câmera
%hook AVCaptureVideoPreviewLayer
-(void)setSession:(AVCaptureSession *)session {
    writeLog(@"[DISPLAY] AVCaptureVideoPreviewLayer setSession: %@ - App: %@",
             session, [[NSBundle mainBundle] bundleIdentifier]);
    %orig;
}

-(AVCaptureSession *)session {
    AVCaptureSession *result = %orig;
    writeLog(@"[DISPLAY] AVCaptureVideoPreviewLayer session acessada: %@ - App: %@",
             result, [[NSBundle mainBundle] bundleIdentifier]);
    return result;
}

-(void)setVideoGravity:(AVLayerVideoGravity)videoGravity {
    writeLog(@"[DISPLAY] AVCaptureVideoPreviewLayer setVideoGravity: %@ - App: %@",
             videoGravity, [[NSBundle mainBundle] bundleIdentifier]);
    %orig;
}

-(void)layoutSublayers {
    writeLog(@"[DISPLAY] AVCaptureVideoPreviewLayer layoutSublayers - Frame: %@ - App: %@",
             NSStringFromCGRect(self.frame), [[NSBundle mainBundle] bundleIdentifier]);
    %orig;
}
%end

// Hooks para buffers de vídeo
%hook AVSampleBufferDisplayLayer
- (void)enqueueSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    // Limitar logging para reduzir sobrecarga
    static int frameCount = 0;
    if (frameCount++ % 30 == 0) {
        writeLog(@"[DISPLAY_HOOK] AVSampleBufferDisplayLayer enqueueSampleBuffer called - Frame #%d - App: %@",
                 frameCount, [[NSBundle mainBundle] bundleIdentifier]);
        logBufferDetails(sampleBuffer, @"AVSampleBufferDisplayLayer enqueueSampleBuffer");
    }
    %orig;
}

- (void)flush {
    writeLog(@"[DISPLAY_HOOK] AVSampleBufferDisplayLayer flush called - App: %@",
             [[NSBundle mainBundle] bundleIdentifier]);
    %orig;
}
%end

// Hooks para captura de foto e vídeo
%hook AVCapturePhotoOutput
-(void)capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    writeLog(@"[PHOTO] AVCapturePhotoOutput capturePhotoWithSettings - Settings: %@, Delegate: %@ - App: %@",
             settings, delegate, [[NSBundle mainBundle] bundleIdentifier]);
    %orig;
}
%end

%hook AVCaptureMovieFileOutput
-(void)startRecordingToOutputFileURL:(NSURL *)outputFileURL recordingDelegate:(id<AVCaptureFileOutputRecordingDelegate>)delegate {
    writeLog(@"[VIDEO] AVCaptureMovieFileOutput startRecordingToOutputFileURL - URL: %@, Delegate: %@ - App: %@",
             outputFileURL, delegate, [[NSBundle mainBundle] bundleIdentifier]);
    %orig;
}

-(void)stopRecording {
    writeLog(@"[VIDEO] AVCaptureMovieFileOutput stopRecording - App: %@",
             [[NSBundle mainBundle] bundleIdentifier]);
    %orig;
}
%end

// Hooks genéricos para capturar delegates
%hook NSObject
// Para AVCaptureVideoDataOutputSampleBufferDelegate
-(void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (![self respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
        %orig;
        return;
    }
    
    // Throttle para reduzir quantidade de logs
    static int frameCount = 0;
    if (frameCount++ % 30 == 0) {
        writeLog(@"[BUFFER_HOOK] Frame de vídeo #%d capturado - Delegate: %@ - App: %@",
                 frameCount, [self class], [[NSBundle mainBundle] bundleIdentifier]);
        
        // Log detalhado sobre o buffer para análise (formato, tamanho, etc)
        logBufferDetails(sampleBuffer, @"didOutputSampleBuffer");
        
        // Captura informações sobre o formato específico do vídeo
        CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        if (pixelBuffer) {
            size_t width = CVPixelBufferGetWidth(pixelBuffer);
            size_t height = CVPixelBufferGetHeight(pixelBuffer);
            OSType pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
            
            char formatStr[5] = {0};
            formatStr[0] = (char)((pixelFormat >> 24) & 0xFF);
            formatStr[1] = (char)((pixelFormat >> 16) & 0xFF);
            formatStr[2] = (char)((pixelFormat >> 8) & 0xFF);
            formatStr[3] = (char)(pixelFormat & 0xFF);
            
            writeLog(@"[PIXEL_FORMAT] Formato exato do buffer: %s, Tamanho: %zux%zu - App: %@",
                     formatStr, width, height, [[NSBundle mainBundle] bundleIdentifier]);
        }
    }
    
    %orig;
}

// Para AVCapturePhotoCaptureDelegate
-(void)captureOutput:(AVCaptureOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(NSError *)error {
    if ([self respondsToSelector:@selector(captureOutput:didFinishProcessingPhoto:error:)]) {
        writeLog(@"[PHOTO] AVCapturePhotoCaptureDelegate didFinishProcessingPhoto - Photo: %@, Error: %@ - App: %@",
                 photo, error, [[NSBundle mainBundle] bundleIdentifier]);
        if (photo) {
            if ([photo respondsToSelector:@selector(metadata)]) {
                writeLog(@"[PHOTO_DETAILS] Metadados: %@ - App: %@",
                         [photo metadata], [[NSBundle mainBundle] bundleIdentifier]);
            }
            
            if ([photo respondsToSelector:@selector(pixelBuffer)]) {
                CVPixelBufferRef pixelBuffer = [photo pixelBuffer];
                if (pixelBuffer) {
                    logPixelBufferDetails(pixelBuffer, @"AVCapturePhotoOutput photo pixelBuffer");
                }
            }
        }
    }
    %orig;
}

// Para AVCaptureFileOutputRecordingDelegate
-(void)captureOutput:(AVCaptureOutput *)output didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error {
    if ([self respondsToSelector:@selector(captureOutput:didFinishRecordingToOutputFileAtURL:fromConnections:error:)]) {
        writeLog(@"[VIDEO] AVCaptureFileOutputRecordingDelegate didFinishRecordingToOutputFile - URL: %@, Error: %@ - App: %@",
                 outputFileURL, error, [[NSBundle mainBundle] bundleIdentifier]);
    }
    %orig;
}
%end

// Hook para CALayer para detectar renderizações desconhecidas
%hook CALayer
-(void)setContents:(id)contents {
    %orig;
    
    // Apenas verificar camadas maiores quando a câmera está ativa
    if (cameraIsActive && contents != nil) {
        CGRect frame = self.frame;
        if (frame.size.width > 100 && frame.size.height > 100) {
            static int contentsCount = 0;
            if (contentsCount++ % 30 == 0) {
                writeLog(@"[DISPLAY_CHECK] CALayer setContents - Tipo: %@ - Frame: %@ - App: %@",
                        [contents class], NSStringFromCGRect(frame), [[NSBundle mainBundle] bundleIdentifier]);
            }
        }
    }
}
%end

%ctor {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
    NSString *processName = [[NSProcessInfo processInfo] processName] ?: @"unknown";
    
    // Apenas evitar processos críticos do sistema
    if ([bundleID isEqualToString:@"com.apple.springboard"] ||
        [bundleID isEqualToString:@"com.apple.backboardd"] ||
        [bundleID isEqualToString:@"com.apple.mediaserverd"]) {
        writeLog(@"[PROTEÇÃO] Não inicializando hooks em processo crítico do sistema: %@", bundleID);
        return;
    }
    
    // Detectar se é um aplicativo que provavelmente usa a câmera
    BOOL isCameraApp =
        [bundleID isEqualToString:@"com.apple.camera"] ||
        [bundleID isEqualToString:@"com.burbn.instagram"] ||
        [bundleID isEqualToString:@"com.toyopagroup.picaboo"] || // Snapchat
        [bundleID isEqualToString:@"com.atebits.Tweetie2"] || // Twitter
        [bundleID isEqualToString:@"com.facebook.Facebook"] ||
        [bundleID isEqualToString:@"net.whatsapp.WhatsApp"] ||
        [bundleID isEqualToString:@"ph.telegra.Telegraph"] ||
        [bundleID isEqualToString:@"com.google.ios.youtube"] ||
        [bundleID isEqualToString:@"com.zhiliaoapp.musically"] || // TikTok
        [processName containsString:@"camera"] ||
        [processName containsString:@"facetime"];
    
    writeLog(@"===== Iniciando Universal Camera Logger - BundleID: %@, ProcessName: %@ =====", bundleID, processName);
    writeLog(@"[APP_TYPE] %@", isCameraApp ? @"App de câmera detectado!" : @"App padrão");
    
    // Informações do dispositivo
    UIDevice *device = [UIDevice currentDevice];
    writeLog(@"[DEVICE_INFO] Nome: %@, Modelo: %@, Sistema: %@ %@",
             device.name, device.model, device.systemName, device.systemVersion);
    
    // Log de todos os frameworks carregados relevantes para câmera
    NSArray *frameworks = [NSBundle allFrameworks];
    for (NSBundle *framework in frameworks) {
        NSString *frameworkID = [framework bundleIdentifier];
        if ([frameworkID containsString:@"camera"] ||
            [frameworkID containsString:@"AVFoundation"] ||
            [frameworkID containsString:@"CoreMedia"] ||
            [frameworkID containsString:@"CoreVideo"]) {
            writeLog(@"[FRAMEWORK] Framework relevante carregado: %@", frameworkID);
        }
    }
    
    // Para apps de câmera, adicionar lógica de busca de delegados
    if (isCameraApp) {
        // Buscar classes específicas de delegados para diferentes apps
        NSArray *delegateClassNames = @[
            @"CAMCaptureEngine",
            @"PLCameraController",
            @"PLCaptureSession",
            @"SCCapture",
            @"TGCameraController",
            @"INCameraController"
        ];
        
        for (NSString *className in delegateClassNames) {
            Class delegateClass = NSClassFromString(className);
            if (delegateClass) {
                writeLog(@"[HOOK_SPECIAL] Encontrado delegado potencial para app: %@", className);
            }
        }
        
        // Adicionar função para verificar sessões ativas de câmera periodicamente
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            writeLog(@"[MONITOR] Iniciando monitoramento para sessões de câmera ativas");
            
            // Buscar todas as instâncias de AVCaptureSession
            NSMutableArray *sessions = [NSMutableArray array];
            // (A lógica real depende de acesso a runtime que é complexo demostrar aqui)
            
            // Log informacional
            writeLog(@"[MONITOR] Encontradas %lu sessões de câmera ativas", (unsigned long)sessions.count);
        });
    }
    
    // Inicializar todos os hooks
    %init;
}
