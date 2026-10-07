"""Génère cablage.svg : schéma de câblage du nœud Sentinel-X (ESP32).

Convention « étiquettes de net » : deux étiquettes de même nom sont reliées.
Source de vérité : firmware/include/config.h et firmware/README.md.

    python3 cablage.py   # écrit cablage.svg à côté de ce fichier
"""

from pathlib import Path

NETS = {
    "5V": "#c62828", "GND": "#37474f",
    "GPIO27": "#1565c0", "GPIO14": "#6a1b9a", "GPIO34": "#2e7d32",
    "GPIO26": "#00838f", "GPIO25": "#ad1457", "GPIO33": "#ef6c00",
}
W, H = 1000, 860
out = []


def text(x, y, s, size=13, anchor="start", weight="normal", color="#212121", italic=False):
    style = ' font-style="italic"' if italic else ""
    out.append(f'<text x="{x}" y="{y}" font-size="{size}" text-anchor="{anchor}" '
               f'font-weight="{weight}" fill="{color}"{style}>{s}</text>')


def line(x1, y1, x2, y2, color="#37474f", width=2):
    out.append(f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="{width}" stroke-linecap="round"/>')


def box(x, y, w, h, title, fill="#fafafa"):
    out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="8" fill="{fill}" stroke="#455a64" stroke-width="2"/>')
    text(x + w / 2, y + 22, title, 15, "middle", "bold")


def net(x, y, name, anchor="start"):
    """Étiquette de net ; anchor = côté où se raccorde le fil."""
    c = NETS[name]
    w = 14 + 8.5 * len(name)
    rx = x if anchor == "start" else x - w
    out.append(f'<rect x="{rx}" y="{y - 11}" width="{w}" height="22" rx="11" fill="{c}" fill-opacity="0.12" stroke="{c}" stroke-width="1.6"/>')
    text(rx + w / 2, y + 4.5, name, 12, "middle", "bold", c)
    return rx, w


def resistor_h(x1, x2, y, label, color):
    mid, half = (x1 + x2) / 2, 22
    line(x1, y, mid - half, y, color)
    out.append(f'<rect x="{mid - half}" y="{y - 7}" width="{2 * half}" height="14" rx="2" fill="#fff" stroke="{color}" stroke-width="2"/>')
    line(mid + half, y, x2, y, color)
    text(mid, y + 22, label, 11, "middle", color="#455a64")


def resistor_v(x, y1, y2, label, color):
    mid, half = (y1 + y2) / 2, 18
    line(x, y1, x, mid - half, color)
    out.append(f'<rect x="{x - 7}" y="{mid - half}" width="14" height="{2 * half}" rx="2" fill="#fff" stroke="{color}" stroke-width="2"/>')
    line(x, mid + half, x, y2, color)
    text(x + 12, mid + 4, label, 11, color="#455a64")


def led(x, y, color):
    """LED vers la droite : anode à gauche (x), cathode à droite (x + 26)."""
    out.append(f'<polygon points="{x},{y - 10} {x},{y + 10} {x + 18},{y}" fill="{color}" fill-opacity="0.25" stroke="{color}" stroke-width="2"/>')
    line(x + 18, y - 10, x + 18, y + 10, color)
    line(x + 18, y, x + 26, y, color)
    for dx in (4, 11):
        line(x + dx, y - 13, x + dx + 6, y - 21, color, 1.4)


# --- en-tête et légende -------------------------------------------------------
text(W / 2, 30, "Sentinel-X — câblage du nœud VIG1L-8-NODE04 (ESP32)", 18, "middle", "bold")
text(W / 2, 52, "Deux étiquettes de même nom sont reliées · GND commun à tous les composants · LED : patte longue (anode) côté résistance", 12, "middle", color="#546e7a", italic=True)

# --- ESP32 ----------------------------------------------------------------------
ex, ey, ew, eh = 40, 90, 250, 570
box(ex, ey, ew, eh, "ESP32 DevKit (esp32dev)", "#eceff1")
pins = [("VIN (5V)", "5V"), ("GND", "GND"), ("GPIO 14", "GPIO14"), ("GPIO 27", "GPIO27"),
        ("GPIO 26", "GPIO26"), ("GPIO 25", "GPIO25"), ("GPIO 33", "GPIO33"), ("GPIO 34 (ADC1)", "GPIO34")]
for i, (label, name) in enumerate(pins):
    y = ey + 70 + i * 52
    out.append(f'<circle cx="{ex + ew}" cy="{y}" r="4" fill="{NETS[name]}"/>')
    text(ex + ew - 12, y + 4, label, 13, "end", "bold")
    line(ex + ew, y, ex + ew + 40, y, NETS[name])
    net(ex + ew + 40, y, name)
text(ex + 16, ey + eh - 76, "Broches toutes du même côté de la carte", 11, color="#455a64")
text(ex + 16, ey + eh - 58, "LED intégrée : GPIO 2 (suit le PIR)", 11, color="#455a64")
text(ex + 16, ey + eh - 40, "USB : alimentation 5 V + programmation", 11, color="#455a64")
text(ex + 16, ey + eh - 22, "Wi-Fi 2,4 GHz → hotspot 192.168.10.0/24", 11, color="#455a64")

# --- composants (à droite) -------------------------------------------------------
cx, cw = 640, 320


def component(y, h, title, pin_list, notes):
    box(cx, y, cw, h, title)
    for i, (label, name) in enumerate(pin_list):
        py = y + 46 + i * 30
        out.append(f'<circle cx="{cx}" cy="{py}" r="4" fill="{NETS[name]}"/>')
        text(cx + 12, py + 4, label, 12, weight="bold")
        line(cx - 36, py, cx, py, NETS[name])
        net(cx - 36, py, name, "end")
    for i, n in enumerate(notes):
        text(cx + 120, y + 46 + i * 18, n, 11, color="#546e7a")


component(80, 130, "DHT22 — température / humidité",
          [("VCC", "GPIO33"), ("DATA", "GPIO27"), ("GND", "GND")],
          ["Alimenté par GPIO 33 (3,3 V,", "~1,5 mA) : redémarrable", "par le firmware. Capteur nu :", "pull-up 10 kΩ DATA → VCC."])

component(230, 130, "HC-SR501 — présence (PIR)",
          [("VCC", "5V"), ("OUT", "GPIO14"), ("GND", "GND")],
          ["Sortie 3,3 V, alimentation 5 V.", "Cavalier sur H (re-déclenchable),", "potentiomètre Tx au minimum.", "Préchauffage : 30 s."])

# MQ-2 : AO passe par un pont diviseur avant GPIO 34
my = 380
box(cx, my, cw, 150, "MQ-2 — gaz / fumées")
for i, (label, name) in enumerate([("VCC", "5V"), ("GND", "GND")]):
    py = my + 46 + i * 30
    out.append(f'<circle cx="{cx}" cy="{py}" r="4" fill="{NETS[name]}"/>')
    text(cx + 12, py + 4, label, 12, weight="bold")
    line(cx - 36, py, cx, py, NETS[name])
    net(cx - 36, py, name, "end")
ao_y = my + 106
out.append(f'<circle cx="{cx}" cy="{ao_y}" r="4" fill="{NETS["GPIO34"]}"/>')
text(cx + 12, ao_y + 4, "AO", 12, weight="bold")
text(cx + 120, my + 46, "Chauffe 5 V (~150 mA) :", 11, color="#546e7a")
text(cx + 120, my + 64, "préchauffage 3 min.", 11, color="#546e7a")
text(cx + 120, my + 82, "AO jusqu'à 5 V → pont", 11, color="#546e7a")
text(cx + 120, my + 100, "diviseur 10k + 2×10k (→ 3,33 V).", 11, color="#546e7a")
text(cx + 120, my + 118, "DO non connecté (seuil fixe).", 11, color="#546e7a")
node_x = cx - 120
resistor_h(cx, node_x, ao_y, "10 kΩ", NETS["GPIO34"])
out.append(f'<circle cx="{node_x}" cy="{ao_y}" r="4" fill="{NETS["GPIO34"]}"/>')
line(node_x, ao_y, node_x - 30, ao_y, NETS["GPIO34"])
net(node_x - 30, ao_y, "GPIO34", "end")
resistor_v(node_x, ao_y, ao_y + 92, "2 × 10 kΩ", NETS["GND"])
net(node_x - 26, ao_y + 104, "GND")

# LED (GPIO → 220 Ω → anode, cathode → GND)
for i, (name, title, color) in enumerate([("GPIO25", "LED mouvement (suit le PIR)", "#ad1457"),
                                          ("GPIO26", "LED environnement (plafond local / alerte IA)", "#00838f")]):
    ly = 700 + i * 72
    text(cx - 250, ly - 22, title, 13, weight="bold")
    _, lw = net(cx - 250, ly, name)
    x0 = cx - 250 + lw
    resistor_h(x0, x0 + 90, ly, "220 Ω*", NETS[name])
    led(x0 + 90, ly, color)
    line(x0 + 116, ly, x0 + 150, ly, NETS["GND"])
    net(x0 + 150, ly, "GND")
    text(x0 + 220, ly + 4, "fixe : plafond local · clignotante : alerte IA" if name == "GPIO26" else "allumée pendant une détection", 11, color="#546e7a")

text(cx - 250, 830, "* 10 kΩ sur le prototype (seule valeur disponible) : LED peu lumineuses", 11, color="#546e7a", italic=True)

svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" '
       f'font-family="DejaVu Sans, Arial, sans-serif">\n<rect width="{W}" height="{H}" fill="#ffffff"/>\n'
       + "\n".join(out) + "\n</svg>\n")
Path(__file__).with_name("cablage.svg").write_text(svg, encoding="utf-8")
print("cablage.svg écrit")
