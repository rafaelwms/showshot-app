#!/bin/bash
# =============================================================================
# dmg_layout.sh — cria o DMG do Show Shot com a janela "bonita": fundo com a
# seta, o app à esquerda e o atalho de Aplicativos à direita.
#
# Uso:  ./dmg_layout.sh <pasta_com_o_conteudo> <nome_do_volume> <saida.dmg>
#
# A pasta de conteúdo deve ter "Show Shot.app" e o link "Applications". O
# fundo (artwork/dmg/background.tiff, um TIFF com as versões 1x e 2x) é
# copiado para uma pasta oculta (.background) dentro do volume, e o Finder é
# instruído (AppleScript) a abrir a janela com o tamanho, o fundo e as
# posições dos ícones — isso fica gravado no .DS_Store do volume.
#
# Se o Finder não puder ser controlado (permissão de Automação negada), o DMG
# sai igual, só que sem o visual customizado (o script avisa).
# Usado por make_dmg.sh; pode ser rodado sozinho para testar o visual.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

STAGING="${1:?pasta de conteúdo}"; VOLNAME="${2:?nome do volume}"; OUT="${3:?saída .dmg}"
BACKGROUND="artwork/dmg/background.tiff"
APP_NAME="Show Shot.app"

# Janela em pontos (mesmo tamanho da arte 1x) e posição dos ícones: as pontas
# da seta desenhada no fundo ficam entre os dois centros (y = 215).
WIN_W=660; WIN_H=400; WIN_X=200; WIN_Y=120
ICON_SIZE=128; APP_X=165; APPS_X=495; ICON_Y=215

warn() { printf '\033[33m⚠\033[0m  %s\n' "$*"; }
quiet_hdiutil() { { hdiutil "$@" 2>&1 >/dev/null; } | { grep -v 'is deprecated' || true; } >&2; }

[[ -d "$STAGING/$APP_NAME" ]] || { echo "falta $APP_NAME em $STAGING" >&2; exit 1; }
[[ -f "$BACKGROUND" ]] || { echo "falta $BACKGROUND" >&2; exit 1; }
[[ ! -d "/Volumes/$VOLNAME" ]] || { echo "Já existe um volume '$VOLNAME' montado (ejete-o e tente de novo)." >&2; exit 1; }

WORK=$(mktemp -d)
RW="$WORK/rw.dmg"
cleanup() { hdiutil detach "/Volumes/$VOLNAME" -force >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT

mkdir -p "$STAGING/.background"
cp "$BACKGROUND" "$STAGING/.background/background.tiff"

# 1) imagem gravável com o conteúdo (folga de 20 MB para o Finder gravar o .DS_Store)
SIZE_MB=$(( $(du -sm "$STAGING" | cut -f1) + 20 ))
quiet_hdiutil create -volname "$VOLNAME" -srcfolder "$STAGING" -fs HFS+ -format UDRW -size "${SIZE_MB}m" -ov "$RW"

# 2) montar e pedir ao Finder o layout
quiet_hdiutil attach "$RW" -readwrite -noverify -noautoopen
sleep 1
if osascript >/dev/null 2>&1 <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {$WIN_X, $WIN_Y, $((WIN_X + WIN_W)), $((WIN_Y + WIN_H))}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to $ICON_SIZE
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "$APP_NAME" of container window to {$APP_X, $ICON_Y}
    set position of item "Applications" of container window to {$APPS_X, $ICON_Y}
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT
then
    sync; sleep 2   # dá tempo de o Finder gravar o .DS_Store
else
    warn "O Finder não pôde ser controlado: o DMG sai sem o fundo customizado."
    warn "Autorize em Ajustes do Sistema → Privacidade e Segurança → Automação (Terminal → Finder)."
fi

# 3) desmontar e comprimir na versão final (somente leitura)
quiet_hdiutil detach "/Volumes/$VOLNAME"
rm -f "$OUT"
quiet_hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT"
