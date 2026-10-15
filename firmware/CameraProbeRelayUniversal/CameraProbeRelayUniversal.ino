/*
 * CameraProbe Relay - Universal Firmware
 *
 * One firmware for every supported relay board. No secrets.h, no editing,
 * no re-flashing to change WiFi: flash it once, then configure it from a
 * web page.
 *
 *   - First boot, or when the saved WiFi can't be reached: the device opens
 *     an open WiFi network called "ConfigRelay". Join it with a phone or
 *     computer and the setup page opens (or browse to http://192.168.4.1).
 *   - Pick your WiFi, your relay board and a device name, then Save. The
 *     device reboots and joins your network.
 *   - On your network: http://onair.local/configure shows and changes the
 *     settings. /on, /off and /status work exactly as before, so CameraProbe
 *     needs no changes.
 *   - Factory reset without a button: plug it in for about 2 seconds and
 *     unplug it, twice; then plug it in a third time and leave it. It starts
 *     in setup mode with all settings erased.
 *   - Firmware updates over WiFi: http://onair.local/update
 *
 * Arduino IDE: Tools > Board > "Generic ESP8266 Module" works for both the
 * ESP-01S and the Wemos D1 Mini (pins are set by number, not D-labels).
 * Pick a Flash Size with an OTA area, e.g. "1MB (FS:64KB OTA:~470KB)".
 * Everything used here ships with the ESP8266 board package.
 */

#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>
#include <ESP8266mDNS.h>
#include <ESP8266HTTPUpdateServer.h>
#include <DNSServer.h>
#include <EEPROM.h>

#define FW_VERSION "1.0.0"

// ---------------------------------------------------------------------------
// Settings you'd only change when building your own variant
// ---------------------------------------------------------------------------

static const char*    SETUP_AP_SSID          = "ConfigRelay";  // open network, no password
static const char*    DEFAULT_HOSTNAME       = "onair";        // CameraProbe's default relay host
static const uint32_t CONNECT_TIMEOUT_MS     = 30UL * 1000UL;  // try the saved WiFi this long at boot
static const uint32_t PORTAL_IDLE_RESTART_MS = 3UL * 60UL * 1000UL; // setup mode, nobody connected: reboot and retry saved WiFi
static const uint32_t WIFI_LOST_RESTART_MS   = 5UL * 60UL * 1000UL; // connected mode, WiFi gone this long: reboot
static const uint32_t BOOT_COUNT_WINDOW_MS   = 10UL * 1000UL;  // a boot shorter than this counts toward factory reset
static const uint8_t  RESET_BOOT_COUNT       = 3;              // this many short boots in a row = factory reset

// ---------------------------------------------------------------------------
// Board presets
// ---------------------------------------------------------------------------

enum Board : uint8_t {
  BOARD_NONE     = 0,  // not chosen yet: no pin is driven
  BOARD_WEMOS_D1 = 1,  // Wemos D1 Mini + relay shield: D1 = GPIO5, on = HIGH
  BOARD_ESP01S   = 2,  // ESP-01S relay module: GPIO0, on = LOW
  BOARD_CUSTOM   = 3   // any pin / logic, chosen on the setup page
};

// Pins offered for "Custom". Leaves out GPIO1/3 (serial) and 6-11 (flash).
static const uint8_t CUSTOM_PINS[] = {0, 2, 4, 5, 12, 13, 14, 15, 16};

// ---------------------------------------------------------------------------
// Stored settings (emulated EEPROM in flash)
// ---------------------------------------------------------------------------

struct Config {
  uint32_t magic;
  uint16_t version;
  char     ssid[33];
  char     pass[65];
  char     host[33];
  uint8_t  board;
  uint8_t  customPin;
  uint8_t  customActiveLow;
  uint32_t crc;
};

struct BootCounter {
  uint32_t magic;
  uint8_t  count;
};

