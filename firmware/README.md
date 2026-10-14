# CameraProbe Relay Firmware

ESP8266 sketches that expose `GET /on`, `GET /off`, and `GET /status` over HTTP, so CameraProbe can flip a physical relay whenever your computer's camera turns on or off. Both are configured to match CameraProbe's default config (`onair.local:80`).

## Which folder do I use?

There are two variants, one per hardware option. Pick the one that matches your board:

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

How it works: +5V is always present on the output pigtail, and the relay switches only the **ground** leg. With the relay off, NO is open, so the device has no return path and stays off. When CameraProbe turns the relay on, COM connects to NO, the circuit completes, and the light comes on.

Limits: the output can't exceed what your USB supply, the pigtail wire gauge and the relay module's terminals can safely carry. The 10A figure is the relay contact rating, not a promise for the whole path. Use a supply and wire sized for your actual load, and for a typical USB light this is far more than needed.

## Arduino IDE setup

1. Install the [Arduino IDE](https://www.arduino.cc/en/software) if you don't already have it.
2. Add the ESP8266 board package: **Arduino IDE → Settings → Additional boards manager URLs**, add:
   ```
   https://arduino.esp8266.com/stable/package_esp8266com_index.json
   ```
3. **Tools → Board → Boards Manager**, search "esp8266", install it.
4. **Tools → Board**, select **"LOLIN(WEMOS) D1 R2 & mini"** for the Wemos D1 Mini, or **"Generic ESP8266 Module"** for the ESP-01S.
5. No extra libraries to install - `ESP8266WiFi`, `ESP8266mDNS`, and `ESP8266WebServer` all ship with the board package.

## Configure and flash

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
