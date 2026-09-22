# Show Shot — Microsoft Store

Material de referência pra submissão do Show Shot na Microsoft Store (Partner Center).
Não é documentação de código — isso é conteúdo de produto/listagem. Para o lado técnico
do empacotamento MSIX (identidade, certificado, arm64, gotchas do pacote `msix`), ver a
seção "Windows Store distribution (MSIX)" em [CLAUDE.md](CLAUDE.md).

## Status da submissão

- **Produto reservado**: Show Shot — `partner.microsoft.com` → Aplicativos e jogos
- **Identidade**: `RafaelWMS.ShowShot` / `Rafael WMS` / `CN=AF042F64-62A1-4E4C-AE05-051096B63CC2`
- **Pacotes enviados (2026-09-22)**: `showshot_x64.msix` (v1.0.0.0) e `showshot_arm64.msix`
  (v1.0.0.0), ambos em Windows 10/11 Desktop, `Windows.Desktop` min version `10.0.17763.0`
- **Pendente**: Listagem da Store (descrição/screenshots/categoria), Classificações
  etárias, política de privacidade publicada numa URL pública

## Listagem da Store

### Nome do produto

Show Shot

### Descrição curta (até ~100 caracteres, usada em listagens compactas)

**PT-BR:** Capture, anote e compartilhe telas na hora — área, janela, tela inteira ou texto.

**EN-US:** Capture, annotate and share your screen instantly — area, window, full screen or text.

### Descrição completa

**PT-BR:**

> Show Shot é um app de captura de tela rápido que fica sempre à mão na bandeja do
> sistema, pronto pra qualquer atalho de teclado.
>
> Congele a tela no instante exato do disparo e escolha o que capturar: uma área
> arrastando o mouse, uma janela específica com um clique, a tela inteira, ou apenas o
> texto que está na tela — reconhecido e copiado direto pra área de transferência, sem
> precisar digitar nada de novo.
>
> Depois de capturar, anote na hora: setas, retângulos, elipses, caneta livre,
> marcador, texto, numeração de passos e desfoque — tudo com cor, espessura e
> transparência ajustáveis, desfazer/refazer e zoom pra trabalhar em detalhes.
>
> Envie o resultado pra onde precisar: copiado direto na área de transferência ou
> salvo em PNG/JPG, com atalho pra abrir a pasta ou repetir a última ação.
>
> **Destaques**
> • Captura de área, janela, tela inteira ou texto (OCR on-device, sem enviar nada
>   pra nuvem)
> • Atalhos globais configuráveis — funciona mesmo com o app em segundo plano
> • Editor completo de anotações com desfazer/refazer e zoom
> • Copiar para a área de transferência ou salvar em PNG/JPG
> • Inicia com o Windows e vive discretamente na bandeja do sistema
> • Tema claro/escuro e cor de destaque seguem automaticamente as configurações do
>   Windows
> • Português e inglês, com detecção automática de idioma
>
> Show Shot não coleta dados pessoais, não exige conta e não envia suas capturas de
> tela para nenhum servidor — tudo acontece localmente no seu computador.

**EN-US:**

> Show Shot is a fast screenshot tool that lives in your system tray, always ready for
> a keyboard shortcut.
>
> It freezes the screen the instant you trigger it, then lets you pick what to
> capture: a dragged area, a specific window with one click, the full screen, or just
> the text on screen — recognized and copied straight to your clipboard, no retyping
> needed.
>
> Once captured, annotate right away: arrows, rectangles, ellipses, freehand pen,
> highlighter, text, step numbering and blur — all with adjustable color, stroke width
> and opacity, undo/redo, and zoom for fine detail work.
>
> Send the result wherever you need it: copied straight to the clipboard, or saved as
> PNG/JPG, with a shortcut to open the folder or repeat the last action.
>
> **Highlights**
> • Area, window, full-screen or text (on-device OCR, nothing sent to the cloud)
>   capture
> • Configurable global hotkeys — works even while the app is in the background
> • Full annotation editor with undo/redo and zoom
> • Copy to clipboard or save as PNG/JPG
> • Starts with Windows and lives quietly in the system tray
> • Light/dark theme and accent color follow your Windows settings automatically
> • Portuguese and English, with automatic language detection
>
> Show Shot doesn't collect personal data, doesn't require an account, and doesn't
> send your screenshots to any server — everything happens locally on your computer.

### Categoria sugerida

**Produtividade** (categoria primária) — alternativa: Ferramentas.

### Palavras-chave / termos de busca

`screenshot`, `screen capture`, `captura de tela`, `annotate`, `anotação`, `OCR`,
`print screen`, `snip`, `markup`, `text recognition`

### Screenshots necessários

A Store pede pelo menos 1 screenshot (recomendado: 3–6) em resolução desktop
(1366×768 mínimo; 1920×1080 fica bem em telas de alta densidade). Sugestão de
sequência, usando o próprio Show Shot pra capturar cada uma:

1. Tela inicial (Home) com os 4 cartões de captura visíveis
2. Overlay de seleção em ação (arrastando uma área, com a lupa/handles visíveis)
3. Editor com algumas anotações aplicadas (seta, texto, numeração)
4. Captura de texto (OCR) — seleção sobre um parágrafo, com o texto reconhecido
5. (Opcional) Menu da bandeja do sistema aberto
6. (Opcional) Tela de Configurações

