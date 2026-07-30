# CameraProbe Relay Firmware

ESP8266 sketch that exposes `GET /on`, `GET /off`, and `GET /status` over HTTP, so CameraProbe can flip a physical relay whenever your Mac's camera turns on or off. This is the firmware actually running on the reference hardware for this project (a Wemos D1 Mini), configured to match CameraProbe's default config (`onair.local:80`).

## Hardware

- ESP8266 board - built and tested on a Wemos D1 Mini; any ESP8266 board works, since the pin is referred to by its `D1` label rather than a raw GPIO number.
- A relay module (or an LED for testing) wired to `D1`. Edit `relayPin` in the sketch if you wire it elsewhere.
- Power the relay module's VCC/GND per its datasheet. Most 5V relay modules run fine off the board's 5V/VIN pin for light use; use a separate 5V supply if the relay is switching anything with real current draw.

## Arduino IDE setup

1. Install the [Arduino IDE](https://www.arduino.cc/en/software) if you don't already have it.
2. Add the ESP8266 board package: **Arduino IDE → Settings → Additional boards manager URLs**, add:
   ```
   https://arduino.esp8266.com/stable/package_esp8266com_index.json
   ```
3. **Tools → Board → Boards Manager**, search "esp8266", install it.
4. **Tools → Board**, select **"LOLIN(WEMOS) D1 R2 & mini"** (or your specific board).
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