static const uint32_t CONFIG_MAGIC   = 0x43505231;  // "CPR1"
static const uint16_t CONFIG_VERSION = 1;
static const uint32_t BOOT_MAGIC     = 0x424F4F54;  // "BOOT"
static const int      EEPROM_SIZE    = 256;
static const int      BOOT_ADDR      = 0;
static const int      CONFIG_ADDR    = 16;

static_assert(BOOT_ADDR + sizeof(BootCounter) <= CONFIG_ADDR, "boot counter overlaps config");
static_assert(CONFIG_ADDR + sizeof(Config) <= EEPROM_SIZE, "config does not fit in EEPROM");

// ---------------------------------------------------------------------------
// Globals
// ---------------------------------------------------------------------------

Config                  cfg;
ESP8266WebServer        server(80);
ESP8266HTTPUpdateServer httpUpdater;
DNSServer               dnsServer;
const IPAddress         apIP(192, 168, 4, 1);

bool     portalMode       = false;
int      relayPin         = -1;
bool     relayActiveLow   = false;
bool     relayOn          = false;
bool     bootCountPending = false;
uint32_t restartAt        = 0;
uint32_t lastApClientMs   = 0;
uint32_t wifiLostSince    = 0;

static const int MAX_SCAN = 20;
String scanned[MAX_SCAN];
int    scannedCount = 0;

// ---------------------------------------------------------------------------
// Config storage
// ---------------------------------------------------------------------------

uint32_t crc32(const uint8_t* data, size_t len) {
  uint32_t crc = 0xFFFFFFFF;
  while (len--) {
    crc ^= *data++;
    for (int k = 0; k < 8; k++) {
      crc = (crc >> 1) ^ (0xEDB88320 & (0u - (crc & 1)));
    }
  }
  return ~crc;
}

uint32_t configCrc(const Config& c) {
  return crc32(reinterpret_cast<const uint8_t*>(&c), offsetof(Config, crc));
}

void setDefaults() {
  memset(&cfg, 0, sizeof(cfg));
  cfg.magic           = CONFIG_MAGIC;
  cfg.version         = CONFIG_VERSION;
  strlcpy(cfg.host, DEFAULT_HOSTNAME, sizeof(cfg.host));
  cfg.board           = BOARD_NONE;
  cfg.customPin       = 0;
  cfg.customActiveLow = 1;
}

bool loadConfig() {
  EEPROM.get(CONFIG_ADDR, cfg);
  bool ok = cfg.magic == CONFIG_MAGIC &&
            cfg.version == CONFIG_VERSION &&
            cfg.crc == configCrc(cfg);
  if (!ok) {
    setDefaults();
    return false;
  }
  cfg.ssid[sizeof(cfg.ssid) - 1] = 0;
  cfg.pass[sizeof(cfg.pass) - 1] = 0;
  cfg.host[sizeof(cfg.host) - 1] = 0;
  return true;
}

void saveConfig() {
  cfg.crc = configCrc(cfg);
  EEPROM.put(CONFIG_ADDR, cfg);
  EEPROM.commit();
}

// Counts boots that end within BOOT_COUNT_WINDOW_MS. Three short boots in a
// row (unplug/replug) erases the settings, so a novice can always get back
// to setup mode without a button or a USB cable.
void checkBootCounter() {
  BootCounter bc;
  EEPROM.get(BOOT_ADDR, bc);
  if (bc.magic != BOOT_MAGIC) {
    bc.magic = BOOT_MAGIC;
    bc.count = 0;
  }
  bc.count++;

  if (bc.count >= RESET_BOOT_COUNT) {
    Serial.println("Factory reset: powered on 3 times in quick succession");
    bc.count = 0;
    EEPROM.put(BOOT_ADDR, bc);
    setDefaults();
    saveConfig();  // commits the boot counter too
    return;
  }

  EEPROM.put(BOOT_ADDR, bc);
  EEPROM.commit();
  bootCountPending = true;
}

