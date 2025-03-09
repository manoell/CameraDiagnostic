#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreImage/CoreImage.h>
#import <Metal/Metal.h>
#import <SceneKit/SceneKit.h>
#import <ARKit/ARKit.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "logger.h"

// Ponteiro para o método original do delegate
static void (*original_captureOutput_didOutputSampleBuffer)(id, SEL, AVCaptureOutput *, CMSampleBufferRef, AVCaptureConnection *);

// Função personalizada para hook dinâmico
static void captureOutput_didOutputSampleBuffer(id self, SEL _cmd, AVCaptureOutput *output, CMSampleBufferRef sampleBuffer, AVCaptureConnection *connection) {
    writeLog(@"[BUFFER_HOOK] Delegate captureOutput called with Output: %@, Connection: %@", output, connection);
    logBufferDetails(sampleBuffer, @"Delegate didOutputSampleBuffer");
    // Chamar o método original, se disponível
    if (original_captureOutput_didOutputSampleBuffer) {
        original_captureOutput_didOutputSampleBuffer(self, _cmd, output, sampleBuffer, connection);
    }
}

%group AVFoundationHooks
%hook AVCaptureSession
-(id)init {
    id result = %orig;
    writeLog(@"[INIT] AVCaptureSession: %@", result);
    return result;
}

-(void)startRunning {
    writeLog(@"[SESSION] AVCaptureSession startRunning - Preset: %@", self.sessionPreset);
    %orig;
}

-(void)stopRunning {
    writeLog(@"[SESSION] AVCaptureSession stopRunning");
    %orig;
}
%end

%hook AVCaptureDevice
+(NSArray *)devices {
    NSArray *result = %orig;
    writeLog(@"[DEVICE] AVCaptureDevice devices: %@", result);
    return result;
}

-(BOOL)lockForConfiguration:(NSError **)error {
    BOOL result = %orig;
    writeLog(@"[DEVICE] lockForConfiguration - Result: %d", result);
    return result;
}
%end

