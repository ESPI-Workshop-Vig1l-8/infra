#!/usr/bin/env bash
# Génère les diagrammes puis le PDF du rapport : build/Workshop2026-M1-G<n>-Dossier.pdf
# Prérequis : Docker, Python 3.   Usage : ./build.sh [numéro de groupe]
set -euo pipefail
cd "$(dirname "$0")"
GROUPE="${1:-<n>}"
IMAGE=minlag/mermaid-cli
RUN=(docker run --rm -u "$(id -u):$(id -g)" -v "$PWD:/data")

for f in diagrammes/*.mmd; do
  "${RUN[@]}" "$IMAGE" -q -i "/data/$f" -o "/data/${f%.mmd}.svg" -b white -c /data/diagrammes/mermaid-config.json
done
python3 diagrammes/cablage.py

mkdir -p build
OUT="build/Workshop2026-M1-G${GROUPE}-Dossier.pdf"
"${RUN[@]}" -e NODE_PATH=/home/mermaidcli/node_modules --entrypoint node "$IMAGE" \
  /data/pdf.js /data/rapport.html "/data/$OUT"
