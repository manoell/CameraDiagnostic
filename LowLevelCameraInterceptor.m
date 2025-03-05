// LowLevelCameraInterceptor.m

#import <UIKit/UIKit.h>
#import "LowLevelCameraInterceptor.h"
#import "logger.h"
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <CoreVideo/CoreVideo.h>
#import <ImageIO/ImageIO.h>
#import "IOSurface.h"

// Funções que serão interceptadas do CoreMedia/CoreVideo
static CVPixelBufferRef (*original_CVPixelBufferGetBaseAddress)(CVPixelBufferRef pixelBuffer);
static OSStatus (*original_CMVideoFormatDescriptionCreateForImageBuffer)(
    CFAllocatorRef allocator,
    CVImageBufferRef imageBuffer,
    CMVideoFormatDescriptionRef *outDesc);
static CVReturn (*original_CVPixelBufferCreate)(
    CFAllocatorRef allocator,
    size_t width, size_t height,
    OSType pixelFormatType,
    CFDictionaryRef pixelBufferAttributes,
    CVPixelBufferRef *pixelBufferOut);
static CVReturn (*original_CVPixelBufferPoolCreatePixelBuffer)(
    CFAllocatorRef allocator,
    CVPixelBufferPoolRef pixelBufferPool,
    CVPixelBufferRef *pixelBufferOut);
static IOSurfaceRef (*original_CVPixelBufferGetIOSurface)(
    CVPixelBufferRef pixelBuffer);
static CVReturn (*original_CVPixelBufferCreateWithIOSurface)(
    CFAllocatorRef allocator,
    IOSurfaceRef surface,
    CFDictionaryRef pixelBufferAttributes,
    CVPixelBufferRef *pixelBufferOut);

// Contador para controle de amostragem
static uint64_t bufferCaptureCounter = 0;
static const uint64_t BUFFER_CAPTURE_INTERVAL = 100; // Capturar 1 a cada 100 buffers

// Estrutura para rastrear fluxo de buffers - crítico para identificar padrões
typedef struct {
    uint64_t bufferId;
    CVPixelBufferRef pixelBuffer;
    CMTime timestamp;
    NSString *source;
    NSString *destination;
    NSDate *captureTime;
} BufferFlowRecord;

// Funções auxiliares
static void SaveBufferSample(CVPixelBufferRef pixelBuffer, NSString *context);
static NSString *PixelBufferDetailedDescription(CVPixelBufferRef pixelBuffer);
static NSString *GetIOServiceProperties(io_service_t service);
//static IOSurfaceRef GetIOSurfaceFromPixelBuffer(CVPixelBufferRef pixelBuffer);
static NSString *DescribeIOSurface(IOSurfaceRef surface);
static NSString *GetCurrentAppInfo(void);
static void AnalyzePixelBufferContent(CVPixelBufferRef pixelBuffer, NSString *context);
static NSData *CapturePixelBufferRawData(CVPixelBufferRef pixelBuffer);
static NSString *HashData(NSData *data);
static NSString *GetCallerInfo(void);

@implementation LowLevelCameraInterceptor {
    NSMutableArray *_hookedSymbols;
    NSMutableArray *_monitoredIOServices;
    NSMutableDictionary *_cameraServiceCache;
    NSMutableArray *_bufferFlowRecords;
    NSMutableDictionary *_activePixelBuffers;
    NSMutableDictionary *_pixelBufferHashes;
    NSMutableDictionary *_surfaceIDMapping;
    dispatch_queue_t _ioQueue;
    dispatch_queue_t _analysisQueue;
    BOOL _isMonitoring;
    io_iterator_t _ioIterator;
    NSDate *_startTimestamp;
}

#pragma mark - Singleton

+ (instancetype)sharedInstance {
    static LowLevelCameraInterceptor *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _hookedSymbols = [NSMutableArray array];
        _monitoredIOServices = [NSMutableArray array];
        _cameraServiceCache = [NSMutableDictionary dictionary];
        _bufferFlowRecords = [NSMutableArray array];
        _activePixelBuffers = [NSMutableDictionary dictionary];
        _pixelBufferHashes = [NSMutableDictionary dictionary];
        _surfaceIDMapping = [NSMutableDictionary dictionary];
        _ioQueue = dispatch_queue_create("com.camera.interceptor.iokit", DISPATCH_QUEUE_SERIAL);
        _analysisQueue = dispatch_queue_create("com.camera.interceptor.analysis", DISPATCH_QUEUE_SERIAL);
        _isMonitoring = NO;
        _captureBufferContent = YES;
        _traceCoreMediaAPIs = YES;
        _traceIOServices = YES;
        _tracePrivateCameraAPIs = YES;
        _startTimestamp = [NSDate date];
        
        // Configurar diretório para amostras de buffer
        NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        _bufferSamplesDirectory = [documentsPath stringByAppendingPathComponent:@"BufferSamples"];
        
        // Criar diretório se não existir
        if (![[NSFileManager defaultManager] fileExistsAtPath:_bufferSamplesDirectory]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:_bufferSamplesDirectory
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:nil];
        }
        
        // Configurar timer para análise periódica de padrões de fluxo
        [NSTimer scheduledTimerWithTimeInterval:10.0
                                         target:self
                                       selector:@selector(analyzeBufferFlowPatterns)
                                       userInfo:nil
                                        repeats:YES];
    }
    return self;
}

#pragma mark - Controle de Monitoramento

- (void)startMonitoring {
    if (_isMonitoring) return;
    
    LOG_INFO(@"Iniciando monitoramento de baixo nível da câmera...");
    
    // 1. Hooks em APIs do CoreMedia/CoreVideo
    if (self.traceCoreMediaAPIs) {
        [self hookCoreMediaAPIs];
    }
    
    // 2. Monitoramento de Serviços IOKit
    if (self.traceIOServices) {
        [self startIOServicesMonitoring];
    }
    
    // 3. Iniciar monitoramento de frameworks privados
    if (self.tracePrivateCameraAPIs) {
        [PrivateFrameworksMonitor startMonitoring];
    }
    
    // 4. Registrar informações do ambiente atual
    [self logSystemEnvironment];
    
    _isMonitoring = YES;
}

- (void)stopMonitoring {
    if (!_isMonitoring) return;
    
    LOG_INFO(@"Parando monitoramento de baixo nível da câmera...");
    
    // Liberar recursos IOKit
    if (_ioIterator) {
        IOObjectRelease(_ioIterator);
        _ioIterator = 0;
    }
    
    // Salvar relatório final de análise
    [self generateFinalReport];
    
    _isMonitoring = NO;
}

- (void)logSystemEnvironment {
    // Registrar informações úteis sobre o dispositivo e ambiente
    UIDevice *device = [UIDevice currentDevice];
    NSProcessInfo *processInfo = [NSProcessInfo processInfo];
    
    LOG_INFO(@"=== Ambiente do Sistema ===");
    LOG_INFO(@"Dispositivo: %@ (%@)", device.model, device.name);
    LOG_INFO(@"Sistema: iOS %@", device.systemVersion);
    LOG_INFO(@"Processo: %@ (PID: %d)", processInfo.processName, processInfo.processIdentifier);
    LOG_INFO(@"Aplicativo: %@", GetCurrentAppInfo());
    LOG_INFO(@"Memória do sistema: %.2f MB", (float)processInfo.physicalMemory / (1024 * 1024));
    LOG_INFO(@"Hora de início: %@", _startTimestamp);
    LOG_INFO(@"=========================");
}

