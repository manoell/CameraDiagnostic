# CameraDiagnostic

![Badge](https://img.shields.io/badge/iOS-14.0%2B-blue)
![Badge](https://img.shields.io/badge/Status-Beta-yellow)

## Visão Geral

CameraDiagnostic é uma ferramenta de diagnóstico para iOS jailbroken que coleta informações detalhadas sobre o funcionamento da câmera em diferentes aplicativos. Desenvolvida para ser usada em conjunto com o tweak VCamMJPEG, esta ferramenta diagnostica e registra as características exatas da câmera nativa para permitir aprimoramentos na substituição do feed de câmera.

## Objetivo

O principal objetivo desta ferramenta é coletar informações cruciais sobre como cada aplicativo utiliza a câmera, incluindo:

- Resoluções nativas de câmeras (frontal/traseira)
- Orientações de vídeo e transformações aplicadas
- Formatos de pixel e configurações de buffer
- Metadados de captura de fotos
- Ajustes específicos de cada aplicativo

Estas informações permitem que o VCamMJPEG realize a substituição do feed da câmera de forma transparente e universal, emulando exatamente as características esperadas por cada aplicativo.

## Características

### Diagnóstico Abrangente
- Monitoramento de AVCaptureSession
- Detecção de características da câmera do dispositivo
- Análise de orientações e transformações de vídeo
- Captura de metadados de fotos e vídeos
- Extração de formatos e configurações

### Logging Detalhado
- Formato JSON para fácil análise
- Organização por sessões e categorias
- Timestamp em cada evento registrado
- Armazenamento eficiente e bem estruturado

### Compatibilidade Universal
- Funciona em qualquer aplicativo que use a câmera
- Mesmo sistema de hooks do VCamMJPEG
- Diagnóstico não intrusivo (não modifica comportamento)
- Suporte a iOS 10 até versões recentes

## Arquitetura do Projeto

O projeto está organizado em componentes bem definidos:

- **Core**
  - `DiagnosticTweak.h/.xm`: Núcleo do tweak e gestão de sessões
  - `Filter.plist`: Configuração de aplicativos suportados
  
- **Utils**
  - `Logger.h/.m`: Sistema de logging com suporte a JSON
  - `MetadataExtractor.h/.m`: Extração de dados da câmera e mídia
  
- **Hooks**
  - `CaptureSessionHooks.xm`: Monitora AVCaptureSession
  - `DeviceHooks.xm`: Monitora características do dispositivo de câmera
  - `OrientationHooks.xm`: Monitora orientações de vídeo
  - `VideoOutputHooks.xm`: Monitora saídas de vídeo e frames
  - `PhotoOutputHooks.xm`: Monitora captura de fotos

## Funcionamento

1. O tweak é carregado quando um aplicativo que usa a câmera é iniciado
2. Cada interação com a câmera é monitorada e registrada
3. Informações detalhadas são salvas em arquivos JSON
4. Cada aplicativo gera sua própria sessão de diagnóstico
5. Os logs são armazenados em `/var/mobile/Documents/CameraDiagnostic/`

## Como Usar

### Instalação

1. Compile o projeto usando o Theos:
   ```bash
   make package
   ```

2. Instale o pacote .deb no dispositivo com jailbreak:
   ```bash
   make install
   ```

### Coletando Dados

1. Abra os aplicativos que deseja diagnosticar (Camera, Instagram, Snapchat, etc.)
2. Use a câmera normalmente, incluindo:
   - Alternar entre câmeras frontal e traseira
   - Mudar orientação do dispositivo
   - Capturar fotos
   - Gravar vídeos (se aplicável)

3. Acesse os logs em `/var/mobile/Documents/CameraDiagnostic/`

### Analisando Resultados

Os arquivos JSON contêm informações organizadas por categorias:
- **session**: Informações gerais da sessão
- **device**: Características do dispositivo de câmera
- **video**: Configurações de vídeo
- **photo**: Configurações de foto
- **orientation**: Orientações detectadas
- **format**: Formatos de mídia
- **metadata**: Metadados diversos

## Integrando com VCamMJPEG

Os dados coletados podem ser usados para:
1. Identificar diferentes implementações entre aplicativos
2. Resolver problemas de compatibilidade
3. Implementar adaptações dinâmicas no VCamMJPEG

## Requisitos

- iOS 10.0 até versões recentes
- Dispositivo com jailbreak
- Theos para compilação

## Próximos Passos

- Implementar auto-diagnóstico no VCamMJPEG
- Criar sistema de adaptação dinâmica
- Expandir compatibilidade com mais aplicativos

## Licença

Código fonte disponível para uso pessoal e educacional.