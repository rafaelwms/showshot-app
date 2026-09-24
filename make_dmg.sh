#!/bin/bash
# =============================================================================
# make_dmg.sh — gera o DMG do Show Shot para distribuição fora da App Store
# (download direto pelo site), assinado com Developer ID e notarizado pela Apple.
#
# Uso:   ./make_dmg.sh
# Guia:  MAKE_DMG.md (pré-requisitos, o que cada etapa faz, problemas comuns)
#
# O script é interativo: pergunta o que precisa e sugere valores padrão entre
# [colchetes] — é só apertar Enter para aceitar. Ele NUNCA pede nem guarda a sua
# senha: a notarização usa um perfil salvo no Keychain (criado na etapa 3, pelo
# próprio `notarytool`, que pede a senha de app diretamente a você).
# =============================================================================

set -euo pipefail # para no primeiro erro, em variável não definida ou em pipe quebrado

# ----------------------------------------------------------------------------
# Utilitários de saída e de pergunta
# ----------------------------------------------------------------------------
bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '   %s\n' "$*"; }
ok()   { printf '\033[32m✔\033[0m  %s\n' "$*"; }
warn() { printf '\033[33m⚠\033[0m  %s\n' "$*"; }
die()  { printf '\033[31m✖  %s\033[0m\n' "$*" >&2; exit 1; }
step() { echo; bold "▶ $*"; }

# ask "Pergunta" "padrão" → devolve a resposta (ou o padrão, se vazia)
ask() {
    local prompt="$1" default="${2:-}" answer
    if [[ -n "$default" ]]; then
        read -r -p "   $prompt [$default]: " answer
        echo "${answer:-$default}"
    else
        read -r -p "   $prompt: " answer
        echo "$answer"
    fi
}

# confirm "Pergunta" → sucesso só se a resposta for s/S
confirm() {
    local answer
    read -r -p "   $1 (s/N): " answer
    [[ "$answer" =~ ^[Ss]$ ]]
}

# Sempre roda a partir da pasta do projeto (onde este script está), para os
# caminhos padrão (pubspec.yaml, build/, dist/) funcionarem de qualquer lugar.
cd "$(dirname "$0")"

bold "Show Shot — gerador de DMG (Developer ID + notarização)"

# ----------------------------------------------------------------------------
# ETAPA 0 — Ferramentas necessárias
# Todas vêm com o Xcode / Command Line Tools; se faltar alguma, o resto não roda.
# ----------------------------------------------------------------------------
step "0. Verificando ferramentas"
for tool in xcrun codesign hdiutil spctl security shasum ditto; do
    command -v "$tool" >/dev/null || die "'$tool' não encontrado. Instale o Xcode (ou: xcode-select --install)."
done
xcrun --find notarytool >/dev/null 2>&1 || die "notarytool não encontrado. Atualize o Xcode (13+)."
xcrun --find stapler    >/dev/null 2>&1 || die "stapler não encontrado. Atualize o Xcode."
ok "Ferramentas ok"