void serviceBootCounter() {
  if (bootCountPending && millis() > BOOT_COUNT_WINDOW_MS) {
    BootCounter bc = {BOOT_MAGIC, 0};
    EEPROM.put(BOOT_ADDR, bc);
    EEPROM.commit();
    bootCountPending = false;
  }
}

// ---------------------------------------------------------------------------
// Relay
// ---------------------------------------------------------------------------

void applyBoard() {
  switch (cfg.board) {
    case BOARD_WEMOS_D1: relayPin = 5; relayActiveLow = false; break;  // D1
    case BOARD_ESP01S:   relayPin = 0; relayActiveLow = true;  break;  // GPIO0
    case BOARD_CUSTOM:   relayPin = cfg.customPin; relayActiveLow = cfg.customActiveLow != 0; break;
    default:             relayPin = -1; break;
  }

  if (relayPin >= 0) {
    // Set the "off" level before switching the pin to output so the relay
    // never clicks on during boot.
    int offLevel = relayActiveLow ? HIGH : LOW;
    digitalWrite(relayPin, offLevel);
    pinMode(relayPin, OUTPUT);
    digitalWrite(relayPin, offLevel);
  }
  relayOn = false;
}

bool setRelay(bool on) {
  if (relayPin < 0) return false;
  digitalWrite(relayPin, (on != relayActiveLow) ? HIGH : LOW);
  relayOn = on;
  return true;
}

const char* boardName(uint8_t b) {
  switch (b) {
    case BOARD_WEMOS_D1: return "Wemos D1 Mini + relay shield";
    case BOARD_ESP01S:   return "ESP-01S relay module";
    case BOARD_CUSTOM:   return "Custom";
    default:             return "Not chosen";
  }
}

