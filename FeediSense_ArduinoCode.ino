#include <Arduino.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <Servo.h>
#include <OneWire.h>
#include <DallasTemperature.h>
#include "HX711.h"
#include <SoftwareSerial.h>
#include <Keypad.h>
#include <RTClib.h>
#include <EEPROM.h>

// -----------------------------------------------------------------------------
// PIN ASSIGNMENTS
// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------
// PIN ASSIGNMENTS & DO CONFIGURATION
// -----------------------------------------------------------------------------
#define DO_PIN A1
#define VREF 5000
#define ADC_RES 1024
#define TWO_POINT_CALIBRATION 0
#define CAL1_V (1684) //mv
#define CAL1_T (30)   //℃
#define CAL2_V (1684) //mv
#define CAL2_T (29.5)   //℃
#define ANALOG_IN_PIN A7


#define LOADCELL_DOUT_PIN 66
#define LOADCELL_SCK_PIN 67
#define SENSOR_PIN 7

const int rly1 = 10;
const int RFpingPin = 5;    // ultrasonic trigger
const int RFrxPin = 6;      // ultrasonic echo
const int pinMyServo1 = 8;  // hopper servo
const int pinMyServo2 = 9;  // ejector servo

// -----------------------------------------------------------------------------
// OBJECTS
// -----------------------------------------------------------------------------
SoftwareSerial mySerial(68, 69);
Servo myservo1, myservo2;
LiquidCrystal_I2C lcd(0x27, 20, 4);
OneWire oneWire(SENSOR_PIN);
HX711 scale;
DallasTemperature tempSensor(&oneWire);
RTC_DS3231 rtc;

// Keypad setup
const byte ROWS = 4, COLS = 4;
char hexaKeys[ROWS][COLS] = {
  {'1', '2', '3', 'A'},
  {'4', '5', '6', 'B'},
  {'7', '8', '9', 'C'},
  {'*', '0', '#', 'D'}
};
byte rowPins[ROWS] = {29, 28, 27, 26};
byte colPins[COLS] = {25, 24, 23, 22};
Keypad customKeypad = Keypad(makeKeymap(hexaKeys), rowPins, colPins, ROWS, COLS);

// -----------------------------------------------------------------------------
// GLOBAL VARIABLES
// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------
// GLOBAL VARIABLES
// -----------------------------------------------------------------------------
float calibration_value = 21.34 + 10;
float calibration_factor = -92;

// --- DO Sensor Variables ---
const uint16_t DO_Table[41] = {
  14460, 14220, 13820, 13440, 13090, 12740, 12420, 12110, 11810, 11530,
  11260, 11010, 10770, 10530, 10300, 10080, 9860, 9660, 9460, 9270,
  9080, 8900, 8730, 8570, 8410, 8250, 8110, 7960, 7820, 7690,
  7560, 7430, 7300, 7180, 7070, 6950, 6840, 6730, 6630, 6530, 6410
};

uint8_t Temperaturet;
uint16_t ADC_Raw;
uint16_t ADC_Voltage;



String tempMobile = "";
String keyd;
String clientNum = "+639000000000";
String ffData;

int manualFeedGrams = 0;
bool isManualDispense = false;
bool isDraining = false;
// Drain related state variables removed. The feeder no longer supports
// automatic or manual drain operations.

const int RISK_LOW = 1;
const int RISK_MED = 2;
const int RISK_HIGH = 3;
int currentRisk = RISK_LOW;
int previousRisk = RISK_LOW;

float smoothedPh = 7.0;

float lastTemp = 0.0;
float lastPh = 0.0;
float lastDo = 0.0;
float lastBattery = 0.0;

int buffer_arr[10];
long RFduration, RFinches;

// -----------------------------------------------------------------------------
// SCHEDULE PERSISTENCE (RTC + EEPROM)
// -----------------------------------------------------------------------------
struct ScheduleSlot {
  uint8_t enabled;
  uint8_t hour;
  uint8_t minute;
  uint16_t grams;
  uint32_t lastRunDateCode; // YYYYMMDD
};

ScheduleSlot schedules[4];

const uint16_t EEPROM_MAGIC = 4206;
const int EEPROM_MAGIC_ADDR = 0;
const int EEPROM_SCHEDULES_ADDR = EEPROM_MAGIC_ADDR + sizeof(EEPROM_MAGIC);