# ----------------------------------------------------------------------------
# ETAPA 1 — Dados da conta Apple Developer
# Team ID: 10 caracteres (developer.apple.com → Membership). O padrão é lido
# do projeto Xcode, que já está configurado com a sua equipe.
# ----------------------------------------------------------------------------
step "1. Conta Apple Developer"
DEFAULT_TEAM=$(grep -m1 -o 'DEVELOPMENT_TEAM = [A-Z0-9]*' macos/Runner.xcodeproj/project.pbxproj 2>/dev/null | awk '{print $3}' || true)
TEAM_ID=$(ask "Team ID" "$DEFAULT_TEAM")
[[ "$TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || die "Team ID inválido: '$TEAM_ID' (esperado: 10 letras/números maiúsculos)."
APPLE_ID=$(ask "E-mail do Apple ID (conta de desenvolvedor)" "")
[[ "$APPLE_ID" == *@* ]] || die "E-mail inválido."

# ----------------------------------------------------------------------------
# ETAPA 2 — Certificado "Developer ID Application"
# É o certificado para distribuir FORA da App Store. O de "Apple Development"
# (desenvolvimento) e o de "Apple Distribution" (loja) não servem aqui: o
# Gatekeeper só aceita Developer ID em apps baixados da internet.
# ----------------------------------------------------------------------------
step "2. Certificado Developer ID Application"
IDENTITIES=$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep "($TEAM_ID)" || true)
if [[ -z "$IDENTITIES" ]]; then
    warn "Nenhum certificado 'Developer ID Application' da equipe $TEAM_ID no Keychain."
    info "Crie no Xcode: Settings → Accounts → sua equipe → Manage Certificates → + → Developer ID Application."
    info "(É preciso ser Account Holder da conta para criar esse tipo de certificado.)"
    die "Crie o certificado e rode o script de novo."
fi
# Nome completo da identidade, ex.: Developer ID Application: Fulano (GSWZYFM8C4)
SIGN_IDENTITY=$(sed -En '1s/.*"(.*)"/\1/p' <<< "$IDENTITIES")
ok "Usando: $SIGN_IDENTITY"

# ----------------------------------------------------------------------------
# ETAPA 3 — Perfil de notarização no Keychain
# O `notarytool` precisa de credenciais para enviar arquivos à Apple. Em vez de
# passar senha por linha de comando, salvamos um "perfil" no Keychain UMA vez.
# A senha pedida é uma *senha de app* (não a senha do Apple ID): gere em
# https://account.apple.com → Login e Segurança → Senhas de Apps.
# ----------------------------------------------------------------------------
step "3. Perfil de notarização"
PROFILE=$(ask "Nome do perfil no Keychain" "showshot-notary")
if xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    ok "Perfil '$PROFILE' encontrado"
else
    warn "Perfil '$PROFILE' ainda não existe (ou as credenciais expiraram)."
    if confirm "Criar agora? O notarytool vai pedir a senha de app"; then
        xcrun notarytool store-credentials "$PROFILE" --apple-id "$APPLE_ID" --team-id "$TEAM_ID" \
            || die "Não foi possível salvar o perfil. Confira e-mail, Team ID e a senha de app."
        ok "Perfil '$PROFILE' salvo no Keychain"
    else
        die "Sem perfil de notarização não dá para continuar."
    fi
fi

# ----------------------------------------------------------------------------
# ETAPA 4 — O app a empacotar
# Esperado: o "Show Shot.app" exportado pelo Xcode em
#   Product → Archive → Distribute App → Direct Distribution
# O Xcode já assina com Developer ID e notariza o .app nesse fluxo.
# (Um .app de `flutter build macos` NÃO serve direto: vem assinado com o
# certificado de desenvolvimento.)
# ----------------------------------------------------------------------------
step "4. App exportado pelo Xcode"
APP_PATH=$(ask "Caminho do 'Show Shot.app' exportado" "$HOME/Desktop/Show Shot.app")
APP_PATH="${APP_PATH/#\~/$HOME}"            # aceita ~/... digitado à mão
APP_PATH="${APP_PATH%/}"                    # tira a barra final, se houver
[[ -d "$APP_PATH" && "$APP_PATH" == *.app ]] || die "Não encontrei um .app em: $APP_PATH"

# 4a. A assinatura está íntegra? (arquivo alterado depois de assinado falha aqui)
codesign --verify --deep --strict "$APP_PATH" 2>/dev/null \
    || die "A assinatura do app está inválida ou ausente. Exporte de novo pelo Xcode."

# 4b. Foi assinado com Developer ID? (e não com o certificado de dev ou da loja)
# Guarda a saída inteira antes de filtrar: com `set -o pipefail`, um `grep -m1`
# que para de ler no meio derruba o script com SIGPIPE (erro "PIPE").
SIGN_INFO=$(codesign -dvv "$APP_PATH" 2>&1)
AUTHORITY=$(awk '/^Authority=/ {sub(/^Authority=/, ""); print; exit}' <<< "$SIGN_INFO")
[[ "$AUTHORITY" == "Developer ID Application"* ]] \
    || die "O app está assinado com '$AUTHORITY'. Exporte pelo Xcode com 'Direct Distribution'."

# 4c. O Gatekeeper aceita o app? (só passa se estiver notarizado)
if spctl --assess --type execute "$APP_PATH" 2>/dev/null; then
    ok "App assinado com Developer ID e notarizado"
else
    warn "O Gatekeeper ainda não aceita o app (ele não parece notarizado)."
    info "O DMG vai ser notarizado mesmo assim, e isso cobre o app que está dentro dele."
    confirm "Continuar?" || exit 1
fi

# ----------------------------------------------------------------------------
# ETAPA 5 — Versão e pasta de saída
# A versão padrão vem do app (CFBundleShortVersionString = "1.0.0" do pubspec).
# ----------------------------------------------------------------------------
step "5. Versão e destino"
APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "")
VERSION=$(ask "Versão (vai no nome do arquivo)" "${APP_VERSION:-1.0.0}")
OUT_DIR=$(ask "Pasta de saída" "$PWD/dist")
OUT_DIR="${OUT_DIR/#\~/$HOME}"
mkdir -p "$OUT_DIR"
DMG_PATH="$OUT_DIR/ShowShot-$VERSION.dmg"
VOLUME_NAME="Show Shot"