bool isAllowedCustomPin(int pin) {
  for (uint8_t p : CUSTOM_PINS) {
    if (p == pin) return true;
  }
  return false;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String htmlEscape(const String& s) {
  String out;
  out.reserve(s.length() + 8);
  for (unsigned int i = 0; i < s.length(); i++) {
    char c = s.charAt(i);
    switch (c) {
      case '&':  out += F("&amp;");  break;
      case '<':  out += F("&lt;");   break;
      case '>':  out += F("&gt;");   break;
      case '"':  out += F("&quot;"); break;
      case '\'': out += F("&#39;");  break;
      default:   out += c;           break;
    }
  }
  return out;
}

// Letters, digits and hyphens; 1-32 chars; no leading/trailing hyphen.
bool validHostname(const String& h) {
  if (h.length() < 1 || h.length() > 32) return false;
  if (h.charAt(0) == '-' || h.charAt(h.length() - 1) == '-') return false;
  for (unsigned int i = 0; i < h.length(); i++) {
    char c = h.charAt(i);
    bool ok = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-';
    if (!ok) return false;
  }
  return true;
}

// Fills scanned[] with unique, non-empty SSIDs, strongest first.
void scanNetworks() {
  scannedCount = 0;
  int n = WiFi.scanNetworks();
  if (n <= 0) {
    WiFi.scanDelete();
    return;
  }

  int order[64];
  int count = n < 64 ? n : 64;
  for (int i = 0; i < count; i++) order[i] = i;
  for (int i = 0; i < count - 1; i++) {
    for (int j = i + 1; j < count; j++) {
      if (WiFi.RSSI(order[j]) > WiFi.RSSI(order[i])) {
        int t = order[i]; order[i] = order[j]; order[j] = t;
      }
    }
  }

  for (int k = 0; k < count && scannedCount < MAX_SCAN; k++) {
    String s = WiFi.SSID(order[k]);
    if (s.length() == 0) continue;
    bool dup = false;
    for (int j = 0; j < scannedCount; j++) {
      if (scanned[j] == s) { dup = true; break; }
    }
    if (!dup) scanned[scannedCount++] = s;
  }
  WiFi.scanDelete();
}

void scheduleRestart(uint32_t delayMs) {
  restartAt = millis() + delayMs;
  if (restartAt == 0) restartAt = 1;
}

// ---------------------------------------------------------------------------
// Web pages
// ---------------------------------------------------------------------------

const char PAGE_HEAD[] PROGMEM =
  "<!DOCTYPE html><html><head><meta charset=utf-8>"
  "<meta name=viewport content='width=device-width,initial-scale=1'>"
  "<title>CameraProbe Relay Setup</title><style>"
  "body{font-family:-apple-system,'Segoe UI',Arial,sans-serif;max-width:480px;margin:20px auto;padding:0 14px;color:#222}"
  "h1{font-size:1.4em}h2{font-size:1.1em;margin-top:28px}"
  "label{display:block;margin-top:14px;font-weight:600}"
  "input,select{width:100%;padding:8px;margin-top:4px;box-sizing:border-box;font-size:1em}"
  ".hint{font-weight:normal;color:#666;font-size:.9em}"
  ".msg{padding:10px;border-radius:6px;background:#e7f5e7}.err{background:#fde8e8}"
  ".status{padding:10px;border-radius:6px;background:#f2f2f2}"
  "button{margin-top:16px;padding:10px 16px;font-size:1em}"
  "fieldset{margin-top:16px;border:1px solid #ccc;border-radius:6px}"
  ".radio{font-weight:normal}.radio input{width:auto;margin-right:8px}"
  "</style></head><body><h1>CameraProbe Relay Setup</h1>";

void sendConfigPage(const String& message, bool isError) {
  String p;
  p.reserve(5000);
  p += FPSTR(PAGE_HEAD);

  // Current status
  p += F("<p class=status>");
  if (portalMode) {
    p += F("<b>Setup mode.</b> Not connected to a WiFi network.");
    if (cfg.ssid[0]) {
      p += F(" Couldn't join <b>");
      p += htmlEscape(cfg.ssid);
      p += F("</b>. It will try again in a few minutes if nobody is using this page.");
    }
  } else {
    p += F("Connected to <b>");
    p += htmlEscape(cfg.ssid);
    p += F("</b> as <b>http://");
    p += htmlEscape(cfg.host);
    p += F(".local</b> (");
    p += WiFi.localIP().toString();
    p += F(")");
  }
  p += F("<br>Relay board: <b>");
  p += boardName(cfg.board);
  p += F("</b></p>");

  if (message.length()) {
    p += isError ? F("<p class='msg err'>") : F("<p class=msg>");
    p += message;  // built from escaped/static text only
    p += F("</p>");
  }

  // --- Settings form ---
  String current = String(cfg.ssid);
  bool currentInList = false;
  for (int i = 0; i < scannedCount; i++) {
    if (scanned[i] == current) currentInList = true;
  }

  p += F("<form method=POST action=/save>");
  p += F("<label>WiFi network<select name=ssid_sel>");
  for (int i = 0; i < scannedCount; i++) {
    p += F("<option value='");
    p += htmlEscape(scanned[i]);
    p += F("'");
    if (scanned[i] == current) p += F(" selected");
    p += F(">");
    p += htmlEscape(scanned[i]);
    p += F("</option>");
  }
  p += F("<option value=''");
  if (scannedCount == 0 || (current.length() && !currentInList)) p += F(" selected");
  p += F(">Other (type the name below)</option></select></label>");

  p += F("<label>Or type the network name <span class=hint>(hidden networks, or one not listed above)</span>"
         "<input name=ssid_other maxlength=32 autocapitalize=none autocorrect=off value='");
  if (current.length() && !currentInList) p += htmlEscape(current);
  p += F("'></label>");

  p += F("<label>WiFi password <span class=hint>");
  if (cfg.ssid[0]) p += F("(leave blank to keep the saved password for the same network)");
  else             p += F("(leave blank for an open network)");
  p += F("</span><input type=password name=pass maxlength=64 autocomplete=off></label>");

  p += F("<label>Device name <span class=hint>(reach it at http://<i>name</i>.local - "
         "CameraProbe expects <b>onair</b> unless you change it there too)</span>"
         "<input name=host maxlength=32 autocapitalize=none autocorrect=off value='");
  p += htmlEscape(cfg.host);
  p += F("'></label>");

  p += F("<fieldset><legend>Relay board</legend>");
  const uint8_t boards[] = {BOARD_WEMOS_D1, BOARD_ESP01S, BOARD_CUSTOM};
  const char* boardLabels[] = {
    "Wemos D1 Mini + relay shield <span class=hint>(pin D1, on = HIGH)</span>",
    "ESP-01S relay module <span class=hint>(GPIO0, on = LOW)</span>",
    "Custom <span class=hint>(set pin and logic below)</span>"
  };
  for (int i = 0; i < 3; i++) {
    p += F("<label class=radio><input type=radio name=board value=");
    p += String(boards[i]);
    if (cfg.board == boards[i]) p += F(" checked");
    p += F(">");
    p += boardLabels[i];
    p += F("</label>");
  }

  p += F("<label>Custom relay pin <span class=hint>(only used for Custom)</span><select name=cpin>");
  for (uint8_t pin : CUSTOM_PINS) {
    p += F("<option value=");
    p += String(pin);
    if (cfg.customPin == pin) p += F(" selected");
    p += F(">GPIO");
    p += String(pin);
    if (pin == 0) p += F(" (ESP-01S relay)");
    if (pin == 5) p += F(" (D1)");
    p += F("</option>");
  }
  p += F("</select></label>");

  p += F("<label>Custom relay turns ON when the pin is <span class=hint>(only used for Custom)</span><select name=clow>");
  p += F("<option value=0");
  if (!cfg.customActiveLow) p += F(" selected");
  p += F(">HIGH</option><option value=1");
  if (cfg.customActiveLow) p += F(" selected");
  p += F(">LOW</option></select></label></fieldset>");

  p += F("<button type=submit>Save and reboot</button></form>");

  // --- Relay test (uses the saved board settings) ---
  if (relayPin >= 0) {
    p += F("<h2>Test the relay</h2>"
           "<button type=button onclick=\"t('on')\">Relay on</button> "
           "<button type=button onclick=\"t('off')\">Relay off</button> "
           "<span id=r class=hint></span>"
           "<script>function t(c){fetch('/'+c).then(function(r){return r.text()})"
           ".then(function(x){document.getElementById('r').textContent=x})}</script>");
  }

  // --- Maintenance ---
  p += F("<h2>Maintenance</h2>"
         "<p><a href=/update>Update firmware</a> <span class=hint>(upload a .bin file)</span></p>"
         "<form method=POST action=/reset onsubmit=\"return confirm('Erase all settings and restart in setup mode?')\">"
         "<button type=submit>Factory reset</button></form>"
         "<p class=hint>CameraProbe Relay firmware " FW_VERSION "</p></body></html>");

  server.send(200, "text/html", p);
}

void sendMessagePage(const String& title, const String& body) {
  String p;
  p.reserve(1200);
  p += FPSTR(PAGE_HEAD);
  p += F("<h2>");
  p += title;
  p += F("</h2><p>");
  p += body;
  p += F("</p></body></html>");
  server.send(200, "text/html", p);
}

// ---------------------------------------------------------------------------
// HTTP handlers
// ---------------------------------------------------------------------------

void sendNotConfigured() {
  server.send(503, "text/plain", "Relay board not configured - open /configure");
}

void handleRoot() {
  if (portalMode) {
    server.sendHeader("Location", "/configure", true);
    server.send(302, "text/plain", "");
    return;
  }
  server.send(200, "text/plain",
              "Camera Relay Controller\n"
              "/on\n"
              "/off\n"
              "/status\n"
              "/configure");
}

void handleOn() {
  if (setRelay(true)) server.send(200, "text/plain", "Relay ON");
  else sendNotConfigured();
}

void handleOff() {
  if (setRelay(false)) server.send(200, "text/plain", "Relay OFF");
  else sendNotConfigured();
}

void handleStatus() {
  if (relayPin < 0) { sendNotConfigured(); return; }
  server.send(200, "text/plain", relayOn ? "ON" : "OFF");
}

void handleConfigure() {
  // In setup mode the list was scanned once before the setup network
  // started (scanning while serving it can drop the phone's connection).
  if (!portalMode) scanNetworks();
  sendConfigPage("", false);
}

void handleSave() {
  String ssid = server.arg("ssid_other");
  ssid.trim();
  if (ssid.length() == 0) ssid = server.arg("ssid_sel");
  String pass = server.arg("pass");
  String host = server.arg("host");
  host.trim();
  host.toLowerCase();
  int board = server.arg("board").toInt();
  int cpin  = server.arg("cpin").toInt();
  int clow  = server.arg("clow").toInt();

  String err;
  if (ssid.length() == 0 || ssid.length() > 32)        err = F("Choose your WiFi network, or type its name.");
  else if (pass.length() > 64)                         err = F("That WiFi password is too long (64 characters max).");
  else if (pass.length() > 0 && pass.length() < 8)     err = F("WiFi passwords are at least 8 characters.");
  else if (!validHostname(host))                       err = F("Device name: use only letters, numbers and hyphens (e.g. onair).");
  else if (board < BOARD_WEMOS_D1 || board > BOARD_CUSTOM) err = F("Choose your relay board.");
  else if (board == BOARD_CUSTOM && !isAllowedCustomPin(cpin)) err = F("Choose a valid custom relay pin.");

  if (err.length()) {
    if (!portalMode) scanNetworks();
    sendConfigPage(err, true);
    return;
  }

  bool sameNetwork = (ssid == String(cfg.ssid));
  strlcpy(cfg.ssid, ssid.c_str(), sizeof(cfg.ssid));
  // Blank password keeps the saved one only for the same network;
  // for a different network, blank means an open network.
  if (pass.length() > 0 || !sameNetwork) {
    strlcpy(cfg.pass, pass.c_str(), sizeof(cfg.pass));
  }
  strlcpy(cfg.host, host.c_str(), sizeof(cfg.host));
  cfg.board           = (uint8_t)board;
  cfg.customPin       = isAllowedCustomPin(cpin) ? (uint8_t)cpin : 0;
  cfg.customActiveLow = clow ? 1 : 0;
  saveConfig();

  setRelay(false);

  String body = F("The device is restarting and will join <b>");
  body += htmlEscape(cfg.ssid);
  body += F("</b>.<br><br>Reconnect this phone or computer to that network, then open "
            "<b>http://");
  body += htmlEscape(cfg.host);
  body += F(".local/configure</b> to check it.<br><br>"
            "If the device can't join, the <b>ConfigRelay</b> network comes back "
            "in about 30 seconds so you can try again.");
  sendMessagePage("Settings saved", body);
  scheduleRestart(2000);
}

void handleReset() {
  setRelay(false);
  setDefaults();
  saveConfig();
  sendMessagePage("Settings erased",
                  "The device is restarting in setup mode. Join the <b>ConfigRelay</b> "
                  "WiFi network to set it up again.");
  scheduleRestart(2000);
}

void handleNotFound() {
  if (portalMode) {
    // Captive portal: any unknown URL (phone/OS connectivity checks
    // included) goes to the setup page, which makes phones pop it up.
    server.sendHeader("Location", String("http://") + apIP.toString() + "/configure", true);
    server.send(302, "text/plain", "");
    return;
  }
  server.send(404, "text/plain", "Not found");
}

// ---------------------------------------------------------------------------
// WiFi
// ---------------------------------------------------------------------------

bool connectWiFi() {
  if (cfg.ssid[0] == 0) return false;

  Serial.printf("Connecting to \"%s\"", cfg.ssid);
  WiFi.mode(WIFI_STA);
  WiFi.hostname(cfg.host);
  WiFi.begin(cfg.ssid, cfg.pass);

  uint32_t start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < CONNECT_TIMEOUT_MS) {
    delay(250);
    serviceBootCounter();
    Serial.print(".");
  }
  Serial.println();
  return WiFi.status() == WL_CONNECTED;
}

