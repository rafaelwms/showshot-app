# Show Shot

**Capture. Anote. Compartilhe.**

Show Shot é um aplicativo desktop (macOS, Windows e Linux) para captura de tela com
anotações, feito em Flutter. Ele vive na barra de menu / bandeja do sistema, responde a
atalhos globais e congela a tela no instante exato do disparo para que você selecione
uma área, uma janela ou a tela inteira, anote e envie para a área de transferência ou
para um arquivo PNG/JPG.

Site: <https://showshot.rafaelwms.com>

---

## Funcionalidades

| Área | O que faz |
| --- | --- |
| **Captura** | Área selecionada, janela específica (clique), tela inteira ou texto (OCR). A tela é congelada no momento do disparo — pelo atalho ou pelo menu do tray. |
| **Overlay de seleção** | Escurecimento fora da seleção, destaque automático da janela sob o cursor (só no modo Janela), lupa de precisão com coordenadas, handles de redimensionamento, guias de terços, tamanho em pixels, atalhos (`⌘/Ctrl+A` seleciona a tela inteira, `Enter` confirma, `Esc` cancela, setas movem 1px / `Shift`+setas 10px, `⌘/Ctrl+C` copia, `⌘/Ctrl+S` salva, `⌘/Ctrl+E` edita, `⌘/Ctrl+T` extrai texto). No modo Texto a barra só tem cancelar e confirmar: confirmar já copia o texto reconhecido. |
| **Texto (OCR)** | Reconhece o texto de uma seleção e copia direto para a área de transferência. macOS usa o framework Vision e Windows usa `Windows.Media.Ocr` (ambos on-device, sem configuração); Linux tenta `tesseract` se estiver instalado. |
| **Editor** | Seta, linha, retângulo, elipse, caneta, marcador, texto, numeração de passos, desfoque, **extrair texto** (arrasta uma região e reconhece só o que está nela); seleção com **mover, redimensionar e girar** qualquer marcação (inclusive texto — as alças dos cantos do texto alteram o tamanho da fonte, e as do desenho livre/marcador ampliam ou reduzem o traço — `Shift` mantém a proporção; **suavizador de curvas** (desligado, ou 5–100%) para caneta e marcador, ajustável depois de desenhar; `Shift` prende a rotação em passos de 15°); paleta + cor personalizada (HSV/hex); espessura, transparência, preenchimento, tamanho de fonte; desfazer/refazer; zoom (roda do mouse, pinça, `⌘/Ctrl +/-/0/1`), pan (ferramenta mão ou `Espaço`). |
| **Saída** | Copiar para a área de transferência (PNG + bitmap nativo), salvar PNG/JPG com diálogo ou direto na pasta padrão (`Imagens/ShowShot`), copiar ao salvar, lista de capturas recentes. |
| **Sistema** | Ícone na barra de menu (macOS/Linux) e tray (Windows), atalhos globais configuráveis, janela do editor configurável (maximizada por padrão, tela cheia ou tamanho da captura), ação do clique esquerdo no ícone da barra de menu/bandeja configurável (padrão: captura de área; o clique direito abre o menu), notificações do sistema para "copiado"/"salvo"/"texto copiado" (desligáveis), iniciar com o sistema (abre discretamente só no tray/barra de menu, sem mostrar a janela), ocultar/mostrar ícone no Dock (macOS), idioma PT/EN automático. |

### Atalhos padrão

| Ação | Atalho |
| --- | --- |
| Capturar área | `Ctrl+Shift+1` (`⌃⇧1` no macOS) |
| Capturar janela | `Ctrl+Shift+2` |
| Capturar tela inteira | `Ctrl+Shift+3` |
| Capturar texto (OCR) | `Ctrl+Shift+4` |

Todos podem ser alterados em **Configurações → Atalhos** (clique no campo e pressione a
combinação; `Backspace` remove).

### Atalhos do editor

`V` selecionar (alça circular acima do objeto gira; `Shift` = passos de 15°) · `H` mover tela · `A` seta · `L` linha · `R` retângulo · `E` elipse ·
`P` caneta · `M` marcador · `T` texto · `N` numeração · `B` desfoque ·
`O` extrair texto (arraste uma região; não deixa anotação, só copia o texto reconhecido) ·
`⌘/Ctrl+Z` desfazer · `⌘/Ctrl+Shift+Z` refazer · `Delete` excluir seleção ·
`⌘/Ctrl+C` copiar · `⌘/Ctrl+S` salvar · `⌘/Ctrl+Shift+S` salvar como ·
`⌘/Ctrl+T` extrair texto da imagem inteira (atalho direto, sem precisar trocar de ferramenta) ·
`Esc` fechar.

---

## Arquitetura