- (void)generateFinalReport {
    LOG_INFO(@"Gerando relatório final de análise da câmera...");
    
    // Analisar padrões de buffer
    [self analyzeBufferFlowPatterns];
    
    // Resumir serviços encontrados
    LOG_INFO(@"Serviços IOKit monitorados: %@", _monitoredIOServices);
    
    // Resumir classes e métodos relevantes
    NSArray *cameraClasses = [PrivateFrameworksMonitor detectedCameraRelatedClasses];
    LOG_INFO(@"Classes relacionadas à câmera detectadas: %@", cameraClasses);
    
    // Identificar pontos de interceptação mais prováveis (baseados na análise)
    LOG_INFO(@"=== PONTOS DE INTERCEPTAÇÃO RECOMENDADOS ===");
    
    // Estruturar com base nos dados coletados - a lógica exata dependerá dos padrões encontrados
    NSArray *interceptPoints = [self identifyKeyInterceptionPoints];
    for (NSDictionary *point in interceptPoints) {
        LOG_INFO(@"Ponto: %@", point[@"name"]);
        LOG_INFO(@"  Tipo: %@", point[@"type"]);
        LOG_INFO(@"  Razão: %@", point[@"reason"]);
        LOG_INFO(@"  Confiança: %@", point[@"confidence"]);
        LOG_INFO(@"  Notas: %@", point[@"notes"]);
    }
    
    // Salvar relatório como um arquivo separado para referência
    NSString *reportPath = [self.bufferSamplesDirectory stringByAppendingPathComponent:@"camera_interception_report.txt"];
    NSMutableString *reportContent = [NSMutableString string];
    
    [reportContent appendFormat:@"=== RELATÓRIO DE INTERCEPTAÇÃO DE CÂMERA ===\n"];
    [reportContent appendFormat:@"Gerado em: %@\n", [NSDate date]];
    [reportContent appendFormat:@"Aplicativo: %@\n", GetCurrentAppInfo()];
    [reportContent appendFormat:@"Duração do monitoramento: %.1f segundos\n",
     [[NSDate date] timeIntervalSinceDate:_startTimestamp]];
    
    [reportContent appendFormat:@"\n=== ESTATÍSTICAS ===\n"];
    [reportContent appendFormat:@"Buffers capturados: %llu\n", bufferCaptureCounter];
    [reportContent appendFormat:@"Padrões de fluxo registrados: %lu\n", (unsigned long)_bufferFlowRecords.count];
    [reportContent appendFormat:@"Buffers ativos: %lu\n", (unsigned long)_activePixelBuffers.count];
    [reportContent appendFormat:@"IOSurfaces monitoradas: %lu\n", (unsigned long)_surfaceIDMapping.count];
    
    [reportContent appendFormat:@"\n=== PONTOS DE INTERCEPTAÇÃO RECOMENDADOS ===\n"];
    for (NSDictionary *point in interceptPoints) {
        [reportContent appendFormat:@"PONTO: %@\n", point[@"name"]];
        [reportContent appendFormat:@"  Tipo: %@\n", point[@"type"]];
        [reportContent appendFormat:@"  Razão: %@\n", point[@"reason"]];
        [reportContent appendFormat:@"  Confiança: %@\n", point[@"confidence"]];
        [reportContent appendFormat:@"  Notas: %@\n\n", point[@"notes"]];
    }
    
    [reportContent appendFormat:@"\n=== SERVIÇOS DETECTADOS ===\n"];
    for (NSString *service in _monitoredIOServices) {
        [reportContent appendFormat:@"- %@\n", service];
    }
    
    [reportContent appendFormat:@"\n=== FRAMEWORKS DETECTADOS ===\n"];
    for (NSString *framework in [PrivateFrameworksMonitor scannedFrameworks]) {
        [reportContent appendFormat:@"- %@\n", framework];
    }
    
    [reportContent appendFormat:@"\n=== FLUXO DE BUFFER TÍPICO ===\n"];
    // Adicionar um exemplo de fluxo de buffer baseado nos dados coletados
    NSDictionary *typicalFlow = [self calculateTypicalBufferFlow];
    [reportContent appendFormat:@"%@\n", typicalFlow[@"description"]];
    
    [reportContent writeToFile:reportPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    LOG_INFO(@"Relatório de interceptação salvo em: %@", reportPath);
}

#pragma mark - Hooks de CoreMedia/CoreVideo

- (void)hookCoreMediaAPIs {
    LOG_INFO(@"Instalando hooks em APIs do CoreMedia/CoreVideo...");
    
    // 1. Interceptar CVPixelBufferGetBaseAddress para monitorar acesso aos dados do buffer
    void *cvPixelBufferSymbol = dlsym(RTLD_DEFAULT, "CVPixelBufferGetBaseAddress");
    if (cvPixelBufferSymbol) {
        MSHookFunction(cvPixelBufferSymbol, (void *)replaced_CVPixelBufferGetBaseAddress, (void **)&original_CVPixelBufferGetBaseAddress);
        [_hookedSymbols addObject:@"CVPixelBufferGetBaseAddress"];
        LOG_INFO(@"  Hooked: CVPixelBufferGetBaseAddress");
    }
    
    // 2. Interceptar CMVideoFormatDescriptionCreateForImageBuffer para monitorar formatos
    void *cmVideoFormatSymbol = dlsym(RTLD_DEFAULT, "CMVideoFormatDescriptionCreateForImageBuffer");
    if (cmVideoFormatSymbol) {
        MSHookFunction(cmVideoFormatSymbol, (void *)replaced_CMVideoFormatDescriptionCreateForImageBuffer, (void **)&original_CMVideoFormatDescriptionCreateForImageBuffer);
        [_hookedSymbols addObject:@"CMVideoFormatDescriptionCreateForImageBuffer"];
        LOG_INFO(@"  Hooked: CMVideoFormatDescriptionCreateForImageBuffer");
    }
    
    // 3. Interceptar CVPixelBufferCreate para monitorar criação de buffers
    void *cvPixelBufferCreateSymbol = dlsym(RTLD_DEFAULT, "CVPixelBufferCreate");
    if (cvPixelBufferCreateSymbol) {
        MSHookFunction(cvPixelBufferCreateSymbol, (void *)replaced_CVPixelBufferCreate, (void **)&original_CVPixelBufferCreate);
        [_hookedSymbols addObject:@"CVPixelBufferCreate"];
        LOG_INFO(@"  Hooked: CVPixelBufferCreate");
    }
    
    // 4. CRÍTICO: Interceptar CVPixelBufferPoolCreatePixelBuffer - fonte comum de buffers da câmera
    void *cvPixelBufferPoolCreateSymbol = dlsym(RTLD_DEFAULT, "CVPixelBufferPoolCreatePixelBuffer");
    if (cvPixelBufferPoolCreateSymbol) {
        MSHookFunction(cvPixelBufferPoolCreateSymbol, (void *)replaced_CVPixelBufferPoolCreatePixelBuffer, (void **)&original_CVPixelBufferPoolCreatePixelBuffer);
        [_hookedSymbols addObject:@"CVPixelBufferPoolCreatePixelBuffer"];
        LOG_INFO(@"  Hooked: CVPixelBufferPoolCreatePixelBuffer");
    }
    
    // 5. CRÍTICO: IOSurface é frequentemente usado para transferência de memória eficiente
    void *cvPixelBufferGetIOSurfaceSymbol = dlsym(RTLD_DEFAULT, "CVPixelBufferGetIOSurface");
    if (cvPixelBufferGetIOSurfaceSymbol) {
        MSHookFunction(cvPixelBufferGetIOSurfaceSymbol, (void *)replaced_CVPixelBufferGetIOSurface, (void **)&original_CVPixelBufferGetIOSurface);
        [_hookedSymbols addObject:@"CVPixelBufferGetIOSurface"];
        LOG_INFO(@"  Hooked: CVPixelBufferGetIOSurface");
    }
    
    // 6. CRÍTICO: Criação de CVPixelBuffer a partir de IOSurface - comum em pipelines
    void *cvPixelBufferCreateWithIOSurfaceSymbol = dlsym(RTLD_DEFAULT, "CVPixelBufferCreateWithIOSurface");
    if (cvPixelBufferCreateWithIOSurfaceSymbol) {
        MSHookFunction(cvPixelBufferCreateWithIOSurfaceSymbol, (void *)replaced_CVPixelBufferCreateWithIOSurface, (void **)&original_CVPixelBufferCreateWithIOSurface);
        [_hookedSymbols addObject:@"CVPixelBufferCreateWithIOSurface"];
        LOG_INFO(@"  Hooked: CVPixelBufferCreateWithIOSurface");
    }
    
    LOG_INFO(@"Total de %lu símbolos do CoreMedia/CoreVideo interceptados", (unsigned long)_hookedSymbols.count);
}

#pragma mark - Monitoramento de Serviços IOKit

- (void)startIOServicesMonitoring {
    dispatch_async(_ioQueue, ^{
        LOG_INFO(@"Iniciando monitoramento de serviços IOKit para câmera...");
        
        // Buscar todos os serviços relacionados à câmera
        mach_port_t masterPort;
        kern_return_t result = IOMasterPort(MACH_PORT_NULL, &masterPort);
        if (result != KERN_SUCCESS) {
            LOG_ERROR(@"Falha ao obter masterPort: %d", result);
            return;
        }
        
        // Buscar por serviços de captura de vídeo/câmera
        NSArray *searchQueries = @[
            @"AppleCamera",
            @"AppleH264",
            @"AppleUSBVideoSupport",
            @"IOUSBDevice",
            @"IOMediaCapture",
            @"AppleAVE",
            @"IOSurface",
            @"AppleCLCD",
            @"AppleM2CLCD",
            @"AppleVXD393",
            @"AppleVXE380",
            @"AppleIntelIOPCIFamily",
            @"AGXFirmwareKextLoader",
            @"AppleVXVideoEncoderDriver",
            @"AppleCameraInterface"
        ];
        
        for (NSString *query in searchQueries) {
            CFMutableDictionaryRef matchDict = IOServiceMatching([query UTF8String]);
            io_iterator_t iterator;
            
            kern_return_t kr = IOServiceGetMatchingServices(masterPort, matchDict, &iterator);
            if (kr != KERN_SUCCESS) {
                LOG_ERROR(@"Falha ao buscar serviços para '%@': %d", query, kr);
                continue;
            }
            
            io_service_t service;
            while ((service = IOIteratorNext(iterator))) {
                NSString *serviceName = (__bridge_transfer NSString *)IORegistryEntryCreateCFProperty(
                                                                                                      service, CFSTR("IONameMatch"), kCFAllocatorDefault, 0);
                
                if (!serviceName) {
                    serviceName = (__bridge_transfer NSString *)IORegistryEntryCreateCFProperty(
                                                                                                service, CFSTR("IOName"), kCFAllocatorDefault, 0);
                }
                
                if (!serviceName) {
                    serviceName = [NSString stringWithFormat:@"UnknownService-%lu", (unsigned long)service];
                }
                
                LOG_INFO(@"Encontrado serviço IOKit relacionado à câmera: %@ (%d)", serviceName, service);
                
                // Obter propriedades detalhadas
                NSString *properties = GetIOServiceProperties(service);
                LOG_INFO(@"Propriedades do serviço %@: %@", serviceName, properties);
                
                // Verificar se há propriedades relacionadas a vídeo/câmera
                if ([properties containsString:@"Video"] ||
                    [properties containsString:@"Camera"] ||
                    [properties containsString:@"Image"] ||
                    [properties containsString:@"Surface"] ||
                    [properties containsString:@"Frame"] ||
                    [properties containsString:@"Media"]) {
                    
                    LOG_INFO(@"Serviço potencialmente interessante para interceptação: %@", serviceName);
                }
                
                // Armazenar em cache
                [_cameraServiceCache setObject:@(service) forKey:serviceName];
                [_monitoredIOServices addObject:serviceName];
                
                // Configurar notificação para quando o serviço for usado
                IOServiceAddInterestNotification(
                                                 masterPort, service, kIOGeneralInterest,
                                                 MyIOServiceInterestCallback, (__bridge void *)(self),
                                                 &_ioIterator);
                
                IOObjectRelease(service);
            }
            IOObjectRelease(iterator);
        }
        
        LOG_INFO(@"Monitorando %lu serviços IOKit relacionados à câmera", (unsigned long)_monitoredIOServices.count);
    });
}

#pragma mark - Análise de Padrões de Buffer

- (void)registerBufferFlow:(CVPixelBufferRef)pixelBuffer
                    source:(NSString *)source
               destination:(NSString *)destination {
    if (!pixelBuffer) return;
    
    dispatch_async(_analysisQueue, ^{
        // Gerar identificador único e hash para o buffer
        NSString *bufferKey = [NSString stringWithFormat:@"%p", pixelBuffer];
        
        // Registrar no sistema de rastreamento
        BufferFlowRecord record;
        record.bufferId = bufferCaptureCounter++;
        record.pixelBuffer = pixelBuffer;
        record.timestamp = CMTimeMake(0, 0); // Placeholder
        record.source = source;
        record.destination = destination;
        record.captureTime = [NSDate date];
        
        // Armazenar registro
        [self->_bufferFlowRecords addObject:[NSValue valueWithBytes:&record objCType:@encode(BufferFlowRecord)]];
        
        // Registrar buffer ativo
        [self->_activePixelBuffers setObject:source forKey:bufferKey];
        
        // Calcular hash do conteúdo para detectar modificações
        if (self.captureBufferContent) {
            NSData *pixelData = CapturePixelBufferRawData(pixelBuffer);
            if (pixelData) {
                NSString *hash = HashData(pixelData);
                [self->_pixelBufferHashes setObject:hash forKey:bufferKey];
            }
        }
        
        // Se temos muitos registros, limpe os mais antigos
        if (self->_bufferFlowRecords.count > 1000) {
            [self->_bufferFlowRecords removeObjectsInRange:NSMakeRange(0, 500)];
        }
    });
}

- (void)analyzeBufferFlowPatterns {
    dispatch_async(_analysisQueue, ^{
        if (self->_bufferFlowRecords.count < 10) {
            return; // Não temos dados suficientes ainda
        }
        
        LOG_INFO(@"Analisando padrões de fluxo de buffer (%lu registros)...",
                 (unsigned long)self->_bufferFlowRecords.count);
        
        // 1. Identificar caminhos comuns de buffer
        NSMutableDictionary *sourcesToDestinations = [NSMutableDictionary dictionary];
        
        for (NSValue *value in self->_bufferFlowRecords) {
            BufferFlowRecord record;
            [value getValue:&record];
            
            NSString *key = record.source ?: @"unknown";
            NSMutableSet *destinations = sourcesToDestinations[key];
            if (!destinations) {
                destinations = [NSMutableSet set];
                sourcesToDestinations[key] = destinations;
            }
            
            if (record.destination) {
                [destinations addObject:record.destination];
            }
        }
        
        // 2. Identificar pontos cruciais de fluxo
        NSMutableArray *criticalPaths = [NSMutableArray array];
        for (NSString *source in sourcesToDestinations) {
            NSSet *destinations = sourcesToDestinations[source];
            if (destinations.count > 2) {
                // Este é um ponto de distribuição interessante
                [criticalPaths addObject:@{
                    @"source": source,
                    @"destinations": destinations.allObjects,
                    @"count": @(destinations.count)
                }];
            }
        }
        
        // 3. Ordenar por número de destinos (potencialmente mais valioso para interceptação)
        [criticalPaths sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
            NSNumber *count1 = obj1[@"count"];
            NSNumber *count2 = obj2[@"count"];
            return [count2 compare:count1]; // Ordem decrescente
        }];
        
        if (criticalPaths.count > 0) {
            LOG_INFO(@"Identificados %lu caminhos críticos de buffer", (unsigned long)criticalPaths.count);
            for (NSDictionary *path in criticalPaths) {
                LOG_INFO(@"  Fonte: %@, Destinos: %lu",
                         path[@"source"],
                         (unsigned long)[path[@"destinations"] count]);
                LOG_DEBUG(@"    Destinos: %@", path[@"destinations"]);
            }
        }
        
        // 4. Analisar modificações de buffer
        NSMutableDictionary *modificationPoints = [NSMutableDictionary dictionary];
        NSMutableSet *processedBuffers = [NSMutableSet set];
        
        for (NSValue *value in self->_bufferFlowRecords) {
            BufferFlowRecord record;
            [value getValue:&record];
            
            NSString *bufferKey = [NSString stringWithFormat:@"%p", record.pixelBuffer];
            if ([processedBuffers containsObject:bufferKey]) continue;
            [processedBuffers addObject:bufferKey];
            
            NSString *initialHash = self->_pixelBufferHashes[bufferKey];
            if (!initialHash) continue;
            
            // Procurar outros registros do mesmo buffer para ver mudanças
            for (NSValue *otherValue in self->_bufferFlowRecords) {
                BufferFlowRecord otherRecord;
                [otherValue getValue:&otherRecord];
                
                if (record.pixelBuffer == otherRecord.pixelBuffer &&
                    ![record.source isEqualToString:otherRecord.source]) {
                    
                    NSString *newHash = self->_pixelBufferHashes[[NSString stringWithFormat:@"%p", otherRecord.pixelBuffer]];
                    if (newHash && ![newHash isEqualToString:initialHash]) {
                        NSString *modKey = [NSString stringWithFormat:@"%@ -> %@", record.source, otherRecord.source];
                        modificationPoints[modKey] = @{
                            @"source": record.source,
                            @"destination": otherRecord.source,
                            @"originalHash": initialHash,
                            @"newHash": newHash
                        };
                        
                        LOG_INFO(@"Detectada modificação de buffer: %@ -> %@", record.source, otherRecord.source);
                    }
                }
            }
        }
        
        if (modificationPoints.count > 0) {
            LOG_INFO(@"Identificados %lu pontos de modificação de buffer",
                     (unsigned long)modificationPoints.count);
        }
        
        // 5. Analisar uso de IOSurface
        NSMutableDictionary *surfaceUsage = [NSMutableDictionary dictionary];
        for (NSString *surfaceID in self->_surfaceIDMapping) {
            NSArray *usages = self->_surfaceIDMapping[surfaceID];
            
            if (usages.count > 1) {
                surfaceUsage[surfaceID] = @{
                    @"id": surfaceID,
                    @"usages": usages,
                    @"count": @(usages.count)
                };
            }
        }
        
        if (surfaceUsage.count > 0) {
            LOG_INFO(@"Identificadas %lu IOSurfaces compartilhadas entre componentes",
                     (unsigned long)surfaceUsage.count);
            
            // Ordenar por número de usos
            NSArray *sortedSurfaces = [surfaceUsage.allValues sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2) {
                NSNumber *count1 = obj1[@"count"];
                NSNumber *count2 = obj2[@"count"];
                return [count2 compare:count1]; // Ordem decrescente
            }];
            
            for (NSDictionary *surface in sortedSurfaces) {
                LOG_INFO(@"  IOSurface %@: %lu usos",
                         surface[@"id"],
                         (unsigned long)[surface[@"usages"] count]);
                LOG_DEBUG(@"    Usos: %@", surface[@"usages"]);
            }
        }
    });
}

