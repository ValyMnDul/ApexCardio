#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <Wire.h>

#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1);

const unsigned char heartBitmap[] PROGMEM = {
	0x00, 0x66, 0xFF, 0xFF, 0x7E, 0x3C, 0x18, 0x00
};

constexpr int ekgPin = 34;
constexpr int pinRed = 16;
constexpr int pinGreen = 17;
constexpr int pinBlue = 18;
constexpr int GRAPH_WIDTH = 128;
constexpr int MAX_BEATS = 250;
constexpr uint32_t SAMPLE_INTERVAL_MS = 20;

BLECharacteristic* pCharacteristic = nullptr;
bool deviceConnected = false;

#define SERVICE_UUID "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

class MyServerCallbacks : public BLEServerCallbacks {
	void onConnect(BLEServer* pServer) override {
		deviceConnected = true;
	}

	void onDisconnect(BLEServer* pServer) override {
		deviceConnected = false;
		pServer->getAdvertising()->start();
	}
};

void setLED(int r, int g, int b) {
	analogWrite(pinRed, r);
	analogWrite(pinGreen, g);
	analogWrite(pinBlue, b);
}

int graphData[GRAPH_WIDTH];
unsigned long beatTimestamps[MAX_BEATS];
int beatIndex = 0;
unsigned long systemStartTime = 0;
unsigned long lastBeatTime = 0;
unsigned long lastSampleTime = 0;
bool firstMinutePassed = false;
bool peakDetected = false;
bool showHeart = false;
int continuousBPM = 0;

void resetBuffers() {
	for (int i = 0; i < GRAPH_WIDTH; i++) {
		graphData[i] = 40;
	}

	for (int i = 0; i < MAX_BEATS; i++) {
		beatTimestamps[i] = 0;
	}
}

void setup() {
	Serial.begin(115200);

	pinMode(pinRed, OUTPUT);
	pinMode(pinGreen, OUTPUT);
	pinMode(pinBlue, OUTPUT);
	setLED(0, 0, 255);

	Wire.begin();
	Wire.setClock(400000);

	if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
		for (;;) {
			delay(1000);
		}
	}

	display.clearDisplay();
	display.setTextColor(WHITE);
	display.display();

	resetBuffers();

	BLEDevice::init("EKG_Olimpiada");
	BLEServer* pServer = BLEDevice::createServer();
	pServer->setCallbacks(new MyServerCallbacks());

	BLEService* pService = pServer->createService(SERVICE_UUID);
	pCharacteristic = pService->createCharacteristic(
		CHARACTERISTIC_UUID,
		BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
	);
	pCharacteristic->addDescriptor(new BLE2902());

	BLEAdvertising* pAdvertising = pServer->getAdvertising();
	pAdvertising->setMinPreferred(0x06);
	pAdvertising->setMinPreferred(0x12);
	pService->start();
	pAdvertising->start();

	systemStartTime = millis();
	lastSampleTime = systemStartTime;
}

void loop() {
	const unsigned long currentTime = millis();
	if (currentTime - lastSampleTime < SAMPLE_INTERVAL_MS) {
		delay(1);
		return;
	}
	lastSampleTime = currentTime;

	const int rawValue = analogRead(ekgPin);
	const int threshold = 2200;

	if (rawValue > threshold) {
		if (!peakDetected && (currentTime - lastBeatTime > 300)) {
			beatTimestamps[beatIndex] = currentTime;
			beatIndex = (beatIndex + 1) % MAX_BEATS;
			lastBeatTime = currentTime;
			showHeart = true;
			peakDetected = true;
		}
	} else {
		peakDetected = false;
	}

	if (currentTime - lastBeatTime > 150) {
		showHeart = false;
	}

	int beatsInLast60Seconds = 0;
	for (int i = 0; i < MAX_BEATS; i++) {
		if (beatTimestamps[i] > 0 && (currentTime - beatTimestamps[i] <= 60000)) {
			beatsInLast60Seconds++;
		}
	}
	continuousBPM = beatsInLast60Seconds;

	if (currentTime - systemStartTime >= 60000) {
		firstMinutePassed = true;
	}

	if (!deviceConnected) {
		setLED(0, 0, 255);
	} else if (!firstMinutePassed) {
		setLED(showHeart ? 0 : 200, showHeart ? 255 : 100, 0);
	} else {
		setLED(showHeart ? 0 : 0, showHeart ? 255 : 20, 0);
	}

	for (int i = 0; i < GRAPH_WIDTH - 1; i++) {
		graphData[i] = graphData[i + 1];
	}
	graphData[GRAPH_WIDTH - 1] = map(rawValue, 0, 4095, 63, 17);

	display.clearDisplay();

	if (showHeart) {
		display.drawBitmap(0, 4, heartBitmap, 8, 8, WHITE);
	}

	display.setTextSize(1);
	display.setCursor(16, 4);
	if (!firstMinutePassed) {
		display.print("Reading... ");
		const int secondsLeft = 60 - ((currentTime - systemStartTime) / 1000);
		display.print(secondsLeft);
		display.print("s");
	} else {
		display.print("BPM:");
		display.print(continuousBPM);
	}

	display.setCursor(110, 4);
	display.print("95%");
	display.drawLine(0, 15, 128, 15, WHITE);

	for (int i = 1; i < GRAPH_WIDTH; i++) {
		display.drawLine(i - 1, graphData[i - 1], i, graphData[i], WHITE);
	}

	display.display();

	if (deviceConnected && pCharacteristic != nullptr) {
		const uint16_t sample = static_cast<uint16_t>(rawValue);
		uint8_t payload[2];
		payload[0] = static_cast<uint8_t>(sample & 0xFF);
		payload[1] = static_cast<uint8_t>((sample >> 8) & 0xFF);
		pCharacteristic->setValue(payload, sizeof(payload));
		pCharacteristic->notify();
	}
}