```
lib/
├── main.dart                 # bootstrap: janela, serviços, tray, hotkeys
├── app.dart                  # MaterialApp + rotas (/, /settings, /overlay, /editor, /blank)
├── core/                     # tema (design tokens), strings PT/EN, AppScope (DI)
├── models/                   # DisplayInfo, WindowInfo, CaptureSession, AppSettings, Annotation
├── services/
│   ├── native_bridge.dart    # canal `shoshot/native` (captura, janelas, overlay, clipboard)
│   ├── capture_service.dart  # congela o display sob o cursor (+ fallback CLI no Linux/Wayland)
│   ├── export_service.dart   # render das anotações, PNG/JPG, clipboard, salvar
│   ├── ocr_service.dart      # reconhecimento de texto (Vision/Windows.Media.Ocr/tesseract)
│   ├── hotkey_service.dart   # atalhos globais (hotkey_manager)
│   ├── tray_service.dart     # ícone e menu do tray (tray_manager)
│   ├── startup_service.dart  # iniciar com o sistema (launch_at_startup)
│   └── settings_service.dart # persistência (shared_preferences)
├── flow/capture_flow.dart    # orquestra captura → overlay → editor e as transições de janela
├── ui/
│   ├── home/                 # janela inicial (ações rápidas + recentes)
│   ├── overlay/              # tela congelada + seleção + lupa
│   ├── editor/               # controller, canvas, painéis de ferramentas/propriedades
│   ├── settings/             # configurações + gravador de atalhos
│   └── widgets/              # componentes compartilhados (GlassPanel, botões, title bar)
└── debug/debug_server.dart   # automação local somente em debug (ver abaixo)
```

Há **uma única janela do sistema** que muda de papel: janela normal (Home/Configurações/
Editor) ou overlay sem borda cobrindo o display capturado. Isso é feito no código nativo
de cada runner, que também implementa a captura de pixels e a lista de janelas:

| Plataforma | Arquivo | Captura | Lista de janelas | Overlay |
| --- | --- | --- | --- | --- |
| macOS | `macos/Runner/ShoShotNative.swift` | ScreenCaptureKit (`SCScreenshotManager`, macOS 14+) com fallback `CGDisplayCreateImage` | `CGWindowListCopyWindowInfo` | `NSWindow` borderless em nível `screenSaver` |
| Windows | `windows/runner/shoshot_native.cpp` | GDI `BitBlt` por monitor (DPI por monitor) | `EnumWindows` + DWM (ignora janelas *cloaked*, tool windows) | `WS_POPUP` + `WS_EX_TOPMOST` no retângulo do monitor |
| Linux | `linux/runner/shoshot_native.cc` | X11 `XGetImage`; em Wayland cai para `gnome-screenshot`/`spectacle`/`grim`/`scrot` | `_NET_CLIENT_LIST_STACKING` (somente X11) | `gtk_window_fullscreen_on_monitor` |

Todas as coordenadas globais são normalizadas em `DisplayInfo` (pontos no macOS, pixels
físicos no Windows/Linux) e convertidas para coordenadas lógicas locais ao display.

---

## Como compilar

Requisitos comuns: Flutter 3.47+ (Dart 3.13+).

```bash
cd app-shoshot
flutter pub get
```

### macOS

- Xcode 15+ (o projeto usa alvo mínimo **macOS 13**).
- `flutter run -d macos` ou `flutter build macos --release`.
- Na primeira captura o sistema pede a permissão **Gravação de Tela**
  (Ajustes do Sistema → Privacidade e Segurança → Gravação de Tela). Após conceder,
  reinicie o Show Shot.
- O app é um *menu bar app* (`LSUIElement`); o ícone no Dock pode ser ativado nas
  configurações.
- "Iniciar com o sistema" usa `SMAppService` (sem dependências externas).

### Windows

