#!/bin/sh
# Rebuild the compiled JSON-IR map artifact from a maps checkout.
#
# Usage: scripts/build_maps_ir.sh <maps-repo> <interscript-ts-repo> <out-dir>
#
# Mirrors the maps repo's CI job (map-artifact.yml): builds the TS
# converter in place and drives scripts/build-json-ir-artifact.mjs.
# The canonical distribution channel remains GitHub Releases — this
# script is for local development and for regenerating the bundled
# test subset.

set -eu
MAPS=${1:-"$(dirname "$0")/../../../maps"}
TS=${2:-"$(dirname "$0")/../../../interscript-ts"}
OUT=${3:-/tmp/isir}

cd "$TS"
if [ ! -d node_modules ]; then
  npm ci
fi
npm run build

npx -y tsx "$MAPS/scripts/build-json-ir-artifact.mjs" "$TS" "$OUT"
echo "artifact ready: $OUT"
