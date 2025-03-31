# CameraDiagnostic

## Descrição

CameraDiagnostic é uma ferramenta de diagnóstico avançada para câmeras em dispositivos iOS com jailbreak. Projetada para monitorar e registrar detalhadamente o funcionamento da câmera em qualquer aplicativo, esta ferramenta fornece informações técnicas essenciais para desenvolvedores que trabalham com substituição de feed de câmera, câmeras virtuais e integração com WebRTC.

## Características

- **Diagnóstico Universal**: Monitora o uso da câmera em qualquer aplicativo iOS, sem exceções
- **Captura Detalhada**: Registra informações técnicas precisas sobre formato de pixel, resolução, FPS, orientação e muitos outros parâmetros
- **Análise de Frames**: Monitora os frames brutos da câmera, permitindo entender exatamente como aplicativos processam o feed de vídeo
- **Compatibilidade com WebRTC**: Fornece todos os detalhes necessários para implementação de soluções de câmera virtual com WebRTC
- **Logging Inteligente**: Salva apenas informações relevantes, evitando sobrecarga desnecessária
- **Análise por Aplicativo**: Gera arquivos JSON detalhados para cada aplicativo monitorado

## Uso Técnico

O CameraDiagnostic funciona através de hooks em várias classes da framework AVFoundation, incluindo:

- `AVCaptureDevice`: Para detectar quando aplicativos solicitam acesso à câmera
- `AVCaptureSession`: Para monitorar início e fim de sessões de câmera
- `AVCaptureVideoDataOutput`: Para analisar frames brutos de vídeo
- `AVCaptureConnection`: Para detectar mudanças de orientação e espelhamento
- `AVCapturePhotoOutput`: Para monitorar captura de fotos

### Informações Coletadas

- Resolução da câmera (frontal e traseira)
- Formato de pixel (420f, 420v, BGRA, etc.)
- Taxa de frames real durante operação (FPS)
- Orientação e espelhamento de vídeo
- Dimensões de layers de preview
- Timing de frames para análise de performance
- Configurações de sessão (presets, formatos, etc.)
- Metadados de captura de foto

## Instalação

1. Certifique-se de ter o Theos instalado no seu sistema
2. Clone este repositório
3. Compile o projeto usando `make package install`
4. O tweak será instalado automaticamente no dispositivo conectado

## Arquivos de Diagnóstico

Os diagnósticos são salvos em:
- `/var/tmp/CameraDiagnostic/diagnostic.log`: Log em tempo real de todos os eventos
- `/var/tmp/CameraDiagnostic/[AppName]_[BundleID]_diagnostics.json`: Informações detalhadas específicas por aplicativo

## Uso com WebRTC

Este diagnóstico foi especialmente desenvolvido para auxiliar na implementação de câmeras virtuais com WebRTC:

- Fornece todos os parâmetros necessários para criar streams WebRTC compatíveis com aplicativos iOS
- Identifica formatos de pixel específicos usados por cada aplicativo
- Detecta mudanças de orientação e configuração em tempo real
- Registra informações de timing para sincronização perfeita

## Compatibilidade

- Dispositivos iOS com jailbreak
- Compatível com iOS 14 ou superior
- Testado em aplicativos como Câmera nativa, Telegram, WhatsApp, Safari (WebRTC)

## Desenvolvimento Futuro

A ferramenta foi desenvolvida para trabalhar em conjunto com projetos de câmera virtual, focando em fornecer diagnósticos precisos e completos para auxiliar no desenvolvimento de soluções avançadas de substituição de câmera.

## Licença

Este projeto é disponibilizado sob a licença MIT.
