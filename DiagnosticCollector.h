#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Classe DiagnosticCollector para coletar e salvar informações de diagnóstico
@interface DiagnosticCollector : NSObject

// Singleton
+ (instancetype)sharedInstance;

// Configuração de sessão
- (void)setSessionInfo:(NSDictionary *)sessionInfo;
- (void)addAppCategory:(NSString *)category;

// Métodos para registrar informações de diferentes componentes
- (void)saveDelegateInfo:(NSDictionary *)delegateInfo;
- (void)recordSessionStart:(NSDictionary *)sessionDetails;
- (void)recordSessionStop:(NSDictionary *)sessionDetails;
- (void)recordSessionInfo:(NSDictionary *)info;
- (void)recordInputAdded:(NSDictionary *)inputInfo;
- (void)recordOutputAdded:(NSDictionary *)outputInfo;
- (void)recordVideoOrientation:(NSDictionary *)orientationInfo;
- (void)recordConnectionProperty:(NSDictionary *)propertyInfo;
- (void)recordCameraFormat:(NSDictionary *)formatInfo;
- (void)recordCameraSwitch:(BOOL)isFrontCamera withResolution:(CGSize)resolution;
- (void)recordVideoOutputDelegate:(NSDictionary *)delegateInfo;
- (void)recordAudioOutputDelegate:(NSDictionary *)delegateInfo;
- (void)recordVideoSettings:(NSDictionary *)settings;
- (void)recordPhotoCapture:(NSDictionary *)captureInfo;
- (void)recordSampleBufferInfo:(NSDictionary *)bufferInfo;
- (void)recordDisplayLayerInfo:(NSDictionary *)displayInfo;
- (void)recordPhotoImageInfo:(NSDictionary *)imageInfo;
- (void)recordPhotoMetadata:(NSDictionary *)metadata;
- (void)recordDeviceOperation:(NSDictionary *)operationInfo;
- (void)recordDeviceFormatChange:(NSDictionary *)formatInfo;
- (void)recordUIImageCreation:(NSDictionary *)imageInfo;
- (void)recordUIImageViewInfo:(NSDictionary *)viewInfo;
- (void)recordImagePickerInfo:(NSDictionary *)pickerInfo;
- (void)recordPreviewLayerCreation:(NSDictionary *)layerInfo;
- (void)recordPreviewLayerOperation:(NSDictionary *)operationInfo;
- (void)recordLayerOperation:(NSDictionary *)operationInfo;
- (void)recordMetadataObjects:(NSDictionary *)metadataInfo;
- (void)recordDroppedFrame:(NSDictionary *)frameInfo;
- (void)forceSaveDiagnostic;

// Métodos de utilidade
- (NSDictionary *)getCurrentSessionInfo;
- (NSArray *)getAllDiagnosticEntries;
- (void)saveAllDiagnostics;
- (NSString *)getSessionID;

@end
