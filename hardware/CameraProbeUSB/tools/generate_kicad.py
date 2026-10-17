#!/usr/bin/env python3
"""
Generates the KiCad files for the CameraProbe USB relay board (Rev A)
from the circuit description below - the single source of truth that
mirrors DESIGN.md.

Outputs (in the parent folder):
  CameraProbeUSB.kicad_sch   schematic (KiCad 8 format; opens in 8 and 9)
  CameraProbeUSB.kicad_pro   minimal project file
  CameraProbeUSB.net         netlist (backup: PCB editor > File > Import > Netlist)

Symbols are simple labelled boxes defined inside the schematic, and every
pin is connected with a net label, so no external symbol libraries are
needed. Re-run after editing CIRCUIT:  python3 tools/generate_kicad.py
"""

import os
import uuid

PROJECT = "CameraProbeUSB"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.dirname(HERE)

G = 2.54  # grid

# Footprints (KiCad standard libraries). USB connectors are left blank on
# purpose: assign them once you have the actual parts (see README).
FP_R = "Resistor_SMD:R_0805_2012Metric_Pad1.20x1.40mm_HandSolder"
FP_C = "Capacitor_SMD:C_0805_2012Metric_Pad1.18x1.45mm_HandSolder"
FP_CT = "Capacitor_Tantalum_SMD:CP_EIA-3216-18_Kemet-A_Pad1.58x1.35mm_HandSolder"
FP_LED = "LED_SMD:LED_0805_2012Metric_Pad1.15x1.40mm_HandSolder"
FP_FUSE = "Fuse:Fuse_1812_4532Metric"
FP_SOT23 = "Package_TO_SOT_SMD:SOT-23"
FP_SOT223 = "Package_TO_SOT_SMD:SOT-223-3_TabPin2"
FP_SOIC16 = "Package_SO:SOIC-16_3.9x9.9mm_P1.27mm"
FP_ESP = "RF_Module:ESP-12E"
FP_SW = "Button_Switch_THT:SW_PUSH_6mm"
FP_TP = "TestPoint:TestPoint_Pad_D1.5mm"

NC = None  # no-connect

# ---------------------------------------------------------------------------
# Symbol types: name -> (box width, [(pin, name, side)])  side: L or R
# ---------------------------------------------------------------------------
TWO = lambda a, b: [("1", a, "L"), ("2", b, "R")]
SYMBOLS = {
    "R":     (5.08, TWO("~", "~")),
    "C":     (5.08, TWO("~", "~")),
    "CP":    (5.08, TWO("+", "-")),
    "LED":   (5.08, [("2", "A", "L"), ("1", "K", "R")]),
    "Fuse":  (5.08, TWO("~", "~")),
    "SW":    (5.08, TWO("~", "~")),
    "TP":    (5.08, [("1", "TP", "L")]),
    "NPN":   (7.62, [("1", "B", "L"), ("3", "C", "R"), ("2", "E", "R")]),
    "NMOS":  (7.62, [("1", "G", "L"), ("3", "D", "R"), ("2", "S", "R")]),
    "PMOS":  (7.62, [("1", "G", "L"), ("2", "S", "R"), ("3", "D", "R")]),
    "AMS1117": (12.7, [("3", "VIN", "L"), ("2", "VOUT", "R"), ("1", "GND", "R")]),
    "USB_A": (12.7, [("1", "VBUS", "R"), ("2", "D-", "R"), ("3", "D+", "R"),
                     ("4", "GND", "R"), ("5", "SHIELD", "R")]),
    "CH340C": (17.78, [("5", "UD+", "L"), ("6", "UD-", "L"), ("16", "VCC", "L"),
                       ("4", "V3", "L"), ("1", "GND", "L"), ("7", "NC", "L"),
                       ("8", "NC", "L"), ("15", "R232", "L"),
                       ("2", "TXD", "R"), ("3", "RXD", "R"), ("13", "DTR#", "R"),
                       ("14", "RTS#", "R"), ("9", "CTS#", "R"), ("10", "DSR#", "R"),
                       ("11", "RI#", "R"), ("12", "DCD#", "R")]),
    "ESP12F": (20.32, [("8", "VCC", "L"), ("15", "GND", "L"), ("3", "EN", "L"),
                       ("1", "RST", "L"), ("2", "ADC", "L"), ("4", "GPIO16", "L"),
                       ("5", "GPIO14", "L"), ("6", "GPIO12", "L"), ("7", "GPIO13", "L"),
                       ("9", "CS0", "L"), ("10", "MISO", "L"),
                       ("18", "GPIO0", "R"), ("17", "GPIO2", "R"), ("16", "GPIO15", "R"),
                       ("19", "GPIO4", "R"), ("20", "GPIO5", "R"), ("21", "RXD", "R"),
                       ("22", "TXD", "R"), ("11", "GPIO9", "R"), ("12", "GPIO10", "R"),
                       ("13", "MOSI", "R"), ("14", "SCLK", "R")]),
}

