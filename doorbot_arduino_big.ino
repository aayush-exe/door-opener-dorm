#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <ESP32Servo.h>

/*
  ESP32 BLE UART Door Controller (iOS-only, sorry guys)

  Commands (send as ASCII text):
    AUTH [pin]     -> authenticate (can change PIN below)
    OPEN           -> unlock
    CLOSE          -> lock
    PING           -> replies PONG
    STATUS         -> replies current status
*/

// Change these to customize to your use-case
const char* DEVICE_NAME = "DormDoor-ESP32";
const char* AUTH_PIN = "1234"; // changethis for no hack

// Edit for your specific servo setup as well
const int SERVO_PIN = 18;            // PWM-capable pin
const int SERVO_LOCK_POS = 150;  
const int SERVO_UNLOCK_POS = 30;
const int SERVO_MOVE_MS = 10000;     // how long to hold at target (ms)

Servo doorServo;

// ---- Security (very basic PIN gate) ----
bool isAuthed = false;
unsigned long authExpiryMs = 0;
const unsigned long AUTH_TTL_MS = 2UL * 60UL * 1000UL; // 2 minutes

// ---- BLE UUIDs (Nordic UART) ----
#define SERVICE_UUID           "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_RX "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
#define CHARACTERISTIC_UUID_TX "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"

// ---- BLE globals ----
BLEServer* pServer = nullptr;
BLECharacteristic* pTxCharacteristic = nullptr;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// ---- Door state ----
enum DoorState { STATE_LOCKED, STATE_UNLOCKED, STATE_UNKNOWN };
DoorState doorState = STATE_UNKNOWN;

// ---- NON-BLOCKING pulse state (added) ----
bool isPulsing = false;
unsigned long pulseStartMs = 0;

// ---- Helper: send a line over TX (Notify) ----
void notifyLine(const String& msg) {
  if (!pTxCharacteristic) return;
  pTxCharacteristic->setValue((uint8_t*)msg.c_str(), msg.length());
  pTxCharacteristic->notify();
}

// ---- Helper: trim & uppercase copy ----
String uptrim(const String& s) {
  String t = s;
  t.trim();
  t.toUpperCase();
  return t;
}

// ---- Actuation Routines ----
void setLocked() {
  doorState = STATE_LOCKED;
  notifyLine("STATUS:LOCKED");
  doorServo.write(SERVO_LOCK_POS);
}

// NON-BLOCKING pulse: start pulse and return immediately (changed)
void pulseUnlock() {
  if (isPulsing) return;               // already pulsing -> ignore
  isPulsing = true;
  pulseStartMs = millis();

  doorState = STATE_UNLOCKED;
  notifyLine("STATUS:UNLOCKED");
  doorServo.write(SERVO_UNLOCK_POS);
}

bool checkAuthFresh() {
  if (!isAuthed) return false;
  if (millis() > authExpiryMs) {
    isAuthed = false;
    notifyLine("AUTH:EXPIRED");
    return false;
  }
  return true;
}

// ---- BLE callbacks ----
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* s) override {
    deviceConnected = true;
    notifyLine("HELLO");
  }
  void onDisconnect(BLEServer* s) override {
    deviceConnected = false;
    isAuthed = false; // drop auth on disconnect
  }
};

class RxCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pChar) override {
    String rx = pChar->getValue();      // use Arduino String
    if (rx.length() == 0) return;
    String cmd = rx;                    // already a String

    cmd.trim();

    // Optional: show raw
    Serial.print("[RX] "); Serial.println(cmd);

    // Tokenize first word (command)
    int sp = cmd.indexOf(' ');
    String head = sp == -1 ? cmd : cmd.substring(0, sp);
    String tail = sp == -1 ? ""  : cmd.substring(sp + 1);

    String HEAD = uptrim(head);
    String TAIL = tail; TAIL.trim(); // tail may be PIN, etc.

    if (HEAD == "PING") {
      notifyLine("PONG");
      return;
    }

    if (HEAD == "STATUS") {
      switch (doorState) {
        case STATE_LOCKED:   notifyLine("STATUS:LOCKED");   break;
        case STATE_UNLOCKED: notifyLine("STATUS:UNLOCKED"); break;
        default:             notifyLine("STATUS:UNKNOWN");  break;
      }
      return;
    }

    if (HEAD == "AUTH") {
      if (TAIL.length() == 0) { notifyLine("ERR:AUTH:NO_PIN"); return; }
      if (TAIL.equals(String(AUTH_PIN))) {
        isAuthed = true;
        authExpiryMs = millis() + AUTH_TTL_MS;
        notifyLine("AUTH:OK");
      } else {
        isAuthed = false;
        notifyLine("ERR:AUTH:BAD_PIN");
      }
      return;
    }

    // Commands below require fresh auth
    if (!checkAuthFresh()) { notifyLine("ERR:AUTH:REQUIRED"); return; }

    if (HEAD == "OPEN") {
      if (isPulsing) { 
        notifyLine("BUSY:IGNORING_OPEN");
        return;
      }
      notifyLine("Unlocking...");
      pulseUnlock();  // non-blocking start
      return;
    }

    if (HEAD == "CLOSE") {
      setLocked();
      return;
    }

    notifyLine("ERR:UNKNOWN_CMD");
  }
};

// ---- Setup & Loop ----
void setup() {
  Serial.begin(115200);
  delay(200);

  // Attach servo (pick reasonable 50 Hz limits for typical SG90/MG90S)
  // Adjust min/max us as needed to match your servo travel safely.
  doorServo.setPeriodHertz(50);
  doorServo.attach(SERVO_PIN, 500, 2500);

  // Start BLE
  BLEDevice::init(DEVICE_NAME);
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);

  // TX (Notify)
  pTxCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID_TX,
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pTxCharacteristic->addDescriptor(new BLE2902());

  // RX (Write)
  BLECharacteristic* pRxCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID_RX,
    BLECharacteristic::PROPERTY_WRITE
  );
  pRxCharacteristic->setCallbacks(new RxCallbacks());

  pService->start();
  // After pService->start();
  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);   // << important
  pAdvertising->setScanResponse(true);          // include name/UUID in scan response
  pAdvertising->setMinPreferred(0x06);          // optional: better iOS compatibility
  pAdvertising->setMinPreferred(0x12);          // optional: better iOS compatibility
  BLEDevice::startAdvertising();

  pServer->getAdvertising()->start();

  notifyLine("READY");
  // Optional: default to locked position on boot
  doorServo.write(SERVO_LOCK_POS);
}

void loop() {
  // Handle reconnect advertising
  if (!deviceConnected && oldDeviceConnected) {
    delay(500);
    pServer->startAdvertising();
    oldDeviceConnected = deviceConnected;
  }
  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = deviceConnected;
  }

  // Soft auth timeout ping (optional)
  if (isAuthed && millis() > authExpiryMs) {
    isAuthed = false;
    notifyLine("AUTH:EXPIRED");
  }

  // NON-BLOCKING pulse completion (added)
  if (isPulsing && (millis() - pulseStartMs >= SERVO_MOVE_MS)) {
    setLocked();           // returns servo to lock + notifies
    isPulsing = false;
  }

  delay(10);
}
