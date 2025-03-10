#import "Tweak.h"

// Grupo para hooks relacionados ao preview
%group PreviewHooks

// Hook para AVCaptureVideoPreviewLayer para entender como o preview é exibido
%hook AVCaptureVideoPreviewLayer

- (id)initWithSession:(AVCaptureSession *)session {
    writeLog(@"[PREVIEW] initWithSession chamado, session: %@", session ? @"presente" : @"nil");
    
    [[DiagnosticCollector sharedInstance] recordPreviewLayerCreation:@{
        @"method": @"initWithSession",
        @"hasSession": @(session != nil),
        @"sessionIsRunning": session ? @([session isRunning]) : @NO
    }];
    
    return %orig;
}

- (void)setSession:(AVCaptureSession *)session {
    writeLog(@"[PREVIEW] setSession chamado, session: %@", session ? @"presente" : @"nil");
    
    [[DiagnosticCollector sharedInstance] recordPreviewLayerOperation:@{
        @"operation": @"setSession",
        @"hasSession": @(session != nil),
        @"sessionIsRunning": session ? @([session isRunning]) : @NO
    }];
    
    %orig;
}

- (void)setVideoGravity:(NSString *)gravity {
    writeLog(@"[PREVIEW] setVideoGravity: %@", gravity);
    
    [[DiagnosticCollector sharedInstance] recordPreviewLayerOperation:@{
        @"operation": @"setVideoGravity",
        @"videoGravity": gravity ?: @"nil"
    }];
    
    %orig;
}

- (void)setFrame:(CGRect)frame {
    static CGRect lastFrame = CGRectZero;
    
    // Só registrar se a frame mudar significativamente para reduzir volume de logs
    if (fabs(frame.size.width - lastFrame.size.width) > 1 || 
        fabs(frame.size.height - lastFrame.size.height) > 1 ||
        fabs(frame.origin.x - lastFrame.origin.x) > 1 || 
        fabs(frame.origin.y - lastFrame.origin.y) > 1) {
        
        writeLog(@"[PREVIEW] setFrame: {{%.1f, %.1f}, {%.1f, %.1f}}", 
                frame.origin.x, frame.origin.y, frame.size.width, frame.size.height);
        
        [[DiagnosticCollector sharedInstance] recordPreviewLayerOperation:@{
            @"operation": @"setFrame",
            @"x": @(frame.origin.x),
            @"y": @(frame.origin.y),
            @"width": @(frame.size.width),
            @"height": @(frame.size.height)
        }];
        
        lastFrame = frame;
    }
    
    %orig;
}

// Hook específico para layers
- (void)addSublayer:(CALayer *)layer {
    writeLog(@"[PREVIEW] addSublayer: %@", NSStringFromClass([layer class]));
    
    [[DiagnosticCollector sharedInstance] recordPreviewLayerOperation:@{
        @"operation": @"addSublayer",
        @"sublayerClass": NSStringFromClass([layer class]),
        @"sublayerFrame": NSStringFromCGRect(layer.frame)
    }];
    
    %orig;
}

- (void)insertSublayer:(CALayer *)layer atIndex:(unsigned int)idx {
    writeLog(@"[PREVIEW] insertSublayer:atIndex: %@, index: %u", NSStringFromClass([layer class]), idx);
    
    [[DiagnosticCollector sharedInstance] recordPreviewLayerOperation:@{
        @"operation": @"insertSublayer:atIndex",
        @"sublayerClass": NSStringFromClass([layer class]),
        @"sublayerFrame": NSStringFromCGRect(layer.frame),
        @"index": @(idx)
    }];
    
    %orig;
}

// Hook para conexão de saída
- (void)setCaptureDevicePointOfInterest:(CGPoint)pointInLayer forPoint:(CGPoint)pointInView {
    writeLog(@"[PREVIEW] setCaptureDevicePointOfInterest: {%.2f, %.2f} forPoint: {%.2f, %.2f}", 
            pointInLayer.x, pointInLayer.y, pointInView.x, pointInView.y);
    
    [[DiagnosticCollector sharedInstance] recordPreviewLayerOperation:@{
        @"operation": @"setCaptureDevicePointOfInterest",
        @"layerPointX": @(pointInLayer.x),
        @"layerPointY": @(pointInLayer.y),
        @"viewPointX": @(pointInView.x),
        @"viewPointY": @(pointInView.y)
    }];
    
    %orig;
}

- (CGPoint)captureDevicePointOfInterestForPoint:(CGPoint)pointInView {
    CGPoint result = %orig;
    
    writeLog(@"[PREVIEW] captureDevicePointOfInterestForPoint: {%.2f, %.2f} -> {%.2f, %.2f}", 
            pointInView.x, pointInView.y, result.x, result.y);
    
    [[DiagnosticCollector sharedInstance] recordPreviewLayerOperation:@{
        @"operation": @"captureDevicePointOfInterestForPoint",
        @"viewPointX": @(pointInView.x),
        @"viewPointY": @(pointInView.y),
        @"resultPointX": @(result.x),
        @"resultPointY": @(result.y)
    }];
    
    return result;
}

// Métodos para transformações
- (void)setAffineTransform:(CGAffineTransform)transform {
    writeLog(@"[PREVIEW] setAffineTransform: [%.2f, %.2f, %.2f, %.2f, %.2f, %.2f]", 
            transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty);
    
    [[DiagnosticCollector sharedInstance] recordPreviewLayerOperation:@{
        @"operation": @"setAffineTransform",
        @"transformA": @(transform.a),
        @"transformB": @(transform.b),
        @"transformC": @(transform.c),
        @"transformD": @(transform.d),
        @"transformTX": @(transform.tx),
        @"transformTY": @(transform.ty)
    }];
    
    %orig;
}

