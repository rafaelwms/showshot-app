# Show Shot — DMG para download direto (fora da App Store)

Guia para gerar o `ShowShot-<versão>.dmg` que vai no site, ao lado da versão da
Mac App Store. O trabalho pesado fica com o [`make_dmg.sh`](make_dmg.sh), que é
interativo e comentado passo a passo. Este documento explica o que precisa estar
pronto antes e o porquê de cada etapa.

## Por que assinar e notarizar

Um app baixado da internet só abre sem o aviso "não pode ser aberto porque a Apple
não pode verificar…" se estiver:

1. **Assinado com Developer ID:** o certificado próprio para distribuição fora da
   loja. O certificado de *Apple Development* e o da App Store não servem.
2. **Notarizado:** a Apple verifica o arquivo automaticamente (malware, assinatura,
   hardened runtime) e emite um "ticket".
3. **Grampeado (stapled):** o ticket fica anexado ao DMG, e o Gatekeeper consegue
   validá-lo até sem internet.

A conta Apple Developer paga já inclui tudo isso, sem custo extra.

## Pode gerar antes da revisão da App Store?

**Pode.** A revisão da loja e a notarização são independentes:

| | Revisão da App Store | Notarização (DMG) |
| --- | --- | --- |
| Quem faz | Pessoas da Apple | Verificação automática |
| Vale para | O que é distribuído pela loja | Apps distribuídos fora da loja |
| Tempo | Horas a dias | Normalmente 1 a 10 minutos |

Cuidados:

- **Mesmo código nas duas versões:** use a mesma versão/build. Se a revisão pedir
  mudanças, gere um DMG novo depois.
- **Um Archive exportado de dois jeitos:** o envio para a loja usa o certificado
  da App Store; o DMG precisa de **Direct Distribution**. Dá para usar o mesmo
  Archive e escolher a outra opção em *Distribute App*.
- **Mesmo bundle id** (`com.rafaelwms.showshot`) nas duas versões: quem instalar
  pelo DMG e depois pela loja pode ver um aviso de que o app já existe. Basta
  apagar o app e instalar de novo. É normal e não afeta a revisão.

## Pré-requisitos (uma vez só)

### 1. Certificado Developer ID Application

No Xcode: **Settings → Accounts →** sua equipe **→ Manage Certificates → + →
Developer ID Application.** Só o *Account Holder* da conta pode criar esse tipo
de certificado.

Para conferir se ele está no Keychain:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

### 2. Senha de app para a notarização

O `notarytool` não aceita a senha normal do Apple ID. Gere uma **senha de app** em
<https://account.apple.com> → *Login e Segurança* → *Senhas de Apps*. Na primeira
execução, o script oferece salvar essa credencial num perfil do Keychain
(`showshot-notary`), e o próprio `notarytool` pede a senha. O script nunca vê nem
grava a senha.

### 3. Dados à mão

| Pergunta do script | Onde encontrar | Padrão |
| --- | --- | --- |
| Team ID | developer.apple.com → Membership | lido do projeto Xcode (`GSWZYFM8C4`) |
| E-mail do Apple ID | o e-mail da conta de desenvolvedor | — |
| Nome do perfil | qualquer nome; fica no Keychain | `showshot-notary` |
| Caminho do `.app` | onde o Xcode exportou (passo abaixo) | `~/Desktop/Show Shot.app` |
| Versão | lida do próprio app | `1.0.0` |
| Pasta de saída | onde o DMG vai ficar | `dist/` (fora do git) |

## Gerando uma versão

1. **Build:** `flutter build macos --release`, para garantir que o Xcode arquive o
   código atual.
2. **Archive:** abra `macos/Runner.xcworkspace` → **Product → Archive**.
3. **Exportar:** no Organizer, clique em **Distribute App → Direct Distribution**.
   O Xcode assina com Developer ID, envia o app para notarização e exporta o
   `Show Shot.app` já notarizado. Salve-o, por exemplo, na Mesa.
