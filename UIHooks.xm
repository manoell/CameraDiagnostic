#import "Tweak.h"

// Grupo para hooks relacionados a UI e imagens
%group UIHooks

// Hook para UIImageView para entender como os previews são exibidos
%hook UIImageView

- (void)setImage:(UIImage *)image {
    // Limitar logs para não sobrecarregar o sistema
    static int callCount = 0;
    if (++callCount % 50 == 0 && image) {  // A cada 50 chamadas e apenas para imagens não nulas
        writeLog(@"[UI] setImage: %@ - tamanho: %.0f x %.0f, escala: %.1f, orientação: %d",
                 NSStringFromClass([image class]), image.size.width, image.size.height,
                 image.scale, (int)image.imageOrientation);
        
        // Tentar identificar se é um preview de câmera
        BOOL mightBePreview = NO;
        
        // Verificar hierarquia de views para identificar previews de câmera
        UIView *view = self;
        NSMutableArray *viewHierarchy = [NSMutableArray array];
        
        while (view) {
            [viewHierarchy addObject:NSStringFromClass([view class])];
            
            if ([NSStringFromClass([view class]) containsString:@"Camera"] ||
                [NSStringFromClass([view class]) containsString:@"Preview"] ||
                [NSStringFromClass([view class]) containsString:@"Thumbnail"]) {
                mightBePreview = YES;
            }
            
            view = view.superview;
            
            // Limitar a profundidade para evitar loops infinitos
            if (viewHierarchy.count > 10) break;
        }
        
        if (mightBePreview) {
            writeLog(@"[UI] Possível preview de câmera detectado na hierarquia: %@", 
                     [viewHierarchy componentsJoinedByString:@" > "]);
            
            // Registrar informações detalhadas sobre o possível preview
            [[DiagnosticCollector sharedInstance] recordUIImageViewInfo:@{
                @"event": @"setImage",
                @"imageWidth": @(image.size.width),
                @"imageHeight": @(image.size.height),
                @"imageScale": @(image.scale),
                @"imageOrientation": @(image.imageOrientation),
                @"viewFrame": NSStringFromCGRect(self.frame),
                @"viewHierarchy": viewHierarchy,
                @"isPossiblePreview": @YES
            }];
        }
    }
    
    %orig;
}

- (void)setContentMode:(UIViewContentMode)contentMode {
    // Mapear modo para string para melhor legibilidade
    NSString *contentModeString;
    switch (contentMode) {
        case UIViewContentModeScaleToFill: contentModeString = @"ScaleToFill"; break;
        case UIViewContentModeScaleAspectFit: contentModeString = @"ScaleAspectFit"; break;
        case UIViewContentModeScaleAspectFill: contentModeString = @"ScaleAspectFill"; break;
        case UIViewContentModeRedraw: contentModeString = @"Redraw"; break;
        case UIViewContentModeCenter: contentModeString = @"Center"; break;
        case UIViewContentModeTop: contentModeString = @"Top"; break;
        case UIViewContentModeBottom: contentModeString = @"Bottom"; break;
        case UIViewContentModeLeft: contentModeString = @"Left"; break;
        case UIViewContentModeRight: contentModeString = @"Right"; break;
        case UIViewContentModeTopLeft: contentModeString = @"TopLeft"; break;
        case UIViewContentModeTopRight: contentModeString = @"TopRight"; break;
        case UIViewContentModeBottomLeft: contentModeString = @"BottomLeft"; break;
        case UIViewContentModeBottomRight: contentModeString = @"BottomRight"; break;
        default: contentModeString = [NSString stringWithFormat:@"Unknown(%d)", (int)contentMode]; break;
    }
    
    // Verificar se pode ser um preview de câmera
    UIImage *image = self.image;
    BOOL mightBePreview = NO;
    
    if (image) {
        // Verificar hierarquia de views
        UIView *view = self;
        while (view) {
            if ([NSStringFromClass([view class]) containsString:@"Camera"] ||
                [NSStringFromClass([view class]) containsString:@"Preview"] ||
                [NSStringFromClass([view class]) containsString:@"Thumbnail"]) {
                mightBePreview = YES;
                break;
            }
            view = view.superview;
            
            // Limitar a profundidade
            if ([view isKindOfClass:[UIWindow class]]) break;
        }
    }
    
    if (mightBePreview) {
        writeLog(@"[UI] setContentMode para possível preview: %@", contentModeString);
        
        [[DiagnosticCollector sharedInstance] recordUIImageViewInfo:@{
            @"event": @"setContentMode",
            @"contentMode": @(contentMode),
            @"contentModeString": contentModeString,
            @"isPossiblePreview": @YES,
            @"hasImage": @(image != nil),
            @"viewFrame": NSStringFromCGRect(self.frame)
        }];
    }
    
    %orig;
}