- (NSArray *)identifyKeyInterceptionPoints {
    NSMutableArray *points = [NSMutableArray array];
    
    // Analisar fluxos para identificar pontos específicos
    // Método baseado nos dados coletados
    
    // 1. CVPixelBufferPoolCreatePixelBuffer - ponto comum de criação de buffers da câmera
    [points addObject:@{
        @"name": @"CVPixelBufferPoolCreatePixelBuffer",
        @"type": @"API Hook",
        @"reason": @"Ponto central de criação de buffers da câmera em todos os aplicativos",
        @"confidence": @"Alta",
        @"notes": @"A substituição neste ponto afetaria todos os buffers criados a partir de um pool, incluindo aqueles da câmera. É um ótimo ponto universal para intercepção."
    }];
    
    // 2. CVPixelBufferCreateWithIOSurface - transferências inter-processo
    [points addObject:@{
        @"name": @"CVPixelBufferCreateWithIOSurface",
        @"type": @"API Hook",
        @"reason": @"Ponto crítico para transferências de memória eficientes entre processos/componentes",
        @"confidence": @"Alta",
        @"notes": @"IOSurface é frequentemente usado para transferir dados de vídeo entre processos e threads. É um ponto ideal para substituição universal."
    }];
    
    // 3. CVPixelBufferGetIOSurface - identificar superfícies compartilhadas
    [points addObject:@{
        @"name": @"IOSurface IDs",
        @"type": @"Rastreamento",
        @"reason": @"IOSurfaces são um mecanismo-chave para compartilhamento de dados entre componentes",
        @"confidence": @"Média",
        @"notes": @"Monitorar IDs de IOSurface pode revelar as conexões exatas entre componentes da pipeline da câmera."
    }];
    
    // 4. Serviço específico do driver de câmera (baseado nos dados coletados)
    NSString *cameraServiceKey = nil;
    for (NSString *key in _monitoredIOServices) {
        if ([key containsString:@"AppleCamera"] ||
            [key containsString:@"IOMediaCapture"]) {
            cameraServiceKey = key;
            break;
        }
    }
    
    if (cameraServiceKey) {
        [points addObject:@{
            @"name": cameraServiceKey,
            @"type": @"IOKit Service",
            @"reason": @"Serviço de nível inferior que controla diretamente o hardware da câmera",
            @"confidence": @"Média",
            @"notes": @"Interceptar no nível do driver oferece a abordagem mais universal, mas é tecnicamente mais desafiador."
        }];
    }
    
    // 5. Frameworks privados identificados
    NSArray *criticalClasses = [PrivateFrameworksMonitor detectedCameraRelatedClasses];
    for (NSString *className in criticalClasses) {
        if ([className containsString:@"CameraDevice"] ||
            [className containsString:@"CaptureSession"] ||
            [className containsString:@"CaptureDevice"]) {
            
            [points addObject:@{
                @"name": className,
                @"type": @"Framework Privado",
                @"reason": @"Classe central no pipeline de processamento de câmera da Apple",
                @"confidence": @"Média",
                @"notes": @"Requer acesso a frameworks privados. Pode ser mais frágil entre atualizações do iOS."
            }];
            
            // Limitar a um número razoável de classes
            if (points.count >= 7) break;
        }
    }
    
    return points;
}