void startPortal() {
  portalMode = true;

  // Scan first, while only the station interface is up.
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  delay(100);
  scanNetworks();

  WiFi.mode(WIFI_AP);
  WiFi.softAPConfig(apIP, apIP, IPAddress(255, 255, 255, 0));
  WiFi.softAP(SETUP_AP_SSID);  // no password: open network

  dnsServer.setErrorReplyCode(DNSReplyCode::NoError);
  dnsServer.start(53, "*", apIP);

  lastApClientMs = millis();
  Serial.printf("Setup mode: join WiFi \"%s\" and open http://%s\n",
                SETUP_AP_SSID, apIP.toString().c_str());
}

// ---------------------------------------------------------------------------
// Arduino entry points
// ---------------------------------------------------------------------------

void setup() {
  Serial.begin(115200);
  delay(50);
  Serial.println();
  Serial.println("CameraProbe Relay firmware " FW_VERSION);

  EEPROM.begin(EEPROM_SIZE);
  if (!loadConfig()) Serial.println("No saved settings - starting fresh");
  checkBootCounter();
  applyBoard();  // relay off (or untouched if no board chosen) before WiFi starts

  WiFi.persistent(false);  // settings live in our own storage, not the SDK's
  WiFi.setAutoReconnect(true);

  if (connectWiFi()) {
    Serial.printf("Connected: %s  http://%s.local\n",
                  WiFi.localIP().toString().c_str(), cfg.host);
    if (MDNS.begin(cfg.host)) {
      MDNS.addService("http", "tcp", 80);
      Serial.println("mDNS responder started");
    }
  } else {
    startPortal();
  }

  server.on("/", handleRoot);
  server.on("/on", handleOn);
  server.on("/off", handleOff);
  server.on("/status", handleStatus);
  server.on("/configure", HTTP_GET, handleConfigure);
  server.on("/save", HTTP_POST, handleSave);
  server.on("/reset", HTTP_POST, handleReset);
  server.onNotFound(handleNotFound);
  httpUpdater.setup(&server);  // adds /update

  server.begin();
  Serial.println("HTTP server started");
}

void loop() {
  serviceBootCounter();

  if (portalMode) {
    dnsServer.processNextRequest();
    if (WiFi.softAPgetStationNum() > 0) {
      lastApClientMs = millis();
    } else if (cfg.ssid[0] && millis() - lastApClientMs > PORTAL_IDLE_RESTART_MS) {
      // Saved WiFi exists but wasn't reachable (e.g. router still booting
      // after a power cut). Nobody is using setup mode, so reboot and retry.
      Serial.println("Setup mode idle - restarting to retry saved WiFi");
      ESP.restart();
    }
  } else {
    MDNS.update();
    if (WiFi.status() == WL_CONNECTED) {
      wifiLostSince = 0;
    } else if (wifiLostSince == 0) {
      wifiLostSince = millis() | 1;
    } else if (millis() - wifiLostSince > WIFI_LOST_RESTART_MS) {
      Serial.println("WiFi lost for 5 minutes - restarting");
      ESP.restart();
    }
  }

  server.handleClient();

  if (restartAt && (int32_t)(millis() - restartAt) >= 0) {
    delay(100);
    ESP.restart();
  }
}
