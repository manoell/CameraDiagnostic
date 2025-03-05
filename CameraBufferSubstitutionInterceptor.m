// CameraBufferSubstitutionInterceptor.m

#import "CameraBufferSubstitutionInterceptor.h"
#import <objc/runtime.h>
#import <CoreVideo/CoreVideo.h>
#import <UIKit/UIKit.h>

// Chave para associar um objeto ao buffer para prevenir liberação prematura
static void *kBufferOwnerKey = &kBufferOwnerKey;

// Classe proxy para interceptação de delegado
@interface AVCaptureVideoDataOutputDelegateProxy : NSProxy <AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic, weak) id<AVCaptureVideoDataOutputSampleBufferDelegate> originalDelegate;

@end

@implementation AVCaptureVideoDataOutputDelegateProxy

- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
    // Verificar se o delegate original responde ao selector e é um NSObject
    if ([self.originalDelegate respondsToSelector:sel] &&
        [self.originalDelegate isKindOfClass:[NSObject class]]) {
        return [(NSObject *)self.originalDelegate methodSignatureForSelector:sel];
    }
    
    // Caso contrário, fornecer uma assinatura padrão para void
    return [NSMethodSignature signatureWithObjCTypes:"v@:"];
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    SEL selector = invocation.selector;
    
    // Intercepta o método de saída do buffer
    if (selector == @selector(captureOutput:didOutputSampleBuffer:fromConnection:)) {
        AVCaptureOutput *output;
        CMSampleBufferRef sampleBuffer;
        AVCaptureConnection *connection;
        
        [invocation getArgument:&output atIndex:2];
        [invocation getArgument:&sampleBuffer atIndex:3];
        [invocation getArgument:&connection atIndex:4];
        
        // Tenta substituir o buffer
        CMSampleBufferRef modifiedBuffer = [[CameraBufferSubstitutionInterceptor sharedInterceptor]
                                          interceptAndPotentiallyReplaceBuffer:sampleBuffer
                                                                   fromOutput:output];
        
        // Substitui o buffer na invocação se for diferente
        if (modifiedBuffer != sampleBuffer) {
            [invocation setArgument:&modifiedBuffer atIndex:3];
        }
    }
    
    // Encaminha para o delegado original
    if ([self.originalDelegate respondsToSelector:selector]) {
        [invocation invokeWithTarget:self.originalDelegate];
    }
}

- (BOOL)respondsToSelector:(SEL)aSelector {
    return [self.originalDelegate respondsToSelector:aSelector];
}

// Implementação explícita do método do protocolo para garantir conformidade
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if ([self.originalDelegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
        // Tenta substituir o buffer
        CMSampleBufferRef modifiedBuffer = [[CameraBufferSubstitutionInterceptor sharedInterceptor]
                                          interceptAndPotentiallyReplaceBuffer:sampleBuffer
                                                                   fromOutput:output];
        
        // Envia para o delegado original
        [self.originalDelegate captureOutput:output didOutputSampleBuffer:modifiedBuffer ? modifiedBuffer : sampleBuffer fromConnection:connection];
    }
}

- (void)captureOutput:(AVCaptureOutput *)output didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if ([self.originalDelegate respondsToSelector:@selector(captureOutput:didDropSampleBuffer:fromConnection:)]) {
        [self.originalDelegate captureOutput:output didDropSampleBuffer:sampleBuffer fromConnection:connection];
    }
}

@end

@interface CameraBufferSubstitutionInterceptor ()

// Mapa de delegados originais para proxies
@property (nonatomic, strong) NSMapTable<id, AVCaptureVideoDataOutputDelegateProxy *> *delegateProxies;

// Mapa para rastrear delegados já swizzled
@property (nonatomic, strong) NSMutableSet<Class> *swizzledDelegateClasses;

// Flag para impedir recursão infinita
@property (nonatomic, assign) BOOL isProcessingBuffer;

@end

@implementation CameraBufferSubstitutionInterceptor

#pragma mark - Singleton