4. **DMG:** rode o script na pasta `app-shoshot`:

   ```bash
   ./make_dmg.sh
   ```

   Ele monta o DMG (o app + um atalho para Aplicativos), assina, notariza e grampeia
   o DMG, confere tudo com o Gatekeeper e gera o SHA-256.

O resultado fica em `dist/ShowShot-<versão>.dmg`, junto com um arquivo `.sha256`.

### O que o script faz, etapa por etapa

| Etapa | O quê | Por quê |
| --- | --- | --- |
| 0 | Confere as ferramentas (`codesign`, `hdiutil`, `notarytool`…) | Vêm com o Xcode; sem elas nada funciona |
| 1 | Pergunta Team ID e e-mail | Identificam a conta na assinatura e na notarização |
| 2 | Procura o certificado Developer ID | Só ele é aceito pelo Gatekeeper em downloads |
| 3 | Confere ou cria o perfil de notarização | Credencial guardada no Keychain, sem senha no script |
| 4 | Valida o `.app`: assinatura íntegra, Developer ID, notarizado | Pega um app exportado do jeito errado antes de perder tempo |
| 5 | Versão e pasta de saída | Nome do arquivo: `ShowShot-1.0.0.dmg` |
| 6 | Monta o conteúdo com `ditto` + atalho `/Applications` | O `ditto` preserva a assinatura do bundle |
| 7 | Cria a imagem (`hdiutil`, formato UDZO compactado) | Formato padrão de distribuição |
| 8 | Assina o DMG com `--timestamp` | A Apple recomenda assinar o contêiner; a notarização exige o timestamp |
| 9 | Envia para notarização e espera | Se recusar, mostra o log da Apple com o motivo |
| 10 | Grampeia o ticket no DMG | Validação funciona offline |
| 11 | Verificação com `spctl` + SHA-256 | Confere como o Gatekeeper do usuário vai conferir |

## Publicando

- **Hospedagem:** anexe o DMG a uma **GitHub Release** do repositório do app (por
  exemplo, a tag `v1.0.0`). Não coloque o arquivo na imagem Docker do site, porque
  cada deploy ficaria cerca de 25 MB maior.
- **Site:** o card do macOS em `site-showshot/src/pages/*/download.html` hoje mostra
  só a Mac App Store. Adicione um botão "Baixar DMG" apontando para o link da
  Release e, se quiser, mostre o SHA-256 ao lado. Ajuste também o texto do topo da
  página, que diz que no Mac o app vem da loja oficial.
- **Atualizações:** quem instala pelo DMG **não recebe atualização automática**. O
  caminho padrão para isso é o framework [Sparkle](https://sparkle-project.org),
  que pede um pouco de código no app e um arquivo de feed no site.

## Problemas comuns

| Sintoma | Causa provável / solução |
| --- | --- |
| Etapa 2: "Nenhum certificado Developer ID" | Crie o certificado (pré-requisito 1). |
| Etapa 3: falha ao salvar o perfil | Use a **senha de app**, não a senha do Apple ID; confira o Team ID. |
| Etapa 4: "assinado com Apple Development" | O `.app` veio do `flutter build` ou foi exportado errado. Exporte pelo Xcode com **Direct Distribution**. |
| Etapa 4: assinatura inválida | O `.app` foi alterado depois de assinado (ou copiado com `cp`). Exporte de novo. |
| Etapa 9: "Invalid" | O log mostra o arquivo exato. Os motivos mais comuns são binário sem *hardened runtime* ou sem timestamp; exportar pelo Xcode resolve os dois. |
| Xcode: "Hardened Runtime is Not Enabled" | `ENABLE_HARDENED_RUNTIME = YES` precisa estar nas configurações do target Runner (`macos/Runner.xcodeproj/project.pbxproj`) — já está, desde 2026-09-24. Se voltar, confira se um merge não removeu. |
| Aviso `hdiutil … is deprecated` | Só um aviso do macOS 27. O `hdiutil` continua funcionando. |