- É preciso do toolchain MSVC + Windows SDK — não do .NET SDK, e não
  necessariamente do app Visual Studio. Duas formas de conseguir:
  - **Visual Studio 2022** (Community serve) com a carga de trabalho *Desktop
    development with C++*; ou
  - **[Build Tools for Visual Studio 2022](https://visualstudio.microsoft.com/downloads/)**
    (instalador avulso, sem a IDE) com a mesma carga de trabalho — use este se
    for editar em outro lugar (Rider, VS Code etc.). Funciona nativamente em
    Windows ARM64 também.
  - Confirme com `flutter doctor -v`: precisa aparecer `[✓]` em "Visual Studio".
- `flutter run -d windows` ou `flutter build windows --release`.
- O executável fica em `build/windows/x64/runner/Release/` (ou `arm64/` em hosts
  ARM64). Para distribuir, empacote a pasta inteira (ou use MSIX/Inno Setup).

### Linux

Alvo principal: Ubuntu 26.04 (GNOME/Wayland), x64 e arm64. Dependências de build
(Debian/Ubuntu):

```bash
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
  libx11-dev libxi-dev libkeybinder-3.0-dev libayatana-appindicator3-dev
```

- `libx11-dev`: captura e lista de janelas nativas em sessões X11.
- `libkeybinder-3.0-dev`: atalhos globais em X11 (`hotkey_manager`) — exigido no build mesmo
  em Wayland.
- `libayatana-appindicator3-dev` e `libxi-dev`: ícone na barra (`tray_manager`).
- Opcional, para o modo Texto (OCR): `sudo apt-get install tesseract-ocr tesseract-ocr-por`
  (o idioma do sistema + inglês são usados automaticamente, se o pacote existir).

`flutter run -d linux` ou `flutter build linux --release`. Para instalar o build no usuário
atual (atalho no menu de apps, ícone no dock e identidade estável para as permissões do
sistema):

```bash
linux/packaging/install-local.sh            # último build release
linux/packaging/install-local.sh --uninstall
```

Pacote `.deb` (o que vai anexado na Release do GitHub), para a arquitetura da máquina
(amd64 ou arm64 — o Flutter não faz cross-compile, então o arm64 é gerado numa máquina
arm64):

```bash
sudo apt-get install dpkg-dev patchelf lintian   # uma vez
linux/packaging/build-deb.sh                     # → build/deb/showshot_<versão>_<arch>.deb + .sha256
lintian build/deb/*.deb                          # deve sair limpo
sudo apt install ./build/deb/showshot_*_amd64.deb
```

Quem já usou o `install-local.sh` deve rodar `linux/packaging/install-local.sh --uninstall`
antes de instalar o pacote **e sair/entrar na sessão**: o GNOME Shell guarda em memória a
entrada antiga (mesmo id `com.rafaelwms.showshot`) e continua tentando abrir o caminho de
`~/.local` até o próximo login.

**Wayland (GNOME):** tudo passa pelos portais do sistema (`xdg-desktop-portal`):

- **Captura:** portal Screenshot. Na primeira captura o GNOME pede uma autorização única
  ("Permitir que o Show Shot faça capturas de tela?"); ela fica salva.
- **Atalhos globais:** portal GlobalShortcuts. Na primeira execução o GNOME mostra os
  atalhos sugeridos (`Ctrl+Shift+1…4`) para você confirmar; para mudá-los depois, use
  *Configurações → Atalhos → Alterar atalhos no sistema* (abre a página do app nas
  Configurações do GNOME).
- **Modo Janela:** o Wayland não permite listar janelas; a escolha é feita na ferramenta
  de captura do próprio GNOME (aba Janela), e o resultado abre direto no editor.

Em sessões **X11** a captura, a lista de janelas e os atalhos são nativos (sem portais).

---

## Servidor de automação (somente debug)

Em builds de debug o app abre um servidor TCP em `127.0.0.1:47391` que permite disparar o
fluxo sem mouse/teclado — útil para testes e para depurar transições de janela. Ele é
removido de builds release (`kDebugMode`).

```bash
printf 'capture area\n' | nc 127.0.0.1 47391
printf 'select 100 100 600 400\nconfirm edit\n' | nc 127.0.0.1 47391
printf 'tool arrow\ndraw 50 50 300 200\ntext 100 300 Olá\naction save\n' | nc 127.0.0.1 47391
```

Comandos: `capture area|window|fullScreen|text [fromHome]`, `select x y w h`, `hover x y`, `windows`,
`confirm edit|copy|save|extractText|cancel`, `tool <nome>`, `draw x1 y1 x2 y2 [...]`, `text x y <texto>`,
`color AARRGGBB`, `style <espessura> <opacidade> [fill]`, `undo`,
`demo` (abre o editor numa imagem gerada — não precisa da permissão de gravação de tela),
`draw shift x1 y1 …` (arrasta com `Shift`), `typing x y <texto>` + `commit` (edita texto sem confirmar),
`dump` (anotações, alças e ângulos), `render` (grava o PNG exportado em `~/Pictures/shoshot_debug_render.png`),
`launch` (como o app foi iniciado), `visible` (janela visível?),
`action save|saveAs|copy|extractText|discard`,
`setting ask|copyAfterSave|magnifier|jpg|language true|false|<valor>`, `home`, `banner on|off` (aviso de permissão de gravação de tela na Home), `settings`,
`hide`, `close`, `stage`, `settingsBack`, `quit`.

---

## Limitações conhecidas / próximos passos

- O overlay cobre apenas o display sob o cursor (múltiplos monitores são suportados um por
  vez).
- Windows está validado em hardware real (x64 e arm64), incluindo OCR. Linux está
  validado em Ubuntu 26.04 x64 (GNOME 50, Wayland); arm64 compila do mesmo código, mas
  precisa ser buildado numa máquina arm64 (o `flutter build linux` não faz cross-compile).
- Linux/Wayland com vários monitores ainda não foi testado: o Wayland não informa a
  posição do cursor fora da janela do app, então a escolha do monitor a capturar pode não
  seguir o cursor.
- OCR (captura de Texto) está implementado de verdade no macOS (framework Vision) e no
  Windows (`Windows.Media.Ocr`, via C++/WinRT). No Linux, depende de `tesseract` estar
  instalado no sistema.
- Ideias futuras: gravação de vídeo/GIF, upload para a nuvem com link curto, pixelização
  além do desfoque, crop no editor, histórico de capturas com busca.