+ (instancetype)sharedInterceptor {
    static CameraBufferSubstitutionInterceptor *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[CameraBufferSubstitutionInterceptor alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _enabled = NO;
        _interceptionStrategy = @"swizzle"; // Default strategy
        _delegateProxies = [NSMapTable weakToStrongObjectsMapTable];
        _swizzledDelegateClasses = [NSMutableSet new];
        _isProcessingBuffer = NO;
    }
    return self;
}

#pragma mark - Hook Installation

- (void)installHooks {
    if ([self.interceptionStrategy isEqualToString:@"swizzle"]) {
        [self installSwizzleHooks];
    } else if ([self.interceptionStrategy isEqualToString:@"proxy"]) {
        [self installProxyHooks];
    } else if ([self.interceptionStrategy isEqualToString:@"direct"]) {
        [self installDirectHooks];
    } else {
        NSLog(@"Estratégia de intercepção desconhecida: %@", self.interceptionStrategy);
    }
}

- (void)uninstallHooks {
    // Como a desinstalação depende da estratégia, implementamos de acordo
    if ([self.interceptionStrategy isEqualToString:@"swizzle"]) {
        [self uninstallSwizzleHooks];
    } else if ([self.interceptionStrategy isEqualToString:@"proxy"]) {
        [self uninstallProxyHooks];
    } else if ([self.interceptionStrategy isEqualToString:@"direct"]) {
        [self uninstallDirectHooks];
    }
}

#pragma mark - Swizzle Strategy

- (void)installSwizzleHooks {
    NSLog(@"Instalando hooks via swizzle...");
    
    // Hook para AVCaptureVideoDataOutput setSampleBufferDelegate:queue:
    Method originalMethod = class_getInstanceMethod([AVCaptureVideoDataOutput class],
                                                   @selector(setSampleBufferDelegate:queue:));
    Method swizzledMethod = class_getInstanceMethod([self class],
                                                   @selector(swizzled_setSampleBufferDelegate:queue:));
    
    method_exchangeImplementations(originalMethod, swizzledMethod);
    
    // Note: We also need to swizzle existing delegate implementations, which we'll do when we detect them
}

- (void)uninstallSwizzleHooks {
    NSLog(@"Desinstalando hooks via swizzle...");
    
    // Revert AVCaptureVideoDataOutput setSampleBufferDelegate:queue:
    Method originalMethod = class_getInstanceMethod([AVCaptureVideoDataOutput class],
                                                   @selector(setSampleBufferDelegate:queue:));
    Method swizzledMethod = class_getInstanceMethod([self class],
                                                   @selector(swizzled_setSampleBufferDelegate:queue:));
    
    method_exchangeImplementations(swizzledMethod, originalMethod);
    
    // Revert swizzled delegate methods (if possible)
    // This is complex and often incomplete - might leak some swizzling
}

- (void)swizzled_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    // Detect and swizzle the delegate if needed
    [self swizzleDelegateIfNeeded:sampleBufferDelegate];
    
    // Call original method (which is now our swizzled method due to the implementation swap)
    [self swizzled_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
}