- (NSDictionary *)calculateTypicalBufferFlow {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSMutableString *flowDescription = [NSMutableString string];
    
    // Simplificar os dados para mostrar um fluxo típico
    NSMutableDictionary *sourceFrequency = [NSMutableDictionary dictionary];
    NSMutableDictionary *transitions = [NSMutableDictionary dictionary];
    
    // Analisar os registros de fluxo
    for (NSValue *value in _bufferFlowRecords) {
        BufferFlowRecord record;
        [value getValue:&record];
        
        NSString *source = record.source ?: @"<unknown>";
        NSString *destination = record.destination ?: @"<unknown>";
        
        // Contagem de fontes
        NSNumber *count = sourceFrequency[source];
        sourceFrequency[source] = @(count ? count.integerValue + 1 : 1);
        
        // Contagem de transições
        NSString *transitionKey = [NSString stringWithFormat:@"%@ -> %@", source, destination];
        NSNumber *transCount = transitions[transitionKey];
        transitions[transitionKey] = @(transCount ? transCount.integerValue + 1 : 1);
    }
    
    // Ordenar fontes por frequência
    NSArray *sortedSources = [sourceFrequency keysSortedByValueUsingComparator:^NSComparisonResult(id obj1, id obj2) {
        return [obj2 compare:obj1]; // Ordem decrescente
    }];
    
    // Construir descrição do fluxo
    [flowDescription appendString:@"Fluxo típico de buffer de vídeo:\n\n"];
    
    // Adicionar os principais nós do fluxo
    if (sortedSources.count > 0) {
        for (NSString *source in sortedSources) {
            [flowDescription appendFormat:@"%@ (%@)\n", source, sourceFrequency[source]];
            
            // Encontrar transições a partir desta fonte
            NSMutableDictionary *destinationsForSource = [NSMutableDictionary dictionary];
            for (NSString *transition in transitions) {
                if ([transition hasPrefix:[NSString stringWithFormat:@"%@ ->", source]]) {
                    NSString *destination = [transition componentsSeparatedByString:@" -> "].lastObject;
                    destinationsForSource[destination] = transitions[transition];
                }
            }
            
            // Ordenar destinos por frequência
            NSArray *sortedDestinations = [destinationsForSource keysSortedByValueUsingComparator:^NSComparisonResult(id obj1, id obj2) {
                return [obj2 compare:obj1]; // Ordem decrescente
            }];
            
            for (NSString *destination in sortedDestinations) {
                [flowDescription appendFormat:@"  └─> %@ (%@)\n", destination, destinationsForSource[destination]];
            }
        }
    } else {
        [flowDescription appendString:@"Dados insuficientes para determinar fluxo típico.\n"];
    }
    
    result[@"description"] = flowDescription;
    result[@"sources"] = sortedSources;
    result[@"transitions"] = transitions;
    
    return result;
}

#pragma mark - Callbacks para Hooks de Funções

// CVPixelBufferGetBaseAddress - Chamado quando um aplicativo acessa dados de pixel
void *replaced_CVPixelBufferGetBaseAddress(CVPixelBufferRef pixelBuffer) {
    void *baseAddress = original_CVPixelBufferGetBaseAddress(pixelBuffer);
    
    static uint64_t callCounter = 0;
    callCounter++;
    
    // Logar apenas periodicamente para evitar spam
    if (callCounter % 100 == 0) {
        NSString *backtrace = [NSThread callStackSymbols].description;
        LOG_INFO(@"⚡️ CVPixelBufferGetBaseAddress chamado para buffer %p (endereço: %p)", pixelBuffer, baseAddress);
        LOG_DEBUG(@"  Stack: %@", backtrace);
        
        // Obter detalhes do buffer
        NSString *details = PixelBufferDetailedDescription(pixelBuffer);
        LOG_DEBUG(@"  Detalhes: %@", details);
        
        NSString *callerInfo = GetCallerInfo();
        [[LowLevelCameraInterceptor sharedInstance] registerBufferFlow:pixelBuffer
                                                                source:@"CVPixelBufferGetBaseAddress"
                                                           destination:callerInfo];
        
        // Capturar amostra do conteúdo se configurado e a cada X frames
        if ([LowLevelCameraInterceptor sharedInstance].captureBufferContent && callCounter % BUFFER_CAPTURE_INTERVAL == 0) {
            SaveBufferSample(pixelBuffer, @"CVPixelBufferGetBaseAddress");
        }
    }
    
    return baseAddress;
}

// CMVideoFormatDescriptionCreateForImageBuffer - Chamado quando um formato é criado
OSStatus replaced_CMVideoFormatDescriptionCreateForImageBuffer(
                                                               CFAllocatorRef allocator,
                                                               CVImageBufferRef imageBuffer,
                                                               CMVideoFormatDescriptionRef *outDesc) {
    
    OSStatus result = original_CMVideoFormatDescriptionCreateForImageBuffer(allocator, imageBuffer, outDesc);
    
    NSString *backtrace = [NSThread callStackSymbols].description;
    LOG_INFO(@"⚡️ CMVideoFormatDescriptionCreateForImageBuffer chamado para buffer %p (resultado: %d)", imageBuffer, result);
    LOG_DEBUG(@"  Stack: %@", backtrace);
    
    // Registrar informações do formato criado
    if (result == noErr && outDesc && *outDesc) {
        CMVideoFormatDescriptionRef desc = *outDesc;
        CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(desc);
        FourCharCode codec = CMFormatDescriptionGetMediaSubType(desc);
        
        char codecStr[5] = {0};
        codecStr[0] = (codec >> 24) & 0xFF;
        codecStr[1] = (codec >> 16) & 0xFF;
        codecStr[2] = (codec >> 8) & 0xFF;
        codecStr[3] = codec & 0xFF;
        
        LOG_INFO(@"  Formato criado: %dx%d, codec: '%s'", dimensions.width, dimensions.height, codecStr);
        
        // Verificar extensões - CRÍTICO para entender as capacidades do buffer
        CFDictionaryRef extensions = CMFormatDescriptionGetExtensions(desc);
        if (extensions) {
            NSDictionary *extDict = (__bridge NSDictionary *)extensions;
            LOG_DEBUG(@"  Extensions: %@", extDict);
            
            // Verificar informações específicas de câmera nas extensões
            for (NSString *key in extDict) {
                if ([key containsString:@"Camera"] ||
                    [key containsString:@"Video"] ||
                    [key containsString:@"PixelFormat"] ||
                    [key containsString:@"IOSurface"]) {
                    LOG_INFO(@"  🔍 Extensão relevante: %@ = %@", key, extDict[key]);
                }
            }
        }
        
        NSString *callerInfo = GetCallerInfo();
        [[LowLevelCameraInterceptor sharedInstance] registerBufferFlow:imageBuffer
                                                                source:callerInfo
                                                           destination:@"CMVideoFormatDescriptionCreateForImageBuffer"];
    }
    
    return result;
}

// CVPixelBufferCreate - Chamado quando um buffer é criado
CVReturn replaced_CVPixelBufferCreate(
                                      CFAllocatorRef allocator,
                                      size_t width, size_t height,
                                      OSType pixelFormatType,
                                      CFDictionaryRef pixelBufferAttributes,
                                      CVPixelBufferRef *pixelBufferOut) {
    
    CVReturn result = original_CVPixelBufferCreate(allocator, width, height, pixelFormatType, pixelBufferAttributes, pixelBufferOut);
    
    char formatStr[5] = {0};
    formatStr[0] = (pixelFormatType >> 24) & 0xFF;
    formatStr[1] = (pixelFormatType >> 16) & 0xFF;
    formatStr[2] = (pixelFormatType >> 8) & 0xFF;
    formatStr[3] = pixelFormatType & 0xFF;
    
    NSString *backtrace = [NSThread callStackSymbols].description;
    LOG_INFO(@"⚡️ CVPixelBufferCreate chamado: %zux%zu, formato: '%s', resultado: %d", width, height, formatStr, result);
    LOG_DEBUG(@"  Stack: %@", backtrace);
    
    if (result == kCVReturnSuccess && pixelBufferOut && *pixelBufferOut) {
        LOG_INFO(@"  Buffer criado: %p", *pixelBufferOut);
        
        // Registrar atributos usados
        if (pixelBufferAttributes) {
            NSDictionary *attributes = (__bridge NSDictionary *)pixelBufferAttributes;
            LOG_DEBUG(@"  Atributos: %@", attributes);
            
            // Verificar propriedades específicas importantes
            BOOL hasIOSurface = NO;
            for (NSString *key in attributes) {
                if ([key containsString:@"IOSurface"]) {
                    hasIOSurface = YES;
                    LOG_INFO(@"  🔍 Propriedade IOSurface encontrada: %@ = %@", key, attributes[key]);
                }
            }
            
            if (hasIOSurface) {
                LOG_INFO(@"  ⚠️ Este buffer usa IOSurface - potencial ponto de interceptação");
            }
        }
        
        NSString *callerInfo = GetCallerInfo();
        [[LowLevelCameraInterceptor sharedInstance] registerBufferFlow:*pixelBufferOut
                                                                source:callerInfo
                                                           destination:@"CVPixelBufferCreate"];
    }
    
    return result;
}