- (void)setFrame:(CGRect)frame {
    static CGRect lastFrame = CGRectZero;
    UIImage *image = self.image;
    
    // Só registrar mudanças significativas em frames para possíveis previews
    if (image && 
        (fabs(frame.size.width - lastFrame.size.width) > 5 || 
         fabs(frame.size.height - lastFrame.size.height) > 5)) {
        
        // Verificar hierarquia para possível preview
        BOOL mightBePreview = NO;
        UIView *view = self;
        while (view) {
            if ([NSStringFromClass([view class]) containsString:@"Camera"] ||
                [NSStringFromClass([view class]) containsString:@"Preview"] ||
                [NSStringFromClass([view class]) containsString:@"Thumbnail"]) {
                mightBePreview = YES;
                break;
            }
            view = view.superview;
            if ([view isKindOfClass:[UIWindow class]]) break;
        }
        
        if (mightBePreview) {
            writeLog(@"[UI] setFrame para possível preview: {{%.1f, %.1f}, {%.1f, %.1f}}",
                    frame.origin.x, frame.origin.y, frame.size.width, frame.size.height);
            
            // Calcular relação de aspecto da imagem e do frame
            float imageAspect = image.size.width / image.size.height;
            float frameAspect = frame.size.width / frame.size.height;
            
            [[DiagnosticCollector sharedInstance] recordUIImageViewInfo:@{
                @"event": @"setFrame",
                @"frameX": @(frame.origin.x),
                @"frameY": @(frame.origin.y),
                @"frameWidth": @(frame.size.width),
                @"frameHeight": @(frame.size.height),
                @"imageWidth": @(image.size.width),
                @"imageHeight": @(image.size.height),
                @"imageAspectRatio": @(imageAspect),
                @"frameAspectRatio": @(frameAspect),
                @"aspectRatioDifference": @(fabs(imageAspect - frameAspect)),
                @"contentMode": @(self.contentMode),
                @"isPossiblePreview": @YES
            }];
            
            lastFrame = frame;
        }
    }
    
    %orig;
}

%end

// Hook para CALayer para entender transformações e composição
%hook CALayer

- (void)addSublayer:(CALayer *)layer {
    // Verificar se estamos lidando com uma layer relacionada a câmera
    BOOL isPreviewRelated = NO;
    if ([layer isKindOfClass:NSClassFromString(@"AVCaptureVideoPreviewLayer")] ||
        [layer isKindOfClass:NSClassFromString(@"AVSampleBufferDisplayLayer")]) {
        isPreviewRelated = YES;
    }
    
    if (isPreviewRelated) {
        writeLog(@"[LAYER] addSublayer: %@ a %@", 
                NSStringFromClass([layer class]), NSStringFromClass([self class]));
        
        [[DiagnosticCollector sharedInstance] recordLayerOperation:@{
            @"operation": @"addSublayer",
            @"parentLayerClass": NSStringFromClass([self class]),
            @"sublayerClass": NSStringFromClass([layer class]),
            @"sublayerFrame": NSStringFromCGRect(layer.frame),
            @"isPreviewRelated": @YES
        }];
    }
    
    %orig;
}