- (void)swizzleDelegateIfNeeded:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)delegate {
    if (!delegate) return;
    
    Class delegateClass = [delegate class];
    
    // Skip if already swizzled
    @synchronized (self.swizzledDelegateClasses) {
        if ([self.swizzledDelegateClasses containsObject:delegateClass]) {
            return;
        }
        
        // Check if the delegate implements the buffer output method
        if ([delegate respondsToSelector:@selector(captureOutput:didOutputSampleBuffer:fromConnection:)]) {
            
            Method originalMethod = class_getInstanceMethod(delegateClass,
                                                           @selector(captureOutput:didOutputSampleBuffer:fromConnection:));
            
            // Create a unique swizzled method selector for this class
            NSString *swizzledSelectorName = [NSString stringWithFormat:@"swizzled_%@_captureOutput:didOutputSampleBuffer:fromConnection:",
                                             NSStringFromClass(delegateClass)];
            SEL swizzledSelector = NSSelectorFromString(swizzledSelectorName);
            
            // Add the swizzled method to our interceptor
            IMP swizzledImp = imp_implementationWithBlock(^(id selfObj,
                                                          AVCaptureOutput *output,
                                                          CMSampleBufferRef sampleBuffer,
                                                          AVCaptureConnection *connection) {
                
                // Don't intercept if we're disabled
                if (![CameraBufferSubstitutionInterceptor sharedInterceptor].isEnabled) {
                    // Use original implementation
                    ((void(*)(id, SEL, AVCaptureOutput *, CMSampleBufferRef, AVCaptureConnection *))
                     method_getImplementation(originalMethod))(selfObj, @selector(captureOutput:didOutputSampleBuffer:fromConnection:),
                                                              output, sampleBuffer, connection);
                    return;
                }
                
                // Avoid reentrant calls
                if ([CameraBufferSubstitutionInterceptor sharedInterceptor].isProcessingBuffer) {
                    // Use original implementation
                    ((void(*)(id, SEL, AVCaptureOutput *, CMSampleBufferRef, AVCaptureConnection *))
                     method_getImplementation(originalMethod))(selfObj, @selector(captureOutput:didOutputSampleBuffer:fromConnection:),
                                                              output, sampleBuffer, connection);
                    return;
                }
                
                [CameraBufferSubstitutionInterceptor sharedInterceptor].isProcessingBuffer = YES;
                
                // Try to substitute the buffer
                CMSampleBufferRef modifiedBuffer = [[CameraBufferSubstitutionInterceptor sharedInterceptor]
                                                  interceptAndPotentiallyReplaceBuffer:sampleBuffer
                                                                           fromOutput:output];
                
                // Call original method with potentially modified buffer
                ((void(*)(id, SEL, AVCaptureOutput *, CMSampleBufferRef, AVCaptureConnection *))
                 method_getImplementation(originalMethod))(selfObj, @selector(captureOutput:didOutputSampleBuffer:fromConnection:),
                                                          output, modifiedBuffer, connection);
                
                [CameraBufferSubstitutionInterceptor sharedInterceptor].isProcessingBuffer = NO;
            });
            
            // Add the method to the class
            class_addMethod(delegateClass, swizzledSelector, swizzledImp, method_getTypeEncoding(originalMethod));
            
            // Get the newly added method
            Method swizzledMethod = class_getInstanceMethod(delegateClass, swizzledSelector);
            
            // Exchange implementations
            method_exchangeImplementations(originalMethod, swizzledMethod);
            
            NSLog(@"Delegate class %@ swizzled for buffer interception", NSStringFromClass(delegateClass));
            
            // Remember that we've swizzled this class
            [self.swizzledDelegateClasses addObject:delegateClass];
        }
    }
}

#pragma mark - Proxy Strategy

- (void)installProxyHooks {
    NSLog(@"Instalando hooks via proxy...");
    
    // Hook para AVCaptureVideoDataOutput setSampleBufferDelegate:queue:
    Method originalMethod = class_getInstanceMethod([AVCaptureVideoDataOutput class],
                                                   @selector(setSampleBufferDelegate:queue:));
    Method swizzledMethod = class_getInstanceMethod([self class],
                                                   @selector(proxy_setSampleBufferDelegate:queue:));
    
    method_exchangeImplementations(originalMethod, swizzledMethod);
}

- (void)uninstallProxyHooks {
    NSLog(@"Desinstalando hooks via proxy...");
    
    // Revert AVCaptureVideoDataOutput setSampleBufferDelegate:queue:
    Method originalMethod = class_getInstanceMethod([AVCaptureVideoDataOutput class],
                                                   @selector(setSampleBufferDelegate:queue:));
    Method swizzledMethod = class_getInstanceMethod([self class],
                                                   @selector(proxy_setSampleBufferDelegate:queue:));
    
    method_exchangeImplementations(swizzledMethod, originalMethod);
    
    // Clear our proxy map
    [self.delegateProxies removeAllObjects];
}

