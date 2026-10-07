#!/usr/bin/env bash
# Génère les diagrammes puis le PDF du rapport : docs/Workshop2026-M1-GXX-Dossier.pdf
# Prérequis : Docker, Python 3.   Usage : ./build.sh [numéro de groupe]
set -euo pipefail
cd "$(dirname "$0")"
GROUPE="${1:-XX}"   # XX en attendant le numéro de groupe
IMAGE=minlag/mermaid-cli
# docs/ est monté sur /data : sources dans /data/gen, PDF écrit dans /data
RUN=(docker run --rm -u "$(id -u):$(id -g)" -v "$(cd .. && pwd):/data")

for f in diagrammes/*.mmd; do
  "${RUN[@]}" "$IMAGE" -q -i "/data/gen/$f" -o "/data/gen/${f%.mmd}.svg" -b white -c /data/gen/diagrammes/mermaid-config.json
done
python3 diagrammes/cablage.py

"${RUN[@]}" -e NODE_PATH=/home/mermaidcli/node_modules --entrypoint node "$IMAGE" \
  /data/gen/pdf.js /data/gen/rapport.html "/data/Workshop2026-M1-G${GROUPE}-Dossier.pdf"
