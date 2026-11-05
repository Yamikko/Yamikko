#!/usr/bin/env bash
# Rend des aperçus PNG des bornes hors de Studio.
# usage : tools/preview.sh <dossier node_modules (three, fengari)> <dossier de sortie> [vues séparées par des virgules] [fxTime]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
nm="$1"; out="$2"; views="${3:-}"; t="${4:-0.3}"
mkdir -p "$out"
export NODE_PATH="$nm:$(npm root -g)"
node "$here/run.js" "$t" "$out/scene.json"
node "$here/render.js" "$out/scene.json" "$out" "$nm" "$views"
