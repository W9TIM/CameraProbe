#!/usr/bin/env python3
"""
One-time starting placement for the Rev A board: moves every footprint in
CameraProbeUSB.kicad_pcb to a planned position and draws the board outline
on Edge.Cuts. Run it once, before any hand edits to the layout:

    python3 tools/place_rev_a.py

Board: 75.3 x 28 mm, top-left corner at (100, 100).
  - J1 (USB-A plug) at the left end, plug sticking out to the left.
  - USB serial + 3.3V regulator next to it.
  - ESP-12F with its antenna hanging over the top edge.
  - Straps/button below the ESP, output switch to its right.
  - J2 (USB-A socket) at the right end, opening facing right.
"""

import os
import re
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
PCB = os.path.join(os.path.dirname(HERE), "CameraProbeUSB.kicad_pcb")

X0, Y0, W, H = 100.0, 100.0, 75.3, 28.0

# ref: (x, y, rotation degrees)
PLACE = {
    # USB input (edge line of the footprint lands on the board's left edge)
    "J1": (96.2, 114.0, 180),
    # USB serial
    "U2": (113.5, 107.5, 0), "C6": (113.5, 114.5, 0),
    "R1": (113.5, 117.5, 0), "R2": (113.5, 120.5, 0),
    "Q1": (120.5, 104.0, 0), "Q2": (120.5, 108.5, 0),
    "R3": (125.5, 104.0, 0), "R4": (125.5, 108.5, 0),
    # Power: fuse, regulator and its capacitors
    "F1": (112.5, 125.0, 0), "C1": (117.5, 123.0, 0), "C2": (120.5, 114.5, 0),
    "U1": (125.0, 123.5, 0), "C3": (121.0, 117.5, 0),
    "C4": (126.5, 117.5, 0), "C5": (126.5, 114.5, 0),
    # Test points and optional power LED in the spare corners beside J1
    "TP1": (102.0, 124.0, 0), "TP2": (105.0, 124.0, 0), "TP3": (102.0, 126.7, 0),
    "R15": (104.0, 101.8, 0), "D2": (104.0, 104.6, 0),
    # ESP-12F: antenna overhangs the top edge
    "U3": (139.1, 104.8, 0),
    # Boot straps, decoupling and button below the ESP
    "C7": (132.5, 120.0, 0), "C8": (132.5, 123.0, 0), "C9": (132.5, 126.0, 0),
    "R5": (137.0, 120.0, 0), "R6": (137.0, 123.0, 0), "R7": (137.0, 126.0, 0),
    "R8": (141.5, 120.0, 0), "R9": (141.5, 123.0, 0), "R10": (141.5, 126.0, 0),
    "SW1": (145.5, 119.5, 0),
    # Output switch and ON AIR LED
    "Q3": (151.5, 104.0, 0), "Q4": (151.5, 109.0, 0),
    "R11": (156.5, 104.0, 0), "R12": (156.5, 107.0, 0), "R13": (156.5, 110.0, 0),
    "C10": (151.5, 113.0, 0), "R14": (156.5, 113.0, 0), "D1": (156.5, 116.0, 0),
    "TP4": (156.5, 120.0, 0),
    # USB output: socket opening flush with the right edge
    "J2": (162.3, 117.5, 90),
}

AT_RE = re.compile(r"\(at ([-\d.]+) ([-\d.]+)(?: ([-\d.]+))?\)")


def blocks(text, head):
    """Yield (start, end) spans of top-level '(head ...' blocks."""
    i = 0
    while True:
        i = text.find("(" + head + " ", i)
        if i < 0:
            return
        depth = 0
        j = i
        in_str = False
        while j < len(text):
            c = text[j]
            if in_str:
                if c == "\\":
                    j += 1
                elif c == '"':
                    in_str = False
            elif c == '"':
                in_str = True
            elif c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0:
                    break
            j += 1
        yield i, j + 1
        i = j + 1


def fmt(v):
    s = f"{v:.4f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def rotate_block(block, rot):
    """Set footprint position/rotation; add rot to the angle of every pad/text."""
    first = AT_RE.search(block)
    head, rest = block[:first.end()], block[first.end():]

    def add_angle(m):
        x, y, a = m.group(1), m.group(2), float(m.group(3) or 0)
        na = (a + rot) % 360
        return f"(at {x} {y} {fmt(na)})" if na else f"(at {x} {y})"

    if rot:
        rest = AT_RE.sub(add_angle, rest)
    return head, rest


def main():
    text = open(PCB).read()
    out, last, moved = [], 0, set()
    for s, e in list(blocks(text, "footprint")):
        block = text[s:e]
        m = re.search(r'\(property "Reference" "([^"]+)"', block)
        ref = m.group(1) if m else None
        if ref in PLACE:
            x, y, rot = PLACE[ref]
            head, rest = rotate_block(block, rot)
            head = AT_RE.sub(lambda _: f"(at {fmt(x)} {fmt(y)}{' ' + fmt(rot) if rot else ''})", head, count=1)
            block = head + rest
            moved.add(ref)
        out.append(text[last:s])
        out.append(block)
        last = e
    out.append(text[last:])
    text = "".join(out)

    # Board outline on Edge.Cuts
    if any('"Edge.Cuts"' in text[a:b] for kind in ("gr_line", "gr_rect", "gr_arc", "gr_poly")
           for a, b in blocks(text, kind)):
        raise SystemExit("Board already has an Edge.Cuts outline - not running twice.")
    corners = [(X0, Y0), (X0 + W, Y0), (X0 + W, Y0 + H), (X0, Y0 + H)]
    lines = []
    for (ax, ay), (bx, by) in zip(corners, corners[1:] + corners[:1]):
        lines.append(f'\t(gr_line (start {fmt(ax)} {fmt(ay)}) (end {fmt(bx)} {fmt(by)}) '
                     f'(stroke (width 0.05) (type default)) (layer "Edge.Cuts") '
                     f'(uuid "{uuid.uuid4()}"))')
    end = text.rstrip().rfind(")")
    text = text[:end].rstrip() + "\n" + "\n".join(lines) + "\n)\n"

    open(PCB, "w").write(text)
    missing = sorted(set(PLACE) - moved)
    print(f"Placed {len(moved)} footprints; outline {W} x {H} mm")
    if missing:
        print("Not found:", missing)


if __name__ == "__main__":
    main()