// -----------------------------------------------------------------------------
// FORWARD DECLARATIONS
// -----------------------------------------------------------------------------
float getTemp();
float getPhValue();
float getDo();
float getVoltage();
float getWeightNow();
void moveServo1(Servo &, int);
void moveServo2(Servo &, int);
void sendSMS(String, String);
void updateSerial();
int feedAmt();
long microsecondsToCentimeters(long);
bool dispenseNow(int, String &);
void executeFeed(int, bool, int scheduleIndex = -1, String scheduleTimeLabel = "");
void safeStopFeeder();
void refreshSensorState();
void checkDueSchedules();
void loadSchedulesFromEEPROM();
void saveSchedulesToEEPROM();
void clearSchedules();
uint32_t makeDateCode(const DateTime &dt);
String twoDigits(int value);
String formatTimeLabel(uint8_t hour, uint8_t minute);
String formatRtcStamp(const DateTime &dt);
bool parseTimeLabel(const String &value, uint8_t &hour, uint8_t &minute);
int splitCsv(const String &input, String parts[], int maxParts);
void handleRtcSet(String msg);
void handleScheduleSet(String msg);
void handleSync(String msg);

// -----------------------------------------------------------------------------
// SETUP
// -----------------------------------------------------------------------------
void setup() {
  Serial.begin(9600);
  mySerial.begin(9600);
  // Increase the timeout on the GSM serial to allow the full SMS body to arrive.
  // A very short timeout (e.g. 100ms) can cause partial reads which then
  // trigger RTC,ERR,BAD_FORMAT or SCHED,ERR,BAD_FORMAT.  One second is a
  // reasonable compromise between responsiveness and reliability.
  mySerial.setTimeout(1000);

  Wire.begin();
  tempSensor.begin();

  lcd.init();
  lcd.backlight();
  lcd.setCursor(0, 0);
  lcd.print("4206 FISH FEEDER");
  // Display a wait message on the third row during initialization. This
  // matches the legacy UI where row 2 (index 0‑based) shows "PLEASE WAIT...".
  lcd.setCursor(0, 2);
  lcd.print("PLEASE WAIT...");

  pinMode(rly1, OUTPUT);
  digitalWrite(rly1, HIGH);

  myservo1.detach();
  myservo2.detach();

  scale.begin(LOADCELL_DOUT_PIN, LOADCELL_SCK_PIN);
  scale.set_scale();
  delay(2000);
  scale.tare();
  scale.set_scale(calibration_factor);

  moveServo2(myservo1, pinMyServo1);
  moveServo1(myservo2, pinMyServo2);

  mySerial.println("AT+CMGF=1");
  delay(100);
  mySerial.println("AT+CNMI=2,2,0,0,0");
  delay(100);

  if (!rtc.begin()) {
  Serial.println("RTC NOT FOUND");
}

  // Fallback only. In production the app will also send RTC,SET.
  if (rtc.lostPower()) {
    rtc.adjust(DateTime(F(__DATE__), F(__TIME__)));
  }

  loadSchedulesFromEEPROM();

  // Do not clear and print "SYSTEM READY" or timestamp here. The display
  // will be managed by the main loop to show risk, feed level and manual
  // feed/drain status. The "PLEASE WAIT..." message will be overwritten
  // by the first feed level update.
}

// -----------------------------------------------------------------------------
// MAIN LOOP
// -----------------------------------------------------------------------------
void loop() {
  updateSerial();

  // Manual feed via keypad. When a manual drain is active the bottom line
  // shows drain status and manual feed input is ignored. Otherwise we
  // collect keypad input and update the prompt on row 3.
  char customKey = customKeypad.getKey();
  // Manual draining has been removed; always allow manual feed entry via keypad.
  if (customKey == '*') {
    keyd = "";
    lcd.setCursor(0, 3);
    lcd.print("MANUAL FEEDING:CLEAR");
    delay(1000);
  } else if (customKey == '#') {
    manualFeedGrams = keyd.toInt();
    keyd = "";
    isManualDispense = true;
    lcd.setCursor(0, 3);
    lcd.print("MANUAL FEEDING:DONE ");
    delay(1000);
  } else if (customKey) {
    keyd += customKey;
  }
  // Display the current manual feed entry on the bottom line
  lcd.setCursor(0, 3);
  String keyLine = String("MANUAL FEEDING: ") + keyd;
  while (keyLine.length() < 20) keyLine += " ";
  lcd.print(keyLine.substring(0, 20));

  // Feed level display
  int feedLevel = feedAmt();
  lcd.setCursor(0, 2);
  if (feedLevel >= 27) {
    lcd.print("FEEDS LEVEL: REFILL ");
  } else if (feedLevel >= 25) {
    lcd.print("FEEDS LEVEL: LOW    ");
  } else if (feedLevel >= 22) {
    lcd.print("FEEDS LEVEL: MID    ");
  } else {
    lcd.print("FEEDS LEVEL: FULL   ");
  }

  // Bottom line update is handled above depending on manual feed or drain state.

  // Read current water values and risk first, before any scheduled/manual feed execution
  refreshSensorState();

  // RTC-based schedule execution
  checkDueSchedules();

  // Drain functionality has been removed; ignore any legacy drain commands.

  if (isManualDispense) {
    isManualDispense = false;
    executeFeed(manualFeedGrams, false);
  }

  // Actively listen to the GSM module while waiting 150ms
  unsigned long waitStart = millis();
  while (millis() - waitStart < 150) {
    updateSerial(); // Keeps the buffer drained!
  }
}

