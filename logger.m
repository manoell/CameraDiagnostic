#import "logger.h"

static int gLogLevel = 5; // Valor padrão: debug (máximo) para capturar tudo

void setLogLevel(int level) {
    gLogLevel = level;
}

NSString *getCallerBundleID() {
    return [[NSBundle mainBundle] bundleIdentifier] ?: @"unknown";
}

void writeLog(NSString *format, ...) {
    if (gLogLevel <= 0) return;
    
    @try {
        va_list args;
        va_start(args, format);
        NSString *formattedString = [[NSString alloc] initWithFormat:format arguments:args];
        va_end(args);
        
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"HH:mm:ss.SSS"];
        NSString *timestamp = [formatter stringFromDate:[NSDate date]];
        
        NSString *bundleID = getCallerBundleID();
        NSString *logMessage = [NSString stringWithFormat:@"[%@] [%@] %@\n", timestamp, bundleID, formattedString];
        
        NSLog(@"[CameraDiag] [%@] %@", bundleID, formattedString);
        
        if (gLogLevel >= 1) {
            NSString *logPath = @"/var/tmp/CameraDiag.log";
            NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
            if (!fileHandle) {
                [@"" writeToFile:logPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
                fileHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
            }
            if (fileHandle) {
                [fileHandle seekToEndOfFile];
                [fileHandle writeData:[logMessage dataUsingEncoding:NSUTF8StringEncoding]];
                [fileHandle closeFile];
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[CameraDiag] ERRO NO LOGGER: %@", e);
    }
}

void logBufferDetails(CMSampleBufferRef buffer, NSString *context) {
    if (!buffer || gLogLevel < 3) return;
    
    CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(buffer);
    CMMediaType mediaType = formatDesc ? CMFormatDescriptionGetMediaType(formatDesc) : 0;
    char mediaTypeStr[5] = {0};
    mediaTypeStr[0] = (char)((mediaType >> 24) & 0xFF);
    mediaTypeStr[1] = (char)((mediaType >> 16) & 0xFF);
    mediaTypeStr[2] = (char)((mediaType >> 8) & 0xFF);
    mediaTypeStr[3] = (char)(mediaType & 0xFF);
    
    CMTime timestamp = CMSampleBufferGetPresentationTimeStamp(buffer);
    writeLog(@"[BUFFER] %@ - MediaType: %s, Timestamp: %.4f, Duration: %.4f",
             context, mediaTypeStr, CMTimeGetSeconds(timestamp), CMTimeGetSeconds(CMSampleBufferGetDuration(buffer)));
    
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(buffer);
    if (pixelBuffer) {
        logPixelBufferDetails(pixelBuffer, context);
    }
}

void logPixelBufferDetails(CVPixelBufferRef buffer, NSString *context) {
    if (!buffer || gLogLevel < 3) return;
    
    size_t width = CVPixelBufferGetWidth(buffer);
    size_t height = CVPixelBufferGetHeight(buffer);
    OSType pixelFormat = CVPixelBufferGetPixelFormatType(buffer);
    writeLog(@"[PIXEL_BUFFER] %@ - Dimensions: %zux%zu, Format: %4.4s",
             context, width, height, (char *)&pixelFormat);
}
