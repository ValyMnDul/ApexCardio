#include <Arduino.h>
#include <SPI.h>
#include <NimBLEDevice.h>
#include "ads1292r_registers.h"

#define LED_PIN 2

#define PIN_MISO 19
#define PIN_MOSI 23
#define PIN_CLK 18
#define PIN_CS 5

#define PIN_DRDY 4
#define PIN_PWDN 22

#define SAMPLES_PER_PACKET 10
#define BYTES_PER_SAMPLE 9

#define BLE_PACKET_SIZE (SAMPLES_PER_PACKET * BYTES_PER_SAMPLE)

uint8_t bleBuffer[BLE_PACKET_SIZE];
uint8_t samplesCounter = 0;

volatile bool newDataAvailable = false;

NimBLEServer* pServer = nullptr;
NimBLECharacteristic* pCaracteristic = nullptr;

bool deviceConnected = false;

#define SERVICE_UUID "12345678-1234-1234-1234-123456789abc"
#define CHARACTERISTIC_UUID "87654321-4321-4321-4321-cba987654321"

class ServerCallbacks: public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* pServer) override {
      deviceConnected = true;
      digitalWrite(LED_PIN, HIGH);
    };

    void onDisconnect(NimBLEServer* pServer) override {
      deviceConnected = false;
      digitalWrite(LED_PIN, LOW);
      NimBLEDevice::getAdvertising()->start();
    }
};

void IRAM_ATTR drdyInterruptHandler(){
  newDataAvailable = true;
}

void sendSpiCommand(uint8_t cmd) {
  digitalWrite(PIN_CS, LOW);
  SPI.transfer(cmd);
  digitalWrite(PIN_CS, HIGH);
}

void writeRegister(uint8_t reg, uint8_t value){
  digitalWrite(PIN_CS, LOW);
  SPI.transfer(ADS1292_CMD_WREG | reg);
  SPI.transfer(0x00);
  SPI.transfer(value);
  digitalWrite(PIN_CS, HIGH);
}

void initADS1292R(){
  digitalWrite(PIN_PWDN, LOW);
  delay(100);
  digitalWrite(PIN_PWDN, HIGH);
  delay(100);

  sendSpiCommand(ADS1292_CMD_SDATAC);
  delay(10);

  writeRegister(ADS1292_REG_CONFIG1, 0x02);
  writeRegister(ADS1292_REG_CONFIG2, 0xE0);
  writeRegister(ADS1292_REG_CH1SET, 0x00);

  sendSpiCommand(ADS1292_CMD_RDATAC);
  sendSpiCommand(ADS1292_CMD_START);
}

void setup(){
  Serial.begin(115200);

  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  pinMode(PIN_CS, OUTPUT);
  pinMode(PIN_PWDN, OUTPUT);
  digitalWrite(PIN_CS, HIGH);

  pinMode(PIN_DRDY, INPUT_PULLUP);
  attachInterrupt(digitalPinToInterrupt(PIN_DRDY), drdyInterruptHandler, FALLING);

  SPI.begin(PIN_CLK, PIN_MISO, PIN_MOSI, PIN_CS);
  SPI.beginTransaction(SPISettings(4000000, MSBFIRST, SPI_MODE1));

  initADS1292R();

  NimBLEDevice::init("ApexCardio");
  pServer = NimBLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());
  
  NimBLEService* pService = pServer->createService(SERVICE_UUID);

  pCaracteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
  );

  pService->start();
  NimBLEAdvertising* pAdvertising = NimBLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->start();

  Serial.println("READY");
}

void loop(){
  static unsigned long lastSampleTime = 0;

  if (millis() - lastSampleTime >= 4) {
    lastSampleTime = millis();

    static int phase = 0;
    uint8_t fakeEkgByte = 128;

    phase = (phase + 1) % 250;

    if (phase > 20 && phase < 30) {
      fakeEkgByte = 220;
    } else if (phase >= 30 && phase < 40) {
      fakeEkgByte = 50;
    }

    bleBuffer[samplesCounter * BYTES_PER_SAMPLE + 0] = 0xC0;
    bleBuffer[samplesCounter * BYTES_PER_SAMPLE + 1] = 0x00;
    bleBuffer[samplesCounter * BYTES_PER_SAMPLE + 2] = 0x00;
    
    bleBuffer[samplesCounter * BYTES_PER_SAMPLE + 3] = 0x00;
    bleBuffer[samplesCounter * BYTES_PER_SAMPLE + 4] = fakeEkgByte;
    bleBuffer[samplesCounter * BYTES_PER_SAMPLE + 5] = 0x00;
    
    bleBuffer[samplesCounter * BYTES_PER_SAMPLE + 6] = 0x00;
    bleBuffer[samplesCounter * BYTES_PER_SAMPLE + 7] = 0x00;
    bleBuffer[samplesCounter * BYTES_PER_SAMPLE + 8] = 0x00;

    samplesCounter++;

    if (samplesCounter >= SAMPLES_PER_PACKET) {
      samplesCounter = 0;

      if (deviceConnected && pCaracteristic != nullptr) {
        pCaracteristic->setValue(bleBuffer, BLE_PACKET_SIZE);
        pCaracteristic->notify();
      }
    }
  }
}