#!/bin/bash
# Corrigir e compilar o projeto CameraDiagnostic

echo "=== Corrigindo problemas de compilação do CameraDiagnostic ==="

# 1. Adicionar os métodos de descrição que estão faltando
echo "Adicionando métodos que faltam em CameraDiagnosticFramework.m..."

# Procurar pelo final do arquivo (antes de @end)
DESCRIPTION_METHODS=$(cat <<'EOT'

#pragma mark - Métodos de Descrição

- (NSString *)descriptionForCMSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    if (!sampleBuffer || !CMSampleBufferIsValid(sampleBuffer)) {
        return @"<Buffer Inválido>";
    }
    
    NSMutableString *desc = [NSMutableString string];
    [desc appendFormat:@"<CMSampleBuffer %p", sampleBuffer];
    
    // Timestamp
    CMTime presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    [desc appendFormat:@", PTS:%lld/%d", presentationTime.value, presentationTime.timescale];
    
    // Duração
    CMTime duration = CMSampleBufferGetDuration(sampleBuffer);
    if (CMTIME_IS_VALID(duration)) {
        [desc appendFormat:@", Duração:%lld/%d", duration.value, duration.timescale];
    }
    
    // Formato
    CMFormatDescriptionRef formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer);
    if (formatDesc) {
        CMMediaType mediaType = CMFormatDescriptionGetMediaType(formatDesc);
        char mediaTypeStr[5] = {0};
        mediaTypeStr[0] = (mediaType >> 24) & 0xFF;
        mediaTypeStr[1] = (mediaType >> 16) & 0xFF;
        mediaTypeStr[2] = (mediaType >> 8) & 0xFF;
        mediaTypeStr[3] = mediaType & 0xFF;
        [desc appendFormat:@", Tipo:'%s'", mediaTypeStr];
        
        // Para tipo de vídeo, adicionar dimensões
        if (mediaType == kCMMediaType_Video) {
            CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(formatDesc);
            [desc appendFormat:@", %dx%d", dimensions.width, dimensions.height];
        }
    }
    
    // Verificar buffer de imagem
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (imageBuffer) {
        [desc appendFormat:@", ImageBuffer:%@", [self descriptionForPixelBuffer:imageBuffer]];
    }
    
    [desc appendString:@">"];
    return desc;
}

- (NSString *)descriptionForAVCaptureConnection:(AVCaptureConnection *)connection {
    if (!connection) {
        return @"<Conexão Inválida>";
    }
    
    NSMutableString *desc = [NSMutableString string];
    [desc appendFormat:@"<AVCaptureConnection %p", connection];
    
    // Estado
    [desc appendFormat:@", Ativo:%@", connection.enabled ? @"Sim" : @"Não"];
    
    // Orientação de vídeo
    if ([connection isVideoOrientationSupported]) {
        NSString *orientationStr = @"Desconhecida";
        switch (connection.videoOrientation) {
            case AVCaptureVideoOrientationPortrait:
                orientationStr = @"Portrait";
                break;
            case AVCaptureVideoOrientationPortraitUpsideDown:
                orientationStr = @"PortraitUpsideDown";
                break;
            case AVCaptureVideoOrientationLandscapeRight:
                orientationStr = @"LandscapeRight";
                break;
            case AVCaptureVideoOrientationLandscapeLeft:
                orientationStr = @"LandscapeLeft";
                break;
        }
        [desc appendFormat:@", Orientação:%@", orientationStr];
    }
    
    // Espelhamento
    if ([connection isVideoMirroringSupported]) {
        [desc appendFormat:@", Espelhado:%@", connection.videoMirrored ? @"Sim" : @"Não"];
    }
    
    // Portas de entrada
    NSMutableArray *inputPortsDesc = [NSMutableArray array];
    for (AVCaptureInputPort *port in connection.inputPorts) {
        NSString *mediaType = port.mediaType ?: @"<Unknown>";
        NSString *sourceDevice = @"";
        
        if ([port.input isKindOfClass:[AVCaptureDeviceInput class]]) {
            AVCaptureDeviceInput *deviceInput = (AVCaptureDeviceInput *)port.input;
            sourceDevice = [NSString stringWithFormat:@", Device:%@", deviceInput.device.localizedName];
        }
        
        [inputPortsDesc addObject:[NSString stringWithFormat:@"{%@%@}", mediaType, sourceDevice]];
    }
    
    if (inputPortsDesc.count > 0) {
        [desc appendFormat:@", InputPorts:%@", inputPortsDesc];
    }
    
    [desc appendString:@">"];
    return desc;
}

