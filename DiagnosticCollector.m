#import "DiagnosticCollector.h"
#import "logger.h"

@interface DiagnosticCollector ()
// Propriedades privadas
@property (nonatomic, strong) NSMutableDictionary *sessionInfoDict;
@property (nonatomic, strong) NSMutableArray *diagnosticEntries;
@property (nonatomic, strong) NSFileManager *fileManager;
@property (nonatomic, strong) dispatch_queue_t saveQueue;
@property (nonatomic, strong) NSMutableSet *appCategories;
@property (nonatomic, assign) NSUInteger entryCounter;
@end

@implementation DiagnosticCollector

// Singleton
+ (instancetype)sharedInstance {
    static DiagnosticCollector *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        _sessionInfoDict = [NSMutableDictionary dictionary];
        _diagnosticEntries = [NSMutableArray array];
        _fileManager = [NSFileManager defaultManager];
        _saveQueue = dispatch_queue_create("com.diagnostic.saveQueue", DISPATCH_QUEUE_SERIAL);
        _appCategories = [NSMutableSet set];
        _entryCounter = 0;
        
        // Registrar observador para notificação de término do aplicativo
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(saveAllDiagnostics)
                                                     name:UIApplicationWillTerminateNotification
                                                   object:nil];
        
        // Criar diretório para diagnósticos se não existir
        [self createDiagnosticsDirectory];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self saveAllDiagnostics];
}

#pragma mark - Diretório para diagnósticos

- (NSString *)diagnosticsDirectoryPath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths firstObject];
    NSString *diagnosticsDirectory = [documentsDirectory stringByAppendingPathComponent:@"CameraDiagnostics"];
    return diagnosticsDirectory;
}

- (void)createDiagnosticsDirectory {
    NSString *diagnosticsDirectory = [self diagnosticsDirectoryPath];
    NSError *error = nil;
    
    if (![self.fileManager fileExistsAtPath:diagnosticsDirectory]) {
        [self.fileManager createDirectoryAtPath:diagnosticsDirectory
                    withIntermediateDirectories:YES
                                     attributes:nil
                                          error:&error];
        
        if (error) {
            writeLog(@"[DIAGNOSTIC] Erro ao criar diretório para diagnósticos: %@", [error localizedDescription]);
        } else {
            writeLog(@"[DIAGNOSTIC] Diretório para diagnósticos criado: %@", diagnosticsDirectory);
        }
    }
}

#pragma mark - Configuração de sessão

- (void)setSessionInfo:(NSDictionary *)sessionInfo {
    if (sessionInfo) {
        [self.sessionInfoDict addEntriesFromDictionary:sessionInfo];
        writeLog(@"[DIAGNOSTIC] Informações de sessão configuradas: %@", sessionInfo);
    }
}

- (void)addAppCategory:(NSString *)category {
    if (category) {
        [self.appCategories addObject:category];
        self.sessionInfoDict[@"appCategories"] = [self.appCategories allObjects];
        writeLog(@"[DIAGNOSTIC] Categoria adicionada: %@", category);
    }
}

#pragma mark - Registro de diagnósticos