- (void)proxy_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue {
    // If disabled or delegate is nil, pass through
    if (!self.isEnabled || !sampleBufferDelegate) {
        [self proxy_setSampleBufferDelegate:sampleBufferDelegate queue:sampleBufferCallbackQueue];
        return;
    }
    
    // Check if we already have a proxy for this delegate
    AVCaptureVideoDataOutputDelegateProxy *proxy = [self.delegateProxies objectForKey:sampleBufferDelegate];
    
    if (!proxy) {
        // Create a new proxy
        proxy = [AVCaptureVideoDataOutputDelegateProxy alloc];
        proxy.originalDelegate = sampleBufferDelegate;
        
        // Store in our map
        [self.delegateProxies setObject:proxy forKey:sampleBufferDelegate];
    }
    
    // Call original method with our proxy - use explicit cast para resolver erro de tipo
    [self proxy_setSampleBufferDelegate:(id<AVCaptureVideoDataOutputSampleBufferDelegate>)proxy queue:sampleBufferCallbackQueue];
}

#pragma mark - Direct Strategy

- (void)installDirectHooks {
    NSLog(@"Instalando hooks diretos (experimental)...");
    
    // Esta estratégia depende de recursos de baixo nível como fishhook
    // e pode ser específica para arquiteturas ARM/iOS
    // Implementação simplificada para fins de demonstração
    
    NSLog(@"AVISO: Hooks diretos não estão implementados totalmente e podem não funcionar");
}

- (void)uninstallDirectHooks {
    NSLog(@"Desinstalando hooks diretos...");
    // Nada a fazer na implementação demonstrativa
}

#pragma mark - Buffer Interception and Replacement

- (CMSampleBufferRef)interceptAndPotentiallyReplaceBuffer:(CMSampleBufferRef)buffer fromOutput:(AVCaptureOutput *)output {
    // Verificação rápida: se não está habilitado ou sem fonte, retorne o buffer original
    if (!self.isEnabled || !self.substitutionSource) {
        return buffer;
    }
    
    // Verifica se o buffer é válido
    if (!buffer || !CMSampleBufferIsValid(buffer)) {
        return buffer;
    }
    
    // Obtém o timestamp de apresentação
    CMTime presentationTime = CMSampleBufferGetPresentationTimeStamp(buffer);
    
    // Solicita um buffer substituto da fonte
    CMSampleBufferRef replacementBuffer = nil;
    
    @try {
        replacementBuffer = [self.substitutionSource provideSubstitutionBufferForOriginalBuffer:buffer
                                                                                   atTimestamp:presentationTime];
    } @catch (NSException *exception) {
        NSLog(@"Exceção ao solicitar buffer substituto: %@", exception);
        return buffer;
    }
    
    // Se não tivermos um buffer substituto, retorne o original
    if (!replacementBuffer) {
        return buffer;
    }
    
    // Verifica se o buffer substituto é válido
    if (!CMSampleBufferIsValid(replacementBuffer)) {
        NSLog(@"Buffer substituto inválido");
        
        if ([self.substitutionSource respondsToSelector:@selector(substitutionFailedForBuffer:error:)]) {
            NSError *error = [NSError errorWithDomain:@"CameraBufferSubstitution"
                                                code:1001
                                            userInfo:@{NSLocalizedDescriptionKey: @"Buffer substituto inválido"}];
            [self.substitutionSource substitutionFailedForBuffer:buffer error:error];
        }
        
        return buffer;
    }
    
    // Notifica a fonte do sucesso na substituição
    if ([self.substitutionSource respondsToSelector:@selector(substitutionBufferWasApplied:)]) {
        [self.substitutionSource substitutionBufferWasApplied:replacementBuffer];
    }
    
    return replacementBuffer;
}

#pragma mark - Buffer Creation Utilities