// CVPixelBufferPoolCreatePixelBuffer - Ponto crítico para interceptação! Frequentemente usado pela câmera
CVReturn replaced_CVPixelBufferPoolCreatePixelBuffer(
                                                     CFAllocatorRef allocator,
                                                     CVPixelBufferPoolRef pixelBufferPool,
                                                     CVPixelBufferRef *pixelBufferOut) {
    
    // Gerar um ID para o pool para rastreamento
    //NSString *poolID = [NSString stringWithFormat:@"%p", pixelBufferPool];
    
    // Registrar quem está chamando
    NSString *callerInfo = GetCallerInfo();
    NSString *appInfo = GetCurrentAppInfo();
    
    LOG_INFO(@"⭐️ CVPixelBufferPoolCreatePixelBuffer chamado: Pool %p, App: %@", pixelBufferPool, appInfo);
    LOG_INFO(@"  Chamador: %@", callerInfo);
    
    // Obter propriedades do pool para verificar se é da câmera
    BOOL isCameraPool = NO;
    CFDictionaryRef poolAttrs = NULL;
    poolAttrs = CVPixelBufferPoolGetAttributes(pixelBufferPool);
    if (poolAttrs) {
        NSDictionary *attrs = (__bridge NSDictionary *)poolAttrs;
        LOG_DEBUG(@"  Pool Attributes: %@", attrs);
        
        // Verificar atributos que indicam origem da câmera
        for (NSString *key in attrs) {
            if ([key containsString:@"Camera"] ||
                [key containsString:@"Video"] ||
                [key containsString:@"AVCapture"]) {
                isCameraPool = YES;
                LOG_INFO(@"  🎯 POOL DE CÂMERA DETECTADO! %@ = %@", key, attrs[key]);
            }
        }
    }
    
    // Executar função original
    CVReturn result = original_CVPixelBufferPoolCreatePixelBuffer(allocator, pixelBufferPool, pixelBufferOut);
    
    if (result == kCVReturnSuccess && pixelBufferOut && *pixelBufferOut) {
        LOG_INFO(@"  Buffer %p criado a partir do pool %p", *pixelBufferOut, pixelBufferPool);
        
        // Analisar as propriedades do buffer criado
        CVPixelBufferRef buffer = *pixelBufferOut;
        NSString *details = PixelBufferDetailedDescription(buffer);
        LOG_DEBUG(@"  Detalhes do buffer: %@", details);
        
        // Registrar no fluxo
        [[LowLevelCameraInterceptor sharedInstance] registerBufferFlow:buffer
                                                                source:isCameraPool ? @"CameraVideoPool" : @"CVPixelBufferPool"
                                                           destination:callerInfo];
        
        // Se for um pool de câmera, registrar uma amostra
        if (isCameraPool) {
            SaveBufferSample(buffer, @"CameraVideoPool");
            LOG_INFO(@"  ⚠️ ESTE É UM PONTO CRÍTICO PARA INTERCEPTAÇÃO UNIVERSAL!");
            
            // Analisar o conteúdo para verificar características do vídeo da câmera
            AnalyzePixelBufferContent(buffer, @"CameraVideoPool");
        }
    }
    
    return result;
}

// CVPixelBufferGetIOSurface - Rastreamento de IOSurfaces
IOSurfaceRef replaced_CVPixelBufferGetIOSurface(CVPixelBufferRef pixelBuffer) {
    IOSurfaceRef surface = original_CVPixelBufferGetIOSurface(pixelBuffer);
    
    static uint64_t callCounter = 0;
    callCounter++;
    
    // Logar periodicamente para evitar spam
    if (callCounter % 50 == 0 && surface) {
        uint32_t surfaceID = IOSurfaceGetID(surface);
        NSString *surfaceIDStr = [NSString stringWithFormat:@"%u", surfaceID];
        NSString *callerInfo = GetCallerInfo();
        
        LOG_INFO(@"⚡️ CVPixelBufferGetIOSurface: Buffer %p -> IOSurface %p (ID: %u)",
                 pixelBuffer, surface, surfaceID);
        
        // Descrever a IOSurface - CRUCIAL para entender o compartilhamento
        NSString *surfaceDesc = DescribeIOSurface(surface);
        LOG_DEBUG(@"  IOSurface Detalhes: %@", surfaceDesc);
        
        // Registrar uso da IOSurface
        LowLevelCameraInterceptor *interceptor = [LowLevelCameraInterceptor sharedInstance];
        NSMutableArray *usages = interceptor->_surfaceIDMapping[surfaceIDStr];
        if (!usages) {
            usages = [NSMutableArray array];
            interceptor->_surfaceIDMapping[surfaceIDStr] = usages;
        }
        if (![usages containsObject:callerInfo]) {
            [usages addObject:callerInfo];
        }
        
        // Se uma IOSurface é usada por múltiplos componentes, é um ponto de interceptação potencial
        if (usages.count > 1) {
            LOG_INFO(@"  ⚠️ IOSurface %u usada por múltiplos componentes: %@", surfaceID, usages);
            LOG_INFO(@"  🎯 IOSurface compartilhada - potencial ponto de interceptação universal");
        }
    }
    
    return surface;
}

// CVPixelBufferCreateWithIOSurface - Criação de buffer a partir de IOSurface
CVReturn replaced_CVPixelBufferCreateWithIOSurface(
                                                   CFAllocatorRef allocator,
                                                   IOSurfaceRef surface,
                                                   CFDictionaryRef pixelBufferAttributes,
                                                   CVPixelBufferRef *pixelBufferOut) {
    
    uint32_t surfaceID = IOSurfaceGetID(surface);
    NSString *callerInfo = GetCallerInfo();
    NSString *appInfo = GetCurrentAppInfo();
    
    LOG_INFO(@"⭐️ CVPixelBufferCreateWithIOSurface: Surface %p (ID: %u), App: %@",
             surface, surfaceID, appInfo);
    LOG_INFO(@"  Chamador: %@", callerInfo);
    
    // Descrever a IOSurface
    NSString *surfaceDesc = DescribeIOSurface(surface);
    LOG_DEBUG(@"  IOSurface Detalhes: %@", surfaceDesc);
    
    // Executar função original
    CVReturn result = original_CVPixelBufferCreateWithIOSurface(allocator, surface, pixelBufferAttributes, pixelBufferOut);
    
    if (result == kCVReturnSuccess && pixelBufferOut && *pixelBufferOut) {
        LOG_INFO(@"  Buffer %p criado a partir da IOSurface %u", *pixelBufferOut, surfaceID);
        
        // Analisar propriedades do buffer criado
        CVPixelBufferRef buffer = *pixelBufferOut;
        NSString *details = PixelBufferDetailedDescription(buffer);
        LOG_DEBUG(@"  Detalhes do buffer: %@", details);
        
        // Registrar no fluxo
        [[LowLevelCameraInterceptor sharedInstance] registerBufferFlow:buffer
                                                                source:[NSString stringWithFormat:@"IOSurface-%u", surfaceID]
                                                           destination:callerInfo];
        
        // Este é frequentemente um ponto crítico para interceptação
        LOG_INFO(@"  ⚠️ CRIAÇÃO DE BUFFER A PARTIR DE IOSURFACE - potencial ponto de interceptação universal");
        
        // Verificar atributos para determinar o uso
        if (pixelBufferAttributes) {
            NSDictionary *attrs = (__bridge NSDictionary *)pixelBufferAttributes;
            for (NSString *key in attrs) {
                if ([key containsString:@"Camera"] ||
                    [key containsString:@"Video"] ||
                    [key containsString:@"Display"]) {
                    LOG_INFO(@"  🎯 Atributo relevante: %@ = %@", key, attrs[key]);
                }
            }
        }
        
        // Salvar uma amostra do buffer
        SaveBufferSample(buffer, @"IOSurfaceBuffer");
        
        // Analisar conteúdo
        AnalyzePixelBufferContent(buffer, @"IOSurfaceBuffer");
        
        // Registrar uso da IOSurface
        NSString *surfaceIDStr = [NSString stringWithFormat:@"%u", surfaceID];
        LowLevelCameraInterceptor *interceptor = [LowLevelCameraInterceptor sharedInstance];
        NSMutableArray *usages = interceptor->_surfaceIDMapping[surfaceIDStr];
        if (!usages) {
            usages = [NSMutableArray array];
            interceptor->_surfaceIDMapping[surfaceIDStr] = usages;
        }
        if (![usages containsObject:callerInfo]) {
            [usages addObject:callerInfo];
        }
    }
    
    return result;
}

#pragma mark - Callback para IOKit

static void MyIOServiceInterestCallback(void *refCon, io_service_t service, uint32_t messageType, void *messageArgument) {
    LowLevelCameraInterceptor *interceptor = (__bridge LowLevelCameraInterceptor *)refCon;
    // Use a variável interceptor aqui para evitar o aviso de não utilização
    if (interceptor) {
        // Faça algo com interceptor
        LOG_DEBUG(@"Callback received for interceptor: %@", interceptor);
    }
    // Esta função é chamada quando há atividade em um serviço IOKit monitorado
    //LowLevelCameraInterceptor *interceptor = (__bridge LowLevelCameraInterceptor *)refCon;
    
    NSString *serviceName = (__bridge_transfer NSString *)IORegistryEntryCreateCFProperty(
                                                                                          service, CFSTR("IONameMatch"), kCFAllocatorDefault, 0);
    
    if (!serviceName) {
        serviceName = (__bridge_transfer NSString *)IORegistryEntryCreateCFProperty(
                                                                                    service, CFSTR("IOName"), kCFAllocatorDefault, 0);
    }
    
    if (!serviceName) {
        serviceName = [NSString stringWithFormat:@"UnknownService-%lu", (unsigned long)service];
    }
    
    // Identificar tipo de mensagem
    NSString *messageTypeStr = @"Desconhecido";
    switch (messageType) {
        case kIOMessageServiceIsTerminated:
            messageTypeStr = @"Terminated";
            break;
        case kIOMessageServiceIsSuspended:
            messageTypeStr = @"Suspended";
            break;
        case kIOMessageServiceIsResumed:
            messageTypeStr = @"Resumed";
            break;
        case kIOMessageServiceIsRequestingClose:
            messageTypeStr = @"RequestingClose";
            break;
        case kIOMessageServiceIsAttemptingOpen:
            messageTypeStr = @"AttemptingOpen";
            break;
        case kIOMessageServiceWasClosed:
            messageTypeStr = @"WasClosed";
            break;
        case kIOMessageServiceBusyStateChange:
            messageTypeStr = @"BusyStateChange";
            break;
    }
    
    // Filtrar para eventos mais importantes
    if (messageType == kIOMessageServiceIsAttemptingOpen ||
        messageType == kIOMessageServiceIsResumed ||
        messageType == kIOMessageServiceIsTerminated) {
        
        LOG_INFO(@"⚡️ Evento IOKit: Serviço %@ (%d) - Mensagem: %@ (%u)", serviceName, service, messageTypeStr, messageType);
        
        // Registrar aplicativo atual
        LOG_INFO(@"  App: %@", GetCurrentAppInfo());
        
        // Capturar stack para ver quem está usando
        NSString *backtrace = [NSThread callStackSymbols].description;
        LOG_DEBUG(@"  Stack: %@", backtrace);
        
        // Verificar propriedades atualizadas do serviço
        NSString *properties = GetIOServiceProperties(service);
        LOG_DEBUG(@"  Propriedades atualizadas: %@", properties);
        
        // Identificar serviços da câmera
        if ([serviceName containsString:@"Camera"] ||
            [serviceName containsString:@"Video"] ||
            [serviceName containsString:@"Media"]) {
            
            LOG_INFO(@"  ⚠️ SERVIÇO DE CÂMERA ATIVO: %@", serviceName);
            
            if (messageType == kIOMessageServiceIsAttemptingOpen) {
                LOG_INFO(@"  🎯 ABERTURA DO DISPOSITIVO DE CÂMERA DETECTADA - ponto de interceptação de baixo nível");
            }
        }
    }
}