- (NSString *)descriptionForAVCaptureVideoDataOutput:(AVCaptureVideoDataOutput *)output {
    if (!output) {
        return @"<Output Inválido>";
    }
    
    NSMutableString *desc = [NSMutableString string];
    [desc appendFormat:@"<AVCaptureVideoDataOutput %p", output];
    
    // Delegate
    id<AVCaptureVideoDataOutputSampleBufferDelegate> delegate = output.sampleBufferDelegate;
    if (delegate) {
        [desc appendFormat:@", Delegate:%@ (%@)", delegate, [delegate class]];
    } else {
        [desc appendString:@", Sem Delegate"];
    }
    
    // Configurações de vídeo
    NSDictionary *videoSettings = output.videoSettings;
    if (videoSettings) {
        NSNumber *width = videoSettings[(NSString*)kCVPixelBufferWidthKey];
        NSNumber *height = videoSettings[(NSString*)kCVPixelBufferHeightKey];
        NSNumber *pixelFormat = videoSettings[(NSString*)kCVPixelBufferPixelFormatTypeKey];
        
        if (width && height) {
            [desc appendFormat:@", %@x%@", width, height];
        }
        
        if (pixelFormat) {
            int format = [pixelFormat intValue];
            char formatStr[5] = {0};
            formatStr[0] = (format >> 24) & 0xFF;
            formatStr[1] = (format >> 16) & 0xFF;
            formatStr[2] = (format >> 8) & 0xFF;
            formatStr[3] = format & 0xFF;
            [desc appendFormat:@", Format:'%s'", formatStr];
        }
        
        // Verificar propriedades IOSurface
        id ioSurfaceProps = videoSettings[(NSString*)kCVPixelBufferIOSurfacePropertiesKey];
        if (ioSurfaceProps) {
            [desc appendString:@", UsaIOSurface:Sim"];
        }
    }
    
    // Conexões
    NSMutableArray *connDesc = [NSMutableArray array];
    for (AVCaptureConnection *conn in output.connections) {
        NSString *desc = [NSString stringWithFormat:@"{Enabled:%@}", conn.enabled ? @"Sim" : @"Não"];
        [connDesc addObject:desc];
    }
    
    if (connDesc.count > 0) {
        [desc appendFormat:@", Conexões:%@", connDesc];
    }
    
    [desc appendString:@">"];
    return desc;
}

- (NSString *)descriptionForPixelBuffer:(CVPixelBufferRef)pixelBuffer {
    if (!pixelBuffer) {
        return @"<Buffer NULL>";
    }
    
    NSMutableString *desc = [NSMutableString string];
    [desc appendFormat:@"<CVPixelBuffer:%p", pixelBuffer];
    
    // Dimensões
    size_t width = CVPixelBufferGetWidth(pixelBuffer);
    size_t height = CVPixelBufferGetHeight(pixelBuffer);
    [desc appendFormat:@", dimensions:%zux%zu", width, height];
    
    // Formato de pixel
    OSType format = CVPixelBufferGetPixelFormatType(pixelBuffer);
    char formatStr[5] = {0};
    formatStr[0] = (format >> 24) & 0xFF;
    formatStr[1] = (format >> 16) & 0xFF;
    formatStr[2] = (format >> 8) & 0xFF;
    formatStr[3] = format & 0xFF;
    [desc appendFormat:@", format:'%s'", formatStr];
    
    // Informações de memória
    [desc appendFormat:@", bytesPerRow:%zu", CVPixelBufferGetBytesPerRow(pixelBuffer)];
    [desc appendFormat:@", dataSize:%zu", CVPixelBufferGetDataSize(pixelBuffer)];
    
    // Planos (para formatos planares como YUV)
    size_t planeCount = CVPixelBufferGetPlaneCount(pixelBuffer);
    if (planeCount > 0) {
        [desc appendFormat:@", planes:%zu", planeCount];
    }
    
    // IOSurface - CRUCIAL para interceptação
    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    IOSurfaceRef surface = CVPixelBufferGetIOSurface(pixelBuffer);
    BOOL hasIOSurface = surface != NULL;
    if (hasIOSurface) {
        uint32_t surfaceID = IOSurfaceGetID(surface);
        [desc appendFormat:@", IOSurfaceID:%u", surfaceID];
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    
    // Attachments
    CFDictionaryRef attachments = CVBufferGetAttachments(pixelBuffer, kCVAttachmentMode_ShouldPropagate);
    if (attachments) {
        CFIndex count = CFDictionaryGetCount(attachments);
        [desc appendFormat:@", attachments:%ld", count];
    }
    
    [desc appendString:@">"];
    return desc;
}
EOT
)

# Adicionar ao arquivo antes do @end
sed -i '' -e "/@end/i\\
${DESCRIPTION_METHODS}\\
" CameraDiagnosticFramework.m

echo "Métodos adicionados com sucesso!"

# 2. Agora vamos fixar outros problemas relacionados às constantes
echo "Corrigindo referências a constantes em CameraDiagnosticFramework.m..."

# Corrigir kCVPixelBufferPoolKey
sed -i '' -e 's/isEqualToString:(NSString\*)kCVPixelBufferPoolKey/isEqualToString:@"PixelBufferPool"/g' CameraDiagnosticFramework.m

# Verificar se o Makefile está configurado corretamente
echo "Verificando o Makefile..."
if ! grep -q "IOSurface" Makefile; then
    echo "Adicionando frameworks necessários ao Makefile..."
    sed -i '' -e 's/CameraDiagnostic_FRAMEWORKS = .*/CameraDiagnostic_FRAMEWORKS = UIKit AVFoundation CoreMedia CoreVideo ImageIO IOSurface IOKit/g' Makefile
fi

# 3. Limpar e compilar
echo "Limpando o projeto e recompilando..."
make clean
make

echo "=== Processo de correção concluído ==="
echo "Se ainda houver erros, por favor, verifique o log de compilação."