if [[ -e "$DMG_PATH" ]]; then
    confirm "Já existe $DMG_PATH. Substituir?" || exit 1
    rm -f "$DMG_PATH"
fi

# ----------------------------------------------------------------------------
# ETAPA 6 — Montar o conteúdo do DMG
# Numa pasta temporária: o app + um atalho para /Applications, para o usuário
# só arrastar um sobre o outro ao abrir o DMG. `ditto` copia preservando
# assinatura, atributos estendidos e links simbólicos do bundle (o `cp -R`
# comum pode estragar a assinatura).
# ----------------------------------------------------------------------------
step "6. Montando o conteúdo do DMG"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT              # apaga a pasta temporária ao sair, com erro ou não
ditto "$APP_PATH" "$STAGING/Show Shot.app"
ln -s /Applications "$STAGING/Applications"
ok "Conteúdo preparado"

# ----------------------------------------------------------------------------
# ETAPA 7 — Criar o DMG
# UDZO = imagem compactada (zlib), somente leitura — o formato padrão para
# distribuir apps. -ov sobrescreve; -srcfolder usa a pasta montada acima.
# ----------------------------------------------------------------------------
step "7. Criando o DMG"
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH" >/dev/null
ok "Criado: $DMG_PATH"

# ----------------------------------------------------------------------------
# ETAPA 8 — Assinar o DMG
# O app dentro já está assinado; assinar também o contêiner (o .dmg) é o que a
# Apple recomenda para distribuição direta. --timestamp adiciona o carimbo de
# data/hora seguro da Apple, exigido pela notarização.
# ----------------------------------------------------------------------------
step "8. Assinando o DMG"
codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
codesign --verify "$DMG_PATH"
ok "DMG assinado"

# ----------------------------------------------------------------------------
# ETAPA 9 — Notarizar
# Envia o DMG para a Apple, que verifica malware e assinaturas de tudo lá
# dentro. --wait espera o resultado (normalmente 1 a 10 minutos). Se for
# recusado, o log da Apple é mostrado com o motivo exato.
# ----------------------------------------------------------------------------
step "9. Notarizando (pode levar alguns minutos)"
SUBMIT_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" --keychain-profile "$PROFILE" --wait 2>&1) || true
echo "$SUBMIT_OUTPUT" | sed 's/^/   /'
if ! grep -q "status: Accepted" <<< "$SUBMIT_OUTPUT"; then
    SUBMISSION_ID=$(awk '/id: [0-9a-f-]+/ && !found {print $2; found=1}' <<< "$SUBMIT_OUTPUT")
    if [[ -n "$SUBMISSION_ID" ]]; then
        warn "Log da Apple para a submissão $SUBMISSION_ID:"
        xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$PROFILE" || true
    fi
    die "A notarização não foi aceita. Veja o log acima."
fi
ok "Notarização aceita"

# ----------------------------------------------------------------------------
# ETAPA 10 — "Grampear" o ticket
# Anexa o comprovante da notarização ao próprio DMG, para o Gatekeeper validar
# o arquivo mesmo sem internet no computador de quem baixou.
# ----------------------------------------------------------------------------
step "10. Grampeando o ticket de notarização"
xcrun stapler staple "$DMG_PATH" >/dev/null
xcrun stapler validate "$DMG_PATH" >/dev/null
ok "Ticket grampeado"

# ----------------------------------------------------------------------------
# ETAPA 11 — Conferência final, como o Gatekeeper do usuário vai fazer
# e o checksum SHA-256, bom de publicar junto do link de download.
# ----------------------------------------------------------------------------
step "11. Verificação final"
spctl --assess --type open --context context:primary-signature -v "$DMG_PATH" 2>&1 | sed 's/^/   /'
SHA=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
echo "$SHA  $(basename "$DMG_PATH")" > "$DMG_PATH.sha256"
SIZE=$(du -h "$DMG_PATH" | cut -f1)

echo
bold "✅ Pronto!"
info "Arquivo:  $DMG_PATH ($SIZE)"
info "SHA-256:  $SHA"
info "(salvo também em $(basename "$DMG_PATH").sha256)"
echo
info "Próximo passo: anexe o DMG a uma GitHub Release do app e aponte o botão"
info "do site para o link (ver MAKE_DMG.md → 'Publicando')."