#pragma mark - Utilitários

// Obter propriedades de um serviço IOKit
static NSString *GetIOServiceProperties(io_service_t service) {
    CFMutableDictionaryRef propertiesDict = NULL;
    kern_return_t kr = IORegistryEntryCreateCFProperties(service, &propertiesDict, kCFAllocatorDefault, 0);
    
    if (kr != KERN_SUCCESS || !propertiesDict) {
        return @"Não foi possível obter propriedades";
    }
    
    NSMutableDictionary *properties = (__bridge_transfer NSMutableDictionary *)propertiesDict;
    
    // Extrair valores úteis para diagnóstico
    NSMutableString *result = [NSMutableString string];
    [result appendString:@"{\n"];
    
    for (NSString *key in properties.allKeys) {
        id value = properties[key];
        [result appendFormat:@"  %@: ", key];
        
        if ([value isKindOfClass:[NSData class]]) {
            NSData *data = (NSData *)value;
            [result appendFormat:@"<Data: %lu bytes>", (unsigned long)data.length];
        } else if ([value isKindOfClass:[NSDictionary class]]) {
            [result appendFormat:@"<Dictionary: %lu entries>", (unsigned long)[(NSDictionary *)value count]];
        } else if ([value isKindOfClass:[NSArray class]]) {
            [result appendFormat:@"<Array: %lu items>", (unsigned long)[(NSArray *)value count]];
        } else {
            [result appendFormat:@"%@", value];
        }
        
        [result appendString:@",\n"];
    }
    
    [result appendString:@"}"];
    return result;
}

// Descrição detalhada de um CVPixelBuffer
static NSString *PixelBufferDetailedDescription(CVPixelBufferRef pixelBuffer) {
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
        
        for (size_t i = 0; i < planeCount; i++) {
            [desc appendFormat:@"\n    Plane %zu: %zux%zu, bytesPerRow:%zu",
             i,
             CVPixelBufferGetWidthOfPlane(pixelBuffer, i),
             CVPixelBufferGetHeightOfPlane(pixelBuffer, i),
             CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, i)];
        }
    }
    
    // IOSurface - CRUCIAL para interceptação
    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    IOSurfaceRef surface = CVPixelBufferGetIOSurface(pixelBuffer);
    BOOL hasIOSurface = surface != NULL;
    if (hasIOSurface) {
        uint32_t surfaceID = IOSurfaceGetID(surface);
        [desc appendFormat:@", IOSurfaceID:%u", surfaceID];
        
        // Verificar propriedades da IOSurface
        size_t surfaceWidth = IOSurfaceGetWidth(surface);
        size_t surfaceHeight = IOSurfaceGetHeight(surface);
        if (surfaceWidth != width || surfaceHeight != height) {
            [desc appendFormat:@", surfaceDimensions:%zux%zu", surfaceWidth, surfaceHeight];
        }
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    
    // Attachments
    CFDictionaryRef attachments = CVBufferGetAttachments(pixelBuffer, kCVAttachmentMode_ShouldPropagate);
    if (attachments) {
        CFIndex count = CFDictionaryGetCount(attachments);
        [desc appendFormat:@", attachments:%ld", count];
        
        // Verificar atributos importantes
        NSDictionary *attachDict = (__bridge NSDictionary *)attachments;
        for (NSString *key in attachDict) {
            if ([key containsString:@"Camera"] ||
                [key containsString:@"Video"] ||
                [key containsString:@"Capture"] ||
                [key containsString:@"Source"]) {
                [desc appendFormat:@"\n    🔍 %@: %@", key, attachDict[key]];
            }
        }
    }
    
    [desc appendString:@">"];
    return desc;
}

// Obter informações sobre a IOSurface
static NSString *DescribeIOSurface(IOSurfaceRef surface) {
    if (!surface) {
        return @"<NULL>";
    }
    
    NSMutableString *desc = [NSMutableString string];
    [desc appendFormat:@"<IOSurface:%p", surface];
    
    // ID e dimensões
    uint32_t surfaceID = IOSurfaceGetID(surface);
    size_t width = IOSurfaceGetWidth(surface);
    size_t height = IOSurfaceGetHeight(surface);
    [desc appendFormat:@", ID:%u, dimensions:%zux%zu", surfaceID, width, height];
    
    // Formato de pixel
    OSType pixelFormat = IOSurfaceGetPixelFormat(surface);
    char formatStr[5] = {0};
    formatStr[0] = (pixelFormat >> 24) & 0xFF;
    formatStr[1] = (pixelFormat >> 16) & 0xFF;
    formatStr[2] = (pixelFormat >> 8) & 0xFF;
    formatStr[3] = pixelFormat & 0xFF;
    [desc appendFormat:@", format:'%s'", formatStr];
    
    // Outras propriedades importantes
    [desc appendFormat:@", bytesPerRow:%zu", IOSurfaceGetBytesPerRow(surface)];
    [desc appendFormat:@", bytesPerElement:%zu", IOSurfaceGetBytesPerElement(surface)];
    [desc appendFormat:@", elementWidth:%zu", IOSurfaceGetElementWidth(surface)];
    [desc appendFormat:@", elementHeight:%zu", IOSurfaceGetElementHeight(surface)];
    [desc appendFormat:@", planeCount:%zu", IOSurfaceGetPlaneCount(surface)];
    
    // Use seed para verificar modificações
    uint32_t seed = IOSurfaceGetSeed(surface);
    [desc appendFormat:@", seed:%u", seed];
    
    // Verificar propriedades adicionais
    NSDictionary *props = (__bridge_transfer NSDictionary *)IOSurfaceCopyAllValues(surface);
    if (props && props.count > 0) {
        [desc appendString:@"\n  Properties:"];
        for (NSString *key in props) {
            [desc appendFormat:@"\n    %@: %@", key, props[key]];
        }
    }
    
    [desc appendString:@">"];
    return desc;
}

// Capturar uma amostra do conteúdo do buffer para análise posterior
static void SaveBufferSample(CVPixelBufferRef pixelBuffer, NSString *context) {
    if (!pixelBuffer) return;
    
    LowLevelCameraInterceptor *interceptor = [LowLevelCameraInterceptor sharedInstance];
    if (!interceptor.captureBufferContent) return;
    
    bufferCaptureCounter++;
    
    // Criar um nome de arquivo único
    NSString *timestamp = [NSString stringWithFormat:@"%lld", (long long)([[NSDate date] timeIntervalSince1970] * 1000)];
    NSString *filename = [NSString stringWithFormat:@"buffer_%@_%llu_%@.png", context, bufferCaptureCounter, timestamp];
    NSString *filePath = [interceptor.bufferSamplesDirectory stringByAppendingPathComponent:filename];
    
    // Adicionar informações do aplicativo atual
    NSString *appInfo = GetCurrentAppInfo();
    filename = [NSString stringWithFormat:@"%@_%@", appInfo, filename];
    
    // Lock do buffer para acesso
    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    
    @try {
        // Criar uma imagem a partir do buffer
        size_t width = CVPixelBufferGetWidth(pixelBuffer);
        size_t height = CVPixelBufferGetHeight(pixelBuffer);
        OSType pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
        
        // Verificar se é um formato que podemos converter para UIImage
        if (pixelFormat == kCVPixelFormatType_32BGRA ||
            pixelFormat == kCVPixelFormatType_32RGBA ||
            pixelFormat == kCVPixelFormatType_24RGB ||
            pixelFormat == kCVPixelFormatType_24BGR) {
            
            CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
            uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(pixelBuffer);
            size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
            
            CGBitmapInfo bitmapInfo;
            if (pixelFormat == kCVPixelFormatType_32BGRA) {
                bitmapInfo = kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst;
            } else if (pixelFormat == kCVPixelFormatType_32RGBA) {
                bitmapInfo = kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast;
            } else if (pixelFormat == kCVPixelFormatType_24RGB) {
                bitmapInfo = kCGBitmapByteOrderDefault;
            } else { // 24BGR
                bitmapInfo = kCGBitmapByteOrder32Little;
            }
            
            CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8, bytesPerRow, colorSpace, bitmapInfo);
            
            if (context) {
                CGImageRef imageRef = CGBitmapContextCreateImage(context);
                if (imageRef) {
                    UIImage *image = [UIImage imageWithCGImage:imageRef];
                    NSData *pngData = UIImagePNGRepresentation(image);
                    [pngData writeToFile:filePath atomically:YES];
                    
                    LOG_INFO(@"📸 Salva amostra de buffer: %@", filename);
                    
                    // Salvar os metadados do buffer junto com a imagem
                    NSString *metadataPath = [filePath stringByReplacingOccurrencesOfString:@".png" withString:@"_metadata.json"];
                    NSMutableDictionary *metadata = [NSMutableDictionary dictionary];
                    metadata[@"timestamp"] = timestamp;
                    metadata[@"context"] = (__bridge id)context;
                    metadata[@"appInfo"] = appInfo;
                    metadata[@"width"] = @(width);
                    metadata[@"height"] = @(height);
                    metadata[@"pixelFormat"] = @(pixelFormat);
                    
                    char formatStr[5] = {0};
                    formatStr[0] = (pixelFormat >> 24) & 0xFF;
                    formatStr[1] = (pixelFormat >> 16) & 0xFF;
                    formatStr[2] = (pixelFormat >> 8) & 0xFF;
                    formatStr[3] = pixelFormat & 0xFF;
                    metadata[@"pixelFormatString"] = [NSString stringWithFormat:@"%s", formatStr];
                    
                    // Verificar IOSurface
                    IOSurfaceRef surface = CVPixelBufferGetIOSurface(pixelBuffer);
                    if (surface) {
                        uint32_t surfaceID = IOSurfaceGetID(surface);
                        metadata[@"hasIOSurface"] = @YES;
                        metadata[@"IOSurfaceID"] = @(surfaceID);
                    } else {
                        metadata[@"hasIOSurface"] = @NO;
                    }
                    
                    // Salvar metadados
                    NSError *jsonError;
                    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:metadata
                                                                       options:NSJSONWritingPrettyPrinted
                                                                         error:&jsonError];
                    if (jsonData && !jsonError) {
                        [jsonData writeToFile:metadataPath atomically:YES];
                    }
                    
                    CGImageRelease(imageRef);
                }
                CGContextRelease(context);
            }
            CGColorSpaceRelease(colorSpace);
        } else {
            // Para formatos não suportados, salvar descrição
            NSString *description = PixelBufferDetailedDescription(pixelBuffer);
            NSString *infoPath = [filePath stringByReplacingOccurrencesOfString:@".png" withString:@".txt"];
            [description writeToFile:infoPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
            
            LOG_INFO(@"📝 Salva descrição de buffer não suportado: %@", filename);
        }
    } @catch (NSException *exception) {
        LOG_ERROR(@"Erro ao salvar amostra de buffer: %@", exception);
    }
    
    // Unlock do buffer
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
}

