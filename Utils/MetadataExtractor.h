#ifndef METADATA_EXTRACTOR_H
#define METADATA_EXTRACTOR_H

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>

@interface MetadataExtractor : NSObject

// Extrair metadados de buffer de amostra
+ (NSDictionary *)metadataFromSampleBuffer:(CMSampleBufferRef)sampleBuffer;

// Extrair metadados de foto
+ (NSDictionary *)metadataFromCapturePhoto:(AVCapturePhoto *)photo;

// Extrair metadados EXIF
+ (NSDictionary *)exifMetadataFromData:(NSData *)imageData;

// Extrair informações de formato de vídeo
+ (NSDictionary *)videoFormatInfoFromDescription:(CMFormatDescriptionRef)formatDescription;

// Extrair informações de formato de foto
+ (NSDictionary *)photoFormatInfoFromSettings:(AVCapturePhotoSettings *)settings;

// Extrair informações de formato de pixel buffer
+ (NSDictionary *)pixelBufferInfoFromBuffer:(CVPixelBufferRef)pixelBuffer;

// Extrair informações de transformação
+ (NSDictionary *)transformInfoFromVideoConnection:(AVCaptureConnection *)connection;

@end

#endif /* METADATA_EXTRACTOR_H */