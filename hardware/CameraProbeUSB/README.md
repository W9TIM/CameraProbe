# CameraProbe USB Relay Board (Rev A)

A USB stick with a USB-A plug in, a switched USB-A socket out, and an ESP-12F inside. It runs the universal relay firmware and is programmed through its own USB plug. The full circuit, parts list, layout rules and bring-up steps are in [DESIGN.md](DESIGN.md).

## Files

| File | What it is |
|---|---|
| `DESIGN.md` | The design spec (start here) |
| `CameraProbeUSB.kicad_pro` | KiCad project: open this |
| `CameraProbeUSB.kicad_sch` | Schematic, generated from the spec |
| `CameraProbeUSB.net` | Netlist (backup way into the PCB editor) |
| `tools/generate_kicad.py` | Script that generates the schematic and netlist from one circuit table |

## Opening it in KiCad (8 or 9)

1. **File → Open Project…** and choose `CameraProbeUSB.kicad_pro`.
2. Open the **Schematic Editor**. The sheet is grouped into five labelled blocks (USB input and regulator, USB serial, ESP-12F, output switch, optional LED). Parts are simple labelled boxes, and connections are made with **net labels**: two pins with the same label (e.g. `+3V3`) are connected.
3. Run **Inspect → Electrical Rules Checker**. It should report no errors.
4. **Assign the two USB connector footprints** (J1 and J2 are left blank on purpose): once your connectors arrive, double-click J1 / J2 → Footprint, and choose a footprint that matches the exact part, or create one from its datasheet. Every other part already has a hand-solder footprint from KiCad's standard libraries.
5. Check the **ESP-12F GPIO4 / GPIO5 pins** (pins 19 and 20) against your module's datasheet. Some ESP-12 modules have these two swapped. If yours does, either swap the `BTN` / `SW_DRV` labels on U3, or keep the board and choose **Custom → GPIO4** in the firmware setup page.
6. **Tools → Update PCB from Schematic** (F8) sends everything to the PCB editor for layout. Follow the layout guidelines in DESIGN.md section 4.

If the schematic won't open for any reason, you can still start the layout: open the **PCB Editor** → **File → Import → Netlist…** → choose `CameraProbeUSB.net`.

## Changing the circuit

Edit the `CIRCUIT` table in `tools/generate_kicad.py`, then run:

```
python3 hardware/CameraProbeUSB/tools/generate_kicad.py
```

This regenerates the schematic and netlist. **Regenerating overwrites the schematic**, so once you start editing the schematic by hand in KiCad (moving parts, assigning footprints), make further changes in KiCad and stop using the script.