// Analisar conteúdo de um buffer para identificar características
static void AnalyzePixelBufferContent(CVPixelBufferRef pixelBuffer, NSString *context) {
    if (!pixelBuffer) return;
    
    // Lock do buffer para acesso
    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    
    @try {
        size_t width = CVPixelBufferGetWidth(pixelBuffer);
        size_t height = CVPixelBufferGetHeight(pixelBuffer);
        OSType pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer);
        
        LOG_INFO(@"🔍 Análise de conteúdo de buffer %p (%@): %zux%zu, formato: %d",
                 pixelBuffer, context, width, height, pixelFormat);
        
        // Verificar se é um formato RGB que podemos analisar facilmente
        if (pixelFormat == kCVPixelFormatType_32BGRA ||
            pixelFormat == kCVPixelFormatType_32RGBA) {
            
            uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(pixelBuffer);
            
            // Analisar uma amostra de pixels (não todos para performance)
            int sampleStep = MAX(1, (int)(width * height / 1000)); // ~1000 amostras
            
            double sumBrightness = 0;
            //double sumVariance = 0;
            int edgeCount = 0;
            int sampleCount = 0;
            
            for (int y = 0; y < height; y += sampleStep) {
                for (int x = 0; x < width; x += sampleStep) {
                    size_t offset = y * bytesPerRow + x * 4;
                    
                    // Obter valores RGB (ordem depende do formato)
                    uint8_t b, g, r;
                    if (pixelFormat == kCVPixelFormatType_32BGRA) {
                        b = baseAddress[offset];
                        g = baseAddress[offset + 1];
                        r = baseAddress[offset + 2];
                        //a = baseAddress[offset + 3];
                    } else { // RGBA
                        r = baseAddress[offset];
                        g = baseAddress[offset + 1];
                        b = baseAddress[offset + 2];
                        //a = baseAddress[offset + 3];
                    }
                    
                    // Calcular brilho
                    double luma = 0.299 * r + 0.587 * g + 0.114 * b;
                    sumBrightness += luma;
                    
                    // Verificar vizinhos para detecção de bordas
                    if (x < width - sampleStep && y < height - sampleStep) {
                        size_t rightOffset = y * bytesPerRow + (x + sampleStep) * 4;
                        size_t bottomOffset = (y + sampleStep) * bytesPerRow + x * 4;
                        
                        // Simplificado para detecção de bordas
                        int diffRight = 0, diffBottom = 0;
                        
                        if (pixelFormat == kCVPixelFormatType_32BGRA) {
                            diffRight = abs((int)baseAddress[offset + 2] - (int)baseAddress[rightOffset + 2]);
                            diffBottom = abs((int)baseAddress[offset + 2] - (int)baseAddress[bottomOffset + 2]);
                        } else { // RGBA
                            diffRight = abs((int)baseAddress[offset] - (int)baseAddress[rightOffset]);
                            diffBottom = abs((int)baseAddress[offset] - (int)baseAddress[bottomOffset]);
                        }
                        
                        // Se a diferença for significativa, isso é uma borda
                        if (diffRight > 30 || diffBottom > 30) {
                            edgeCount++;
                        }
                    }
                    
                    sampleCount++;
                }
            }
            
            // Calcular estatísticas
            double avgBrightness = sumBrightness / sampleCount / 255.0; // Normalizado para [0,1]
            double edgeDensity = (double)edgeCount / sampleCount;
            
            LOG_INFO(@"  Estatísticas: Brilho médio=%.3f, Densidade de bordas=%.3f",
                     avgBrightness, edgeDensity);
            
            // Análise heurística
            BOOL possibleCameraInput = NO;
            NSMutableArray *reasons = [NSMutableArray array];
            
            // Heurística de brilho - câmeras tendem a ter distribuição mais natural
            if (avgBrightness > 0.1 && avgBrightness < 0.9) {
                [reasons addObject:@"distribuição de brilho natural"];
                possibleCameraInput = YES;
            }
            
            // Heurística de bordas - conteúdo da câmera geralmente tem bordas
            if (edgeDensity > 0.05 && edgeDensity < 0.4) {
                [reasons addObject:@"densidade de bordas típica de imagem real"];
                possibleCameraInput = YES;
            }
            
            if (possibleCameraInput) {
                LOG_INFO(@"  ⚠️ O conteúdo parece ser de uma câmera real: %@",
                         [reasons componentsJoinedByString:@", "]);
            } else {
                LOG_INFO(@"  O conteúdo não tem características típicas de câmera.");
            }
        }
    } @catch (NSException *exception) {
        LOG_ERROR(@"Erro ao analisar conteúdo do buffer: %@", exception);
    }
    
    // Unlock do buffer
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
}

// Capturar dados brutos de um buffer para hash e comparação
static NSData *CapturePixelBufferRawData(CVPixelBufferRef pixelBuffer) {
    if (!pixelBuffer) return nil;
    
    CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    
    NSData *result = nil;
    @try {
        void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
        size_t dataSize = CVPixelBufferGetDataSize(pixelBuffer);
        
        if (baseAddress && dataSize > 0) {
            // Para performance, capturar apenas uma amostra representativa
            size_t maxSampleSize = 256 * 1024; // 256KB max para evitar excesso de memória
            size_t sampleSize = MIN(dataSize, maxSampleSize);
            
            // Usar cada N bytes para garantir que temos uma boa amostra de todo o buffer
            if (dataSize > maxSampleSize) {
                size_t stride = dataSize / sampleSize;
                uint8_t *sampleBuffer = malloc(sampleSize);
                
                if (sampleBuffer) {
                    for (size_t i = 0; i < sampleSize; i++) {
                        size_t srcIdx = i * stride;
                        sampleBuffer[i] = ((uint8_t *)baseAddress)[srcIdx];
                    }
                    
                    result = [NSData dataWithBytes:sampleBuffer length:sampleSize];
                    free(sampleBuffer);
                }
            } else {
                result = [NSData dataWithBytes:baseAddress length:dataSize];
            }
        }
    } @catch (NSException *exception) {
        LOG_ERROR(@"Erro ao capturar dados brutos do buffer: %@", exception);
    }
    
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    return result;
}

// Calcular hash de dados para identificar modificações
static NSString *HashData(NSData *data) {
    if (!data) return nil;
    
    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    
    NSMutableString *hash = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) {
        [hash appendFormat:@"%02x", digest[i]];
    }
    
    return hash;
}

// Obter informações do aplicativo atual
static NSString *GetCurrentAppInfo() {
    NSBundle *mainBundle = [NSBundle mainBundle];
    NSString *bundleID = [mainBundle bundleIdentifier];
    NSString *appName = [mainBundle objectForInfoDictionaryKey:@"CFBundleDisplayName"] ?:
    [mainBundle objectForInfoDictionaryKey:@"CFBundleName"];
    
    return [NSString stringWithFormat:@"%@-%@", appName ?: @"Unknown", bundleID ?: @"Unknown"];
}

// Extrair informações do chamador a partir do stack trace
static NSString *GetCallerInfo() {
    NSArray *symbols = [NSThread callStackSymbols];
    
    // Pular os primeiros frames (própria função e hook)
    for (NSUInteger i = 2; i < symbols.count; i++) {
        NSString *symbol = symbols[i];
        
        // Procurar por um componente significativo
        if ([symbol containsString:@"Camera"] ||
            [symbol containsString:@"Video"] ||
            [symbol containsString:@"AVCapture"] ||
            [symbol containsString:@"ImageCapture"] ||
            [symbol containsString:@"Preview"]) {
            
            // Extrair apenas o componente relevante
            NSArray *components = [symbol componentsSeparatedByString:@" "];
            if (components.count >= 4) {
                return components[3]; // Geralmente contém o nome da função/método
            }
            return symbol;
        }
    }
    
    // Se não encontrou nada específico, retorna o primeiro frame não-hook
    if (symbols.count > 2) {
        NSString *symbol = symbols[2];
        NSArray *components = [symbol componentsSeparatedByString:@" "];
        if (components.count >= 4) {
            return components[3];
        }
        return symbol;
    }
    
    return @"Unknown Caller";
}

@end

#pragma mark - Private Frameworks Monitor

@implementation PrivateFrameworksMonitor

static NSMutableArray *_scannedFrameworks;
static NSMutableArray *_detectedClasses;

+ (void)initialize {
    if (self == [PrivateFrameworksMonitor class]) {
        _scannedFrameworks = [NSMutableArray array];
        _detectedClasses = [NSMutableArray array];
    }
}

