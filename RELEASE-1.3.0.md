# Show Shot 1.3.0 — escopo e plano

Versão atual: 1.2.0+2 (`pubspec.yaml`, `msix_version: 1.2.0.0`). Alvo: 1.3.0.
Registro combinado com o Rafael em 2026-11-20. Status: `[ ]` pendente, `[~]` em andamento, `[x]` feito e verificado.

## Correção

- [~] **C1 — "Iniciar com o Sistema" não funciona no Windows (x64 e arm64) em instalações via Winget.**
  - ✅ **2026-11-20, arm64 validado (Radxa, MSIX de teste sideload):** a tarefa `ShowShotStartup` ficou habilitada (State=2, "Rafael WMS" no Gerenciador de Tarefas), nada foi gravado na `Run`, e após o reboot o app subiu de `WindowsApps` com `--autostart`, só na bandeja.
  - Pendentes: x64 no Desktop (`asus-win11`) e confirmação final no pacote da Store (1.3.0 publicada).
  - Radxa: o Show Shot da Store foi desinstalado para o teste e o MSIX de teste (publicador "Msix Testing") está instalado; o certificado de teste está em `LocalMachine\TrustedPeople`. Desfazer ao final.
  Só funciona no Desktop do Rafael, onde o build original foi feito (exe solto, sem pacote).
  - Hipótese principal: o Winget instala o pacote **MSIX** da Store (`msstore`). `StartupService` usa `launch_at_startup`
    com `appPath: Platform.resolvedExecutable`, que grava a chave `HKCU\...\Run`. Em app empacotado (MSIX) essa chave
    é virtualizada/ignorada e o caminho dentro de `WindowsApps` muda a cada versão. Em exe solto a chave funciona — por isso só o build local inicia.
  - Implementado (2026-11-20, **sem teste em hardware**): em Windows empacotado o `StartupService` usa o `StartupTask` MSIX (`ShowShotStartup`, declarado em `msix_config.startup_task`) via métodos nativos `isPackaged`/`startupTaskState`/`setStartupTask`; `launch_at_startup` segue só para exe solto/macOS/Linux; se o usuário desativou no Gerenciador de Tarefas, a opção volta a desligada com dica + botão para `ms-settings:startupapps`.
  - Caminho provável de correção: declarar `startup_task` no `msix_config` (extensão `windows.startupTask` do manifesto)
    e usar o modo MSIX do `launch_at_startup` (`packageName`), mantendo o registro como fallback para exe solto.
  - A confirmar antes de codar: como o Rafael instala (Store/msstore ou `winget-pkgs` com exe/MSIX?) e se o `--autostart` chega ao app.
  - Verificar em: Windows x64 (`asus-win11`) e Windows arm64 (Radxa, `q6a-win11`), instalando **via Winget**, reiniciando/relogando de fato.

## Melhorias

- [x] **M1 — Editor: ferramenta Crop.** Corte seletivo pelo usuário; proporções fixas (1:1, 3:4, 4:3, 16:9 …) e Custom (livre).
  - ✅ 2026-11-21 aprovado pelo Rafael no macOS ("ferramenta completa").
  - Implementado em 2026-11-21, falta compilar e testar manualmente: `ToolType.crop` (tecla `C`, transitória), `lib/models/crop.dart` (lógica pura), histórico com imagem (`UndoHistory` + `EditorSnapshot`), recorte de anotações que cruzam a borda (clip no canvas e no `ExportService.render`), debug `croprect`/`cropratio`/`cropapply`/`cropcancel`, testes em `test/crop_test.dart`.
- [x] **M2 — Configurações/Editor: lembrar ajustes das ferramentas.** Opção liga/desliga para guardar cor, espessura (e demais estilos) e **última ferramenta usada**.
  - ✅ 2026-11-20 testado no Windows arm64 (MSIX 1.2.0.2/1.2.0.3).
  - Implementado (2026-11-20), falta teste manual: `AppSettings.rememberTools` + `ToolMemory` (tamanhos em unidades lógicas), debounce 300 ms, OCR não é lembrado.
- [x] **M3 — Configurações: salvar na última pasta usada.** Se não existir mais → pasta padrão; se também não existir → criá-la. (Atenção ao bookmark sandbox do macOS, `saveDirectoryBookmark`.)
  - ✅ 2026-11-20 testado no Windows arm64.
  - Implementado em 2026-11-20 (`saveToLastFolder` + `lastSaveDirectory`, `ExportService.resolveSaveDirectoryPath`, teste em `test/save_directory_test.dart`); falta validar manualmente (Win/Linux/macOS sandbox).