// -----------------------------------------------------------------------------
// RTC / SCHEDULE HELPERS
// -----------------------------------------------------------------------------
void clearSchedules() {
  for (int i = 0; i < 4; i++) {
    schedules[i].enabled = 0;
    schedules[i].hour = 0;
    schedules[i].minute = 0;
    schedules[i].grams = 0;
    schedules[i].lastRunDateCode = 0;
  }
}

void loadSchedulesFromEEPROM() {
  uint16_t magic = 0;
  EEPROM.get(EEPROM_MAGIC_ADDR, magic);

  if (magic != EEPROM_MAGIC) {
    clearSchedules();
    saveSchedulesToEEPROM();
    return;
  }

  for (int i = 0; i < 4; i++) {
    EEPROM.get(EEPROM_SCHEDULES_ADDR + (i * (int)sizeof(ScheduleSlot)), schedules[i]);
    if (schedules[i].hour > 23 || schedules[i].minute > 59) {
      schedules[i].enabled = 0;
      schedules[i].hour = 0;
      schedules[i].minute = 0;
      schedules[i].grams = 0;
      schedules[i].lastRunDateCode = 0;
    }
  }
}

void saveSchedulesToEEPROM() {
  EEPROM.put(EEPROM_MAGIC_ADDR, EEPROM_MAGIC);
  for (int i = 0; i < 4; i++) {
    EEPROM.put(EEPROM_SCHEDULES_ADDR + (i * (int)sizeof(ScheduleSlot)), schedules[i]);
  }
}

uint32_t makeDateCode(const DateTime &dt) {
  return ((uint32_t)dt.year() * 10000UL) + ((uint32_t)dt.month() * 100UL) + (uint32_t)dt.day();
}

String twoDigits(int value) {
  return (value < 10) ? ("0" + String(value)) : String(value);
}

String formatTimeLabel(uint8_t hour, uint8_t minute) {
  return twoDigits(hour) + ":" + twoDigits(minute);
}

String formatRtcStamp(const DateTime &dt) {
  return String(dt.year()) + "-" + twoDigits(dt.month()) + "-" + twoDigits(dt.day()) +
         " " + twoDigits(dt.hour()) + ":" + twoDigits(dt.minute()) + ":" + twoDigits(dt.second());
}

bool parseTimeLabel(const String &value, uint8_t &hour, uint8_t &minute) {
  int colon = value.indexOf(':');
  if (colon == -1) return false;

  int hh = value.substring(0, colon).toInt();
  int mm = value.substring(colon + 1).toInt();
  if (hh < 0 || hh > 23 || mm < 0 || mm > 59) return false;

  hour = (uint8_t)hh;
  minute = (uint8_t)mm;
  return true;
}

int splitCsv(const String &input, String parts[], int maxParts) {
  int count = 0;
  int start = 0;

  while (count < maxParts) {
    int comma = input.indexOf(',', start);
    if (comma == -1) {
      parts[count++] = input.substring(start);
      break;
    }
    parts[count++] = input.substring(start, comma);
    start = comma + 1;
  }

  return count;
}

void checkDueSchedules() {
  DateTime now = rtc.now();
  uint32_t today = makeDateCode(now);

  for (int i = 0; i < 4; i++) {
    if (!schedules[i].enabled || schedules[i].grams <= 0) continue;
    if (schedules[i].lastRunDateCode == today) continue;

    if (now.hour() == schedules[i].hour && now.minute() == schedules[i].minute && now.second() < 5) {
      schedules[i].lastRunDateCode = today;
      saveSchedulesToEEPROM();
      executeFeed(schedules[i].grams, true, i + 1, formatTimeLabel(schedules[i].hour, schedules[i].minute));
    }
  }
}

