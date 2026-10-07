# Rapport d'ingénierie technique

Source of the deliverable [`../Workshop2026-M1-Gn-Dossier.pdf`](../Workshop2026-M1-Gn-Dossier.pdf) (`Gn` until the group number is known) (in French): network diagram, wiring diagram, security matrix, AI documentation, post-pentest audit.

```bash
./build.sh        # -> docs/Workshop2026-M1-Gn-Dossier.pdf
./build.sh 3      # -> docs/Workshop2026-M1-G3-Dossier.pdf
```

Needs Docker and Python 3. The `minlag/mermaid-cli` image renders the diagrams and its Chromium prints the PDF into `docs/`. Commit the regenerated PDF with the source changes.

| File | Content |
|---|---|
| `rapport.html` | the report text |
| `style.css` | A4 print layout |
| `diagrammes/*.mmd` | Mermaid sources: network, infrastructure, sequence diagrams |
| `diagrammes/cablage.py` | generates the wiring diagram `cablage.svg` (pins from `firmware/include/config.h`) |
| `pdf.js` | prints `rapport.html` to PDF (run by `build.sh`) |

Boxes marked **À COMPLÉTER** (`class="a-completer"`, `class="tbd"`) are placeholders: group number, team, measurements on the Raspberry Pi, pentest results.
