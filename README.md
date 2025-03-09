# Camera Diagnostic

Um tweak para diagnóstico completo do pipeline da câmera em iOS, com foco na análise do aplicativo nativo de câmera e preparação para implementação universal.

## Objetivo

Este tweak foi desenvolvido para registrar e analisar o funcionamento da câmera no iOS, com o objetivo de compreender como o sistema processa o feed da câmera. As informações coletadas serão utilizadas para criar um sistema capaz de substituir o feed da câmera de forma indetectável e que funcione tanto para visualização quanto para captura de fotos e vídeos.

## Status Atual

O tweak está funcionando perfeitamente com o aplicativo de câmera nativa do iOS, capturando informações detalhadas sobre todo o pipeline de processamento. Isso inclui:

- Inicialização e configuração da sessão
- Troca entre câmeras frontal e traseira
- Captura de fotos 
- Gravação de vídeos
- Configurações de orientação e espelhamento
- Conexões entre componentes do sistema de câmera

Para o aplicativo nativo, as informações coletadas são suficientes para implementar uma substituição completa e transparente do feed da câmera.

## Pontos de Interesse Identificados

1. **Visualização em tempo real**: O feed é processado através de `AVCaptureVideoPreviewLayer`, que recebe dados da sessão de captura e os exibe na interface.

2. **Captura de fotos**: Controlada por `AVCapturePhotoOutput capturePhotoWithSettings`, que especifica as configurações da foto e o delegate que receberá a imagem final.

3. **Gravação de vídeo**: Gerenciada por `CAMCaptureMovieFileOutput`, que recebe o feed de vídeo e o salva em um arquivo.

4. **Fluxo de dados**: O ponto chave é o método `captureOutput:didOutputSampleBuffer:fromConnection:`, onde os frames brutos são processados antes de serem enviados para a interface ou para gravação.

## Como Usar

1. Instale o tweak em seu dispositivo com jailbreak
2. Use o aplicativo nativo de câmera 
3. Examine os logs gerados em `/var/tmp/CameraDiag.log`
4. Compare os logs entre diferentes operações (foto, vídeo, troca de câmera)

## Estrutura dos Logs

Os logs contêm prefixos que indicam o tipo de operação sendo monitorada:

- `[INIT]` - Inicialização de objetos
- `[SESSION]` - Operações da sessão de captura
- `[DEVICE]` - Operações do dispositivo de câmera
- `[DEVICE_INPUT]` - Configurações de entrada
- `[DISPLAY]` - Operações de exibição
- `[CONNECTION]` - Configurações de conexão
- `[PHOTO]` - Operações de captura de foto
- `[VIDEO]` - Operações de gravação de vídeo
- `[BUFFER_HOOK]` - Informações sobre os buffers de imagem
- `[PIXEL_FORMAT]` - Detalhes sobre formatos de pixel

## Próximos Passos

### Fase 1: Atual - Diagnóstico da Câmera Nativa
✅ Análise completa do aplicativo de câmera nativa
✅ Identificação dos pontos-chave para substituição
✅ Mapeamento do pipeline completo (visualização + captura)

### Fase 2: Expansão para Outros Aplicativos
- Adaptar o tweak para capturar informações em outros aplicativos populares
- Comparar implementações entre diferentes aplicativos
- Identificar padrões comuns e diferenças no uso da câmera

### Fase 3: Desenvolvimento da Solução de Substituição
- Implementar substituição de feed para o aplicativo nativo como prova de conceito
- Adaptar a solução para funcionar universalmente com base nos padrões identificados
- Testar a solução em múltiplos aplicativos

## Ponto Ideal para Substituição

Com base na análise atual, o ponto mais promissor para substituição do feed na câmera nativa é o método `captureOutput:didOutputSampleBuffer:fromConnection:`. Este método recebe os frames brutos da câmera antes que sejam processados para exibição ou gravação, permitindo uma substituição transparente que afetará tanto a visualização em tempo real quanto a captura de fotos e vídeos.

## Notas Técnicas

- O tweak utiliza Logos (Theos) para criar hooks no sistema iOS
- Filter.plist está configurado para carregar o tweak em todos os aplicativos via UIKit
- Os logs são gerados em formato legível para facilitar a análise
- A solução final deverá preservar metadados importantes como orientação, timestamp e configurações de câmera para manter total compatibilidade

## Conclusão

A análise do aplicativo de câmera nativa fornece uma base sólida para compreender o pipeline de processamento da câmera no iOS. O próximo desafio é expandir esta análise para outros aplicativos e desenvolver uma solução de substituição universal que funcione de forma transparente e indetectável em todo o sistema.
