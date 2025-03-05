#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <mach/mach_time.h>

// Forward declarations
static void analyzeBuffer(CMSampleBufferRef buffer, NSString *source);
static void logPixelBuffer(CVPixelBufferRef pixelBuffer, NSString *context);
static void logAttachments(CMSampleBufferRef sampleBuffer);

#pragma mark - AVCaptureSession Hooks

%hook AVCaptureSession

// Track when camera sessions are created and started
- (id)init {
    id session = %orig;
    NSLog(@"[CameraDiag] AVCaptureSession initialized: %p", session);
    return session;
}

- (void)startRunning {
    NSLog(@"[CameraDiag] AVCaptureSession starting: %p", self);
    
    // Log all inputs and their properties
    NSArray *inputs = [self inputs];
    NSLog(@"[CameraDiag] Session has %lu inputs", (unsigned long)[inputs count]);
    for (AVCaptureInput *input in inputs) {
        if ([input isKindOfClass:%c(AVCaptureDeviceInput)]) {
            AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)input;
            AVCaptureDevice *device = [deviceInput device];
            NSLog(@"[CameraDiag] Camera device: %@, position: %ld, uniqueID: %@, modelID: %@",
                  [device localizedName],
                  (long)[device position],
                  [device uniqueID],
                  [device modelID]);
            
            // Log device format (crucial for matching in substitution)
            AVCaptureDeviceFormat *format = [device activeFormat];
            CMFormatDescriptionRef formatDescription = [format formatDescription];
            FourCharCode mediaSubType = CMFormatDescriptionGetMediaSubType(formatDescription);
            NSLog(@"[CameraDiag] Device format: dimensions=%@, mediaSubType=%c%c%c%c, max framerate=%f",
                  CMVideoFormatDescriptionGetDimensions(formatDescription).width ?
                  [NSString stringWithFormat:@"%dx%d",
                   CMVideoFormatDescriptionGetDimensions(formatDescription).width,
                   CMVideoFormatDescriptionGetDimensions(formatDescription).height] : @"unknown",
                  (char)((mediaSubType >> 24) & 0xFF),
                  (char)((mediaSubType >> 16) & 0xFF),
                  (char)((mediaSubType >> 8) & 0xFF),
                  (char)(mediaSubType & 0xFF),
                  [[format videoSupportedFrameRateRanges][0] maxFrameRate]);
        }
    }
    
    // Log all outputs and their properties
    NSArray *outputs = [self outputs];
    NSLog(@"[CameraDiag] Session has %lu outputs", (unsigned long)[outputs count]);
    for (AVCaptureOutput *output in outputs) {
        NSLog(@"[CameraDiag] Output: %@", [output class]);
        
        if ([output isKindOfClass:%c(AVCaptureVideoDataOutput)]) {
            AVCaptureVideoDataOutput *videoOutput = (AVCaptureVideoDataOutput *)output;
            NSLog(@"[CameraDiag] Video output settings: %@", [videoOutput videoSettings]);
            NSLog(@"[CameraDiag] Video output delegate: %@", [videoOutput sampleBufferDelegate]);
        }
        else if ([output isKindOfClass:%c(AVCapturePhotoOutput)]) {
            AVCapturePhotoOutput *photoOutput = (AVCapturePhotoOutput *)output;
            NSLog(@"[CameraDiag] Photo output supported formats: %@", [photoOutput availablePhotoCodecTypes]);
        }
    }
    
    // Log connections - available on iOS 13+, so we check availability first
    if (@available(iOS 13.0, *)) {
        NSArray *connections = [self connections];
        NSLog(@"[CameraDiag] Session has %lu connections", (unsigned long)[connections count]);
        for (AVCaptureConnection *connection in connections) {
            NSLog(@"[CameraDiag] Connection: input ports=%@, output=%@, enabled=%d",
                  [connection inputPorts],
                  [connection output],
                  [connection isEnabled]);
        }
    }
    
    %orig;
    NSLog(@"[CameraDiag] AVCaptureSession started: %p", self);
}

- (void)stopRunning {
    NSLog(@"[CameraDiag] AVCaptureSession stopping: %p", self);
    %orig;
}

- (void)addInput:(AVCaptureInput *)input {
    NSLog(@"[CameraDiag] Adding input to session: %@", input);
    %orig;
}

- (void)addOutput:(AVCaptureOutput *)output {
    NSLog(@"[CameraDiag] Adding output to session: %@", output);
    %orig;
}

%end

#pragma mark - Output Delegate Hooks

%hook AVCaptureVideoDataOutput

// Track when delegates are set up to receive camera frames
- (void)setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    NSLog(@"[CameraDiag] Setting video buffer delegate: %@ on queue: %@",
          [sampleBufferDelegate class], sampleBufferCallbackQueue);
    %orig;
}

%end

%hook AVCapturePhotoOutput

// Track photo capture process
- (void)capturePhotoWithSettings:(AVCapturePhotoSettings *)settings delegate:(id<AVCapturePhotoCaptureDelegate>)delegate {
    NSLog(@"[CameraDiag] Capturing photo with settings: %@, delegate: %@", settings, [delegate class]);
    %orig;
}

