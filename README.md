# CameraDiagnostic

## Ferramenta de Diagnóstico da Câmera iOS

![Badge](https://img.shields.io/badge/iOS-14.0%2B-blue)
![Badge](https://img.shields.io/badge/Status-Desenvolvimento-orange)

## Visão Geral

CameraDiagnostic é uma ferramenta para análise profunda da câmera em dispositivos iOS, projetada para inspecionar e diagnosticar como diferentes aplicativos interagem com o sistema de câmera nativo. A ferramenta coleta dados extensos sobre cada etapa do pipeline da câmera, permitindo entender seu funcionamento interno para implementações futuras.

## Objetivos

1. **Diagnóstico Completo**: Coletar informações detalhadas sobre cada etapa do pipeline da câmera
2. **Análise Multi-Aplicativos**: Monitorar como diferentes apps interagem com a câmera
3. **Identificação de Padrões**: Descobrir elementos em comum entre diferentes implementações
4. **Documentação do API**: Entender o funcionamento prático das APIs de câmera do iOS

## Componentes Monitorados

### 1. Configuração da Câmera
- Formatos de captura
- Resoluções suportadas
- Orientações
- Configurações de taxa de frames
- Troca entre câmeras frontal/traseira

### 2. Pipeline de Processamento
- Delegados e callbacks
- Fluxo de sample buffers
- Formatos de pixel
- Transformações de dados
- Metadados

### 3. Interface do Usuário
- Layers de preview
- Transformações e geometria
- Hierarquia de views
- Manipulação de imagens

### 4. Captura de Fotos
- Configurações de foto
- Processamento de imagem
- Metadados EXIF
- Miniaturas e previews

## Arquitetura do Projeto

O projeto está dividido em componentes especializados:

- **Tweak.xm**: Inicialização e configuração global
- **CameraHooks.xm**: Hooks para componentes principais de câmera (AVCaptureSession, AVCaptureDevice)
- **PhotoHooks.xm**: Hooks específicos para captura de fotos
- **PreviewHooks.xm**: Hooks para preview e exibição
- **UIHooks.xm**: Hooks para interface de usuário
- **DiagnosticCollector**: Sistema de coleta e armazenamento de dados
- **Logger**: Sistema de log para depuração

## Dados Coletados

Todos os dados são salvos em formato JSON estruturado, incluindo:

- Timestamp de cada evento
- Identificação de sessão
- Propriedades relevantes
- Hierarquias de componentes
- Resolução, formato e metadados
- Estatísticas de performance

## Implementação

A ferramenta utiliza a técnica de "method swizzling" através do framework Theos para interceptar chamadas de API sem modificar os aplicativos alvo. Todas as operações são realizadas de forma não-intrusiva, apenas coletando dados sem interferir no funcionamento normal.

## Como Usar

1. Compilar e instalar o tweak em um dispositivo com jailbreak
2. Abrir qualquer aplicativo que use a câmera
3. Utilizar a câmera normalmente
4. Os dados serão coletados automaticamente
5. Verificar os arquivos JSON de diagnóstico no diretório `/var/mobile/Documents/CameraDiagnostics/`

## Principais Pontos de Interesse

- **Pontos de injeção**: Encontrar o local ideal para substituir o feed da câmera
- **Compatibilidade**: Identificar padrões comuns entre diferentes aplicativos
- **Mapeamento de formato**: Entender os formatos de imagem utilizados em cada etapa
- **Sincronização**: Compreender mecanismos de timing e sincronização
- **Metadados críticos**: Identificar quais metadados são essenciais para manter compatibilidade

## Análise de Dados

Os dados coletados podem ser analisados para:

1. Criar um mapa completo do pipeline da câmera em cada aplicativo
2. Identificar pontos em comum entre diferentes implementações
3. Determinar os requisitos para uma implementação de câmera virtual transparente
4. Documentar as práticas reais de uso da API AVFoundation

## Requisitos

- iOS 14.0 ou superior
- Dispositivo com jailbreak
- Acesso a permissões de câmera

## Próximos Passos

- Expandir monitoramento para mais classes e métodos
- Adicionar ferramentas de visualização para os dados coletados
- Criar relatórios comparativos entre diferentes aplicativos
- Desenvolver protótipo de substituição baseado nos dados coletados

## Notas

Esta ferramenta é exclusivamente para diagnóstico e pesquisa. Todas as informações coletadas são armazenadas localmente no dispositivo e não são compartilhadas.