void handleRtcSet(String msg) {
  String parts[12];
  int count = splitCsv(msg, parts, 12);
  if (count < 8) {
    sendSMS("RTC,ERR,BAD_FORMAT", clientNum);
    return;
  }

  int year = parts[2].toInt();
  int month = parts[3].toInt();
  int day = parts[4].toInt();
  int hour = parts[5].toInt();
  int minute = parts[6].toInt();
  int second = parts[7].toInt();

  if (year < 2024 || month < 1 || month > 12 || day < 1 || day > 31 || hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 59) {
    sendSMS("RTC,ERR,INVALID_VALUE", clientNum);
    return;
  }

  rtc.adjust(DateTime(year, month, day, hour, minute, second));
  sendSMS("RTC,OK," + formatRtcStamp(rtc.now()), clientNum);
}

void handleScheduleSet(String msg) {
  // Split into CSV parts; allow up to 20 fields.
  String parts[20];
  int count = splitCsv(msg, parts, 20);

  // Need at least "SCHED,SET" and one slot; otherwise fail.
  if (count < 3) {
    sendSMS("SCHED,ERR,BAD_FORMAT", clientNum);
    return;
  }

  int activeCount = 0;
  // Reset all four slots.
  for (int i = 0; i < 4; i++) {
    schedules[i].enabled = 0;
    schedules[i].hour = 0;
    schedules[i].minute = 0;
    schedules[i].grams = 0;
    schedules[i].lastRunDateCode = 0;
  }

  // Each slot is a triple of enabled,time,grams starting at index 2.
  for (int i = 0; i < 4; i++) {
    int base = 2 + i * 3;
    if (base >= count) continue;  // not enough tokens left

    int enabled = (base < count && parts[base].length() > 0) ? parts[base].toInt() : 0;
    String timeLabel = (base + 1 < count) ? parts[base + 1] : "";
    int grams = (base + 2 < count && parts[base + 2].length() > 0) ? parts[base + 2].toInt() : 0;

    timeLabel.trim();
    timeLabel.replace("\r", "");
    timeLabel.replace("\n", "");

    if (enabled == 1 && grams > 0) {
      uint8_t hh = 0, mm = 0;
      if (!parseTimeLabel(timeLabel, hh, mm)) {
        sendSMS("SCHED,ERR,BAD_TIME_SLOT_" + String(i + 1), clientNum);
        return;
      }
      schedules[i].enabled = 1;
      schedules[i].hour = hh;
      schedules[i].minute = mm;
      schedules[i].grams = grams;
      schedules[i].lastRunDateCode = 0;
      activeCount++;
    }
  }

  saveSchedulesToEEPROM();
  sendSMS("SCHED,SAVED," + String(activeCount), clientNum);
}
// ---------------------------------------------------------------------------
// NEW COMMAND HANDLERS (SYNC: and SCH:)
// The prototype can also accept a simplified comma/semicolon delimited format
// for setting the RTC and daily schedules.  SYNC:YYYY,MM,DD,HH,MM,SS will
// adjust the DS3231 clock and respond with RTC,OK,<timestamp>, while
// SCH:HHMM,WW;HHMM,WW;... will update up to four feeding slots.  Unused
// positions should be sent as 9999,0 so the Arduino can ignore them.
void handleSync(String msg) {
  // Accept simplified SYNC commands of the form SYNC:YYYY,MM,DD,HH,MM,SS.
  // Remove the prefix and any control characters. The GSM module may
  // append invisible \r, \n or commas; we ignore trailing empty tokens.
  if (msg.startsWith("SYNC:")) {
    msg.remove(0, 5);
  }
  msg.trim();
  msg.replace("\r", "");
  msg.replace("\n", "");

  // Split on commas. We use splitCsv to collect up to 10 parts.
  String parts[10];
  int numParts = splitCsv(msg, parts, 10);

  // Collect the first six non‑empty tokens and convert them to integers.
  int values[6];
  int count = 0;
  for (int i = 0; i < numParts && count < 6; i++) {
    if (parts[i].length() == 0) continue;
    values[count++] = parts[i].toInt();
  }
  if (count < 6) {
    sendSMS("RTC,ERR,BAD_FORMAT", clientNum);
    return;
  }

  int year   = values[0];
  int month  = values[1];
  int day    = values[2];
  int hour   = values[3];
  int minute = values[4];
  int second = values[5];

  // Validate date/time boundaries; reject clearly invalid numbers.
  if (year < 2024 || month < 1 || month > 12 || day < 1 || day > 31 ||
      hour < 0 || hour > 23 || minute < 0 || minute > 59 || second < 0 || second > 59) {
    sendSMS("RTC,ERR,INVALID_VALUE", clientNum);
    return;
  }

  rtc.adjust(DateTime(year, month, day, hour, minute, second));
  sendSMS("RTC,OK," + formatRtcStamp(rtc.now()), clientNum);
}

