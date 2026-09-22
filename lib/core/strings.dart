import 'dart:io';

import 'package:flutter/widgets.dart';

import '../models/app_settings.dart';
import '../models/capture_mode.dart';
import 'app_scope.dart';

/// UI strings. Resolved from [AppLanguage] (system locale by default).
abstract class Strings {
  const Strings();

  static Strings of(BuildContext context) {
    final language = AppScope.of(context).settings.settings.language;
    return forLanguage(language);
  }

  static Strings forLanguage(AppLanguage language) {
    switch (language) {
      case AppLanguage.portuguese:
        return const _Pt();
      case AppLanguage.english:
        return const _En();
      case AppLanguage.system:
        final locale = Platform.localeName.toLowerCase();
        return locale.startsWith('pt') ? const _Pt() : const _En();
    }
  }

  String get appName => 'Show Shot';
  String get tagline;

  // Capture modes
  String modeName(CaptureMode mode);
  String modeDescription(CaptureMode mode);

  // Home
  String get recentCaptures;
  String get noRecentCaptures;
  String get settings;
  String get runsInBackground;
  String get openFolder;
  String get removeFromList;
  String get permissionTitle;
  String get permissionBody;
  String get permissionOpenSettings;
  String get permissionRequest;
  String get quit;
  String get openApp;
  String get hideWindow;

  // Overlay
  String get hintDrag;
  String get hintClickWindow;
  String get hintEnter;
  String get hintEsc;
  String get hintSpace;
  String get edit;
  String get copy;
  String get save;
  String get cancel;
  String get capturing;
  String get captureFailed;
  String get extractText;
  String get textCopied;
  String get noTextFound;

  // Editor
  String get toolSelect;
  String get toolArrow;
  String get toolLine;
  String get toolRect;
  String get toolEllipse;
  String get toolPen;
  String get toolMarker;
  String get toolText;
  String get toolNumber;
  String get toolBlur;
  String get toolHand;
  String get color;
  String get strokeWidth;
  String get opacity;
  String get fill;
  String get fontSize;
  String get undo;
  String get redo;
  String get zoomIn;
  String get zoomOut;
  String get zoomFit;
  String get zoomActual;
  String get delete;
  String get clearAll;
  String get copyToClipboard;
  String get saveToFile;
  String get saveAs;
  String get discard;
  String get copied;
  String savedTo(String path);
  String get saveFailed;
  String get textPlaceholder;
  String get discardConfirmTitle;
  String get discardConfirmBody;
  String get keepEditing;
  String get editorTitle;

  // Settings
  String get sectionGeneral;
  String get sectionShortcuts;
  String get sectionSaving;
  String get sectionAbout;
  String get launchAtStartup;
  String get launchAtStartupHint;
  String get showDockIcon;
  String get showDockIconHint;
  String get language;
  String get languageSystem;
  String get languagePortuguese;
  String get languageEnglish;
  String get showMagnifier;
  String get showMagnifierHint;
  String get afterCapture;
  String get afterCaptureHint;
  String afterCaptureOption(AfterCaptureAction action);
  String get saveFormat;
  String get jpgQuality;
  String get saveDirectory;
  String get saveDirectoryDefault;
  String get chooseFolder;
  String get askWhereToSave;
  String get askWhereToSaveHint;
  String get copyAfterSave;
  String get copyAfterSaveHint;
  String get resetDefaults;
  String get recordShortcut;
  String get pressKeys;
  String get clearShortcut;
  String get shortcutsHint;
  String get shortcutRegisterFailed;
  String get version;
  String get website;
  String get madeBy;
  String get back;
  String get done;
  String get platformNotes;
  String get waylandWarning;
}

class _Pt extends Strings {
  const _Pt();

  @override
  String get tagline => 'Capture. Anote. Compartilhe.';

  @override
  String modeName(CaptureMode mode) => switch (mode) {
    CaptureMode.area => 'Área',
    CaptureMode.window => 'Janela',
    CaptureMode.fullScreen => 'Tela inteira',
    CaptureMode.text => 'Texto',
  };

  @override
  String modeDescription(CaptureMode mode) => switch (mode) {
    CaptureMode.area => 'Arraste para selecionar uma região da tela',
    CaptureMode.window => 'Clique em uma janela para capturá-la',
    CaptureMode.fullScreen => 'Captura o monitor sob o cursor',
    CaptureMode.text => 'Arraste para reconhecer o texto de uma região',
  };