%end

#pragma mark - Buffer Processing Hooks

%hook NSObject

// This is where we intercept the camera frames as they're delivered to apps
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if ([self respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
        NSString *className = NSStringFromClass([self class]);
        
        // Track the first time we see a new class handling camera frames
        static NSMutableSet *seenClasses = nil;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            seenClasses = [NSMutableSet new];
        });
        
        if (![seenClasses containsObject:className]) {
            [seenClasses addObject:className];
            NSLog(@"[CameraDiag] New buffer handler class detected: %@", className);
            NSLog(@"[CameraDiag] Class hierarchy: %@", NSStringFromClass([self superclass]));
            
            // Log stack trace to understand calling context
            NSArray *callStack = [NSThread callStackSymbols];
            NSLog(@"[CameraDiag] First-time handler stack trace: %@",
                  [callStack componentsJoinedByString:@"\n"]);
        }
        
        // Analyze the buffer structure
        analyzeBuffer(sampleBuffer, className);
    }
    
    %orig;
}

// Track image data after it's been processed for photo capture
- (void)captureOutput:(AVCapturePhotoOutput *)output didFinishProcessingPhoto:(AVCapturePhoto *)photo error:(NSError *)error {
    if ([self respondsToSelector:@selector(captureOutput:didFinishProcessingPhoto:error:)]) {
        NSLog(@"[CameraDiag] Photo processed by: %@, data length: %lu",
              [self class], (unsigned long)[[photo fileDataRepresentation] length]);
    }
    %orig;
}

%end

#pragma mark - Buffer Copy and Manipulation Hooks

// Hook low-level buffer copy operation to track buffer flow
%hookf(OSStatus, CMSampleBufferCreateCopy, CFAllocatorRef allocator, CMSampleBufferRef sbuf, CMSampleBufferRef *sbufOut) {
    OSStatus result = %orig;
    if (result == noErr && sbufOut && *sbufOut) {
        NSLog(@"[CameraDiag] Buffer copied: %p -> %p", sbuf, *sbufOut);
    }
    return result;
}

// Track pixel buffer creation to understand conversion process
%hookf(CVReturn, CVPixelBufferCreate, CFAllocatorRef allocator, size_t width, size_t height, OSType pixelFormatType, CFDictionaryRef pixelBufferAttributes, CVPixelBufferRef *pixelBufferOut) {
    CVReturn result = %orig;
    if (result == kCVReturnSuccess && pixelBufferOut && *pixelBufferOut) {
        NSLog(@"[CameraDiag] New CVPixelBuffer created: %p, %zux%zu, format=%c%c%c%c",
              *pixelBufferOut, width, height,
              (char)((pixelFormatType >> 24) & 0xFF),
              (char)((pixelFormatType >> 16) & 0xFF),
              (char)((pixelFormatType >> 8) & 0xFF),
              (char)(pixelFormatType & 0xFF));
    }
    return result;
}

// Track when buffers are locked for access (important for substitution)
%hookf(CVReturn, CVPixelBufferLockBaseAddress, CVPixelBufferRef pixelBuffer, CVOptionFlags lockFlags) {
    NSLog(@"[CameraDiag] CVPixelBufferLockBaseAddress: %p, flags: %lu",
          pixelBuffer, (unsigned long)lockFlags);
    return %orig;
}

#pragma mark - UI Presentation Hooks

// Track when preview layers are set up
%hook AVCaptureVideoPreviewLayer

- (void)setSession:(AVCaptureSession *)session {
    NSLog(@"[CameraDiag] Preview layer (%p) connected to session: %p", self, session);
    %orig;
}

- (void)setVideoGravity:(AVLayerVideoGravity)videoGravity {
    NSLog(@"[CameraDiag] Preview layer (%p) gravity set: %@", self, videoGravity);
    %orig;
}

%end

// Track where camera content is being displayed
%hook CALayer

- (void)setContents:(id)contents {
    if (contents) {
        Class contentsClass = object_getClass(contents);
        NSString *className = NSStringFromClass(contentsClass);
        
        // Focus on camera-related content only
        if ([className containsString:@"IOSurface"] ||
            [className containsString:@"CVPixelBuffer"] ||
            [className containsString:@"CMSampleBuffer"]) {
            NSLog(@"[CameraDiag] Camera content being set to layer: %@, content class: %@",
                  [self class], className);
        }
    }
    %orig;
}

%end

#pragma mark - Security Detection Hooks

// Track when apps check for file existence (common in jailbreak detection)
%hook NSFileManager

- (BOOL)fileExistsAtPath:(NSString *)path {
    BOOL result = %orig;
    // Only log camera-related or jailbreak-detection-related checks
    if ([path containsString:@"Camera"] ||
        [path containsString:@"camera"] ||
        [path containsString:@"AVCapture"] ||
        [path containsString:@"/Applications/Cydia.app"] ||
        [path containsString:@"/Library/MobileSubstrate"]) {
        NSLog(@"[CameraDiag] Security check: fileExistsAtPath: %@, result: %d", path, result);
    }
    return result;
}