+ (nullable CMSampleBufferRef)createSampleBufferFromUIImage:(UIImage *)image
                                       withReferenceBuffer:(CMSampleBufferRef)referenceBuffer {
    if (!image || !referenceBuffer || !CMSampleBufferIsValid(referenceBuffer)) {
        return NULL;
    }
    
    // Obter dimensões do buffer de referência
    CVImageBufferRef refImageBuffer = CMSampleBufferGetImageBuffer(referenceBuffer);
    if (!refImageBuffer) {
        return NULL;
    }
    
    size_t refWidth = CVPixelBufferGetWidth(refImageBuffer);
    size_t refHeight = CVPixelBufferGetHeight(refImageBuffer);
    
    // Criar um contexto gráfico para desenhar a imagem com as dimensões corretas
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    uint8_t *bitmapData = calloc(refWidth * refHeight * 4, sizeof(uint8_t));
    
    CGContextRef context = CGBitmapContextCreate(
        bitmapData,
        refWidth,
        refHeight,
        8,
        refWidth * 4,
        colorSpace,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
    );
    
    // Desenhar a imagem no contexto (redimensionando se necessário)
    CGContextDrawImage(context, CGRectMake(0, 0, refWidth, refHeight), image.CGImage);
    
    // Obter o timestamp do buffer de referência
    CMTime presentationTime = CMSampleBufferGetPresentationTimeStamp(referenceBuffer);
    
    // Criar buffer a partir dos dados de pixel
    CMSampleBufferRef resultBuffer = [self createSampleBufferFromPixelData:bitmapData
                                                                    width:refWidth
                                                                   height:refHeight
                                                             pixelFormat:kCVPixelFormatType_32BGRA
                                                      withPresentationTime:presentationTime];
    
    // Liberar recursos
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    free(bitmapData);
    
    return resultBuffer;
}

+ (nullable CMSampleBufferRef)createSampleBufferFromPixelData:(uint8_t *)pixelData
                                                      width:(size_t)width
                                                     height:(size_t)height
                                               pixelFormat:(OSType)pixelFormat
                                     withPresentationTime:(CMTime)presentationTime {
    if (!pixelData || width == 0 || height == 0) {
        return NULL;
    }
    
    // 1. Criar um CVPixelBuffer
    CVPixelBufferRef pixelBuffer = NULL;
    
    NSDictionary *options = @{
        (NSString *)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES
    };
    
    CVReturn status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        pixelFormat,
        (__bridge CFDictionaryRef)options,
        &pixelBuffer
    );
    
    if (status != kCVReturnSuccess || !pixelBuffer) {
        NSLog(@"Falha ao criar CVPixelBuffer: %d", status);
        return NULL;
    }
    
    // 2. Copiar os dados para o buffer
    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    
    void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
    size_t dataSize = bytesPerRow * height;
    
    memcpy(baseAddress, pixelData, dataSize);
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    
    // 3. Criar uma descrição de formato para o buffer
    CMFormatDescriptionRef formatDescription = NULL;
    status = CMVideoFormatDescriptionCreateForImageBuffer(
        kCFAllocatorDefault,
        pixelBuffer,
        &formatDescription
    );
    
    if (status != noErr || !formatDescription) {
        NSLog(@"Falha ao criar CMFormatDescription: %d", status);
        CVPixelBufferRelease(pixelBuffer);
        return NULL;
    }
    
    // 4. Criar o CMSampleBuffer
    CMSampleBufferRef sampleBuffer = NULL;
    
    // Intervalos de tempo
    CMSampleTimingInfo timingInfo = {
        .duration = kCMTimeInvalid,
        .presentationTimeStamp = presentationTime,
        .decodeTimeStamp = presentationTime
    };
    
    status = CMSampleBufferCreateReadyWithImageBuffer(
        kCFAllocatorDefault,
        pixelBuffer,
        formatDescription,
        &timingInfo,
        &sampleBuffer
    );
    
    if (status != noErr || !sampleBuffer) {
        NSLog(@"Falha ao criar CMSampleBuffer: %d", status);
        CFRelease(formatDescription);
        CVPixelBufferRelease(pixelBuffer);
        return NULL;
    }
    
    // 5. Associar o pixel buffer ao sample buffer para evitar liberação prematura
    // Cria um objeto "dono" do buffer para manter referência e impedir liberação prematura
    NSMutableData *bufferOwner = [NSMutableData dataWithBytes:pixelData length:dataSize];
    objc_setAssociatedObject((__bridge id)sampleBuffer, kBufferOwnerKey, bufferOwner, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    // 6. Liberar recursos
    CFRelease(formatDescription);
    CVPixelBufferRelease(pixelBuffer);
    
    return sampleBuffer;
}

@end
