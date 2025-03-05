// IOSurface.h - Versão simplificada sem conflitos para Tweak
// Use este arquivo apenas se o IOSurface.framework não estiver disponível

#ifndef CUSTOM_IOSURFACE_H
#define CUSTOM_IOSURFACE_H

#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct __IOSurface *IOSurfaceRef;

// Funções para gerenciar IOSurface - apenas as necessárias para o projeto
uint32_t IOSurfaceGetID(IOSurfaceRef surface);
CFDictionaryRef IOSurfaceCopyAllValues(IOSurfaceRef surface);
size_t IOSurfaceGetWidth(IOSurfaceRef surface);
size_t IOSurfaceGetHeight(IOSurfaceRef surface);
size_t IOSurfaceGetBytesPerRow(IOSurfaceRef surface);
size_t IOSurfaceGetBytesPerElement(IOSurfaceRef surface);
size_t IOSurfaceGetElementWidth(IOSurfaceRef surface);
size_t IOSurfaceGetElementHeight(IOSurfaceRef surface);
size_t IOSurfaceGetPlaneCount(IOSurfaceRef surface);
uint32_t IOSurfaceGetSeed(IOSurfaceRef surface);
OSType IOSurfaceGetPixelFormat(IOSurfaceRef surface);

#ifdef __cplusplus
}
#endif

#endif /* CUSTOM_IOSURFACE_H */
