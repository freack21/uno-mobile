#!/usr/bin/env bash
# Builds the installable, offline-capable web app (PWA) into build/web.
# Usage: tool/build_web.sh [base-href]   e.g. tool/build_web.sh /uno-mobile/
set -euo pipefail
cd "$(dirname "$0")/.."

BASE_HREF="${1:-/}"
flutter build web --release \
  --no-web-resources-cdn \
  --web-content-hash \
  --base-href "$BASE_HREF"

# Stamp the service worker so each build is detected as an update.
VERSION="$(sha256sum build/web/precache_manifest.json | cut -c1-12)"
sed -i "s/__BUILD_VERSION__/${VERSION}/" build/web/sw.js
echo "Built PWA ${VERSION} (base href ${BASE_HREF})"