- [x] **M4 — Configurações: padrão de nome para arquivos sequenciais.** Prefixo customizado: `ARQUIVO_01.png`, `FOTO_01.png`… (definir largura do contador e como o contador continua).
  - ✅ 2026-11-20 testado no Windows arm64.
  - Implementado em 2026-11-20 (`FileNamer` em `lib/services/file_namer.dart`, campos `fileNaming/namePrefix/nameSeparator/nameDigits/sequenceNext`, UI em Salvar, teste em `test/file_namer_test.dart`); falta validar manualmente.
- [x] **M5 — Configurações: "Salvar todas as telas" (nova opção).** Captura/salva todos os monitores.
  - ✅ 2026-11-21 testado no macOS com 2 monitores (um arquivo por tela e combinada, disposição correta).
  - ✅ 2026-11-20 testado no Windows arm64 com 1 monitor. **Falta testar com vários monitores** (um arquivo por tela e imagem combinada).
  - Implementado em 2026-11-20 (`CaptureMode.allScreens` + atalho Ctrl+Shift+5 + item do tray/card da Home, `AppSettings.allScreensMode` perScreen|combined, `ScreenLayout` em `lib/services/screen_layout.dart`, `FileNamer.nextBatch`, `ExportService.compose/saveBatch`; testes em `test/screen_layout_test.dart` e `test/file_namer_test.dart`); falta validar manualmente (1 e 2+ monitores, mixed-DPI, Wayland).
- [x] **M3/M5 — Correções (2026-11-21)** ✅ testadas no macOS pelo Rafael. (a) Ações sem janela (todas as telas, salvar direto/copiar/extrair texto da overlay): se a notificação do SO não foi entregue, a Home é aberta para mostrar o toast (`_reportHeadless`). (b) macOS sandbox: "última pasta usada" sobrevive ao relançamento (`lastSaveDirectoryBookmark`, `requestFolderAccess` nativo com painel "Permitir" após Salvar Como, vários escopos ativos; testes em `test/save_directory_test.dart`).

- [x] **M6 — Editor: ferramenta Carimbo (clone stamp, estilo Photoshop).** Alt/Option+clique define a origem; ao pintar, copia da origem mantendo o deslocamento (modo alinhado). Tamanho do pincel e dureza (borda suave). Não destrutivo, com undo, editável/selecionável como as demais anotações.
  - ✅ 2026-11-21 testado no macOS.
  - Implementado em 2026-11-21, falta compilar e testar manualmente: `ToolType.stamp` (tecla `S`), `StampAnnotation` + `StampSourceState` (`annotation.dart`), `AnnotationStyle.brushSize/hardness` (+ `ToolMemory`), debug `stampsource`/`stampstyle`, testes em `test/stamp_test.dart`.
- [x] **M7 — Editor: alinhamento do texto.** Esquerda/centro/direita (justificar a decidir) na ferramenta Texto e alterável pela ferramenta Seleção (barra de propriedades).
  - ✅ 2026-11-21 aprovado pelo Rafael no Windows arm64 (MSIX 1.2.0.4).
  - Implementado em 2026-11-21, falta compilar e testar manualmente: `AnnotationStyle.textAlign` (+ `ToolMemory`), controle de 3 botões na barra, `TextField.textAlign`, `align` no debug server; justificar fora do escopo.
- [x] **M8 — Editor: ícones homogêneos.** Uma única família de ícones, mesmo peso, grade e tamanho óptico, substituindo a mistura atual (Material + pintados à mão, ex.: `_CursorIcon`).
  - ✅ 2026-11-21 testado no macOS.
  - Decisão 2026-11-21: Phosphor **Regular** como padrão + opção "Ícones em negrito" (Phosphor Bold). Prévia aprovada: https://claude.ai/artifact/RAHtohWtmzvKs7izxXZiWF
  - Implementado em 2026-11-21, falta `flutter pub get`, compilar e testar visualmente: `lib/core/app_icons.dart` (`AppIcons` + tamanhos ópticos), `phosphor_flutter`, `AppSettings.boldIcons` (Configurações > Geral, debug `setting boldIcons`), editor/overlay/barra de título migrados; Home/Configurações seguem Material.

- [ ] **B1 — Distorção da janela ao abrir os menus suspensos das Configurações (Windows arm64, Radxa).** Acontece em todos os dropdowns, inclusive nos da 1.2.0. O menu "…" do editor (`PopupMenuButton`) não distorce. Tentei trocar o `_Dropdown` por `PopupMenuButton`, não resolveu e reverti. Suspeita: algo próprio da tela de Configurações (blur ou camadas) combinado com a GPU Adreno via ANGLE. Falta comparar com o x64 (Desktop). Adiado por decisão do Rafael. Confirmado de novo na 1.3.0 arm64 (2026-11-21); no macOS não acontece.

