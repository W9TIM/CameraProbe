# CameraProbe USB Relay Board - Design Spec (Rev A, hand-solder)

A single USB stick that replaces the ESP-01S relay module and its pigtail wiring:

```
 USB charger / computer  ==>  [ USB-A plug | CameraProbe USB board | USB-A socket ]  ==>  light / USB device
                                 power in       ESP-12F + switch        switched 5V out
                                 (+ data for programming)
```

- Plugged into a **USB charger**: normal use. The output socket's 5V is switched on and off by CameraProbe over WiFi.
- Plugged into a **computer**: the same plug carries USB data to an on-board USB-to-serial chip, so the Arduino IDE, esptool or the web flasher can program it with no programmer, jumper or button.
- Runs the existing **universal firmware** unchanged. The output switch is on **GPIO5, on = HIGH**, which is identical to the Wemos D1 preset.

> **Status:** design spec for review. The circuit uses standard, widely copied sub-circuits (NodeMCU/Wemos-style USB serial with auto-reset, high-side MOSFET load switch). Part numbers are suggestions: check stock and datasheets, and make sure each footprint matches the exact part you buy, before ordering boards.

## 1. Design choices

| Decision | Choice | Why |
|---|---|---|
| WiFi chip | **ESP-12F** module (ESP8266, 4 MB) | Same chip as the tested firmware; edge pads are hand-solderable |
| USB-serial | **CH340C** (SOIC-16) | Internal oscillator, so no crystal needed; hand-solderable; same family as the Wemos D1 Mini |
| Auto-program | 2 x NPN transistors on DTR/RTS (NodeMCU circuit) | esptool/Arduino enter flash mode automatically |
| Output switch | **High-side P-MOSFET** (AO3401A) driven by an N-MOSFET (2N7002) | Silent, no relay coil current; switches +5V, which is correct for USB loads; **off by default** at power-up |
| 3.3V supply | **AMS1117-3.3** (SOT-223) | Easiest regulator to hand-solder; adequate for ESP8266 peaks (~350 mA) |
| Output rating | **5V, 1.5A max** | Limited by the USB-A plug's 1.5A rating (CNC Tech 1001-011-01101) and the polyfuse |
| Part sizes | 0805 passives, SOT-23 / SOT-223 / SOIC-16 | Hand-solderable with a fine tip, flux and tweezers |

## 2. Schematic, block by block

Net names in `CAPS`. `VBUS` = raw USB 5V from the plug, `5V` = after the fuse, `5V_OUT` = switched output, `3V3` = regulated 3.3V.

### 2.1 USB input (J1, USB-A male plug)

| J1 pin | Net |
|---|---|
| 1 VBUS | `VBUS` |
| 2 D- | `USB_DM` |
| 3 D+ | `USB_DP` |
| 4 GND | `GND` |
| Shell | `GND` (through-hole tabs soldered for strength) |

- **F1** polyfuse, 1.5 A hold (1812): `VBUS` to `5V`. Protects the charger or computer port if the output is shorted.
- **C1** 10 µF 0805 (16V+) and **C2** 100 nF 0805: `5V` to `GND`, near J1.
- *(Optional, DNP for Rev A)* **U4** USBLC6-2SC6 ESD protection on `USB_DP`/`USB_DM`.

### 2.2 3.3V regulator (U1, AMS1117-3.3)

- VIN = `5V`, VOUT = `3V3`, GND/ADJ = `GND` (tab is VOUT: use copper pour for heat).
- **C3** 10 µF 0805 on VIN.
- **C4** 22 µF tantalum (1206/3216) or 22 µF 0805 ceramic on VOUT, plus **C5** 100 nF. (AMS1117 stability: follow the datasheet for your exact part; a 22 µF tantalum is the safe choice.)

### 2.3 USB-to-serial (U2, CH340C, SOIC-16)

CH340C runs from **3.3V**, so its serial pins are at the ESP8266's logic level with no level shifting.

| U2 pin | Name | Connects to |
|---|---|---|
| 1 | GND | `GND` |
| 2 | TXD | **R1** 470 Ω to ESP `RXD` (GPIO3) |
| 3 | RXD | **R2** 470 Ω to ESP `TXD` (GPIO1) |
| 4 | V3 | `3V3` (tie to VCC when running at 3.3V) |
| 5 | UD+ | `USB_DP` |
| 6 | UD- | `USB_DM` |
| 13 | DTR# | `DTR` (auto-reset) |
| 14 | RTS# | `RTS` (auto-reset) |
| 16 | VCC | `3V3`, with **C6** 100 nF close to the pin |
| others | - | not connected |

*(Verify the pin numbers against the CH340C datasheet before layout. Package variants differ.)*

