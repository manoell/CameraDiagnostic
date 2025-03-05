// IOKit.h - Declarações simplificadas para o IOKit
// Este arquivo contém apenas as declarações necessárias para o CameraDiagnostic

#ifndef IOKIT_H
#define IOKIT_H

#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach.h>

typedef mach_port_t io_object_t;
typedef io_object_t io_service_t;
typedef io_object_t io_connect_t;
typedef io_object_t io_iterator_t;
typedef UInt32 IOOptionBits;

// Constantes
#define kIOServicePlane "IOService"
#define kIOGeneralInterest "IOGeneralInterest"
#define kIOReturnSuccess 0

// Tipos de mensagens para notificação
enum {
    kIOMessageServiceIsTerminated = 0x010000,
    kIOMessageServiceIsSuspended = 0x020000,
    kIOMessageServiceIsResumed = 0x030000,
    kIOMessageServiceIsRequestingClose = 0x100000,
    kIOMessageServiceIsAttemptingOpen = 0x200000,
    kIOMessageServiceWasClosed = 0x400000,
    kIOMessageServiceBusyStateChange = 0x800000
};

// Protótipos de funções
extern kern_return_t IOMasterPort(mach_port_t bootstrapPort, mach_port_t *masterPort);
extern CFMutableDictionaryRef IOServiceMatching(const char *name);
extern kern_return_t IOServiceGetMatchingServices(mach_port_t masterPort, CFDictionaryRef matching, io_iterator_t *existing);
extern kern_return_t IOObjectRelease(io_object_t object);
extern io_object_t IOIteratorNext(io_iterator_t iterator);
extern CFTypeRef IORegistryEntryCreateCFProperty(io_object_t entry, CFStringRef key, CFAllocatorRef allocator, IOOptionBits options);
extern kern_return_t IORegistryEntryCreateCFProperties(io_object_t entry, CFMutableDictionaryRef *properties, CFAllocatorRef allocator, IOOptionBits options);
extern kern_return_t IOServiceAddInterestNotification(mach_port_t masterPort, io_service_t service, const char *interestType, void (*callback)(void *refcon, io_service_t service, uint32_t messageType, void *messageArgument), void *refcon, io_object_t *notification);

typedef void (*IOServiceInterestCallback)(void *refcon, io_service_t service, uint32_t messageType, void *messageArgument);

#endif /* IOKIT_H */