// Handle individual schedule slots: S1, S2, S3, or S4
void handleSingleSchedule(int slotIndex, String msg) {
  // Strip the prefix (e.g., "S1:")
  msg.remove(0, 3); 
  msg.trim();

  // If the user clears the schedule from the app
  if (msg == "CLEAR" || msg == "" || msg == ";") {
    schedules[slotIndex].enabled = 0;
    schedules[slotIndex].hour = 0;
    schedules[slotIndex].minute = 0;
    schedules[slotIndex].grams = 0;
    schedules[slotIndex].lastRunDateCode = 0;
    saveSchedulesToEEPROM();
    sendSMS("SCHED,CLEARED,S" + String(slotIndex + 1), clientNum);
    return;
  }

  // Find the comma separating time and grams
  int comma = msg.indexOf(',');
  if (comma == -1) {
    sendSMS("SCHED,ERR,NO_COMMA", clientNum);
    return;
  }

  String timeStr = msg.substring(0, comma);
  String weightStr = msg.substring(comma + 1);
  weightStr.replace(";", ""); // Clean up any stray semicolons

  if (timeStr.length() >= 4) {
    int hh = timeStr.substring(0, 2).toInt();
    int mm = timeStr.substring(2, 4).toInt();
    int grams = weightStr.toInt();

    // Validate the numbers
    if (hh >= 0 && hh <= 23 && mm >= 0 && mm <= 59 && grams > 0) {
      schedules[slotIndex].enabled = 1;
      schedules[slotIndex].hour = (uint8_t)hh;
      schedules[slotIndex].minute = (uint8_t)mm;
      schedules[slotIndex].grams = (uint16_t)grams;
      schedules[slotIndex].lastRunDateCode = 0; // Reset so it runs today
      
      saveSchedulesToEEPROM();
      sendSMS("SCHED,SAVED,S" + String(slotIndex + 1), clientNum);
      return;
    }
  }
  sendSMS("SCHED,ERR,BAD_VALS", clientNum);
}


// -----------------------------------------------------------------------------
// SENSOR / RISK
// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------
// SENSOR / RISK
// -----------------------------------------------------------------------------
void refreshSensorState() {
  lastDo = getDo();
  lastPh = getPhValue();
  lastTemp = getTemp();
  lastBattery = getVoltage();

  int doRisk = (lastDo > 5.0) ? 1 : (lastDo < 3.0) ? 3 : 2;
  int phRisk = (lastPh < 5.5 || lastPh > 10.0) ? 3 : ((lastPh >= 5.5 && lastPh <= 6.4) || (lastPh >= 8.6 && lastPh <= 10.0)) ? 2 : 1;
  int tRisk = (lastTemp < 20.0 || lastTemp > 35.0) ? 3 : (lastTemp >= 24.0 && lastTemp <= 32.0) ? 1 : 2;

  if (doRisk == 3 || phRisk == 3 || tRisk == 3) {
    currentRisk = RISK_HIGH;
    lcd.setCursor(0, 1);
    lcd.print("WATER RISK: HIGH    ");
  } else if (doRisk == 2 || phRisk == 2 || tRisk == 2) {
    currentRisk = RISK_MED;
    lcd.setCursor(0, 1);
    lcd.print("WATER RISK: MID     ");
  } else {
    currentRisk = RISK_LOW;
    lcd.setCursor(0, 1);
    lcd.print("WATER RISK: LOW     ");
  }

  if (currentRisk != previousRisk) {
    ffData = String(lastTemp, 1) + "," + String(lastPh, 1) + "," + String(lastDo, 1);
    sendSMS(ffData, clientNum);
  }

  previousRisk = currentRisk;
}
// -----------------------------------------------------------------------------
// FEED EXECUTION
// -----------------------------------------------------------------------------
void safeStopFeeder() {
  myservo1.attach(pinMyServo1);
  myservo1.write(170);
  delay(500);
  myservo1.detach();

  myservo2.attach(pinMyServo2);
  myservo2.write(10);
  delay(500);
  myservo2.detach();

  digitalWrite(rly1, HIGH);
}