+ (void)startMonitoring {
    LOG_INFO(@"Iniciando monitoramento de frameworks privados...");
    
    // Analisar frameworks relacionados à câmera
    [self scanFramework:@"/System/Library/PrivateFrameworks/CameraKit.framework"];
    [self scanFramework:@"/System/Library/PrivateFrameworks/CMCapture.framework"];
    [self scanFramework:@"/System/Library/PrivateFrameworks/MediaToolbox.framework"];
    [self scanFramework:@"/System/Library/Frameworks/AVFoundation.framework"];
    
    // Procurar em todas as classes carregadas
    [self scanAllLoadedClasses];
    
    LOG_INFO(@"Monitoramento de frameworks privados iniciado. Frameworks escaneados: %lu, Classes relacionadas à câmera: %lu",
             (unsigned long)_scannedFrameworks.count,
             (unsigned long)_detectedClasses.count);
}

+ (void)scanFramework:(NSString *)frameworkPath {
    // Verificar se o framework existe
    if (![[NSFileManager defaultManager] fileExistsAtPath:frameworkPath]) {
        LOG_INFO(@"Framework não encontrado: %@", frameworkPath);
        return;
    }
    
    LOG_INFO(@"Escaneando framework: %@", frameworkPath);
    [_scannedFrameworks addObject:frameworkPath];
    
    // Tentar carregar o framework
    void *handle = dlopen([frameworkPath UTF8String], RTLD_LAZY);
    if (!handle) {
        LOG_ERROR(@"Não foi possível carregar framework: %@, Erro: %s", frameworkPath, dlerror());
        return;
    }
    
    // Obter caminho do framework
    NSString *frameworkName = [frameworkPath lastPathComponent];
    NSString *frameworkBase = [frameworkName stringByReplacingOccurrencesOfString:@".framework" withString:@""];
    
    // Hook em classes específicas com base no framework
    if ([frameworkBase isEqualToString:@"CameraKit"]) {
        [self hookCameraKitClasses];
    } else if ([frameworkBase isEqualToString:@"CMCapture"]) {
        [self hookCMCaptureClasses];
    } else if ([frameworkBase isEqualToString:@"MediaToolbox"]) {
        [self hookMediaToolboxClasses];
    }
    
    dlclose(handle);
}

+ (void)scanAllLoadedClasses {
    LOG_INFO(@"Escaneando todas as classes carregadas por padrões relacionados à câmera...");
    
    // Palavras-chave para busca em nomes de classes
    NSArray *cameraKeywords = @[
        @"Camera", @"Capture", @"Video", @"Frame", @"Buffer",
        @"AVCapture", @"CMSample", @"Stream", @"Cam", @"Photo",
        @"Image", @"Preview", @"Record", @"Media", @"Pixel"
    ];
    
    // Obter todas as classes registradas
    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    
    // Filtrar classes potencialmente relacionadas à câmera
    for (unsigned int i = 0; i < classCount; i++) {
        NSString *className = NSStringFromClass(classes[i]);
        
        // Verificar cada palavra-chave
        for (NSString *keyword in cameraKeywords) {
            if ([className rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) {
                if (![_detectedClasses containsObject:className]) {
                    [_detectedClasses addObject:className];
                    
                    // Procurar métodos relacionados à câmera nesta classe
                    [self inspectCameraRelatedClass:classes[i]];
                }
                break;
            }
        }
    }
    
    free(classes);
}

+ (void)inspectCameraRelatedClass:(Class)cls {
    NSString *className = NSStringFromClass(cls);
    
    // Verificar métodos desta classe
    unsigned int methodCount = 0;
    Method *methods = class_copyMethodList(cls, &methodCount);
    
    NSMutableString *interestingMethods = [NSMutableString string];
    BOOL hasInterestingMethods = NO;
    
    // Palavras-chave para métodos de interesse
    NSArray *methodKeywords = @[
        @"camera", @"capture", @"video", @"frame", @"buffer",
        @"sampleBuffer", @"image", @"preview", @"record"
    ];
    
    for (unsigned int i = 0; i < methodCount; i++) {
        Method method = methods[i];
        SEL selector = method_getName(method);
        NSString *methodName = NSStringFromSelector(selector);
        
        // Verificar cada palavra-chave
        for (NSString *keyword in methodKeywords) {
            if ([methodName rangeOfString:keyword options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [interestingMethods appendFormat:@"\n    - %@", methodName];
                hasInterestingMethods = YES;
                break;
            }
        }
    }
    
    free(methods);
    
    if (hasInterestingMethods) {
        LOG_INFO(@"Classe relacionada à câmera: %@%@", className, interestingMethods);
        
        // Adicionar hooks em métodos cruciais
        [self addHooksForCameraRelatedClass:cls];
    }
}

+ (void)addHooksForCameraRelatedClass:(Class)cls {
    NSString *className = NSStringFromClass(cls);
    
    // Lista de seletores que seriam cruciais para interceptar
    NSArray *criticalSelectors = @[
        @"captureOutput:didOutputSampleBuffer:fromConnection:",
        @"startCapture",
        @"stopCapture",
        @"captureStillImage",
        @"processBuffer:",
        @"setupCaptureSession",
        @"startCamera",
        @"stopCamera",
        @"setupCamera",
        @"captureFrame",
        @"renderFrame:",
        @"renderBuffer:",
        @"processVideoBuffer:",
        @"recordVideo",
        @"startVideoRecording",
        @"stopVideoRecording",
        @"takePicture"
    ];
    
    // Verificar e adicionar hooks para cada seletor crítico
    for (NSString *selectorName in criticalSelectors) {
        SEL selector = NSSelectorFromString(selectorName);
        Method method = class_getInstanceMethod(cls, selector);
        
        if (method) {
            LOG_INFO(@"🎯 Encontrado método crítico: %@ em %@", selectorName, className);
            
            // Criar um identificador único para este método
            //NSString *hookIdentifier = [NSString stringWithFormat:@"%@_%@", className, selectorName];
            
            // Preparar hook dinamicamente
            // Nota: Este é um código conceitual. A implementação real do hook
            // requer mais trabalho para ser dinâmica para qualquer método
            
            // Exemplo: Hook para processBuffer:
            if ([selectorName isEqualToString:@"processBuffer:"]) {
                [self hookProcessBufferMethod:cls selector:selector];
            }
            // Adicione mais casos específicos conforme necessário
        }
    }
}

// Exemplo de hook específico para método processBuffer:
+ (void)hookProcessBufferMethod:(Class)cls selector:(SEL)selector {
    // Esta implementação é conceitual e simplificada
    // Uma implementação real exigiria mais cuidados com tipos e argumentos
    
    Method originalMethod = class_getInstanceMethod(cls, selector);
    
    // Cria uma implementação de substituição
    IMP replacement = imp_implementationWithBlock(^(id self, id buffer) {
        LOG_INFO(@"⚡️ %@ processBuffer: chamado com %@", [self class], buffer);
        
        // Registrar detalhes do buffer
        if ([buffer isKindOfClass:[NSObject class]]) {
            LOG_INFO(@"  Buffer tipo: %@", [buffer class]);
        }
        
        // Capturar stack trace
        NSString *backtrace = [NSThread callStackSymbols].description;
        LOG_DEBUG(@"  Stack: %@", backtrace);
        
        // Chamar o método original
        typedef id (*OriginalImp)(id, SEL, id);
        OriginalImp originalImp = (OriginalImp)method_getImplementation(originalMethod);
        
        // Executar o método original e obter o resultado
        id result = originalImp(self, selector, buffer);
        
        LOG_INFO(@"  processBuffer: concluído, resultado: %@", result);
        return result;
    });
    
    // Substitui a implementação
    method_setImplementation(originalMethod, replacement);
    LOG_INFO(@"Hook instalado para %@ processBuffer:", NSStringFromClass(cls));
}

// Hooks específicos para CameraKit
+ (void)hookCameraKitClasses {
    LOG_INFO(@"Instalando hooks específicos para CameraKit...");
    
    // Classes comuns do CameraKit
    NSArray *cameraKitClasses = @[
        @"CAMCaptureController",
        @"CAMCaptureSession",
        @"CAMPreviewView",
        @"CAMViewfinderViewController",
        @"CKCamera",
        @"CKCameraDevice"
    ];
    
    for (NSString *className in cameraKitClasses) {
        Class cls = NSClassFromString(className);
        if (cls) {
            LOG_INFO(@"Encontrada classe CameraKit: %@", className);
            [_detectedClasses addObject:className];
            
            // Inspecionar métodos da classe
            [self inspectCameraRelatedClass:cls];
        }
    }
}

// Hooks específicos para CMCapture
+ (void)hookCMCaptureClasses {
    LOG_INFO(@"Instalando hooks específicos para CMCapture...");
    
    // Classes comuns do CMCapture
    NSArray *cmCaptureClasses = @[
        @"CMCapture",
        @"CMCaptureSession",
        @"CMCaptureDevice",
        @"CMVideoCaptureDevice",
        @"CMCaptureConnection"
    ];
    
    for (NSString *className in cmCaptureClasses) {
        Class cls = NSClassFromString(className);
        if (cls) {
            LOG_INFO(@"Encontrada classe CMCapture: %@", className);
            [_detectedClasses addObject:className];
            
            // Inspecionar métodos da classe
            [self inspectCameraRelatedClass:cls];
        }
    }
}

// Hooks específicos para MediaToolbox
+ (void)hookMediaToolboxClasses {
    LOG_INFO(@"Instalando hooks específicos para MediaToolbox...");
    
    // Classes e funções do MediaToolbox são em sua maioria C APIs
    // Aqui precisaríamos usar fishhook ou técnicas similares
    // Este é um exemplo simplificado
    
    // Símbolos comuns do MediaToolbox
    NSArray *mediaToolboxSymbols = @[
        @"MTRegisterVideoCaptureDevice",
        @"MTCaptureCreateSession",
        @"MTCaptureSessionSetDevice",
        @"MTVideoProcessCreate"
    ];
    
    for (NSString *symbolName in mediaToolboxSymbols) {
        void *symbol = dlsym(RTLD_DEFAULT, [symbolName UTF8String]);
        if (symbol) {
            LOG_INFO(@"Encontrado símbolo MediaToolbox: %@", symbolName);
            // Para hook real, usaríamos MSHookFunction aqui
        }
    }
}

+ (NSArray<NSString *> *)scannedFrameworks {
    return [_scannedFrameworks copy];
}

+ (NSArray<NSString *> *)detectedCameraRelatedClasses {
    return [_detectedClasses copy];
}

@end
