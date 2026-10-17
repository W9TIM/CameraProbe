#!/usr/bin/env python3
"""
Silkscreen cleanup for the Rev A board (run once, with the PCB editor closed):

  - hides every part reference (R1, C6, ...) on the top silkscreen. On a
    hand-solder board this crowded they only overlap each other; use the
    assembly map (ASSEMBLY.md / assembly.png) to see which part goes where.
    Footprint outlines and pin-1 marks stay printed.
  - adds board labels on the back silkscreen: IN / OUT, the board name and rev.

    python3 tools/silkscreen_rev_a.py
"""

import os
import re
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
PCB = os.path.join(os.path.dirname(HERE), "CameraProbeUSB.kicad_pcb")

# (text, x, y, size mm) on B.SilkS (mirrored so it reads correctly from the back)
BACK_TEXT = [
    ("IN", 103.5, 102.6, 1.5),
    ("OUT", 170.0, 102.6, 1.5),
    ("CameraProbe USB  Rev A", 131.0, 124.6, 1.2),
    ("W9TIM / github.com/W9TIM/CameraProbe", 137.5, 126.6, 0.9),
]

def main():
    text = open(PCB).read()
    if '(gr_text "CameraProbe USB' in text:
        raise SystemExit("Silkscreen script already applied - nothing to do.")

    pattern = re.compile(
        r'(\(property "Reference" "[^"]+"\n(\t+)\(at [^\n]+\n\t+\(layer "F\.SilkS"\)\n)(?!\t+\(hide)')
    text, n = pattern.subn(lambda m: m.group(1) + m.group(2) + "(hide yes)\n", text)

    items = []
    for i, (label, x, y, size) in enumerate(BACK_TEXT):
        thick = round(size * 0.15, 3)
        items.append(
            f'\t(gr_text "{label}"\n\t\t(at {x} {y} 0)\n\t\t(layer "B.SilkS")\n\t\t(uuid "{uuid.uuid4()}")\n'
            f'\t\t(effects\n\t\t\t(font\n\t\t\t\t(size {size} {size})\n\t\t\t\t(thickness {thick})\n'
            f'\t\t\t)\n\t\t\t(justify mirror)\n\t\t)\n\t)')
    end = text.rstrip().rfind(")")
    text = text[:end].rstrip() + "\n" + "\n".join(items) + "\n)\n"
    open(PCB, "w").write(text)
    print(f"Hid {n} reference labels; added {len(items)} back-silkscreen labels")


if __name__ == "__main__":
    main()