void executeFeed(int targetFeed, bool isScheduled, int scheduleIndex, String scheduleTimeLabel) {
  String failReason = "";
  int originalTarget = targetFeed;

  if (targetFeed <= 0) {
    return;
  }

  if (isDraining) {
    if (isScheduled) sendSMS("FEED,ABORTED,SCHED," + String(scheduleIndex) + "," + scheduleTimeLabel + ",MAINTENANCE_MODE_ACTIVE", clientNum);
    else sendSMS("FEED,ABORTED,MANUAL,MAINTENANCE_MODE_ACTIVE", clientNum);
    return; // Stop the feed completely
  }

  // --- Water Risk Safety Checks (Unchanged) ---
  if (currentRisk == RISK_HIGH) {
    if (isScheduled) sendSMS("FEED,ABORTED,SCHED," + String(scheduleIndex) + "," + scheduleTimeLabel + ",HIGH_RISK", clientNum);
    else sendSMS("FEED,ABORTED,MANUAL,HIGH_RISK", clientNum);
    safeStopFeeder();
    return;
  }

  if (currentRisk == RISK_MED) {
    targetFeed = (targetFeed * 80L) / 100L;
    if (targetFeed < 1 && originalTarget > 0) targetFeed = 1;
    if (isScheduled) sendSMS("FEED,REDUCED,SCHED," + String(scheduleIndex) + "," + scheduleTimeLabel + "," + String(originalTarget) + "," + String(targetFeed), clientNum);
    else sendSMS("FEED,REDUCED,MANUAL," + String(originalTarget) + "," + String(targetFeed), clientNum);
  }

  // --- Dispensing Logic ---
  int fullPortions = targetFeed / 50;
  int remainder = targetFeed % 50;
  bool success = true;
  int totalDispensed = 0; // NEW: Keep track of successfully dropped feed

  for (int i = 0; i < fullPortions; i++) {
    int roundDispensed = 0;
    if (!dispenseNow(50, failReason, roundDispensed)) {
      totalDispensed += roundDispensed;
      success = false;
      break; // Abort further chunks if this one failed
    }
    totalDispensed += roundDispensed;
  }

  if (success && remainder > 0) {
    int roundDispensed = 0;
    if (!dispenseNow(remainder, failReason, roundDispensed)) {
      success = false;
    }
    totalDispensed += roundDispensed;
  }

  // --- Final Reporting Logic (Matching your exact request) ---
  // --- Final Reporting Logic ---
  if (success) {
    // SCENARIO 1: 100% Success (CORRECTED - Reports TARGET weight)
    if (isScheduled) sendSMS("FEED,DONE,SCHED," + String(scheduleIndex) + "," + scheduleTimeLabel + "," + String(targetFeed), clientNum);
    else sendSMS("FEED,DONE,MANUAL," + String(targetFeed), clientNum);
  } else {
    if (failReason.length() == 0) failReason = "UNKNOWN";

    // SCENARIO 2: Partial feed (It failed, but we ALREADY successfully dispensed SOME feed)
    if (totalDispensed > 0) {
      if (isScheduled) sendSMS("FEED,PARTIAL,SCHED," + String(scheduleIndex) + "," + scheduleTimeLabel + "," + String(targetFeed) + "," + String(totalDispensed) + "," + failReason, clientNum);
      else sendSMS("FEED,PARTIAL,MANUAL," + String(targetFeed) + "," + String(totalDispensed) + "," + failReason, clientNum);
    } 
    // SCENARIO 3: Total failure (Failed immediately, 0g dispensed, 3-second rule triggered)
    else {
      if (isScheduled) sendSMS("FEED,FAIL,SCHED," + String(scheduleIndex) + "," + scheduleTimeLabel + "," + failReason, clientNum);
      else sendSMS("FEED,FAIL,MANUAL," + failReason, clientNum);
    }
  }
}