  @override
  String get recentCaptures => 'Capturas recentes';
  @override
  String get noRecentCaptures => 'Suas capturas salvas aparecerão aqui.';
  @override
  String get settings => 'Configurações';
  @override
  String get runsInBackground =>
      'O Show Shot continua ativo na barra de menu. Use os atalhos a qualquer momento.';
  @override
  String get openFolder => 'Mostrar no Finder / pasta';
  @override
  String get removeFromList => 'Remover da lista';
  @override
  String get permissionTitle => 'Permissão de gravação de tela';
  @override
  String get permissionBody =>
      'O macOS exige permissão de "Gravação de Tela" para capturar screenshots. '
      'Depois de autorizar em Ajustes do Sistema, reinicie o Show Shot.';
  @override
  String get permissionOpenSettings => 'Abrir Ajustes do Sistema';
  @override
  String get permissionRequest => 'Solicitar permissão';
  @override
  String get quit => 'Sair do Show Shot';
  @override
  String get openApp => 'Abrir Show Shot';
  @override
  String get hideWindow => 'Ocultar janela';

  @override
  String get hintDrag => 'Arraste para selecionar uma área';
  @override
  String get hintClickWindow => 'Clique para capturar a janela';
  @override
  String get hintEnter => 'Enter confirma';
  @override
  String get hintSpace => 'Espaço captura a tela inteira';
  @override
  String get hintEsc => 'Esc cancela';
  @override
  String get edit => 'Editar';
  @override
  String get copy => 'Copiar';
  @override
  String get save => 'Salvar';
  @override
  String get cancel => 'Cancelar';
  @override
  String get capturing => 'Capturando…';
  @override
  String get captureFailed => 'Não foi possível capturar a tela.';
  @override
  String get extractText => 'Extrair texto';
  @override
  String get textCopied => 'Texto copiado';
  @override
  String get noTextFound => 'Nenhum texto encontrado';

  @override
  String get toolSelect => 'Selecionar';
  @override
  String get toolArrow => 'Seta';
  @override
  String get toolLine => 'Linha';
  @override
  String get toolRect => 'Retângulo';
  @override
  String get toolEllipse => 'Elipse';
  @override
  String get toolPen => 'Caneta';
  @override
  String get toolMarker => 'Marcador';
  @override
  String get toolText => 'Texto';
  @override
  String get toolNumber => 'Numeração';
  @override
  String get toolBlur => 'Desfoque';
  @override
  String get toolHand => 'Mover tela';
  @override
  String get color => 'Cor';
  @override
  String get strokeWidth => 'Espessura';
  @override
  String get opacity => 'Transparência';
  @override
  String get fill => 'Preenchido';
  @override
  String get fontSize => 'Tamanho do texto';
  @override
  String get undo => 'Desfazer';
  @override
  String get redo => 'Refazer';
  @override
  String get zoomIn => 'Aproximar';
  @override
  String get zoomOut => 'Afastar';
  @override
  String get zoomFit => 'Ajustar à janela';
  @override
  String get zoomActual => 'Tamanho real';
  @override
  String get delete => 'Excluir';
  @override
  String get clearAll => 'Limpar anotações';
  @override
  String get copyToClipboard => 'Copiar';
  @override
  String get saveToFile => 'Salvar';
  @override
  String get saveAs => 'Salvar como…';
  @override
  String get discard => 'Descartar';
  @override
  String get copied => 'Copiado para a área de transferência';
  @override
  String savedTo(String path) => 'Salvo em $path';
  @override
  String get saveFailed => 'Não foi possível salvar o arquivo.';
  @override
  String get textPlaceholder => 'Digite o texto…';
  @override
  String get discardConfirmTitle => 'Descartar captura?';
  @override
  String get discardConfirmBody => 'As anotações feitas serão perdidas.';
  @override
  String get keepEditing => 'Continuar editando';
  @override
  String get editorTitle => 'Editor';