%end

#pragma mark - Analysis Helper Functions

// Analyze buffer contents and metadata
static void analyzeBuffer(CMSampleBufferRef buffer, NSString *source) {
    if (!buffer) return;
    
    // Limit logging frequency to avoid overwhelming logs
    static uint64_t lastBufferAnalysisTime = 0;
    uint64_t currentTime = mach_absolute_time();
    
    // Only log once per second max
    if (currentTime - lastBufferAnalysisTime < 1000000000) {
        return;
    }
    lastBufferAnalysisTime = currentTime;
    
    // Get timing information
    CMTime presentationTime = CMSampleBufferGetPresentationTimeStamp(buffer);
    CMTime duration = CMSampleBufferGetDuration(buffer);
    Float64 timeInSeconds = CMTimeGetSeconds(presentationTime);
    
    // Log basic buffer info
    NSLog(@"[CameraDiag] Buffer from %@: time=%.3fs, duration=%.4fs",
          source, timeInSeconds, CMTimeGetSeconds(duration));
    
    // Analyze attachments and metadata
    logAttachments(buffer);
    
    // Analyze pixel buffer
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(buffer);
    if (imageBuffer) {
        logPixelBuffer(imageBuffer, [NSString stringWithFormat:@"Buffer from %@", source]);
    }
    
    // Get format description
    CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(buffer);
    if (formatDesc) {
        FourCharCode mediaSubType = CMFormatDescriptionGetMediaSubType(formatDesc);
        NSLog(@"[CameraDiag] Buffer format: media type=%@, subtype=%c%c%c%c",
              CMFormatDescriptionGetMediaType(formatDesc) == kCMMediaType_Video ? @"video" : @"other",
              (char)((mediaSubType >> 24) & 0xFF),
              (char)((mediaSubType >> 16) & 0xFF),
              (char)((mediaSubType >> 8) & 0xFF),
              (char)(mediaSubType & 0xFF));
        
        // Get dimensions for video
        if (CMFormatDescriptionGetMediaType(formatDesc) == kCMMediaType_Video) {
            CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDesc);
            NSLog(@"[CameraDiag] Video dimensions: %dx%d", dimensions.width, dimensions.height);
        }
    }
}

// Analyze pixel buffer properties
static void logPixelBuffer(CVPixelBufferRef pixelBuffer, NSString *context) {
    if (!pixelBuffer) return;
    
    // Get basic properties
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    OSType pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    size_t planeCount = CVPixelBufferGetPlaneCount(pixelBuffer);
    
    NSLog(@"[CameraDiag] %@: %zux%zu, format=%c%c%c%c, bytesPerRow=%zu, planes=%zu",
          context, width, height,
          (char)((pixelFormat >> 24) & 0xFF),
          (char)((pixelFormat >> 16) & 0xFF),
          (char)((pixelFormat >> 8) & 0xFF),
          (char)(pixelFormat & 0xFF),
          bytesPerRow, planeCount);
    
    // Check if buffer is contiguous
    Boolean isContiguous = CVPixelBufferIsPlanar(pixelBuffer) == 0;
    NSLog(@"[CameraDiag] Pixel buffer is %@", isContiguous ? @"contiguous" : @"planar");
}

// Analyze buffer attachments and metadata
static void logAttachments(CMSampleBufferRef sampleBuffer) {
    // Get attachments if available
    CFArrayRef attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, FALSE);
    if (attachmentsArray && CFArrayGetCount(attachmentsArray) > 0) {
        CFDictionaryRef attachments = (CFDictionaryRef)CFArrayGetValueAtIndex(attachmentsArray, 0);
        if (attachments) {
            // Log generic information about attachments
            NSLog(@"[CameraDiag] Buffer has %ld attachment keys", CFDictionaryGetCount(attachments));
            
            // Look for DependsOnOthers key
            if (CFDictionaryContainsKey(attachments, kCMSampleAttachmentKey_DependsOnOthers)) {
                CFBooleanRef value = (CFBooleanRef)CFDictionaryGetValue(attachments, kCMSampleAttachmentKey_DependsOnOthers);
                NSLog(@"[CameraDiag] Buffer depends on others: %@", value == kCFBooleanTrue ? @"YES" : @"NO");
            }
            
            // Look for NotSync key (indicates if frame is keyframe)
            if (CFDictionaryContainsKey(attachments, kCMSampleAttachmentKey_NotSync)) {
                CFBooleanRef value = (CFBooleanRef)CFDictionaryGetValue(attachments, kCMSampleAttachmentKey_NotSync);
                NSLog(@"[CameraDiag] Buffer is key frame: %@", value == kCFBooleanFalse ? @"YES" : @"NO");
            }
        }
    }
    
    // Check for metadata attachments
    CFTypeRef metadataAttachment = CMGetAttachment(sampleBuffer, CFSTR("MetadataDictionary"), NULL);
    if (metadataAttachment) {
        NSLog(@"[CameraDiag] Buffer has metadata attachment");
    }
}

%ctor {
    %init;
    NSLog(@"[CameraDiag] **** Camera Diagnostic Tweak Initialized ****");
}
