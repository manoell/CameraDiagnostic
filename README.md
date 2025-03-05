# Camera Diagnostic Tool

Uma ferramenta de diagnóstico para iOS (com jailbreak) que fornece informações detalhadas sobre o funcionamento da câmera, visando identificar os pontos ideais para substituição do feed de forma indetectável e universal.

## Objetivo

Esta ferramenta foi desenvolvida para:

1. Diagnosticar o pipeline completo da câmera do iOS
2. Identificar os pontos exatos onde o feed da câmera pode ser substituído
3. Determinar quais metadados e propriedades precisam ser preservados
4. Detectar mecanismos de segurança que poderiam identificar a substituição
5. Fornecer insights para implementação de uma solução universal que funcione em todos os aplicativos

## Instalação

1. Certifique-se de ter o ambiente Theos configurado corretamente
2. Clone este repositório
3. Execute `make package install` para compilar e instalar o tweak
4. Reinicie o SpringBoard (`killall -9 SpringBoard`)

## Como Usar

1. Após a instalação, abra qualquer aplicativo que utilize a câmera
2. Use o aplicativo normalmente para capturar informações diagnósticas
3. Os logs são gravados no syslog do sistema

## Visualização de Logs

### Via SSH:
```bash
ssh root@[IP-DO-DISPOSITIVO]
tail -f /var/log/syslog | grep CameraDiag
```

### Via macOS:
1. Conecte o dispositivo ao Mac via USB
2. Abra o aplicativo Console (Aplicativos > Utilitários)
3. Selecione seu dispositivo na barra lateral
4. Filtre por "CameraDiag"

### Via dispositivo:
- Use o NewTerm2 e execute o comando `tail -f /var/log/syslog | grep CameraDiag`
- Ou use o Filza para navegar até `/var/log/syslog`

## Interpretação dos Logs

O tweak registra informações em pontos-chave do pipeline da câmera:

### Pontos de Interesse:

- **Inicialização da câmera**: Logs com "AVCaptureSession" mostram quando uma sessão é criada
- **Classes manipuladoras**: "New buffer handler class detected" identifica classes que processam dados da câmera
- **Formatos de buffer**: "Buffer format" mostra detalhes técnicos dos buffers de imagem
- **Caminho de renderização**: "Camera content being set to layer" indica quando o conteúdo chega à UI
- **Verificações de segurança**: "Security check" detecta verificações que podem identificar substituições

### Informações Cruciais:

Preste atenção especial a:

1. **Sequência de chamadas**: A ordem em que os componentes são inicializados
2. **Metadados preservados**: Propriedades que precisam ser replicadas na substituição
3. **Caminho comum**: Pontos do pipeline presentes em todos os aplicativos
4. **Verificações específicas**: Mecanismos que aplicativos usam para validar a autenticidade

## Como Funciona

O tweak utiliza o Cydia Substrate para interceptar chamadas relacionadas à câmera em vários níveis:

1. **AVFoundation**: Intercepta APIs de alto nível para configuração de câmera
2. **CoreMedia/CoreVideo**: Monitora a manipulação de buffers de imagem
3. **Apresentação de UI**: Acompanha como os dados da câmera são renderizados na tela
4. **Segurança**: Detecta verificações que poderiam identificar uma substituição

## Próximos Passos

Após coletar informações suficientes:

1. Identifique o ponto ideal para interceptação (geralmente em `captureOutput:didOutputSampleBuffer:fromConnection:`)
2. Determine os metadados e propriedades que precisam ser preservados
3. Desenvolva um método para substituir os dados do buffer mantendo as propriedades originais
4. Implemente verificações para evitar detecção por apps específicos

## Aviso Legal

Esta ferramenta é desenvolvida apenas para fins educacionais e de pesquisa. Utilize-a de acordo com as leis e regulamentos locais.