bool dispenseNow(int feedLimit, String &failReason, int &actualDispensed) {
  unsigned long startTime = millis();
  float initialWeight = getWeightNow();
  bool weightChanged = false;
  bool isTimeout = false;

  myservo1.attach(pinMyServo1);
  for (int pos = 170; pos >= 150; pos -= 2) {
    myservo1.write(pos);
    delay(20);
  }

  while (feedLimit > getWeightNow()) {
    float currentWeight = getWeightNow();
    if (!weightChanged && currentWeight > initialWeight + 0.5) {
      weightChanged = true;
    }

    // Your original 3-second rule
    // Your original 3-second rule
    if (!weightChanged && (millis() - startTime) > 3000UL) {
      failReason = "NO_WEIGHT_CHANGE_3S";
      actualDispensed = 0; // Nothing dropped

      // 1. Safely close the hopper (servo1)
      myservo1.write(170);
      delay(500);
      myservo1.detach();

      // 2. Return immediately WITHOUT executing the dump sequence
      return false; 
    }

    // Your original 15-second rule
    if ((millis() - startTime) > 15000UL) {
      failReason = "DISPENSE_TIMEOUT";
      isTimeout = true;
      break; // Stop waiting, but BREAK so we proceed to dump the partial feed!
    }
  }

  // Record exactly how much fell onto the scale before we dump it
  actualDispensed = (int)getWeightNow(); 
  if (actualDispensed < 0) actualDispensed = 0; // Prevent negative readings

// -- NEW Dump Sequence (Waits for weight to reach zero) --
  myservo1.write(170);
  delay(500);
  myservo1.detach();

  // 1. Open the ejector (servo2) to start dumping
  myservo2.attach(pinMyServo2);
  myservo2.write(170);
  delay(500);
  myservo2.detach();

  digitalWrite(rly1, LOW);

  // 2. Wait until the scale reads empty (under 1.5g to account for drift)
  // We use a 10-second timeout so it doesn't freeze if a pellet gets stuck.
  unsigned long dumpStartTime = millis();
  while (getWeightNow() > 1.5 && (millis() - dumpStartTime) < 10000UL) {
    delay(100); // Wait a fraction of a second and check the scale again
  }

  // 3. Close the ejector (servo2) now that the pan is empty
  myservo2.attach(pinMyServo2);
  myservo2.write(10);
  delay(500);
  myservo2.detach();

  delay(6000);
  digitalWrite(rly1, HIGH);
  delay(1000);

  // Return true if it was perfect, false if we timed out
  return !isTimeout;
}
// -----------------------------------------------------------------------------
// SMS HELPERS / COMMAND PARSER
// -----------------------------------------------------------------------------
void sendSMS(String msg, String num) {
  mySerial.println("AT+CMGF=1");
  delay(100);
  mySerial.print("AT+CMGS=\"");
  mySerial.print(num);
  mySerial.println("\"");
  delay(100);
  mySerial.print(msg);
  mySerial.write(26);
  delay(500);
}

void updateSerial() {
  while (mySerial.available()) {
    String line = mySerial.readStringUntil('\n');
    line.trim();

    if (line.startsWith("+CMT:")) {
      int q1 = line.indexOf('"');
      int q2 = line.indexOf('"', q1 + 1);

      if (q1 != -1 && q2 != -1) {
        clientNum = line.substring(q1 + 1, q2);
        clientNum.trim();
        tempMobile = clientNum;
      }

      // Read the SMS body.  A single readStringUntil() can return an empty
      // string if the GSM module breaks the message across multiple lines or
      // characters are still arriving.  Loop until we get a non‑empty line or
      // until a 2‑second overall timeout expires.  After reading, trim any
      // leading/trailing whitespace and strip carriage returns to avoid
      // contaminating the CSV parser.
      String msg;
      unsigned long startMs = millis();
      do {
        msg = mySerial.readStringUntil('\n');
        msg.trim();
        // Remove any stray carriage returns.  Without this, a trailing \r
        // character can be included in the last field and break numeric
        // conversions.
        msg.replace("\r", "");
      } while (msg.length() == 0 && (millis() - startMs < 2000));

      if (msg.startsWith("RTC,SET,")) {
        handleRtcSet(msg);
      } else if (msg.startsWith("SCHED,SET,")) {
        handleScheduleSet(msg);
      } else if (msg.startsWith("SYNC:")) {
        // New RTC sync command: SYNC:YYYY,MM,DD,HH,MM,SS
        handleSync(msg);
      } else if (msg.startsWith("S1:")) {
        handleSingleSchedule(0, msg);
      } else if (msg.startsWith("S2:")) {
        handleSingleSchedule(1, msg);
      } else if (msg.startsWith("S3:")) {
        handleSingleSchedule(2, msg);
      } else if (msg.startsWith("S4:")) {
        handleSingleSchedule(3, msg);
      } else if (msg.startsWith("CMD_")) {
        String cmd = msg.substring(4);
        if (cmd == "0000") {
          ffData = String(getTemp(), 1) + "," + String(getPhValue(), 1) + "," + String(getDo(), 1);
          sendSMS(ffData, clientNum);
          
        } else if (cmd == "OPEN") {
          isDraining = true;
          // --- NEW DRAIN OPEN COMMAND ---
          // 1. Open Hopper (Servo 1) halfway to avoid pan reversing
          myservo1.attach(pinMyServo1);
          myservo1.write(90); 
          delay(500);
          myservo1.detach(); // Detach prevents the servo from buzzing/overheating while left open

          // 2. Open Ejector (Servo 2) to the dumping position
          myservo2.attach(pinMyServo2);
          myservo2.write(170); 
          delay(500);
          myservo2.detach();

          // 3. Confirm back to the app
          sendSMS("DRAIN,OPENED", clientNum);

        } else if (cmd == "CLOSE") {
          isDraining = false;
          // --- NEW DRAIN CLOSE COMMAND ---
          safeStopFeeder(); // Reuses your existing function that resets both servos
          sendSMS("DRAIN,CLOSED", clientNum);

        } else {
          // If it's not 0000, OPEN, or CLOSE, interpret it as a manual feed weight
          manualFeedGrams = cmd.toInt();
          isManualDispense = true;
        }
      } else if (msg == "0000") {
        ffData = String(getTemp(), 1) + "," + String(getPhValue(), 1) + "," + String(getDo(), 1);
        sendSMS(ffData, clientNum);
      } else if (msg.length() == 4 && isDigit(msg[0]) && isDigit(msg[1]) && isDigit(msg[2]) && isDigit(msg[3])) {
        manualFeedGrams = msg.toInt();
        isManualDispense = true;
      }
    }
  }
}

