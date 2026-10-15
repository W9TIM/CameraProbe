# CameraProbe Relay Firmware

ESP8266 sketches that expose `GET /on`, `GET /off`, and `GET /status` over HTTP, so CameraProbe can flip a physical relay whenever your computer's camera turns on or off. All of them match CameraProbe's default config (`onair.local:80`).

## Recommended: universal firmware (flash, boot, configure, go)

`CameraProbeRelayUniversal/` is one firmware for every supported board. You don't edit a `secrets.h` file, and you never re-flash it to change WiFi. You set the WiFi network, board type and device name from a web page.

**First-time setup**

1. Flash `CameraProbeRelayUniversal.ino` (see [Arduino IDE setup](#arduino-ide-setup); choose **Generic ESP8266 Module** for either board).
2. Power the device. With no settings saved yet, it starts an open WiFi network called **ConfigRelay**.
3. Join **ConfigRelay** from a phone or computer. The setup page usually opens by itself; if not, browse to `http://192.168.4.1`.
4. Choose your WiFi network, enter its password, pick your **relay board** (Wemos D1 Mini + relay shield, ESP-01S relay module, or Custom pin/logic), and keep the device name `onair` unless you also change it in CameraProbe's Preferences.
5. Click **Save and reboot**. The device joins your network. Reconnect your phone or computer to your home WiFi and open `http://onair.local/configure` to confirm. The page has **Relay on / Relay off** test buttons.

**Later**

- **Check or change settings:** `http://onair.local/configure`. The saved WiFi password is never shown. Leave the field blank to keep it.
- **New router or WiFi password:** if the device can't join its saved network within about 30 seconds of power-up, it opens **ConfigRelay** again so you can enter the new details.
- **Power cuts:** if the router is still starting up, the device waits in setup mode. If nobody connects to it within 3 minutes, it restarts and tries the saved network again, so it reconnects by itself once the router is back.
- **Factory reset (no button needed):** plug the device in for about 2 seconds and unplug it, two times. Plug it in a third time and leave it. All settings are erased and it starts **ConfigRelay**. The **Factory reset** button on the setup page does the same.
- **Firmware updates over WiFi:** `http://onair.local/update` accepts a `.bin` file. In the Arduino IDE, export one with **Sketch → Export Compiled Binary**. After the first USB flash, you don't need the programmer again.

The relay always starts **off** at power-up. Until a board is chosen, the firmware doesn't drive any pin at all. That matters on the ESP-01S, where GPIO0 must not be held low while it boots.

Security note: **ConfigRelay** is an open network by design, so it's easy for novices. It only appears when the device isn't on your WiFi. On your home network, `/configure` and `/update` have no password, so anyone on that network can change them. That's the same trust level as `/on` and `/off`.

## Fixed-configuration sketches

The original sketches are still here for anyone who prefers settings compiled into the firmware. Each one targets one board and reads WiFi details from `secrets.h`. Pick the one that matches your board:

| Folder | Hardware | Relay logic |
|---|---|---|
| `CameraProbeRelay/` | Wemos D1 Mini + D1 Mini relay shield (photo and parts links in `Wemos D1 Device/`) | Relay pin `D1`; ON = HIGH, OFF = LOW |
| `CameraProbeRelay8266/` | ESP-01S WiFi relay module (wiring, programmer and datasheet in `ESP8266 Module Device/`) | Relay pin GPIO0; ON = LOW, OFF = HIGH (active-low) |

The rest of this guide applies to both. Wherever it says `CameraProbeRelay.ino`, open the `.ino` in the folder you chose (`CameraProbeRelay8266.ino` for the ESP-01S).

## Hardware

- **Wemos D1 Mini variant:** a Wemos D1 Mini with a relay shield (or an LED for testing) on `D1`. Edit `relayPin` in the sketch if you wire it elsewhere.
- **ESP-01S relay variant:** an ESP-01S relay module, programmed through a USB-to-ESP-01 adapter (CH340G). The relay is on GPIO0. On a 2-relay board the second relay is on GPIO2.
- Power the relay module's VCC/GND per its datasheet. Most 5V relay modules run fine off the board's 5V/VIN pin for light use; use a separate 5V supply if the relay is switching anything with real current draw.

## Single-supply wiring (ESP-01S relay variant)

The ESP-01S relay module can run the board and the switched device from one 5V USB supply, using two USB-A pigtails:

- **Male USB-A pigtail** - the power *input*, plugged into any 5V USB supply.
- **Female USB-A pigtail** - the switched *output*; plug the light or other 5V USB device into it.

| Connection | Wired to |
|---|---|
| Board power input **+5V (VCC)** | Male pigtail **+5V** and Female pigtail **+5V** (both on the same terminal) |
| Board power input **GND** | Male pigtail **GND**, plus a jumper to the relay **COM** |
| Relay **COM** | Jumper to board power GND (above) |
| Relay **NO** (Normally Open) | Female pigtail **GND** |
| Relay **NC** (Normally Closed) | Not connected |

```
 USB supply --> Male pigtail
                  +5V ---+---------------- Board VCC ---- Female pigtail +5V
                         |
                  GND ---+-- Board GND
                            |
                            +-- jumper --> Relay COM
                                           Relay NO  --> Female pigtail GND
                                           Relay NC  --> (unused)
```

![Example wiring of the ESP-01S relay module](ESP8266%20Module%20Device/Example%20Wiring.jpeg)

*Example of the finished wiring. The photo is upside down compared with the manufacturer's diagram in `ESP8266 Module Device/`, so the relay block is on the left and the power block is in the middle. The white jumper runs from the relay **COM** (middle terminal) to the power block **GND**. The black wire in the relay block is the **NO** terminal, which goes to the female pigtail GND. The red wires, both on the power block **VCC**, are the male and female pigtail +5V. The other black wire on the power block is the male pigtail GND.*

How it works: +5V is always present on the output pigtail, and the relay switches only the **ground** leg. With the relay off, NO is open, so the device has no return path and stays off. When CameraProbe turns the relay on, COM connects to NO, the circuit completes, and the light comes on.

Limits: the output can't exceed what your USB supply, the pigtail wire gauge and the relay module's terminals can safely carry. The 10A figure is the relay contact rating, not a promise for the whole path. Use a supply and wire sized for your actual load, and for a typical USB light this is far more than needed.

## Arduino IDE setup

1. Install the [Arduino IDE](https://www.arduino.cc/en/software) if you don't already have it.
2. Add the ESP8266 board package: **Arduino IDE → Settings → Additional boards manager URLs**, add:
   ```
   https://arduino.esp8266.com/stable/package_esp8266com_index.json
   ```
3. **Tools → Board → Boards Manager**, search "esp8266", install it.
4. **Tools → Board**, select **"Generic ESP8266 Module"** for the universal firmware (either board), or for the fixed sketches **"LOLIN(WEMOS) D1 R2 & mini"** (Wemos D1 Mini) / **"Generic ESP8266 Module"** (ESP-01S). For the universal firmware, also set **Tools → Flash Size** to an option with an OTA area, such as **"1MB (FS:64KB OTA:~470KB)"**, so `/update` works.
5. No extra libraries to install - `ESP8266WiFi`, `ESP8266mDNS`, and `ESP8266WebServer` all ship with the board package.

## Configure and flash (fixed-configuration sketches)

For the universal firmware, just open `CameraProbeRelayUniversal/CameraProbeRelayUniversal.ino`, upload it, and follow [First-time setup](#recommended-universal-firmware-flash-boot-configure-go) above. Skip steps 2–3 below, since there's no `secrets.h`.

1. Open `CameraProbeRelay.ino` in the Arduino IDE.
2. In this same folder, copy `secrets.h.example` to `secrets.h` and fill in your real WiFi network name and password:
   ```
   cp secrets.h.example secrets.h
   ```
   `secrets.h` is gitignored, so it's never committed - your WiFi password stays off GitHub even though this repo is public.
3. If you're wiring the relay to a different pin, or want a different mDNS hostname than `onair`, edit `relayPin` / the `MDNS.begin("onair")` call near the top of the sketch (and update `relay.host` in `config.json` to match).
4. Plug in the board, select the correct port under **Tools → Port**, and click **Upload**.
5. Open the Serial Monitor (115200 baud) to confirm it connects to WiFi and starts the mDNS responder - it prints its IP address once connected.

## Verify

From any machine on the same network:

```
curl http://onair.local/on
curl http://onair.local/off
curl http://onair.local/status
```

`/on` and `/off` return `Relay ON` / `Relay OFF` and the relay should click; `/status` reports the current state (`ON` or `OFF`) without changing it. This matches exactly what CameraProbe's `relay.host` / `relay.port` config expects - with the default hostname, no config changes are needed on the Mac side.
