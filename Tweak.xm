#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <UIKit/UIKit.h>
#import <CoreImage/CoreImage.h>

// Função para salvar log em arquivo
static void writeToFile(NSString *message) {
    NSString *logPath = @"/var/tmp/CameraDiag.log";
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    
    if (!fileHandle) {
        [@"" writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
        fileHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    }
    
    [fileHandle seekToEndOfFile];
    NSString *logEntry = [NSString stringWithFormat:@"[%@] %@\n",
                        [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                      dateStyle:NSDateFormatterNoStyle
                                                      timeStyle:NSDateFormatterMediumStyle], message];
    [fileHandle writeData:[logEntry dataUsingEncoding:NSUTF8StringEncoding]];
    [fileHandle closeFile];
}

// Grupos de classes para monitoramento global
%group AVFoundationHooks

// Hook para toda a classe AVCaptureSession
%hook AVCaptureSession
-(id)init {
    id result = %orig;
    writeToFile([NSString stringWithFormat:@"[INIT] AVCaptureSession: %@", result]);
    return result;
}
// Este é um hook genérico que intercepta TODOS os métodos da classe
-(void)forwardInvocation:(NSInvocation *)invocation {
    NSString *selector = NSStringFromSelector([invocation selector]);
    writeToFile([NSString stringWithFormat:@"[METHOD] AVCaptureSession calling: %@", selector]);
    %orig;
}
%end

// Hook para toda a classe AVCaptureDevice
%hook AVCaptureDevice
// Hook genérico para métodos de classe
+ (void)forwardInvocation:(NSInvocation *)invocation {
    NSString *selector = NSStringFromSelector([invocation selector]);
    writeToFile([NSString stringWithFormat:@"[CLASS_METHOD] AVCaptureDevice calling: %@", selector]);
    %orig;
}

// Hook genérico para métodos de instância
- (void)forwardInvocation:(NSInvocation *)invocation {
    NSString *selector = NSStringFromSelector([invocation selector]);
    writeToFile([NSString stringWithFormat:@"[METHOD] AVCaptureDevice calling: %@", selector]);
    %orig;
}
%end

// Continue com outras classes de AVFoundation...
%hook AVCaptureDeviceInput %end
%hook AVCaptureOutput %end
%hook AVCaptureVideoDataOutput %end
%hook AVCapturePhotoOutput %end
%hook AVCaptureVideoPreviewLayer %end

%end // fim do grupo AVFoundationHooks

%group CoreVideoHooks
%hook CVPixelBufferPool %end
%hook CVPixelBuffer

// Hook genérico para métodos
-(void)forwardInvocation:(NSInvocation *)invocation {
    NSString *selector = NSStringFromSelector([invocation selector]);
    writeToFile([NSString stringWithFormat:@"[METHOD] CVPixelBuffer calling: %@", selector]);
    %orig;
}
%end
// Adicione mais classes de CoreVideo aqui
%end // fim do grupo CoreVideoHooks

%group CoreMediaHooks
%hook CMSampleBuffer

// Hook genérico para métodos
-(void)forwardInvocation:(NSInvocation *)invocation {
    NSString *selector = NSStringFromSelector([invocation selector]);
    writeToFile([NSString stringWithFormat:@"[METHOD] CMSampleBuffer calling: %@", selector]);
    %orig;
}
%end
// Adicione mais classes de CoreMedia aqui
%end // fim do grupo CoreMediaHooks

// Atualizando o hook para interceptar chamadas de delegados de buffer
%group DefaultHooks
%hook NSObject
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    writeToFile([NSString stringWithFormat:@"[BUFFER] didOutputSampleBuffer chamado em objeto: %@", self]);
    
    // Logs sobre o sampleBuffer
    if (sampleBuffer) {
        CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
        if (formatDescription) {
            // Corrigido: CMFormatDescriptionGetMediaType retorna um FourCharCode (unsigned int)
            CMMediaType mediaType = CMFormatDescriptionGetMediaType(formatDescription);
            // Converter FourCharCode para string para logging
            char mediaTypeStr[5] = {0};
            mediaTypeStr[0] = (char)((mediaType >> 24) & 0xFF);
            mediaTypeStr[1] = (char)((mediaType >> 16) & 0xFF);
            mediaTypeStr[2] = (char)((mediaType >> 8) & 0xFF);
            mediaTypeStr[3] = (char)(mediaType & 0xFF);
            mediaTypeStr[4] = '\0';
            
            writeToFile([NSString stringWithFormat:@"[BUFFER] Media Type: %s", mediaTypeStr]);
        }
        
        CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        if (pixelBuffer) {
            size_t width = CVPixelBufferGetWidth(pixelBuffer);
            size_t height = CVPixelBufferGetHeight(pixelBuffer);
            writeToFile([NSString stringWithFormat:@"[BUFFER] Pixel Buffer Dimensions: %zu x %zu", width, height]);
        }
    }
    
    %orig;
}
%end
%end // fim do grupo DefaultHooks

%group DisplayLayerHooks
%hook AVSampleBufferDisplayLayer
- (void)enqueueSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    writeToFile([NSString stringWithFormat:@"[DISPLAY] AVSampleBufferDisplayLayer enqueueSampleBuffer: %p", sampleBuffer]);
    %orig;
}

- (void)flush {
    writeToFile(@"[DISPLAY] AVSampleBufferDisplayLayer flush");
    %orig;
}
%end
%end

%group ImageProcessingHooks
%hook CIContext
- (CIImage *)createImageWithCVPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    CIImage *result = %orig;
    writeToFile([NSString stringWithFormat:@"[IMAGE_PROCESSING] CIContext createImageWithCVPixelBuffer: %p -> %@", pixelBuffer, result]);
    return result;
}
%end

%hook CIImage
+ (instancetype)imageWithCVPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    CIImage *result = %orig;
    writeToFile([NSString stringWithFormat:@"[IMAGE_PROCESSING] CIImage imageWithCVPixelBuffer: %p -> %@", pixelBuffer, result]);
    return result;
}
%end
%end

%group MediaReaderHooks
%hook AVAssetReader
- (BOOL)startReading {
    BOOL result = %orig;
    writeToFile([NSString stringWithFormat:@"[MEDIA_READER] AVAssetReader startReading: %d", result]);
    return result;
}
%end

%hook AVAssetReaderTrackOutput
- (CMSampleBufferRef)copyNextSampleBuffer {
    CMSampleBufferRef result = %orig;
    writeToFile([NSString stringWithFormat:@"[MEDIA_READER] AVAssetReaderTrackOutput copyNextSampleBuffer: %p", result]);
    return result;
}
%end
%end

// Inicialização dos hooks
%ctor {
    writeToFile(@"===== Iniciando Universal Camera Logger =====");
    %init(DefaultHooks);
    %init(AVFoundationHooks);
    %init(CoreVideoHooks);
    %init(CoreMediaHooks);
    %init(DisplayLayerHooks);
    %init(ImageProcessingHooks);
    %init(MediaReaderHooks);
}
