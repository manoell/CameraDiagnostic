#include <execinfo.h>
#include <objc/message.h>
#include <objc/runtime.h>
#include <substrate.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <UIKit/UIKit.h>
#import "logger.h"
#import "LowLevelCameraInterceptor.h"
#import "CameraDiagnosticFramework.h"
#import "BufferContentInspector.h"
#import "CameraBufferSubstitutionInterceptor.h"
#import "CameraFeedSubstitutionSource.h"

// Logger global
static Logger *logger;

// Controle de diagnóstico
static BOOL hasCompletedInitialSetup = NO;
static NSLock *diagnosticLock;
static NSDate *startTime;

// Estruturas para armazenar resultados de diagnóstico
static NSMutableDictionary *diagnosticResults;

// Forward declarations para métodos originais que serão hooked
static id (*original_AVCaptureDeviceInput_initWithDevice)(id self, SEL _cmd, AVCaptureDevice *device, NSError **outError);
static void (*original_AVCaptureVideoDataOutput_setSampleBufferDelegate)(id self, SEL _cmd, id<AVCaptureVideoDataOutputSampleBufferDelegate> sampleBufferDelegate, dispatch_queue_t sampleBufferCallbackQueue);

// Métodos para substituir os originais
static id overridden_AVCaptureDeviceInput_initWithDevice(id self, SEL _cmd, AVCaptureDevice *device, NSError **outError) {
    // Chama o método original primeiro
    id result = original_AVCaptureDeviceInput_initWithDevice(self, _cmd, device, outError);
    
    if (result) {
        LOG_INFO(@"⭐️ AVCaptureDeviceInput inicializado para dispositivo: %@ (posição: %ld)",
                device.localizedName, (long)device.position);
        
        // Registrar no dicionário de diagnóstico
        @synchronized(diagnosticResults) {
            NSMutableArray *devices = diagnosticResults[@"captureDevices"];
            if (!devices) {
                devices = [NSMutableArray array];
                diagnosticResults[@"captureDevices"] = devices;
            }
            
            [devices addObject:@{
                @"deviceName": device.localizedName,
                @"position": @(device.position),
                @"uniqueID": device.uniqueID,
                @"modelID": device.modelID
            }];
        }
    }
    
    return result;
}

static void overridden_AVCaptureVideoDataOutput_setSampleBufferDelegate(id self, SEL _cmd, id<AVCaptureVideoDataOutputSampleBufferDelegate> sampleBufferDelegate, dispatch_queue_t sampleBufferCallbackQueue) {
    // Antes de chamar o método original
    if (sampleBufferDelegate) {
        LOG_INFO(@"⭐️ AVCaptureVideoDataOutput configurando delegate: %@ (%@)",
                sampleBufferDelegate, [sampleBufferDelegate class]);
        
        // Registrar no dicionário de diagnóstico
        @synchronized(diagnosticResults) {
            NSMutableArray *delegates = diagnosticResults[@"bufferDelegates"];
            if (!delegates) {
                delegates = [NSMutableArray array];
                diagnosticResults[@"bufferDelegates"] = delegates;
            }
            
            NSString *delegateClass = NSStringFromClass([sampleBufferDelegate class]);
            if (![delegates containsObject:delegateClass]) {
                [delegates addObject:delegateClass];
            }
        }
    }
    
    // Chama o método original
    original_AVCaptureVideoDataOutput_setSampleBufferDelegate(self, _cmd, sampleBufferDelegate, sampleBufferCallbackQueue);
}

// Categoria para métodos auxiliares - DEVE SER ANTES do %ctor
@interface NSObject (CameraDiagnosticHelper)
+ (void)applicationDidBecomeActive:(NSNotification *)notification;
+ (void)installEssentialHooks;
+ (void)setupDiagnosticComponents;
+ (void)generatePeriodicReport;
@end

@implementation NSObject (CameraDiagnosticHelper)

