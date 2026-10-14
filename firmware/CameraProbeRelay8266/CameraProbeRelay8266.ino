/*
 * CameraProbe Relay Firmware
 *
 * Matches CameraProbe's default config (relay.host = "onair.local",
 * relay.port = 80): responds to GET /on and GET /off with a plain-text
 * reply, plus a /status endpoint for checking the current relay state.
 */

#include <ESP8266WiFi.h>
#include <ESP8266WebServer.h>
#include <ESP8266mDNS.h>
#include "secrets.h" // copy secrets.h.example to secrets.h and fill in your WiFi credentials

const char* ssid = WIFI_SSID;
const char* password = WIFI_PASSWORD;
const char* hostname = NET_HOSTNAME;

ESP8266WebServer server(80);

//const int relayPin = D1; // Wemo D1 Mini  - On=HIGH Off=LOW (See Below)
const int relayPin = 0; // Generic ESP8266 Relay board - On=LOW Off=HIGH (See Below)
//                      // If 8266 is a 2-relay board, the second relay pin is 2
                        

void handleRoot() {
  server.send(200, "text/plain",
              "Camera Relay Controller\n"
              "/on\n"
              "/off\n"
              "/status");
}

void handleOn() {
  digitalWrite(relayPin, LOW);
  server.send(200, "text/plain", "Relay ON");
}

void handleOff() {
  digitalWrite(relayPin, HIGH);
  server.send(200, "text/plain", "Relay OFF");
}

void handleStatus() {

  String state =
      // digitalRead(relayPin) ? "ON" : "OFF"; //Wemos Version
      digitalRead(relayPin) ? "OFF" : "ON"; //8266 Version
  server.send(200, "text/plain", state);
}

void setup() {

  pinMode(relayPin, OUTPUT);
  digitalWrite(relayPin, HIGH); // Wemos D1 = LOW, 8266=HIGH

  Serial.begin(115200);

  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid, password);

  Serial.print("Connecting ");

  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }


  if (MDNS.begin(hostname)) { //edit this line to change the local hostname 
      Serial.println("mDNS responder started");
  }

  Serial.println();
  Serial.print("Connected: ");
  Serial.println(WiFi.localIP());

  server.on("/", handleRoot);
  server.on("/on", handleOn);
  server.on("/off", handleOff);
  server.on("/status", handleStatus);

  server.begin();

  Serial.println("HTTP Server Started");
}

void loop() {
  MDNS.update();
  server.handleClient();
}