// Método genérico para adicionar uma entrada de diagnóstico
- (void)addDiagnosticEntry:(NSString *)type withInfo:(NSDictionary *)info {
    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
    
    // Informações básicas
    entry[@"type"] = type;
    entry[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
    entry[@"entryId"] = @(++self.entryCounter);
    
    // Adicionar informações específicas
    if (info) {
        entry[@"info"] = info;
    }
    
    // Thread-safety para adicionar à lista
    @synchronized (self.diagnosticEntries) {
        [self.diagnosticEntries addObject:entry];
    }
    
    // Salvar automaticamente após acumular certo número de entradas
    if (self.diagnosticEntries.count % 100 == 0) {
        [self saveAllDiagnostics];
    }
}

#pragma mark - Métodos para registro de componentes específicos

- (void)saveDelegateInfo:(NSDictionary *)delegateInfo {
    [self addDiagnosticEntry:@"delegateInfo" withInfo:delegateInfo];
}

- (void)recordSessionStart:(NSDictionary *)sessionDetails {
    [self addDiagnosticEntry:@"sessionStart" withInfo:sessionDetails];
}

- (void)recordSessionStop:(NSDictionary *)sessionDetails {
    [self addDiagnosticEntry:@"sessionStop" withInfo:sessionDetails];
}

- (void)recordSessionInfo:(NSDictionary *)info {
    [self addDiagnosticEntry:@"sessionInfo" withInfo:info];
}

- (void)recordInputAdded:(NSDictionary *)inputInfo {
    [self addDiagnosticEntry:@"inputAdded" withInfo:inputInfo];
}

- (void)recordOutputAdded:(NSDictionary *)outputInfo {
    [self addDiagnosticEntry:@"outputAdded" withInfo:outputInfo];
}

- (void)recordVideoOrientation:(NSDictionary *)orientationInfo {
    [self addDiagnosticEntry:@"videoOrientation" withInfo:orientationInfo];
}

- (void)recordConnectionProperty:(NSDictionary *)propertyInfo {
    [self addDiagnosticEntry:@"connectionProperty" withInfo:propertyInfo];
}

- (void)recordCameraFormat:(NSDictionary *)formatInfo {
    [self addDiagnosticEntry:@"cameraFormat" withInfo:formatInfo];
}

- (void)recordCameraSwitch:(BOOL)isFrontCamera withResolution:(CGSize)resolution {
    [self addDiagnosticEntry:@"cameraSwitch" withInfo:@{
        @"isFrontCamera": @(isFrontCamera),
        @"width": @(resolution.width),
        @"height": @(resolution.height)
    }];
}

- (void)recordVideoOutputDelegate:(NSDictionary *)delegateInfo {
    [self addDiagnosticEntry:@"videoOutputDelegate" withInfo:delegateInfo];
}

- (void)recordAudioOutputDelegate:(NSDictionary *)delegateInfo {
    [self addDiagnosticEntry:@"audioOutputDelegate" withInfo:delegateInfo];
}

- (void)recordVideoSettings:(NSDictionary *)settings {
    [self addDiagnosticEntry:@"videoSettings" withInfo:settings];
}

- (void)recordPhotoCapture:(NSDictionary *)captureInfo {
    [self addDiagnosticEntry:@"photoCapture" withInfo:captureInfo];
}

- (void)recordSampleBufferInfo:(NSDictionary *)bufferInfo {
    [self addDiagnosticEntry:@"sampleBufferInfo" withInfo:bufferInfo];
}

- (void)recordDisplayLayerInfo:(NSDictionary *)displayInfo {
    [self addDiagnosticEntry:@"displayLayerInfo" withInfo:displayInfo];
}

- (void)recordPhotoImageInfo:(NSDictionary *)imageInfo {
    [self addDiagnosticEntry:@"photoImageInfo" withInfo:imageInfo];
}

- (void)recordPhotoMetadata:(NSDictionary *)metadata {
    [self addDiagnosticEntry:@"photoMetadata" withInfo:metadata];
}

- (void)recordDeviceOperation:(NSDictionary *)operationInfo {
    [self addDiagnosticEntry:@"deviceOperation" withInfo:operationInfo];
}

- (void)recordDeviceFormatChange:(NSDictionary *)formatInfo {
    [self addDiagnosticEntry:@"deviceFormatChange" withInfo:formatInfo];
}

- (void)recordUIImageCreation:(NSDictionary *)imageInfo {
    [self addDiagnosticEntry:@"uiImageCreation" withInfo:imageInfo];
}

- (void)recordUIImageViewInfo:(NSDictionary *)viewInfo {
    [self addDiagnosticEntry:@"uiImageViewInfo" withInfo:viewInfo];
}

- (void)recordImagePickerInfo:(NSDictionary *)pickerInfo {
    [self addDiagnosticEntry:@"imagePickerInfo" withInfo:pickerInfo];
}

- (void)recordPreviewLayerCreation:(NSDictionary *)layerInfo {
    [self addDiagnosticEntry:@"previewLayerCreation" withInfo:layerInfo];
}

- (void)recordPreviewLayerOperation:(NSDictionary *)operationInfo {
    [self addDiagnosticEntry:@"previewLayerOperation" withInfo:operationInfo];
}

- (void)recordLayerOperation:(NSDictionary *)operationInfo {
    [self addDiagnosticEntry:@"layerOperation" withInfo:operationInfo];
}

- (void)recordMetadataObjects:(NSDictionary *)metadataInfo {
    [self addDiagnosticEntry:@"metadataObjects" withInfo:metadataInfo];
}

- (void)recordDroppedFrame:(NSDictionary *)frameInfo {
    [self addDiagnosticEntry:@"droppedFrame" withInfo:frameInfo];
}

#pragma mark - Métodos de acesso aos dados

- (NSDictionary *)getCurrentSessionInfo {
    return [self.sessionInfoDict copy];
}

- (NSArray *)getAllDiagnosticEntries {
    @synchronized (self.diagnosticEntries) {
        return [self.diagnosticEntries copy];
    }
}

- (NSString *)getSessionID {
    return self.sessionInfoDict[@"sessionID"];
}

#pragma mark - Métodos de salvamento

- (void)saveAllDiagnostics {
    // Executar em fila separada para não bloquear a UI
    dispatch_async(self.saveQueue, ^{
        NSString *sessionID = [self getSessionID];
        if (!sessionID) {
            writeLog(@"[DIAGNOSTIC] Erro: SessionID ausente, não é possível salvar diagnósticos");
            return;
        }
        
        NSString *processName = self.sessionInfoDict[@"processName"] ?: @"unknown";
        
        // Criar dicionário completo com todas as informações
        NSMutableDictionary *diagnosticData = [NSMutableDictionary dictionary];
        
        // Adicionar informações da sessão
        diagnosticData[@"sessionInfo"] = [self.sessionInfoDict copy];
        
        // Adicionar timestamp de salvamento
        diagnosticData[@"saveTimestamp"] = @([[NSDate date] timeIntervalSince1970]);
        
        // Sincronizar acesso ao array de entradas
        NSArray *entriesCopy;
        @synchronized (self.diagnosticEntries) {
            entriesCopy = [self.diagnosticEntries copy];
            [self.diagnosticEntries removeAllObjects]; // Limpar após copiar
        }
        
        // Adicionar entradas ao diagnóstico
        diagnosticData[@"entries"] = entriesCopy;
        
        // Contar entradas por tipo para resumo
        NSMutableDictionary *entryCounts = [NSMutableDictionary dictionary];
        for (NSDictionary *entry in entriesCopy) {
            NSString *type = entry[@"type"];
            if (type) {
                NSNumber *count = entryCounts[type];
                entryCounts[type] = @(count.integerValue + 1);
            }
        }
        diagnosticData[@"entryCounts"] = entryCounts;
        
        // Converter para JSON
        NSError *error = nil;
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:diagnosticData
                                                          options:NSJSONWritingPrettyPrinted
                                                            error:&error];
        
        if (error || !jsonData) {
            writeLog(@"[DIAGNOSTIC] Erro ao converter diagnóstico para JSON: %@", [error localizedDescription]);
            return;
        }
        
        // Criar nome de arquivo com timestamp
        NSString *timestamp = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970]];
        NSString *fileName = [NSString stringWithFormat:@"%@_%@_%@.json", processName, sessionID, timestamp];
        NSString *filePath = [[self diagnosticsDirectoryPath] stringByAppendingPathComponent:fileName];
        
        // Salvar para o arquivo
        BOOL success = [jsonData writeToFile:filePath atomically:YES];
        
        if (success) {
            writeLog(@"[DIAGNOSTIC] Diagnóstico salvo com sucesso: %@ (%lu entradas)",
                   fileName, (unsigned long)entriesCopy.count);
        } else {
            writeLog(@"[DIAGNOSTIC] Erro ao salvar diagnóstico para arquivo: %@", filePath);
        }
    });
}

#pragma mark - Métodos de apoio

- (NSString *)formatDictionary:(NSDictionary *)dict {
    NSError *error = nil;
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:dict options:NSJSONWritingPrettyPrinted error:&error];
    
    if (error || !jsonData) {
        return @"{\"error\": \"Falha ao formatar dicionário\"}";
    }
    
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

@end
