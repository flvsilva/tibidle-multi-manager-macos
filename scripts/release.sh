#!/bin/zsh
# Publishes a GitHub release: ./scripts/release.sh 1.0.0
# Builds the app with that version, tags vVERSION on the pushed main and uploads the DMG and the ZIP.
set -euo pipefail
cd "${0:a:h}/.."

VERSION="${1:?uso: scripts/release.sh VERSAO (ex.: 1.0.0)}"
TAG="v$VERSION"

[ -z "$(git status --porcelain)" ] || { echo "Há mudanças sem commit." >&2; exit 1; }
git fetch -q origin
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "HEAD difere de origin/main: faça o push antes." >&2; exit 1; }
! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || { echo "A tag $TAG já existe." >&2; exit 1; }

swift test
VERSION="$VERSION" ./scripts/build-app.sh

NOTES="$(mktemp)"
trap 'rm -f "$NOTES"' EXIT
cat > "$NOTES" <<NOTES
## Instalar

1. Baixe **TibidleMultiManager-macOS.dmg** (abaixo, em *Assets*), abra e arraste **Tibidle Multi-Manager** para **Aplicativos**.
2. Abra o app. Na primeira vez o macOS avisa que não pode verificar o desenvolvedor (o app não tem assinatura da Apple): clique em **OK**, vá em **Ajustes do Sistema → Privacidade e Segurança**, role até o aviso do Tibidle Multi-Manager e clique em **Abrir Mesmo Assim**.
   Alternativa pelo Terminal: \`xattr -dr com.apple.quarantine "/Applications/Tibidle Multi-Manager.app"\`.

Requer macOS 14 Sonoma ou mais recente (Apple Silicon ou Intel). O ZIP tem o mesmo app, para quem preferir.
NOTES

git tag -a "$TAG" -m "Tibidle Multi-Manager $VERSION"
git push -q origin "$TAG"
gh release create "$TAG" dist/TibidleMultiManager-macOS.dmg dist/TibidleMultiManager-macOS.zip \
  --title "Tibidle Multi-Manager $VERSION" --notes-file "$NOTES" --latest