  @override
  String get sectionGeneral => 'Geral';
  @override
  String get sectionShortcuts => 'Atalhos';
  @override
  String get sectionSaving => 'Salvamento';
  @override
  String get sectionAbout => 'Sobre';
  @override
  String get launchAtStartup => 'Iniciar com o sistema';
  @override
  String get launchAtStartupHint =>
      'Abre o Show Shot silenciosamente ao fazer login.';
  @override
  String get showDockIcon => 'Mostrar ícone no Dock';
  @override
  String get showDockIconHint =>
      'Por padrão o Show Shot vive apenas na barra de menu.';
  @override
  String get language => 'Idioma';
  @override
  String get languageSystem => 'Automático (sistema)';
  @override
  String get languagePortuguese => 'Português';
  @override
  String get languageEnglish => 'English';
  @override
  String get showMagnifier => 'Lupa de precisão';
  @override
  String get showMagnifierHint =>
      'Mostra uma lupa ao lado do cursor durante a seleção.';
  @override
  String get afterCapture => 'Ao confirmar com Enter';
  @override
  String get afterCaptureHint => 'O que fazer com a área selecionada.';
  @override
  String afterCaptureOption(AfterCaptureAction action) => switch (action) {
    AfterCaptureAction.openEditor => 'Abrir no editor',
    AfterCaptureAction.copyToClipboard => 'Copiar direto',
    AfterCaptureAction.saveToFile => 'Salvar direto',
  };
  @override
  String get saveFormat => 'Formato padrão';
  @override
  String get jpgQuality => 'Qualidade JPG';
  @override
  String get saveDirectory => 'Pasta de destino';
  @override
  String get saveDirectoryDefault => 'Imagens / ShowShot';
  @override
  String get chooseFolder => 'Escolher…';
  @override
  String get askWhereToSave => 'Perguntar onde salvar';
  @override
  String get askWhereToSaveHint =>
      'Desligado: salva direto na pasta de destino.';
  @override
  String get copyAfterSave => 'Copiar ao salvar';
  @override
  String get copyAfterSaveHint =>
      'Também coloca a imagem na área de transferência.';
  @override
  String get resetDefaults => 'Restaurar padrões';
  @override
  String get recordShortcut => 'Clique e pressione o atalho';
  @override
  String get pressKeys => 'Pressione as teclas…';
  @override
  String get clearShortcut => 'Remover atalho';
  @override
  String get shortcutsHint =>
      'Os atalhos funcionam globalmente, mesmo com o Show Shot em segundo plano.';
  @override
  String get shortcutRegisterFailed =>
      'Não foi possível registrar este atalho. Ele pode estar em uso por outro app.';
  @override
  String get version => 'Versão';
  @override
  String get website => 'showshot.rafaelwms.com';
  @override
  String get madeBy => 'Feito com Flutter por Rafael WMS';
  @override
  String get back => 'Voltar';
  @override
  String get done => 'Concluído';
  @override
  String get platformNotes => 'Notas da plataforma';
  @override
  String get waylandWarning =>
      'Sessão Wayland detectada: a captura usa ferramentas do sistema e a detecção de janelas fica indisponível.';
}

class _En extends Strings {
  const _En();

  @override
  String get tagline => 'Capture. Annotate. Share.';

  @override
  String modeName(CaptureMode mode) => switch (mode) {
    CaptureMode.area => 'Area',
    CaptureMode.window => 'Window',
    CaptureMode.fullScreen => 'Full screen',
    CaptureMode.text => 'Text',
  };

  @override
  String modeDescription(CaptureMode mode) => switch (mode) {
    CaptureMode.area => 'Drag to select a region of the screen',
    CaptureMode.window => 'Click a window to capture it',
    CaptureMode.text => 'Drag to recognize text in a region',
    CaptureMode.fullScreen => 'Captures the display under the cursor',
  };

  @override
  String get recentCaptures => 'Recent captures';
  @override
  String get noRecentCaptures => 'Your saved captures will show up here.';
  @override
  String get settings => 'Settings';
  @override
  String get runsInBackground =>
      'Show Shot keeps running in the menu bar / tray. Use the shortcuts any time.';
  @override
  String get openFolder => 'Reveal in folder';
  @override
  String get removeFromList => 'Remove from list';
  @override
  String get permissionTitle => 'Screen recording permission';
  @override
  String get permissionBody =>
      'macOS requires the "Screen Recording" permission to take screenshots. '
      'After granting it in System Settings, restart Show Shot.';
  @override
  String get permissionOpenSettings => 'Open System Settings';
  @override
  String get permissionRequest => 'Request permission';
  @override
  String get quit => 'Quit Show Shot';
  @override
  String get openApp => 'Open Show Shot';
  @override
  String get hideWindow => 'Hide window';

  @override
  String get hintDrag => 'Drag to select an area';
  @override
  String get hintClickWindow => 'Click to capture the window';
  @override
  String get hintEnter => 'Enter confirms';
  @override
  String get hintSpace => 'Space captures the whole screen';
  @override
  String get hintEsc => 'Esc cancels';
  @override
  String get edit => 'Edit';
  @override
  String get copy => 'Copy';
  @override
  String get save => 'Save';
  @override
  String get cancel => 'Cancel';
  @override
  String get capturing => 'Capturing…';
  @override
  String get captureFailed => 'Could not capture the screen.';
  @override
  String get extractText => 'Extract text';
  @override
  String get textCopied => 'Text copied';
  @override
  String get noTextFound => 'No text found';