## Ordem de execução

C1 → M3 → M4 → M2 → M5 → M7 → M8 → M6 → M1.
M8 vem antes de M6/M1 para que as ferramentas novas já nasçam com os ícones novos.

## Modus operandi

- Orquestração, plano e revisão final: Claude (Opus, esforço médio), no servidor `wms-server-04`.
- Construção: agentes Sonnet. Validação: agentes Sonnet com checklist por item. O esforço de cada etapa é definido por item.
- Branch `release/1.3.0` a partir do `develop`, com um commit por item. Commit/push só quando o Rafael mandar, e sem PR a menos que ele peça.
- Devices em 2026-11-20: Mac livre; Radxa no Windows 11 arm64 com o Flutter recém-instalado (o Rafael está usando).

## Decisões (2026-11-20)

- C1: o Rafael instala com `winget install 9NX0J9N066SM` (fonte `msstore`, então é o MSIX da Store). Isso reforça a hipótese da chave Run vs. `startup_task`.
- M1: a seleção do crop funciona como a de área da tela (arrastar, alças), depois **confirma**. O corte é destrutivo na imagem base, as anotações são deslocadas e tudo tem **undo**.
- M4: o contador é **global** (não depende da pasta). O usuário define o prefixo (ex.: `ARQUIVO` → `ARQUIVO_01.png`). Opções extras a propor: separador, número de dígitos, botão para zerar o contador, prévia do próximo nome.
- M5: o **usuário escolhe** entre um arquivo por monitor e uma imagem única combinada.

## Extra (fora do código, opcional)

- Listagem no Winget: a fonte `msstore` mostra o ID da Store (`9NX0J9N066SM`) e versão "Unknown". Isso é o normal dessa fonte, não um erro de configuração da loja. Para aparecer como `RafaelWMS.ShowShot` com versão, é preciso publicar um manifesto no repositório comunitário `microsoft/winget-pkgs` (o `wingetcreate` ajuda). Isso exige um instalador baixável por URL pública (MSIX assinado ou exe).

## Fechamento da release

> Ordem de validação (2026-11-21), tudo nativo e uma de cada vez: 1. Mac DMG · 2. Mac App Store · 3. Windows arm64 (Radxa) · 4. Linux arm64 (Radxa) · 5. Linux x64 (Desktop) · 6. Windows x64 (Desktop).
>
> Progresso: ✅ 1. Mac DMG (notarizado, release em rascunho v1.3.0 no GitHub) · ✅ 2. Mac App Store (build 3 enviado) · ✅ 3. Windows arm64 (MSIX 1.3.0.0 de teste validado pelo Rafael; pacote da Store em `C:\projects\dist` na Radxa, aguardando o código final) · ✅ 4. Linux arm64 (Radxa, Ubuntu 26.10 Wayland: `showshot_1.3.0_arm64.deb` com lintian limpo, validado pelo Rafael, anexado à release em rascunho) · ✅ 5. Linux x64 (Desktop, Ubuntu 26.04.1 Wayland: `showshot_1.3.0_amd64.deb` com lintian limpo, validado pelo Rafael, anexado à release em rascunho) · ⏳ 6. Windows x64.
> Atenção: DMG, App Store build 3 e o MSIX arm64 são de antes do merge do `develop-linux` (correção das elipses no Linux). Se o código mudar de novo, regenerar todos no fim (App Store build 4).
>
> Regra combinada (2026-11-21): o merge no `main` só acontece depois de validar **todas** as plataformas e arquiteturas: macOS arm64, Windows x64, Windows arm64, Linux x64 e Linux arm64.

- [x] Subir versão: 1.3.0+3 (`pubspec.yaml`, `msix_version` 1.3.0.0, Xcode MARKETING/CURRENT_PROJECT_VERSION, Runner.rc, metainfo do Linux, tela Sobre, `make_dmg.sh`)
- [ ] `flutter analyze` limpo, `dart format`, `flutter test`
- [ ] Builds: macOS arm64 (Mac), Windows x64 (Desktop), Windows arm64 (Radxa), Linux x64 (Desktop), Linux arm64 (Radxa)
- [ ] Testes por plataforma via debug server; correção C1 validada via Winget

## Notas para o changelog

- Linux/Wayland: o novo atalho "Todas as telas" muda o conjunto de atalhos, então o GNOME ou o KDE vão pedir uma vez para confirmar os atalhos depois da atualização.
