// CameraDiagnosticFramework.h

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, CameraDiagnosticLogLevel) {
    CameraDiagnosticLogLevelInfo,
    CameraDiagnosticLogLevelDebug,
    CameraDiagnosticLogLevelWarning,
    CameraDiagnosticLogLevelError
};

@interface CameraDiagnosticFramework : NSObject

+ (instancetype)sharedInstance;

// Configuração
- (void)startDiagnosticWithLogLevel:(CameraDiagnosticLogLevel)level;
- (void)stopDiagnostic;
- (void)setLogToFile:(BOOL)logToFile;
- (void)setLogFilePath:(NSString *)path;

// Hook para swizzling de métodos
- (void)hookCameraAPIs;
- (void)hookAVCaptureSession;
- (void)hookAVCaptureVideoDataOutput;
- (void)hookUIImagePickerController;
- (void)hookCoreMedia;

// Diagnóstico específico
- (void)dumpCameraConfiguration;
- (void)analyzeActiveCaptureSessions;
- (void)analyzeVideoDataOutputs;
- (void)analyzeBufferProcessingChain;
- (void)analyzeRenderingPipeline;
- (void)detectApplicationUsingCamera;
- (void)traceBufferLifecycle;

// Utilitários
- (void)logMessageWithLevel:(CameraDiagnosticLogLevel)level
                     format:(NSString *)format, ...;
- (NSString *)descriptionForCMSampleBuffer:(CMSampleBufferRef)sampleBuffer;
- (NSString *)descriptionForAVCaptureConnection:(AVCaptureConnection *)connection;
- (NSString *)descriptionForAVCaptureVideoDataOutput:(AVCaptureVideoDataOutput *)output;
- (NSString *)descriptionForPixelBuffer:(CVPixelBufferRef)pixelBuffer;

@end

NS_ASSUME_NONNULL_END
