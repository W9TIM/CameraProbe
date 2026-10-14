# ESP-01S Relay Module - 3D-Printed Case Design Spec

Design brief for a compact enclosure for the `CameraProbeRelay8266` hardware (ESP-01S relay module, single-supply USB wiring - see `../README.md`).

> **Measure first.** The datasheet in this folder is a schematic only and gives no mechanical dimensions. The numbers marked *(est.)* are typical for this style of module; measure your actual board with calipers and update the table before printing.

## 1. Board facts (from the photo and schematic)

| Item | Value |
|---|---|
| Layout | Relay (blue cube) on the left, two green screw-terminal blocks along the **bottom** edge, ESP-01S module plugged in on the **right** |
| Board footprint | ~36 x 25 mm *(est.)* |
| Overall height | ~19 mm *(est.)*, set by the relay body; the ESP-01S sits ~11 mm above the board *(est.)* |
| Terminal block A (3-pos) | NO / COM / NC, 3.5 mm pitch *(est.)* |
| Terminal block B (2-pos) | GND / VCC power input |
| Antenna | PCB trace on the ESP-01S, right end - **must not be blocked by metal** |
| Reset button | On the ESP-01S side edge |
| Power | 5V; do not exceed what the regulator on the board allows |

## 2. Wiring that the case must accommodate

- **Two pigtails** leave the case: a **male USB-A** pigtail (power in) and a **female USB-A** pigtail (switched output), each with 2 conductors (+5V/GND).
- Five screw terminals are used: power block (GND, VCC) and relay block (NO, COM). NC is unused.
- Two jumpers inside the case: board GND to COM. Leave ~10 mm of wire slack above the terminals.

## 3. Case concept

Two-part clamshell: **base** (holds the board) plus **lid** (snap-fit or two M2 screws). Target external size about **50 x 34 x 28 mm** *(est.; board + 7 mm wall/clearance on each long side, 2 mm walls)*.

### Layout

```
        TOP VIEW (lid off)
 +-----------------------------------------+
 |  [ relay ]            [ ESP-01S ]  ~~~  |  <- antenna end: plastic only
 |  [ NO COM NC ][ GND VCC ]               |
 +----------|---|---------|-----|----------+
            |   |         |     |
        cable exit(s) on this side
```

### Requirements

1. **Board mounting:** four 2 mm-tall standoffs under the board corners (or ribs on the long edges). Check whether the board has mounting holes; if not, use side rails plus a lid that presses down on the relay.
2. **Cable exits:** two 7 mm round or U-shaped notches, one per pigtail, on the **terminal-side wall**, with a printed strain-relief pocket for a zip tie or knot inside each. Keep the male input exit and female output exit apart so they're easy to tell apart.
3. **Terminal access:** the lid should come off without disturbing the wiring. A small screwdriver slot is not needed if the lid fully removes.
4. **Antenna end:** no metal screws or inserts within 15 mm of the ESP-01S antenna; keep that wall thin (~1.5 mm).
5. **Reset / status LED:** a 3 mm hole or light-pipe over the board's green LED (location *(to be measured)*), and optional access to the reset button on the side.
6. **Ventilation:** 1.5 mm slots on the lid above the relay for heat; relays warm slightly when energized for long periods.
7. **Labels:** emboss or engrave `IN` by the male pigtail exit and `OUT` by the female exit.
8. **Print settings:** PLA or PETG, 0.2 mm layers, 3 perimeters, no supports (print base open side up, lid flat). Tolerances: 0.3 mm clearance on all fits; adjust for your printer.

### Mounting options (pick one)

- Two screw ears on the base for wall or desk-edge mounting, 3.2 mm holes, or
- A flat back with a recess for 3M foam tape.

## 4. Checklist before printing

- [ ] Measure board L x W x H and the terminal block heights.
- [ ] Measure the position of the ESP-01S, its LED, and the reset button from the board edges.
- [ ] Confirm the pigtail cable diameter and set the exit slot width (cable + 0.5 mm).
- [ ] Test-fit with a 20-minute draft print at 0.3 mm layer height.
- [ ] Add the final STL/STEP files to this folder.