# ---------------------------------------------------------------------------
# Circuit: groups of (ref, symbol, value, footprint, {pin: net})
# ---------------------------------------------------------------------------
CIRCUIT = [
    ("1. USB input, fuse, 3.3V regulator", [
        ("J1", "USB_A", "USB-A plug (IN)", "", {"1": "VBUS", "2": "USB_DM", "3": "USB_DP", "4": "GND", "5": "GND"}),
        ("F1", "Fuse", "2A hold PTC", FP_FUSE, {"1": "VBUS", "2": "+5V"}),
        ("C1", "C", "10uF", FP_C, {"1": "+5V", "2": "GND"}),
        ("C2", "C", "100nF", FP_C, {"1": "+5V", "2": "GND"}),
        ("U1", "AMS1117", "AMS1117-3.3", FP_SOT223, {"3": "+5V", "2": "+3V3", "1": "GND"}),
        ("C3", "C", "10uF", FP_C, {"1": "+5V", "2": "GND"}),
        ("C4", "CP", "22uF tant", FP_CT, {"1": "+3V3", "2": "GND"}),
        ("C5", "C", "100nF", FP_C, {"1": "+3V3", "2": "GND"}),
        ("TP1", "TP", "TP_5V", FP_TP, {"1": "+5V"}),
        ("TP2", "TP", "TP_3V3", FP_TP, {"1": "+3V3"}),
        ("TP3", "TP", "TP_GND", FP_TP, {"1": "GND"}),
    ]),
    ("2. USB-to-serial (CH340C at 3.3V) and auto-program", [
        ("U2", "CH340C", "CH340C", FP_SOIC16, {
            "5": "USB_DP", "6": "USB_DM", "16": "+3V3", "4": "+3V3", "1": "GND",
            "7": NC, "8": NC, "15": NC,
            "2": "CH_TXD", "3": "CH_RXD", "13": "DTR", "14": "RTS",
            "9": NC, "10": NC, "11": NC, "12": NC}),
        ("C6", "C", "100nF", FP_C, {"1": "+3V3", "2": "GND"}),
        ("R1", "R", "470", FP_R, {"1": "CH_TXD", "2": "ESP_RXD"}),
        ("R2", "R", "470", FP_R, {"1": "CH_RXD", "2": "ESP_TXD"}),
        ("R3", "R", "10k", FP_R, {"1": "DTR", "2": "Q1_B"}),
        ("Q1", "NPN", "MMBT3904", FP_SOT23, {"1": "Q1_B", "2": "RTS", "3": "EN"}),
        ("R4", "R", "10k", FP_R, {"1": "RTS", "2": "Q2_B"}),
        ("Q2", "NPN", "MMBT3904", FP_SOT23, {"1": "Q2_B", "2": "DTR", "3": "GPIO0"}),
    ]),
    ("3. ESP-12F, boot straps, button", [
        ("U3", "ESP12F", "ESP-12F", FP_ESP, {
            "8": "+3V3", "15": "GND", "3": "EN", "1": "RST",
            "2": NC, "4": NC, "5": NC, "6": NC, "7": NC, "9": NC, "10": NC,
            "18": "GPIO0", "17": "GPIO2", "16": "GPIO15", "19": "BTN",
            "20": "SW_DRV", "21": "ESP_RXD", "22": "ESP_TXD",
            "11": NC, "12": NC, "13": NC, "14": NC}),
        ("C7", "C", "10uF", FP_C, {"1": "+3V3", "2": "GND"}),
        ("C8", "C", "100nF", FP_C, {"1": "+3V3", "2": "GND"}),
        ("R5", "R", "10k", FP_R, {"1": "+3V3", "2": "EN"}),
        ("C9", "C", "100nF", FP_C, {"1": "EN", "2": "GND"}),
        ("R6", "R", "10k", FP_R, {"1": "+3V3", "2": "RST"}),
        ("R7", "R", "10k", FP_R, {"1": "+3V3", "2": "GPIO0"}),
        ("R8", "R", "10k", FP_R, {"1": "+3V3", "2": "GPIO2"}),
        ("R9", "R", "10k", FP_R, {"1": "GPIO15", "2": "GND"}),
        ("R10", "R", "10k", FP_R, {"1": "+3V3", "2": "BTN"}),
        ("SW1", "SW", "Button", FP_SW, {"1": "BTN", "2": "GND"}),
    ]),
    ("4. Output switch (high-side P-MOSFET), ON AIR LED, USB output", [
        ("R12", "R", "1k", FP_R, {"1": "SW_DRV", "2": "Q4_G"}),
        ("R13", "R", "100k", FP_R, {"1": "Q4_G", "2": "GND"}),
        ("Q4", "NMOS", "2N7002", FP_SOT23, {"1": "Q4_G", "3": "Q3_G", "2": "GND"}),
        ("R11", "R", "10k", FP_R, {"1": "+5V", "2": "Q3_G"}),
        ("Q3", "PMOS", "AO3401A", FP_SOT23, {"1": "Q3_G", "2": "+5V", "3": "5V_OUT"}),
        ("C10", "C", "10uF", FP_C, {"1": "5V_OUT", "2": "GND"}),
        ("R14", "R", "1k", FP_R, {"1": "5V_OUT", "2": "LED_ON_A"}),
        ("D1", "LED", "Red ON AIR", FP_LED, {"2": "LED_ON_A", "1": "GND"}),
        ("J2", "USB_A", "USB-A socket (OUT)", "", {"1": "5V_OUT", "2": "OUT_D", "3": "OUT_D", "4": "GND", "5": "GND"}),
        ("TP4", "TP", "TP_GPIO5", FP_TP, {"1": "SW_DRV"}),
    ]),
    ("5. Optional power LED", [
        ("R15", "R", "2.2k", FP_R, {"1": "+3V3", "2": "PWR_LED_A"}),
        ("D2", "LED", "Green PWR (opt)", FP_LED, {"2": "PWR_LED_A", "1": "GND"}),
    ]),
]

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def uid():
    return str(uuid.uuid4())