### 2.4 Auto-program circuit (Q1, Q2 = MMBT3904 NPN, SOT-23)

This is the standard NodeMCU arrangement:

| Part | Base | Emitter | Collector |
|---|---|---|---|
| **Q1** | `DTR` via **R3** 10 kΩ | `RTS` | ESP `EN` |
| **Q2** | `RTS` via **R4** 10 kΩ | `DTR` | ESP `GPIO0` |

esptool toggles DTR/RTS so that EN is pulsed low while GPIO0 is held low, which boots the ESP into flash mode. With a charger (no data), both transistors stay off and the ESP boots normally.

### 2.5 ESP-12F (U3) and boot straps

| ESP-12F pin | Connection |
|---|---|
| VCC | `3V3`, **C7** 10 µF + **C8** 100 nF right at the pin |
| GND | `GND` (pour) |
| EN (CH_PD) | **R5** 10 kΩ to `3V3`, **C9** 100 nF to `GND`, Q1 collector |
| RST | **R6** 10 kΩ to `3V3` |
| GPIO0 | **R7** 10 kΩ to `3V3`, Q2 collector |
| GPIO2 | **R8** 10 kΩ to `3V3` (the module's own blue LED is also on GPIO2) |
| GPIO15 | **R9** 10 kΩ to `GND` (must be low at boot) |
| TXD / RXD | via R2 / R1 to the CH340C |
| **GPIO5** | Output switch drive (section 2.6) |
| **GPIO4** | Push button **SW1** to `GND`, **R10** 10 kΩ to `3V3` |
| all others | not connected |

### 2.6 Output switch (high-side load switch)

```
  5V ──────────┬──────────── S
               │             Q3  AO3401A (P-ch)
              R11 10k        D ───── 5V_OUT ──> J2 VBUS
               │             G
               ├─────────────┘
               │
               D
  GPIO5 ─R12 1k─ G   Q4  2N7002 (N-ch)
               │ S
              R13 100k
               │ │
  GND ─────────┴─┘
```

- GPIO5 LOW (or ESP not running): Q4 off, R11 pulls Q3's gate to 5V, so **the output is off**. The output stays off during boot, flashing and resets.
- GPIO5 HIGH: Q4 on, Q3's gate is pulled to GND, so **the output is on**.
- **R13** 100 kΩ keeps Q4 off while GPIO5 floats during boot.
- **C10** 10 µF on `5V_OUT` (optional; keep small to limit inrush current).
- **D1** "ON AIR" LED (red, 0805) + **R14** 1 kΩ from `5V_OUT` to `GND`. It lights whenever the output is actually powered: a hardware indicator independent of the firmware.

AO3401A at 1.5 A dissipates roughly 0.1 W. Give its drain and source generous copper (section 4).

### 2.7 USB output (J2, USB-A female socket)

| J2 pin | Net |
|---|---|
| 1 VBUS | `5V_OUT` |
| 2 D- and 3 D+ | **bridged together** (USB "dedicated charger" signal, so phones and lights will draw more than 500 mA); *not* connected to the input data lines |
| 4 GND, shell | `GND` |

### 2.8 Optional power LED

**D2** green LED + **R15** 2.2 kΩ from `3V3` to `GND`. Leave it unpopulated if you'd rather keep it dark.

## 3. Bill of materials (Rev A)

The exact parts ordered for the first build are in `BOM.csv` and `digikey_order.csv`.

| Ref | Qty | Part | Package | Example MPN |
|---|---|---|---|---|
| U3 | 1 | ESP-12F WiFi module | castellated module | Ai-Thinker ESP-12F |
| U2 | 1 | USB-UART bridge | SOIC-16 | WCH CH340C |
| U1 | 1 | 3.3V LDO, 1 A | SOT-223 | AMS1117-3.3 (Rev A build: TI LM1117MPX-3.3/NOPB) |
| Q1, Q2 | 2 | NPN transistor | SOT-23 | MMBT3904 |
| Q3 | 1 | P-ch MOSFET, -20V/-3A or better | SOT-23 | AO3401A (Rev A build: Vishay SI2301CDS-T1-BE3) |
| Q4 | 1 | N-ch MOSFET | SOT-23 | 2N7002 |
| F1 | 1 | Polyfuse 1.5 A hold | 1812 | Bourns MF-MSMF150 (or equivalent) |
| J1 | 1 | USB-A **male plug**, right angle, PCB mount | SMD + THT tabs | **CNC Tech 1001-011-01101** (Digi-Key 1175-1008-ND) |
| J2 | 1 | USB-A **female socket**, right angle, through-hole | THT | **Molex 0676433910** |
| SW1 | 1 | Tactile switch, side or top actuated | 6x3.5 mm SMD/THT | any |
| D1 | 1 | Red LED | 0805 | any |
| D2 | 1 | Green LED (optional) | 0805 | any |
| C1, C3, C7, C10 | 4 | 10 µF, 16V, X5R/X7R | 0805 | any |
| C4 | 1 | 22 µF tantalum, 10V | 3216 (A case) | any |
| C2, C5, C6, C8, C9 | 5 | 100 nF, X7R | 0805 | any |
| R1, R2 | 2 | 470 Ω | 0805 | any |
| R3-R11 | 9 | 10 kΩ | 0805 | any |
| R12, R14 | 2 | 1 kΩ | 0805 | any |
| R13 | 1 | 100 kΩ | 0805 | any |
| R15 | 1 | 2.2 kΩ (optional) | 0805 | any |
| U4 | 0 | USBLC6-2SC6 (DNP Rev A) | SOT-23-6 | ST USBLC6-2SC6 |

Approximate parts cost: US$6-8 per board in small quantities (the ESP-12F and connectors are most of it).

## 4. Layout guidelines (KiCad)

- **Board:** 2-layer, 1.6 mm, 1 oz copper, HASL or ENIG. Target about **60 x 26 mm**: J1 at the left end, J2 at the right end, ESP-12F along one long edge.
- **Antenna:** the ESP-12F's PCB antenna must **overhang the board edge**, or sit over a board area with **no copper on either layer** and no traces, at least 15 mm wide around it. Keep the USB connectors and the MOSFET away from it.
- **Power path** (J1 → F1 → Q3 → J2 and GND return): traces **at least 1.5 mm** wide, or copper pours. Put stitching vias near the connectors.
- **Ground:** a solid ground pour on the bottom layer; stitch the top pour to it with vias.
- **USB data:** keep `USB_DP`/`USB_DM` short, routed side by side, same length within ~1 mm, with no vias if possible. Rev A doesn't need impedance control at 12 Mbit/s.
- **Decoupling:** every 100 nF capacitor goes within 2–3 mm of its pin (CH340C VCC, ESP VCC, regulator).
- **Regulator and MOSFET heat:** generous copper on the AMS1117 tab and on Q3's drain and source.
- **Hand-solder friendly:** use KiCad's "HandSolder" footprint variants for 0805 parts; keep 1 mm or more between parts; put all SMD parts on the top side.
- **Silkscreen:** label `IN` (J1), `OUT` (J2), the button, and "CameraProbe USB Rev A"; add test points `TP_5V`, `TP_3V3`, `TP_GND`, `TP_GPIO5`.
- **Button and LEDs:** place them where the case can expose them (button on the long edge opposite the antenna).

## 5. Assembly order and bring-up

Build in stages and test each one:

1. **Power:** solder F1, U1, C1-C5. Plug into a USB charger. Measure about **5V** at `TP_5V` and **3.3V** at `TP_3V3`. Unplug.
2. **USB serial:** solder U2, C6, R1, R2, Q1, Q2, R3, R4. Plug into a computer; a new serial port should appear (on a Mac, `ls /dev/cu.*`; on Windows, Device Manager → Ports).
3. **ESP-12F:** solder U3, its straps (R5-R10, C7-C9) and SW1. Plug into the computer and flash the universal firmware from the Arduino IDE (Generic ESP8266 Module, 4MB flash is fine) or the web flasher. It should flash with no buttons or jumpers.
4. **Output switch:** solder Q3, Q4, R11-R14, D1, C10 and J2. Boot, join **ConfigRelay**, choose board **Wemos D1 Mini + relay shield** (GPIO5, on = HIGH) and test with the **Relay on/off** buttons. D1 should light and a USB lamp in J2 should switch.
5. **Load test:** run the output at your real load for 15 minutes; Q3, F1 and U1 should be warm at most.

## 6. Firmware notes

- Works today with the universal firmware: choose the Wemos D1 preset, or Custom → GPIO5, HIGH.
- Planned firmware additions for this board (small changes):
  - a named preset, **"CameraProbe USB board"**;
  - **SW1 on GPIO4:** a short press toggles the output; holding it for 10 seconds does a factory reset (an easier option than the power-cycle method);
  - the ESP-12F's blue LED on GPIO2 as a status light (blinking = setup mode, solid briefly = connected).

## 7. Later (Rev B, PCBWay assembly)

- Switch to 0603 or 0402 passives and let PCBWay place every SMD part. Only J1/J2 are hand-soldered, or they become SMD too.
- Shrink the board toward ~45 x 20 mm.
- Consider making the board itself the USB-A plug (a 2.0 mm thick PCB with gold fingers) to remove J1.
- Populate the USBLC6-2SC6 ESD protection.
- Matching 3D-printed case (OpenSCAD), once the board outline is fixed.