  @override
  String get toolSelect => 'Select';
  @override
  String get toolArrow => 'Arrow';
  @override
  String get toolLine => 'Line';
  @override
  String get toolRect => 'Rectangle';
  @override
  String get toolEllipse => 'Ellipse';
  @override
  String get toolPen => 'Pen';
  @override
  String get toolMarker => 'Highlighter';
  @override
  String get toolText => 'Text';
  @override
  String get toolNumber => 'Numbered step';
  @override
  String get toolBlur => 'Blur';
  @override
  String get toolHand => 'Pan';
  @override
  String get color => 'Color';
  @override
  String get strokeWidth => 'Stroke width';
  @override
  String get opacity => 'Opacity';
  @override
  String get fill => 'Filled';
  @override
  String get fontSize => 'Font size';
  @override
  String get undo => 'Undo';
  @override
  String get redo => 'Redo';
  @override
  String get zoomIn => 'Zoom in';
  @override
  String get zoomOut => 'Zoom out';
  @override
  String get zoomFit => 'Fit to window';
  @override
  String get zoomActual => 'Actual size';
  @override
  String get delete => 'Delete';
  @override
  String get clearAll => 'Clear annotations';
  @override
  String get copyToClipboard => 'Copy';
  @override
  String get saveToFile => 'Save';
  @override
  String get saveAs => 'Save as…';
  @override
  String get discard => 'Discard';
  @override
  String get copied => 'Copied to clipboard';
  @override
  String savedTo(String path) => 'Saved to $path';
  @override
  String get saveFailed => 'Could not save the file.';
  @override
  String get textPlaceholder => 'Type your text…';
  @override
  String get discardConfirmTitle => 'Discard capture?';
  @override
  String get discardConfirmBody => 'Your annotations will be lost.';
  @override
  String get keepEditing => 'Keep editing';
  @override
  String get editorTitle => 'Editor';

  @override
  String get sectionGeneral => 'General';
  @override
  String get sectionShortcuts => 'Shortcuts';
  @override
  String get sectionSaving => 'Saving';
  @override
  String get sectionAbout => 'About';
  @override
  String get launchAtStartup => 'Launch at login';
  @override
  String get launchAtStartupHint =>
      'Starts Show Shot silently when you sign in.';
  @override
  String get showDockIcon => 'Show Dock icon';
  @override
  String get showDockIconHint =>
      'By default Show Shot lives only in the menu bar.';
  @override
  String get language => 'Language';
  @override
  String get languageSystem => 'Automatic (system)';
  @override
  String get languagePortuguese => 'Português';
  @override
  String get languageEnglish => 'English';
  @override
  String get showMagnifier => 'Precision magnifier';
  @override
  String get showMagnifierHint =>
      'Shows a loupe next to the cursor while selecting.';
  @override
  String get afterCapture => 'When confirming with Enter';
  @override
  String get afterCaptureHint => 'What to do with the selected area.';
  @override
  String afterCaptureOption(AfterCaptureAction action) => switch (action) {
    AfterCaptureAction.openEditor => 'Open in editor',
    AfterCaptureAction.copyToClipboard => 'Copy right away',
    AfterCaptureAction.saveToFile => 'Save right away',
  };
  @override
  String get saveFormat => 'Default format';
  @override
  String get jpgQuality => 'JPG quality';
  @override
  String get saveDirectory => 'Destination folder';
  @override
  String get saveDirectoryDefault => 'Pictures / ShowShot';
  @override
  String get chooseFolder => 'Choose…';
  @override
  String get askWhereToSave => 'Ask where to save';
  @override
  String get askWhereToSaveHint =>
      'Off: saves straight into the destination folder.';
  @override
  String get copyAfterSave => 'Copy when saving';
  @override
  String get copyAfterSaveHint => 'Also puts the image on the clipboard.';
  @override
  String get resetDefaults => 'Reset to defaults';
  @override
  String get recordShortcut => 'Click and press the shortcut';
  @override
  String get pressKeys => 'Press keys…';
  @override
  String get clearShortcut => 'Remove shortcut';
  @override
  String get shortcutsHint =>
      'Shortcuts work globally, even while Show Shot is in the background.';
  @override
  String get shortcutRegisterFailed =>
      'This shortcut could not be registered. Another app may already use it.';
  @override
  String get version => 'Version';
  @override
  String get website => 'showshot.rafaelwms.com';
  @override
  String get madeBy => 'Built with Flutter by Rafael WMS';
  @override
  String get back => 'Back';
  @override
  String get done => 'Done';
  @override
  String get platformNotes => 'Platform notes';
  @override
  String get waylandWarning =>
      'Wayland session detected: capture uses system tools and window detection is unavailable.';
}