ROOT = uid()

def fmt(v):
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return "0" if s == "-0" else s

FONT = "(effects (font (size 1.27 1.27)))"
FONT_HIDE = "(effects (font (size 1.27 1.27)) hide)"

def symbol_geometry(name):
    width, pins = SYMBOLS[name]
    left = [p for p in pins if p[2] == "L"]
    right = [p for p in pins if p[2] == "R"]
    n = max(len(left), len(right), 1)
    height = (n + 1) * G
    top = height / 2
    geo = {}
    for i, (num, pname, _) in enumerate(left):
        geo[num] = (-width / 2 - G, top - (i + 1) * G, 0, pname)
    for i, (num, pname, _) in enumerate(right):
        geo[num] = (width / 2 + G, top - (i + 1) * G, 180, pname)
    return width, height, geo

def lib_symbol(name):
    width, height, geo = symbol_geometry(name)
    hide_names = name in ("R", "C", "Fuse", "SW")
    out = [f'(symbol "{PROJECT}:{name}" (pin_names (offset 0.508){" hide" if hide_names else ""}) '
           f'(exclude_from_sim no) (in_bom yes) (on_board yes)']
    out.append(f'(property "Reference" "X" (at 0 {fmt(height/2 + 1.27)} 0) {FONT})')
    out.append(f'(property "Value" "{name}" (at 0 {fmt(-height/2 - 1.27)} 0) {FONT})')
    out.append(f'(property "Footprint" "" (at 0 0 0) {FONT_HIDE})')
    out.append(f'(property "Datasheet" "" (at 0 0 0) {FONT_HIDE})')
    out.append(f'(symbol "{name}_0_1" (rectangle (start {fmt(-width/2)} {fmt(height/2)}) '
               f'(end {fmt(width/2)} {fmt(-height/2)}) (stroke (width 0.254) (type default)) '
               f'(fill (type background))))')
    pins = []
    for num, (x, y, ang, pname) in geo.items():
        pins.append(f'(pin passive line (at {fmt(x)} {fmt(y)} {ang}) (length {fmt(G)}) '
                    f'(name "{pname}" {FONT}) (number "{num}" {FONT}))')
    out.append(f'(symbol "{name}_1_1" {" ".join(pins)})')
    out.append(")")
    return " ".join(out)