- (void)insertSublayer:(CALayer *)layer atIndex:(unsigned)index {
    // Verificar se estamos lidando com uma layer relacionada a câmera
    BOOL isPreviewRelated = NO;
    if ([layer isKindOfClass:NSClassFromString(@"AVCaptureVideoPreviewLayer")] ||
        [layer isKindOfClass:NSClassFromString(@"AVSampleBufferDisplayLayer")]) {
        isPreviewRelated = YES;
    }
    
    if (isPreviewRelated) {
        writeLog(@"[LAYER] insertSublayer: %@ atIndex: %u em %@", 
                NSStringFromClass([layer class]), index, NSStringFromClass([self class]));
        
        [[DiagnosticCollector sharedInstance] recordLayerOperation:@{
            @"operation": @"insertSublayer:atIndex",
            @"parentLayerClass": NSStringFromClass([self class]),
            @"sublayerClass": NSStringFromClass([layer class]),
            @"sublayerFrame": NSStringFromCGRect(layer.frame),
            @"index": @(index),
            @"isPreviewRelated": @YES
        }];
    }
    
    %orig;
}

- (void)insertSublayer:(CALayer *)layer below:(CALayer *)sibling {
    // Verificar se estamos lidando com uma layer relacionada a câmera
    BOOL isPreviewRelated = NO;
    if ([layer isKindOfClass:NSClassFromString(@"AVCaptureVideoPreviewLayer")] ||
        [layer isKindOfClass:NSClassFromString(@"AVSampleBufferDisplayLayer")]) {
        isPreviewRelated = YES;
    }
    
    if (isPreviewRelated) {
        writeLog(@"[LAYER] insertSublayer: %@ below: %@ em %@", 
                NSStringFromClass([layer class]), 
                NSStringFromClass([sibling class]),
                NSStringFromClass([self class]));
        
        [[DiagnosticCollector sharedInstance] recordLayerOperation:@{
            @"operation": @"insertSublayer:below",
            @"parentLayerClass": NSStringFromClass([self class]),
            @"sublayerClass": NSStringFromClass([layer class]),
            @"siblingClass": NSStringFromClass([sibling class]),
            @"sublayerFrame": NSStringFromCGRect(layer.frame),
            @"isPreviewRelated": @YES
        }];
    }
    
    %orig;
}

- (void)insertSublayer:(CALayer *)layer above:(CALayer *)sibling {
    // Verificar se estamos lidando com uma layer relacionada a câmera
    BOOL isPreviewRelated = NO;
    if ([layer isKindOfClass:NSClassFromString(@"AVCaptureVideoPreviewLayer")] ||
        [layer isKindOfClass:NSClassFromString(@"AVSampleBufferDisplayLayer")]) {
        isPreviewRelated = YES;
    }
    
    if (isPreviewRelated) {
        writeLog(@"[LAYER] insertSublayer: %@ above: %@ em %@", 
                NSStringFromClass([layer class]), 
                NSStringFromClass([sibling class]),
                NSStringFromClass([self class]));
        
        [[DiagnosticCollector sharedInstance] recordLayerOperation:@{
            @"operation": @"insertSublayer:above",
            @"parentLayerClass": NSStringFromClass([self class]),
            @"sublayerClass": NSStringFromClass([layer class]),
            @"siblingClass": NSStringFromClass([sibling class]),
            @"sublayerFrame": NSStringFromCGRect(layer.frame),
            @"isPreviewRelated": @YES
        }];
    }
    
    %orig;
}

- (void)setFrame:(CGRect)frame {
    // Verificar se é uma layer relacionada a câmera
    BOOL isPreviewRelated = NO;
    if ([self isKindOfClass:NSClassFromString(@"AVCaptureVideoPreviewLayer")] ||
        [self isKindOfClass:NSClassFromString(@"AVSampleBufferDisplayLayer")]) {
        isPreviewRelated = YES;
    }
    
    if (isPreviewRelated) {
        static CGRect lastFrame = CGRectZero;
        
        // Só registrar mudanças significativas
        if (fabs(frame.size.width - lastFrame.size.width) > 5 || 
            fabs(frame.size.height - lastFrame.size.height) > 5) {
            
            writeLog(@"[LAYER] setFrame: {{%.1f, %.1f}, {%.1f, %.1f}} para %@",
                    frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
                    NSStringFromClass([self class]));
            
            [[DiagnosticCollector sharedInstance] recordLayerOperation:@{
                @"operation": @"setFrame",
                @"layerClass": NSStringFromClass([self class]),
                @"frameX": @(frame.origin.x),
                @"frameY": @(frame.origin.y),
                @"frameWidth": @(frame.size.width),
                @"frameHeight": @(frame.size.height),
                @"isPreviewRelated": @YES
            }];
            
            lastFrame = frame;
        }
    }
    
    %orig;
}