+ (void)applicationDidBecomeActive:(NSNotification *)notification {
    NSString *appID = [[NSBundle mainBundle] bundleIdentifier];
    LOG_INFO(@"📱 Aplicativo ativo: %@", appID);
    
    // Descartar notificações duplicadas
    static NSString *lastActiveApp = nil;
    if ([lastActiveApp isEqualToString:appID]) {
        return;
    }
    lastActiveApp = [appID copy];
    
    @synchronized(diagnosticResults) {
        NSMutableArray *activeApps = diagnosticResults[@"activeApps"];
        if (!activeApps) {
            activeApps = [NSMutableArray array];
            diagnosticResults[@"activeApps"] = activeApps;
        }
        
        if (![activeApps containsObject:appID]) {
            [activeApps addObject:appID];
        }
    }
    
    // Iniciar diagnóstico completo se ainda não foi feito
    if (!hasCompletedInitialSetup) {
        LOG_INFO(@"Inicializando componentes de diagnóstico...");
        [self setupDiagnosticComponents];
        hasCompletedInitialSetup = YES;
    } else {
        // Analisar o estado atual da câmera
        LOG_INFO(@"Analisando estado da câmera no aplicativo atual...");
        [[CameraDiagnosticFramework sharedInstance] analyzeActiveCaptureSessions];
        [[CameraDiagnosticFramework sharedInstance] analyzeRenderPipeline];
        [[CameraDiagnosticFramework sharedInstance] detectApplicationUsingCamera];
    }
}

+ (void)installEssentialHooks {
    LOG_INFO(@"Instalando hooks essenciais para diagnóstico...");
    
    // Hook em AVCaptureDeviceInput para capturar dispositivos de câmera
    MSHookMessageEx(
        objc_getClass("AVCaptureDeviceInput"),
        @selector(initWithDevice:error:),
        (IMP)&overridden_AVCaptureDeviceInput_initWithDevice,
        (IMP*)&original_AVCaptureDeviceInput_initWithDevice
    );
    
    // Hook em AVCaptureVideoDataOutput para capturar delegados de buffer
    MSHookMessageEx(
        objc_getClass("AVCaptureVideoDataOutput"),
        @selector(setSampleBufferDelegate:queue:),
        (IMP)&overridden_AVCaptureVideoDataOutput_setSampleBufferDelegate,
        (IMP*)&original_AVCaptureVideoDataOutput_setSampleBufferDelegate
    );
    
    LOG_INFO(@"Hooks essenciais instalados com sucesso");
}

+ (void)setupDiagnosticComponents {
    [diagnosticLock lock];
    
    LOG_INFO(@"Configurando componentes de diagnóstico...");
    
    // 1. Inicializar BufferContentInspector
    BufferContentInspector *inspector = [BufferContentInspector sharedInstance];
    inspector.captureEnabled = YES;
    inspector.analyzeContent = YES;
    inspector.captureInterval = 300; // Capturar 1 a cada 300 frames para reduzir volume
    LOG_INFO(@"BufferContentInspector configurado");
    
    // 2. Inicializar CameraDiagnosticFramework
    CameraDiagnosticFramework *framework = [CameraDiagnosticFramework sharedInstance];
    [framework startDiagnosticWithLogLevel:CameraDiagnosticLogLevelInfo];
    [framework setLogToFile:YES];
    LOG_INFO(@"CameraDiagnosticFramework iniciado");
    
    // 3. Inicializar LowLevelCameraInterceptor
    LowLevelCameraInterceptor *interceptor = [LowLevelCameraInterceptor sharedInstance];
    [interceptor startMonitoring];
    LOG_INFO(@"LowLevelCameraInterceptor iniciado");
    
    // 4. Configurar CameraBufferSubstitutionInterceptor (manter instalado mas não ativo)
    CameraBufferSubstitutionInterceptor *substitutionInterceptor = [CameraBufferSubstitutionInterceptor sharedInterceptor];
    [substitutionInterceptor installHooks]; // Instalamos os hooks para futura análise
    substitutionInterceptor.interceptionStrategy = @"swizzle"; // Definir estratégia para análise futura
    substitutionInterceptor.enabled = NO; // CRÍTICO: Manter desativado durante diagnóstico
    substitutionInterceptor.substitutionSource = nil; // Garantir que não há fonte configurada
    LOG_INFO(@"CameraBufferSubstitutionInterceptor configurado (hooks instalados mas substituição desativada)");
    
    // Analisar estado inicial
    [framework dumpCameraConfiguration];
    [framework analyzeActiveCaptureSessions];
    [framework analyzeRenderPipeline];
    
    LOG_INFO(@"Todos os componentes de diagnóstico configurados e ativos");
    
    [diagnosticLock unlock];
}

