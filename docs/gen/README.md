# Rapport d'ingénierie technique

Source of the deliverable [`../Workshop2026-M1-G04-Dossier.pdf`](../Workshop2026-M1-G04-Dossier.pdf) (in French): network diagram, wiring diagram, security matrix, AI documentation.

```bash
./build.sh        # -> docs/Workshop2026-M1-G04-Dossier.pdf (group 04)
```

Needs Docker and Python 3. The `minlag/mermaid-cli` image renders the diagrams and its Chromium prints the PDF into `docs/`. Commit the regenerated PDF with the source changes.

| File | Content |
|---|---|
| `rapport.html` | the report text |
| `style.css` | A4 print layout |
| `diagrammes/*.mmd` | Mermaid sources: network, infrastructure, sequence diagrams |
| `images/` | screenshots used in the report |
| `diagrammes/cablage.py` | generates the wiring diagram `cablage.svg` (pins from `firmware/include/config.h`) |
| `pdf.js` | prints `rapport.html` to PDF (run by `build.sh`) |

