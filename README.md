# Camera Diagnostic

Um tweak para diagnóstico completo do pipeline da câmera em iOS.

## Objetivo

Este tweak foi desenvolvido para registrar e analisar todos os aspectos do funcionamento da câmera no iOS, com o objetivo de compreender como o sistema processa o feed da câmera. As informações coletadas serão utilizadas para criar um sistema capaz de substituir o feed da câmera de forma indetectável e universal em qualquer aplicativo.

## Funcionamento

O Camera Diagnostic monitora e registra:

- Inicialização e configuração da sessão de câmera (AVCaptureSession)
- Fluxo de dados de vídeo através do pipeline completo
- Formatos, metadados e propriedades dos buffers de vídeo
- Manipulação de imagem e processamento de frames
- Renderização e exibição do feed da câmera na UI
- Verificações de segurança e autenticidade do sistema

## Componentes Monitorados

- **AVFoundation**: Classes principais relacionadas à captura de vídeo
- **CoreMedia**: Gerenciamento de buffers de amostra e metadados
- **CoreVideo**: Processamento de buffers de pixel
- **CoreImage**: Manipulação e processamento de imagens
- **Media Readers**: Componentes para leitura de vídeos existentes
- **Display Layers**: Camadas de exibição de vídeo

## Logs

Todos os logs são salvos em `/var/tmp/CameraDiag.log`. O arquivo pode ficar grande rapidamente devido à quantidade de informações capturadas.

## Como Usar

1. Instale o tweak em seu dispositivo com jailbreak
2. Use aplicativos que acessam a câmera (aplicativo Câmera, Instagram, Snapchat, etc.)
3. Colete os logs para análise
4. Use as informações para identificar pontos de intervenção para substituição do feed

## Análise dos Logs

Os logs contêm prefixos para facilitar a categorização:

- `[INIT]` - Inicialização de objetos
- `[METHOD]` - Chamadas de método
- `[BUFFER]` - Informações sobre buffers de vídeo
- `[DISPLAY]` - Operações de renderização e exibição
- `[IMAGE_PROCESSING]` - Operações de processamento de imagem
- `[MEDIA_READER]` - Operações de leitura de mídia

## Desenvolvimento

### Pré-requisitos:
- Theos instalado
- SDK iOS
- Dispositivo com jailbreak para testes

### Compilação:
```bash
make
make package
```

### Instalação:
```bash
make install
```

## Próximos Passos

Após a coleta de dados suficientes, a próxima etapa é desenvolver um mecanismo que possa:

1. Interceptar o feed da câmera no ponto ideal do pipeline
2. Substituir os dados com um feed alternativo
3. Preservar todos os metadados e propriedades necessários
4. Garantir que a substituição seja indetectável pelos aplicativos

## Notas

Este tweak é apenas para análise e diagnóstico, não realiza nenhuma substituição efetiva do feed da câmera.