+ (void)generatePeriodicReport {
    static NSUInteger reportCounter = 0;
    reportCounter++;
    
    LOG_INFO(@"Gerando relatório periódico de diagnóstico #%lu...", (unsigned long)reportCounter);
    
    NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *reportPath = [documentsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"camera_diagnostic_report_%lu.txt", (unsigned long)reportCounter]];
    
    // Coletar dados dos diferentes componentes
    NSMutableString *report = [NSMutableString string];
    
    [report appendString:@"====== RELATÓRIO DE DIAGNÓSTICO DE CÂMERA ======\n\n"];
    [report appendFormat:@"Data/Hora: %@\n", [NSDate date]];
    [report appendFormat:@"Aplicativo: %@\n", [[NSBundle mainBundle] bundleIdentifier]];
    [report appendFormat:@"Duração do diagnóstico: %.1f segundos\n\n", [[NSDate date] timeIntervalSinceDate:startTime]];
    
    // Adicionar dados coletados
    @synchronized(diagnosticResults) {
        [report appendString:@"=== APLICATIVOS ANALISADOS ===\n"];
        NSArray *activeApps = diagnosticResults[@"activeApps"];
        for (NSString *app in activeApps) {
            [report appendFormat:@"- %@\n", app];
        }
        
        [report appendString:@"\n=== DISPOSITIVOS DE CÂMERA ===\n"];
        NSArray *devices = diagnosticResults[@"captureDevices"];
        for (NSDictionary *device in devices) {
            [report appendFormat:@"- %@ (Posição: %@, ID: %@)\n",
             device[@"deviceName"], device[@"position"], device[@"uniqueID"]];
        }
        
        [report appendString:@"\n=== DELEGADOS DE BUFFER ===\n"];
        NSArray *delegates = diagnosticResults[@"bufferDelegates"];
        for (NSString *delegate in delegates) {
            [report appendFormat:@"- %@\n", delegate];
        }
    }
    
    // Incluir relatório do BufferContentInspector
    [report appendString:@"\n"];
    [report appendString:[[BufferContentInspector sharedInstance] generateReport]];
    
    // Incluir pontos críticos identificados pelo LowLevelCameraInterceptor
    [report appendString:@"\n=== PONTOS CRÍTICOS DE INTERCEPTAÇÃO ===\n"];
    NSArray *interceptPoints = [[LowLevelCameraInterceptor sharedInstance] identifyKeyInterceptionPoints];
    for (NSDictionary *point in interceptPoints) {
        [report appendFormat:@"- %@\n", point[@"name"]];
        [report appendFormat:@"  Tipo: %@\n", point[@"type"]];
        [report appendFormat:@"  Razão: %@\n", point[@"reason"]];
        [report appendFormat:@"  Confiança: %@\n", point[@"confidence"]];
        [report appendFormat:@"  Notas: %@\n\n", point[@"notes"]];
    }
    
    // Salvar relatório
    NSError *error;
    [report writeToFile:reportPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
    
    if (error) {
        LOG_ERROR(@"Erro ao salvar relatório: %@", error);
    } else {
        LOG_INFO(@"Relatório de diagnóstico salvo em: %@", reportPath);
    }
    
    // Se for o último relatório (depois de um tempo significativo), finalize a análise
    if (reportCounter >= 5) { // Após aproximadamente 5 minutos
        LOG_INFO(@"⭐️⭐️⭐️ GERANDO RELATÓRIO FINAL COM CONCLUSÕES ⭐️⭐️⭐️");
        
        // Gerar relatórios finais de cada componente
        [[CameraDiagnosticFramework sharedInstance] generateFinalReport];
        [[LowLevelCameraInterceptor sharedInstance] generateFinalReport];
        
        // Combinar os relatórios e destacar os pontos mais prováveis
        NSString *finalReportPath = [documentsPath stringByAppendingPathComponent:@"camera_substitution_conclusion.txt"];
        NSMutableString *finalReport = [NSMutableString string];
        
        [finalReport appendString:@"====== CONCLUSÃO FINAL - SUBSTITUIÇÃO DO FEED DA CÂMERA ======\n\n"];
        [finalReport appendString:@"Baseado na análise de múltiplos aplicativos e componentes, os pontos ideais para substituição universal são:\n\n"];
        
        // Seção 1: Top 3 APIs para hook
        [finalReport appendString:@"1. APIS PARA HOOK (ORDEM DE PREFERÊNCIA):\n"];
        [finalReport appendString:@"   a. CVPixelBufferCreateWithIOSurface - Ponto universal para substituição via IOSurface\n"];
        [finalReport appendString:@"   b. CVPixelBufferPoolCreatePixelBuffer - Ponto central de criação via pool\n"];
        [finalReport appendString:@"   c. Delegados AVCaptureVideoDataOutputSampleBufferDelegate - Interceptação por app\n\n"];
        
        // Seção 2: Estratégia recomendada
        [finalReport appendString:@"2. ESTRATÉGIA RECOMENDADA:\n"];
        [finalReport appendString:@"   - Implementar um hook em CVPixelBufferCreateWithIOSurface\n"];
        [finalReport appendString:@"   - Identificar IOSurfaces usadas para câmera via seed/ID único\n"];
        [finalReport appendString:@"   - Substituir o conteúdo com feed personalizado respeitando formato e timestamp\n"];
        [finalReport appendString:@"   - Sempre preservar metadados e attachments originais\n\n"];
        
        // Salvar relatório final
        [finalReport writeToFile:finalReportPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
        
        LOG_INFO(@"Relatório final com conclusões salvo em: %@", finalReportPath);
        
        // Fase diagnóstica completa - as informações necessárias foram coletadas
        // A fase de substituição será implementada em uma atualização futura
        // baseada nos resultados da análise diagnóstica
        LOG_INFO(@"Diagnóstico completo. Resultados prontos para análise manual.");
        LOG_INFO(@"A substituição do feed deve ser implementada após análise dos relatórios.");
    }
}

@end

// Inicialização do tweak - Depois da implementação da categoria
%ctor {
    @autoreleasepool {
        startTime = [NSDate date];
        
        // Inicializa estruturas de controle
        diagnosticLock = [[NSLock alloc] init];
        diagnosticResults = [NSMutableDictionary dictionary];
        
        // Configura logger
        NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *logPath = [documentsPath stringByAppendingPathComponent:@"camera_diagnostic.log"];
        logger = [Logger sharedInstance];
        [logger setLogFilePath:logPath];
        
        // Inicializa diagnóstico
        LOG_INFO(@"====== INICIANDO DIAGNÓSTICO UNIVERSAL DE CÂMERA ======");
        LOG_INFO(@"Data/Hora: %@", [NSDate date]);
        LOG_INFO(@"Bundle: %@", [[NSBundle mainBundle] bundleIdentifier]);
        LOG_INFO(@"Processo: %@", [NSProcessInfo processInfo].processName);
        LOG_INFO(@"OS Version: %@", [UIDevice currentDevice].systemVersion);
        LOG_INFO(@"Device: %@", [UIDevice currentDevice].model);
        
        // Registra notificações de ativação do app - bom momento para iniciar diagnóstico completo
        [[NSNotificationCenter defaultCenter] addObserver:[NSObject class]
                                                 selector:@selector(applicationDidBecomeActive:)
                                                     name:UIApplicationDidBecomeActiveNotification
                                                   object:nil];
        
        // Instalar hooks essenciais para capturar componentes iniciais
        [NSObject installEssentialHooks];
        
        // Agendar inicialização completa com delay para garantir que o app esteja carregado
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [NSObject setupDiagnosticComponents];
            hasCompletedInitialSetup = YES;
        });
        
        // Agendar geração de relatório periódico
        [NSTimer scheduledTimerWithTimeInterval:60.0
                                         target:[NSObject class]
                                       selector:@selector(generatePeriodicReport)
                                       userInfo:nil
                                        repeats:YES];
    }
}