def label_text_len(net):
    return len(net) * 1.0 + 2

# ---------------------------------------------------------------------------
# Build schematic
# ---------------------------------------------------------------------------

def build():
    items = []
    placed = []  # for netlist
    used_symbols = set()
    y = 30.48
    for title, comps in CIRCUIT:
        items.append(f'(text "{title}" (exclude_from_sim no) (at 20.32 {fmt(y)} 0) '
                     f'(effects (font (size 2.54 2.54) bold) (justify left bottom)) (uuid "{uid()}"))')
        y += 7.62
        x = 30.48
        row_h = 0
        for ref, sym, value, fp, nets in comps:
            used_symbols.add(sym)
            width, height, geo = symbol_geometry(sym)
            lmax = max([label_text_len(nets[n]) for n, g in geo.items() if g[2] == 0 and nets.get(n)] + [0])
            rmax = max([label_text_len(nets[n]) for n, g in geo.items() if g[2] == 180 and nets.get(n)] + [0])
            span = lmax + width + rmax + 4 * G + 12.7
            if x + span > 570:
                x = 30.48
                y += row_h + 12.7
                row_h = 0
            cx = round((x + lmax + 2 * G + width / 2) / G) * G
            cy = round((y + height / 2 + 2.54) / G) * G
            items.append(placed_symbol(ref, sym, value, fp, cx, cy, height, geo))
            for num, (px, py, ang, _) in geo.items():
                ex, ey = cx + px, cy - py
                net = nets.get(num)
                if net is None:
                    items.append(f'(no_connect (at {fmt(ex)} {fmt(ey)}) (uuid "{uid()}"))')
                    continue
                dx = -G if ang == 0 else G
                wx = ex + dx
                items.append(f'(wire (pts (xy {fmt(ex)} {fmt(ey)}) (xy {fmt(wx)} {fmt(ey)})) '
                             f'(stroke (width 0) (type default)) (uuid "{uid()}"))')
                if ang == 0:
                    items.append(f'(label "{net}" (at {fmt(wx)} {fmt(ey)} 180) (fields_autoplaced yes) '
                                 f'(effects (font (size 1.27 1.27)) (justify right bottom)) (uuid "{uid()}"))')
                else:
                    items.append(f'(label "{net}" (at {fmt(wx)} {fmt(ey)} 0) (fields_autoplaced yes) '
                                 f'(effects (font (size 1.27 1.27)) (justify left bottom)) (uuid "{uid()}"))')
            placed.append((ref, sym, value, fp, nets))
            x += span
            row_h = max(row_h, height + 7.62)
        y += row_h + 15.24

    notes = ("CameraProbe USB relay board Rev A - generated by tools/generate_kicad.py from DESIGN.md. "
             "Assign J1/J2 footprints to match the USB connectors you buy. "
             "Verify ESP-12F GPIO4/GPIO5 pin order against your module's datasheet.")
    items.append(f'(text "{notes}" (exclude_from_sim no) (at 20.32 15.24 0) '
                 f'(effects (font (size 1.524 1.524)) (justify left bottom)) (uuid "{uid()}"))')

    libs = " ".join(lib_symbol(s) for s in sorted(used_symbols))
    sch = (f'(kicad_sch (version 20231120) (generator "eeschema") (generator_version "8.0") '
           f'(uuid "{ROOT}") (paper "A2") '
           f'(title_block (title "CameraProbe USB Relay Board") (rev "A") (company "W9TIM / CameraProbe")) '
           f'(lib_symbols {libs}) '
           + " ".join(items) +
           ' (sheet_instances (path "/" (page "1"))))')
    return sch, placed