### Classificações etárias (IARC, dentro do Partner Center)

O questionário de classificação é preenchido dentro do Partner Center (gera uma
classificação IARC). Como o Show Shot não tem violência, conteúdo sexual, linguagem
imprópria, jogos de azar, compras integradas, publicidade, nem compartilhamento
online de conteúdo gerado pelo usuário, as respostas devem ser "não" pra
praticamente todas as perguntas — resultando na classificação mais baixa disponível
(ex.: PEGI 3 / ESRB Everyone / equivalentes). Vale conferir se alguma pergunta
específica sobre "captura de tela de outros aplicativos" ou "acesso a conteúdo do
dispositivo" aparece — se aparecer, é justo marcar que sim (é a função central do
app), mas isso normalmente não eleva a faixa etária.

## Política de privacidade

A Store **exige uma URL pública** com a política de privacidade antes de aceitar a
submissão. O texto abaixo está pronto — falta só publicá-lo em algum lugar acessível
(sugestão: `showshot.rafaelwms.com/privacy`, uma página estática, um Gist, ou até uma
issue fixada no repositório, contanto que a URL seja estável).

---

### Política de Privacidade — Show Shot

*Última atualização: 22 de setembro de 2026*

O Show Shot é um aplicativo de captura e anotação de tela desenvolvido por Rafael
WMS. Esta política descreve, de forma direta, como o aplicativo lida com dados.

**Resumo: o Show Shot não coleta, armazena ou transmite nenhum dado pessoal seus.**
Tudo o que o aplicativo faz acontece localmente, no seu próprio computador.

**O que o aplicativo acessa, e por quê**

- **Tela do dispositivo**: o Show Shot captura a tela (ou parte dela) apenas quando
  você aciona explicitamente uma captura — por atalho de teclado, pelo menu da
  bandeja do sistema ou pela janela principal. Nenhuma captura acontece em segundo
  plano ou sem sua ação direta.
- **Reconhecimento de texto (OCR)**: quando você usa a função "Texto", o
  reconhecimento é feito inteiramente no seu dispositivo, usando os recursos nativos
  do sistema operacional (Vision no macOS, Windows.Media.Ocr no Windows, ou
  Tesseract localmente instalado no Linux). O conteúdo da captura nunca é enviado
  para servidores externos, da Microsoft, da Apple, ou de qualquer outro serviço.
- **Área de transferência (clipboard)**: ao usar "Copiar", a imagem ou o texto
  reconhecido é colocado na área de transferência do sistema operacional, como
  qualquer aplicativo que ofereça essa função.
- **Sistema de arquivos**: ao usar "Salvar", a captura é gravada como um arquivo
  PNG ou JPG na pasta que você escolher (ou na pasta padrão configurada nas
  preferências do aplicativo). O Show Shot não acessa nenhum outro arquivo do seu
  computador além dos que você salva por essa função.
- **Preferências do aplicativo**: configurações como idioma, atalhos de teclado,
  formato de imagem preferido e a lista de capturas recentes ficam guardadas
  localmente no seu dispositivo (usando o mecanismo de preferências do próprio
  sistema operacional). Essas informações nunca saem do seu computador.
- **Aparência do sistema**: o aplicativo lê o tema (claro/escuro) e a cor de destaque
  configurados no seu sistema operacional, apenas para adaptar sua própria
  aparência visual — essa informação não é armazenada nem compartilhada.

**O que o aplicativo *não* faz**

- Não coleta dados de uso, analytics ou telemetria.
- Não exige criação de conta nem login.
- Não envia capturas de tela, textos reconhecidos ou qualquer outro conteúdo para
  servidores, nuvens ou terceiros.
- Não contém anúncios.
- Não compartilha dados com terceiros, porque não coleta dados para começar.
- Não usa rastreadores, cookies ou identificadores de publicidade.

**Permissões do sistema**

Em alguns sistemas operacionais, o Show Shot pode solicitar permissões do sistema
(como acesso à gravação de tela, necessário para que qualquer aplicativo de captura
funcione). Essas permissões são usadas exclusivamente para a função de captura em
si, no momento em que você aciona uma captura — nunca para monitoramento contínuo
ou coleta de dados em segundo plano.

**Crianças**

O Show Shot não é direcionado a crianças e não coleta intencionalmente informações
de nenhum usuário, independentemente da idade — porque, como descrito acima, não
coleta informações de forma alguma.

**Alterações nesta política**

Caso esta política mude no futuro (por exemplo, se uma nova funcionalidade passar a
envolver algum serviço externo), a data no topo desta página será atualizada e, se a
mudança for relevante, ela será destacada nas notas de versão do aplicativo na
Microsoft Store.

**Contato**

Dúvidas sobre esta política podem ser enviadas para: rafael.wms@live.com

---

## Notas de release (v1.0.0)

Sugestão de texto pra primeira versão publicada na Store:

**PT-BR:**
> Primeira versão do Show Shot na Microsoft Store! Captura de área, janela, tela
> inteira e texto (OCR), editor completo de anotações, atalhos globais
> configuráveis, e suporte nativo a x64 e ARM64.

**EN-US:**
> First release of Show Shot on the Microsoft Store! Area, window, full-screen and
> text (OCR) capture, a full annotation editor, configurable global hotkeys, and
> native x64 and ARM64 support.