// -----------------------------------------------------------------------------
// DRAIN FEEDS
// -----------------------------------------------------------------------------
// The draining function has been removed. Draining operations are no longer supported.

// -----------------------------------------------------------------------------
// SENSORS & ACTUATORS
// -----------------------------------------------------------------------------
float getTemp() {
  tempSensor.requestTemperatures();
  return tempSensor.getTempCByIndex(0);
}

float getPhValue() {
  for (int i = 0; i < 10; i++) {
    buffer_arr[i] = analogRead(A0);
    delay(10);
    updateSerial();
  }

  for (int i = 0; i < 9; i++) {
    for (int j = i + 1; j < 10; j++) {
      if (buffer_arr[i] > buffer_arr[j]) {
        int t = buffer_arr[i];
        buffer_arr[i] = buffer_arr[j];
        buffer_arr[j] = t;
      }
    }
  }

  long avg = 0;
  for (int i = 2; i < 8; i++) avg += buffer_arr[i];
  float volt = (float)avg * 5.0 / 1024.0 / 6.0;
  return -5.70 * volt + calibration_value;
}

int16_t readDO(uint32_t voltage_mv, uint8_t temperature_c) {
#if TWO_POINT_CALIBRATION == 00
  uint16_t V_saturation = (uint32_t)CAL1_V + (uint32_t)35 * temperature_c - (uint32_t)CAL1_T * 35;
  return (voltage_mv * DO_Table[temperature_c] / V_saturation);
#else
  uint16_t V_saturation = (int16_t)((int8_t)temperature_c - CAL2_T) * ((uint16_t)CAL1_V - CAL2_V) / ((uint8_t)CAL1_T - CAL2_T) + CAL2_V;
  return (voltage_mv * DO_Table[temperature_c] / V_saturation);
#endif
}

float getDo() {
  // 1. Get the REAL temperature from your Dallas sensor
  float realTemp = getTemp(); 
  
  // 2. Convert it to a whole number
  Temperaturet = (uint8_t)realTemp; 

  // 3. SAFETY CHECK: Ensure it never goes above 40°C to prevent crashing the DO_Table
  if (Temperaturet > 40) {
    Temperaturet = 40; 
  }

  // 4. Do the normal math
  ADC_Raw = analogRead(DO_PIN);
  ADC_Voltage = uint32_t(VREF) * ADC_Raw / ADC_RES;
  float DOmgPerL = readDO(ADC_Voltage, Temperaturet);
  
  return DOmgPerL / 1000.0;
}

float getVoltage() {
  long reading = analogRead(ANALOG_IN_PIN);
  return (reading / 1024.0) * 5.0;
}

float getWeightNow() {
  return scale.get_units();
}

int feedAmt() {
  long total = 0;

  for (int i = 0; i < 3; i++) {
    pinMode(RFpingPin, OUTPUT);
    digitalWrite(RFpingPin, LOW);
    delayMicroseconds(2);
    digitalWrite(RFpingPin, HIGH);
    delayMicroseconds(5);
    digitalWrite(RFpingPin, LOW);

    pinMode(RFrxPin, INPUT);
    RFduration = pulseIn(RFrxPin, HIGH, 30000);
    if (RFduration == 0) RFduration = 2000;

    total += microsecondsToCentimeters(RFduration);
    delay(10);
    updateSerial();
  }

  return total / 3;
}

long microsecondsToCentimeters(long microseconds) {
  return microseconds / 29 / 2;
}

void moveServo1(Servo &s, int pin) {
  s.attach(pin);
  delay(10);
  s.write(10);
  delay(1000);
  s.detach();
}

void moveServo2(Servo &s, int pin) {
  s.attach(pin);
  delay(10);
  s.write(170);
  delay(1000);
  s.detach();
}
