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
| **Captura** | Área selecionada, janela específica (clique) ou tela inteira. A tela é congelada no momento do disparo — pelo atalho ou pelo menu do tray. |
| **Overlay de seleção** | Escurecimento fora da seleção, destaque automático da janela sob o cursor, lupa de precisão com coordenadas, handles de redimensionamento, guias de terços, tamanho em pixels, atalhos (`Space` tela inteira, `Enter` confirma, `Esc` cancela, setas movem 1px / `Shift`+setas 10px, `⌘/Ctrl+C` copia, `⌘/Ctrl+S` salva, `⌘/Ctrl+E` edita). |
| **Editor** | Seta, linha, retângulo, elipse, caneta, marcador, texto, numeração de passos, desfoque; seleção/mover/redimensionar; paleta + cor personalizada (HSV/hex); espessura, transparência, preenchimento, tamanho de fonte; desfazer/refazer; zoom (roda do mouse, pinça, `⌘/Ctrl +/-/0/1`), pan (ferramenta mão ou `Espaço`). |
| **Saída** | Copiar para a área de transferência (PNG + bitmap nativo), salvar PNG/JPG com diálogo ou direto na pasta padrão (`Imagens/ShowShot`), copiar ao salvar, lista de capturas recentes. |
| **Sistema** | Ícone na barra de menu (macOS/Linux) e tray (Windows), atalhos globais configuráveis, iniciar com o sistema, ocultar/mostrar ícone no Dock (macOS), idioma PT/EN automático. |

### Atalhos padrão

| Ação | Atalho |
| --- | --- |
| Capturar área | `Ctrl+Shift+1` (`⌃⇧1` no macOS) |
| Capturar janela | `Ctrl+Shift+2` |
| Capturar tela inteira | `Ctrl+Shift+3` |

Todos podem ser alterados em **Configurações → Atalhos** (clique no campo e pressione a
combinação; `Backspace` remove).

### Atalhos do editor

`V` selecionar · `H` mover tela · `A` seta · `L` linha · `R` retângulo · `E` elipse ·
`P` caneta · `M` marcador · `T` texto · `N` numeração · `B` desfoque ·
`⌘/Ctrl+Z` desfazer · `⌘/Ctrl+Shift+Z` refazer · `Delete` excluir seleção ·
`⌘/Ctrl+C` copiar · `⌘/Ctrl+S` salvar · `⌘/Ctrl+Shift+S` salvar como · `Esc` fechar.

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

Dependências de build (Debian/Ubuntu):

```bash
sudo apt-get install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev \
  libx11-dev libxi-dev libkeybinder-3.0-dev
```

- `libx11-dev`: captura e lista de janelas nativas (X11).
- `libkeybinder-3.0-dev`: atalhos globais (`hotkey_manager`).
- `libxi-dev`: ícone do tray (`tray_manager`).

`flutter run -d linux` ou `flutter build linux --release`.

Em sessões **Wayland** a captura nativa e os atalhos globais não estão disponíveis
(limitação do protocolo): o app usa as ferramentas de screenshot do desktop e a detecção
de janelas fica desligada. Use uma sessão X11 (ou XWayland) para a experiência completa.

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

Comandos: `capture area|window|fullScreen`, `select x y w h`, `hover x y`, `windows`,
`confirm edit|copy|save|cancel`, `tool <nome>`, `draw x1 y1 x2 y2 [...]`, `text x y <texto>`,
`color AARRGGBB`, `style <espessura> <opacidade> [fill]`, `undo`,
`action save|saveAs|copy|discard`,
`setting ask|copyAfterSave|magnifier|jpg|language true|false|<valor>`, `home`, `settings`,
`hide`, `close`, `stage`, `settingsBack`, `quit`.

---

## Limitações conhecidas / próximos passos

- O overlay cobre apenas o display sob o cursor (múltiplos monitores são suportados um por
  vez).
- Windows e Linux foram escritos contra as APIs oficiais, mas o build nativo destas
  plataformas ainda precisa ser validado em máquinas reais.
- Ideias futuras: gravação de vídeo/GIF, upload para a nuvem com link curto, OCR, pixelização
  além do desfoque, crop no editor, histórico de capturas com busca.