- (void)setTransform:(CATransform3D)transform {
    // Apenas principais componentes para simplicidade
    writeLog(@"[PREVIEW] setTransform: matriz 3D");
    
    // Capturar componentes principais da transformação 3D
    [[DiagnosticCollector sharedInstance] recordPreviewLayerOperation:@{
        @"operation": @"setTransform",
        @"transform_m11": @(transform.m11),
        @"transform_m12": @(transform.m12),
        @"transform_m13": @(transform.m13),
        @"transform_m14": @(transform.m14),
        @"transform_m21": @(transform.m21),
        @"transform_m22": @(transform.m22),
        // ... (limitado por brevidade)
    }];
    
    %orig;
}

// Hook para visibilidade 
- (void)setOpacity:(float)opacity {
    // Apenas registrar mudanças significativas
    static float lastOpacity = -1;
    if (fabs(opacity - lastOpacity) > 0.05) {
        writeLog(@"[PREVIEW] setOpacity: %.2f", opacity);
        
        [[DiagnosticCollector sharedInstance] recordPreviewLayerOperation:@{
            @"operation": @"setOpacity",
            @"opacity": @(opacity)
        }];
        
        lastOpacity = opacity;
    }
    
    %orig;
}

- (void)setHidden:(BOOL)hidden {
    writeLog(@"[PREVIEW] setHidden: %d", hidden);
    
    [[DiagnosticCollector sharedInstance] recordPreviewLayerOperation:@{
        @"operation": @"setHidden",
        @"hidden": @(hidden)
    }];
    
    %orig;
}

%end

// Hook para AVSampleBufferDisplayLayer para examinar a renderização direta de sample buffers
%hook AVSampleBufferDisplayLayer

- (id)init {
    id result = %orig;
    
    writeLog(@"[DISPLAY] AVSampleBufferDisplayLayer init");
    
    [[DiagnosticCollector sharedInstance] recordDisplayLayerInfo:@{
        @"event": @"init",
        @"layerClass": NSStringFromClass([self class])
    }];
    
    return result;
}

- (void)enqueueSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if (sampleBuffer && CMSampleBufferIsValid(sampleBuffer)) {
        // Extrair informações sobre o frame
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        if (imageBuffer) {
            size_t width = CVPixelBufferGetWidth(imageBuffer);
            size_t height = CVPixelBufferGetHeight(imageBuffer);
            
            // Log limitado para não sobrecarregar
            static int frameCount = 0;
            static NSTimeInterval lastLogTime = 0;
            NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
            
            if (++frameCount % 100 == 0 || currentTime - lastLogTime > 5.0) {
                lastLogTime = currentTime;
                writeLog(@"[DISPLAY] enqueueSampleBuffer: %zu x %zu", width, height);
                
                // Adicional: capturar formato do pixel buffer
                OSType pixelFormat = CVPixelBufferGetPixelFormatType(imageBuffer);
                
                // Converter para string de 4 caracteres
                char formatString[5] = {0};
                formatString[0] = (char)((pixelFormat >> 24) & 0xFF);
                formatString[1] = (char)((pixelFormat >> 16) & 0xFF);
                formatString[2] = (char)((pixelFormat >> 8) & 0xFF);
                formatString[3] = (char)(pixelFormat & 0xFF);
                
                // Registrar diagnóstico periodicamente
                [[DiagnosticCollector sharedInstance] recordDisplayLayerInfo:@{
                    @"event": @"enqueueSampleBuffer",
                    @"width": @(width),
                    @"height": @(height),
                    @"pixelFormat": @(pixelFormat),
                    @"pixelFormatString": [NSString stringWithUTF8String:formatString],
                    @"frameCount": @(frameCount)
                }];
            }
        }
    }
    
    %orig;
}

- (void)flush {
    writeLog(@"[DISPLAY] flush");
    
    [[DiagnosticCollector sharedInstance] recordDisplayLayerInfo:@{
        @"event": @"flush"
    }];
    
    %orig;
}

- (void)flushAndRemoveImage {
    writeLog(@"[DISPLAY] flushAndRemoveImage");
    
    [[DiagnosticCollector sharedInstance] recordDisplayLayerInfo:@{
        @"event": @"flushAndRemoveImage"
    }];
    
    %orig;
}

- (void)setVideoGravity:(NSString *)videoGravity {
    writeLog(@"[DISPLAY] setVideoGravity: %@", videoGravity);
    
    [[DiagnosticCollector sharedInstance] recordDisplayLayerInfo:@{
        @"event": @"setVideoGravity",
        @"videoGravity": videoGravity ?: @"nil"
    }];
    
    %orig;
}

- (void)setReadyForMoreMediaData:(BOOL)ready {
    static BOOL lastReadyState = NO;
    if (ready != lastReadyState) {
        writeLog(@"[DISPLAY] setReadyForMoreMediaData: %d", ready);
        
        [[DiagnosticCollector sharedInstance] recordDisplayLayerInfo:@{
            @"event": @"setReadyForMoreMediaData",
            @"ready": @(ready)
        }];
        
        lastReadyState = ready;
    }
    
    %orig;
}

%end

%end // grupo PreviewHooks

// Constructor específico deste arquivo
%ctor {
    %init(PreviewHooks);
}