def placed_symbol(ref, sym, value, fp, cx, cy, height, geo):
    pins = " ".join(f'(pin "{n}" (uuid "{uid()}"))' for n in geo)
    return (f'(symbol (lib_id "{PROJECT}:{sym}") (at {fmt(cx)} {fmt(cy)} 0) (unit 1) '
            f'(exclude_from_sim no) (in_bom yes) (on_board yes) (dnp no) (uuid "{uid()}") '
            f'(property "Reference" "{ref}" (at {fmt(cx)} {fmt(cy - height/2 - 1.27)} 0) {FONT}) '
            f'(property "Value" "{value}" (at {fmt(cx)} {fmt(cy + height/2 + 1.27)} 0) {FONT}) '
            f'(property "Footprint" "{fp}" (at {fmt(cx)} {fmt(cy)} 0) {FONT_HIDE}) '
            f'(property "Datasheet" "" (at {fmt(cx)} {fmt(cy)} 0) {FONT_HIDE}) '
            f'{pins} '
            f'(instances (project "{PROJECT}" (path "/{ROOT}" (reference "{ref}") (unit 1)))))')

def build_netlist(placed):
    comps = []
    nets = {}
    for ref, sym, value, fp, pinmap in placed:
        comps.append(f'(comp (ref "{ref}") (value "{value}") (footprint "{fp}") '
                     f'(libsource (lib "{PROJECT}") (part "{sym}") (description "")) '
                     f'(sheetpath (names "/") (tstamps "/")) (tstamps "{uid()}"))')
        for pin, net in pinmap.items():
            if net is None:
                continue
            nets.setdefault(net, []).append((ref, pin))
    net_items = []
    for i, (name, nodes) in enumerate(sorted(nets.items()), start=1):
        node_s = " ".join(f'(node (ref "{r}") (pin "{p}"))' for r, p in nodes)
        net_items.append(f'(net (code "{i}") (name "{name}") {node_s})')
    return (f'(export (version "E") (design (source "{PROJECT}.kicad_sch") (tool "generate_kicad.py")) '
            f'(components {" ".join(comps)}) (nets {" ".join(net_items)}))'), nets

PRO = """{
  "meta": {
    "filename": "CameraProbeUSB.kicad_pro",
    "version": 1
  }
}
"""

if __name__ == "__main__":
    sch, placed = build()
    net, nets = build_netlist(placed)
    with open(os.path.join(OUT, f"{PROJECT}.kicad_sch"), "w") as f:
        f.write(sch + "\n")
    with open(os.path.join(OUT, f"{PROJECT}.net"), "w") as f:
        f.write(net + "\n")
    pro = os.path.join(OUT, f"{PROJECT}.kicad_pro")
    if not os.path.exists(pro):
        with open(pro, "w") as f:
            f.write(PRO)
    single = [n for n, nodes in nets.items() if len(nodes) < 2]
    print(f"{len(placed)} parts, {len(nets)} nets")
    if single:
        print("WARNING: nets with only one connection:", single)