- (void)setTransform:(CATransform3D)transform {
    // Verificar se é uma layer relacionada a câmera
    BOOL isPreviewRelated = NO;
    if ([self isKindOfClass:NSClassFromString(@"AVCaptureVideoPreviewLayer")] ||
        [self isKindOfClass:NSClassFromString(@"AVSampleBufferDisplayLayer")]) {
        isPreviewRelated = YES;
    }
    
    if (isPreviewRelated) {
        // Para simplificar, verificamos apenas se é uma transformação de identidade ou não
        BOOL isIdentity = CATransform3DIsIdentity(transform);
        
        if (!isIdentity) {
            writeLog(@"[LAYER] setTransform: %@ -> transformação não-identidade", 
                    NSStringFromClass([self class]));
            
            // Capturar alguns componentes principais da transformação para diagnóstico
            [[DiagnosticCollector sharedInstance] recordLayerOperation:@{
                @"operation": @"setTransform",
                @"layerClass": NSStringFromClass([self class]),
                @"isIdentity": @(isIdentity),
                @"transform_m11": @(transform.m11),
                @"transform_m12": @(transform.m12),
                @"transform_m21": @(transform.m21),
                @"transform_m22": @(transform.m22),
                @"transform_m41": @(transform.m41), // tx
                @"transform_m42": @(transform.m42), // ty
                @"isPreviewRelated": @YES
            }];
        }
    }
    
    %orig;
}

- (void)setMasksToBounds:(BOOL)masksToBounds {
    // Verificar se é uma layer relacionada a câmera
    BOOL isPreviewRelated = NO;
    if ([self isKindOfClass:NSClassFromString(@"AVCaptureVideoPreviewLayer")] ||
        [self isKindOfClass:NSClassFromString(@"AVSampleBufferDisplayLayer")]) {
        isPreviewRelated = YES;
    }
    
    if (isPreviewRelated) {
        writeLog(@"[LAYER] setMasksToBounds: %d para %@", 
                masksToBounds, NSStringFromClass([self class]));
        
        [[DiagnosticCollector sharedInstance] recordLayerOperation:@{
            @"operation": @"setMasksToBounds",
            @"layerClass": NSStringFromClass([self class]),
            @"masksToBounds": @(masksToBounds),
            @"isPreviewRelated": @YES
        }];
    }
    
    %orig;
}

- (void)setCornerRadius:(CGFloat)cornerRadius {
    // Verificar se é uma layer relacionada a câmera
    BOOL isPreviewRelated = NO;
    if ([self isKindOfClass:NSClassFromString(@"AVCaptureVideoPreviewLayer")] ||
        [self isKindOfClass:NSClassFromString(@"AVSampleBufferDisplayLayer")]) {
        isPreviewRelated = YES;
    }
    
    if (isPreviewRelated && cornerRadius > 0) {
        writeLog(@"[LAYER] setCornerRadius: %.2f para %@", 
                cornerRadius, NSStringFromClass([self class]));
        
        [[DiagnosticCollector sharedInstance] recordLayerOperation:@{
            @"operation": @"setCornerRadius",
            @"layerClass": NSStringFromClass([self class]),
            @"cornerRadius": @(cornerRadius),
            @"isPreviewRelated": @YES
        }];
    }
    
    %orig;
}

%end

%end // grupo UIHooks

// Constructor específico deste arquivo
%ctor {
    %init(UIHooks);
}