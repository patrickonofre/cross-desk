#!/bin/bash
# sparkle-sign-release.sh — assina o zip de uma release com a chave EdDSA do
# Sparkle e imprime o <item> pronto pra colar em docs/appcast.xml.
#
# Pré-requisito: a chave privada já existe no Keychain, conta "cross-desk"
# (rodar `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account
# cross-desk` uma vez — exclusiva deste app, separada da conta padrão usada
# por outros projetos na mesma máquina). O comando nunca imprime a chave
# privada, só a pública — é seguro rodar mesmo via agente, desde que com
# confirmação explícita do dono da chave.
#
# Uso:
#   macos/Scripts/sparkle-sign-release.sh <caminho-do-zip> <versão-curta> <build>
# Exemplo:
#   macos/Scripts/sparkle-sign-release.sh build/CrossDesk.zip 1.2.0 21
set -euo pipefail

ZIP="${1:-}"
SHORT_VERSION="${2:-}"
BUILD="${3:-}"

if [[ -z "$ZIP" || -z "$SHORT_VERSION" || -z "$BUILD" || ! -f "$ZIP" ]]; then
    echo "uso: $0 <caminho-do-zip> <versão-curta> <build>" >&2
    exit 2
fi

cd "$(dirname "$0")/../CrossDeskKit"
SIGN_TOOL=".build/artifacts/sparkle/Sparkle/bin/sign_update"
if [[ ! -x "$SIGN_TOOL" ]]; then
    echo "error: $SIGN_TOOL não encontrado — rode 'swift package resolve' primeiro." >&2
    exit 1
fi

# sign_update's own stdout already includes both edSignature and length
# attributes (e.g. `sparkle:edSignature="..." length="..."`) — don't add a
# second length= or the appcast item ends up with a duplicate attribute.
SIGNATURE_LINE="$("$SIGN_TOOL" --account cross-desk "$OLDPWD/$ZIP")"
PUB_DATE=$(date -R)

cat <<ITEM

Cole este <item> dentro de <channel> em docs/appcast.xml (mais novo primeiro):

        <item>
            <title>$SHORT_VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$BUILD</sparkle:version>
            <sparkle:shortVersionString>$SHORT_VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure
                url="https://github.com/patrickonofre/cross-desk/releases/download/v$SHORT_VERSION/CrossDesk.zip"
                $SIGNATURE_LINE
                type="application/octet-stream" />
        </item>
ITEM