%hook AVCaptureVideoDataOutput
-(void)setSampleBufferDelegate:(id)delegate queue:(dispatch_queue_t)queue {
    writeLog(@"[OUTPUT] AVCaptureVideoDataOutput setSampleBufferDelegate - Delegate: %@, Queue: %@", delegate, queue);
    %orig;
    if (delegate && [delegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
        MSHookMessageEx(object_getClass(delegate),
                        @selector(captureOutput:didOutputSampleBuffer:fromConnection:),
                        (IMP)&captureOutput_didOutputSampleBuffer,
                        (IMP *)&original_captureOutput_didOutputSampleBuffer);
    }
}

-(id)sampleBufferDelegate {
    id result = %orig;
    writeLog(@"[OUTPUT] AVCaptureVideoDataOutput sampleBufferDelegate accessed: %@", result);
    return result;
}
%end

%hook AVCaptureOutput
-(id)init {
    id result = %orig;
    writeLog(@"[INIT] AVCaptureOutput: %@", result);
    return result;
}
%end
%end

%group CoreMediaHooks
%hook CMSampleBuffer
-(id)init {
    id result = %orig;
    writeLog(@"[INIT] CMSampleBuffer: %@", result);
    return result;
}
%end
%end

%group CoreVideoHooks
%hook CVPixelBuffer
-(id)init {
    id result = %orig;
    writeLog(@"[INIT] CVPixelBuffer: %@", result);
    return result;
}
%end
%end

%group CoreImageHooks
%hook CIContext
-(CIImage *)createCGImage:(CIImage *)image fromRect:(CGRect)rect {
    CIImage *result = %orig;
    writeLog(@"[IMAGE_PROCESSING] CIContext createCGImage - Input: %@, Output: %@", image, result);
    return result;
}
%end
%end

%group MetalHooks
%hook MTLDevice
+(id)newDevice {
    id result = %orig;
    writeLog(@"[METAL] MTLDevice newDevice: %@", result);
    return result;
}

-(id<MTLTexture>)newTextureWithDescriptor:(MTLTextureDescriptor *)descriptor {
    id<MTLTexture> result = %orig;
    writeLog(@"[METAL] MTLDevice newTextureWithDescriptor - Width: %lu, Height: %lu",
             (unsigned long)descriptor.width, (unsigned long)descriptor.height);
    return result;
}
%end
%end

%group SceneKitHooks
%hook SCNRenderer
-(void)renderAtTime:(NSTimeInterval)time {
    writeLog(@"[SCENEKIT] SCNRenderer renderAtTime: %.4f", time);
    %orig;
}
%end
%end

%group ARKitHooks
%hook ARSession
-(void)runWithConfiguration:(ARConfiguration *)configuration {
    writeLog(@"[ARKIT] ARSession runWithConfiguration: %@", configuration);
    %orig;
}

-(ARFrame *)currentFrame {
    ARFrame *result = %orig;
    if (result) {
        logPixelBufferDetails(result.capturedImage, @"ARFrame capturedImage");
    }
    writeLog(@"[ARKIT] ARSession currentFrame: %@", result);
    return result;
}
%end
%end

%group UIKitHooks
%hook UIView
-(void)drawRect:(CGRect)rect {
    %orig;
    if ([self.layer isKindOfClass:[AVCaptureVideoPreviewLayer class]]) {
        writeLog(@"[DISPLAY] UIView drawRect with AVCaptureVideoPreviewLayer");
    }
}
%end

%hook CALayer
-(void)renderInContext:(CGContextRef)context {
    %orig;
    if ([self isKindOfClass:[AVSampleBufferDisplayLayer class]]) {
        writeLog(@"[DISPLAY] CALayer renderInContext with AVSampleBufferDisplayLayer");
    }
}
%end
%end

%group BufferHooks
%hook AVCaptureVideoDataOutput
-(void)setSampleBufferDelegate:(id)delegate queue:(dispatch_queue_t)queue {
    writeLog(@"[OUTPUT] AVCaptureVideoDataOutput setSampleBufferDelegate - Delegate: %@, Queue: %@", delegate, queue);
    %orig;
    if (delegate && [delegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
        MSHookMessageEx(object_getClass(delegate),
                        @selector(captureOutput:didOutputSampleBuffer:fromConnection:),
                        (IMP)&captureOutput_didOutputSampleBuffer,
                        (IMP *)&original_captureOutput_didOutputSampleBuffer);
    }
}
%end

%hook AVSampleBufferDisplayLayer
- (void)enqueueSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    writeLog(@"[DISPLAY_HOOK] AVSampleBufferDisplayLayer enqueueSampleBuffer called");
    logBufferDetails(sampleBuffer, @"AVSampleBufferDisplayLayer enqueueSampleBuffer");
    %orig;
}
%end
%end

%group IntegrityHooks
%hook AVCaptureDevice
-(BOOL)isConnected {
    BOOL result = %orig;
    writeLog(@"[INTEGRITY] AVCaptureDevice isConnected: %d", result);
    return result;
}

-(NSString *)uniqueID {
    NSString *result = %orig;
    writeLog(@"[INTEGRITY] AVCaptureDevice uniqueID: %@", result);
    return result;
}
%end
%end

%group LowLevelHooks
%hook CALayer
-(void)renderInContext:(CGContextRef)context {
    %orig;
    if (self.contents != nil && ![self isKindOfClass:[AVSampleBufferDisplayLayer class]]) {
        writeLog(@"[UNKNOWN_RENDER] CALayer renderInContext detectou renderização não identificada: %@", self);
    }
}
%end

%hook UIApplication
-(void)beginReceivingRemoteControlEvents {
    %orig;
    writeLog(@"[SYSTEM] beginReceivingRemoteControlEvents - Possível ativação de câmera ou mídia");
}
%end
%end

%group CaptureOutputHooks
%hook AVCapturePhotoOutput
-(void)capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    writeLog(@"[PHOTO] AVCapturePhotoOutput capturePhotoWithSettings - Settings: %@, Delegate: %@", settings, delegate);
    %orig;
}

-(void)captureOutput:(AVCaptureOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(NSError *)error {
    writeLog(@"[PHOTO] AVCapturePhotoOutput didFinishProcessingPhoto - Photo: %@, Error: %@", photo, error);
    if (photo) {
        CVPixelBufferRef pixelBuffer = [photo pixelBuffer];
        if (pixelBuffer) {
            logPixelBufferDetails(pixelBuffer, @"AVCapturePhotoOutput photo pixelBuffer");
        }
    }
    %orig;
}
%end

%hook AVCaptureMovieFileOutput
-(void)startRecordingToOutputFileURL:(NSURL *)outputFileURL recordingDelegate:(id<AVCaptureFileOutputRecordingDelegate>)delegate {
    writeLog(@"[VIDEO] AVCaptureMovieFileOutput startRecordingToOutputFileURL - URL: %@, Delegate: %@", outputFileURL, delegate);
    %orig;
}

-(void)captureOutput:(AVCaptureOutput *)output didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL fromConnections:(NSArray *)connections error:(NSError *)error {
    writeLog(@"[VIDEO] AVCaptureMovieFileOutput didFinishRecordingToOutputFile - URL: %@, Error: %@", outputFileURL, error);
    %orig;
}
%end
%end

%ctor {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
    NSString *processName = [[NSProcessInfo processInfo] processName] ?: @"unknown";
    writeLog(@"===== Iniciando Universal Camera Logger v2 - BundleID: %@, ProcessName: %@ =====", bundleID, processName);
    %init(AVFoundationHooks);
    %init(CoreMediaHooks);
    %init(CoreVideoHooks);
    %init(CoreImageHooks);
    %init(MetalHooks);
    %init(SceneKitHooks);
    %init(ARKitHooks);
    %init(UIKitHooks);
    %init(BufferHooks);
    %init(IntegrityHooks);
    %init(LowLevelHooks);
    %init(CaptureOutputHooks);
}
