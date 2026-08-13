#include <Arduino.h>
#include <SPI.h>
#include <NimBLEDevice.h>
#include "ads1292r_registers.h"

#define LED_PIN 2

#define PIN_MISO 19
#define PIN_MOSI 23
#define PIN_CLK 18
#define PIN_CS 5

#define PIN_DRDY 22
#define PIN_START 4
#define PIN_RESET 33

#define SAMPLES_PER_PACKET 10
#define BYTES_PER_SAMPLE 9
#define BLE_PACKET_SIZE (SAMPLES_PER_PACKET * BYTES_PER_SAMPLE)

#define SERVICE_UUID "12345678-1234-1234-1234-123456789abc"
#define CHARACTERISTIC_UUID "87654321-4321-4321-4321-cba987654321"

SPISettings adsSPI(
    100000,
    MSBFIRST,
    SPI_MODE1
);

NimBLEServer* pServer = nullptr;
NimBLECharacteristic* pCharacteristic = nullptr;

bool deviceConnected = false;

TaskHandle_t adcTaskHandle = nullptr;
TaskHandle_t bleTaskHandle = nullptr;

QueueHandle_t sampleQueue = nullptr;

uint8_t bleBuffer[BLE_PACKET_SIZE];

struct Biquad
{
    float b0;
    float b1;
    float b2;
    float a1;
    float a2;

    float x1;
    float x2;
    float y1;
    float y2;

    Biquad(
        float _b0,
        float _b1,
        float _b2,
        float _a1,
        float _a2
    )
    {
        b0 = _b0;
        b1 = _b1;
        b2 = _b2;
        a1 = _a1;
        a2 = _a2;

        x1 = 0.0f;
        x2 = 0.0f;
        y1 = 0.0f;
        y2 = 0.0f;
    }

    float process(float x)
    {
        float y =
            b0 * x +
            b1 * x1 +
            b2 * x2 -
            a1 * y1 -
            a2 * y2;

        x2 = x1;
        x1 = x;

        y2 = y1;
        y1 = y;

        return y;
    }
};

Biquad highPass(
    0.98763698f,
    -1.97527397f,
    0.98763698f,
    -1.97512112f,
    0.97542682f
);

Biquad notch50(
    0.98236277f,
    -0.60713358f,
    0.98236277f,
    -0.60713358f,
    0.96472554f
);

Biquad lowPass(
    0.17508764f,
    0.35017529f,
    0.17508764f,
    -0.51930341f,
    0.21965398f
);

float morphSlow = 0.0f;

class ServerCallbacks : public NimBLEServerCallbacks
{
    void onConnect(NimBLEServer* pServer) override
    {
        deviceConnected = true;
        digitalWrite(LED_PIN, HIGH);
    }

    void onDisconnect(NimBLEServer* pServer) override
    {
        deviceConnected = false;
        digitalWrite(LED_PIN, LOW);
        NimBLEDevice::getAdvertising()->start();
    }
};

void adsCommand(uint8_t cmd)
{
    SPI.beginTransaction(adsSPI);

    digitalWrite(PIN_CS, LOW);

    delayMicroseconds(10);

    SPI.transfer(cmd);

    delayMicroseconds(20);

    digitalWrite(PIN_CS, HIGH);

    SPI.endTransaction();

    delayMicroseconds(20);
}

void adsReset()
{
    digitalWrite(PIN_RESET, HIGH);
    delay(10);

    digitalWrite(PIN_RESET, LOW);
    delay(10);

    digitalWrite(PIN_RESET, HIGH);
    delay(200);
}

void writeRegister(
    uint8_t reg,
    uint8_t value
)
{
    SPI.beginTransaction(adsSPI);

    digitalWrite(PIN_CS, LOW);

    delayMicroseconds(10);

    SPI.transfer(
        ADS1292_CMD_WREG |
        reg
    );

    SPI.transfer(0x00);

    delayMicroseconds(100);

    SPI.transfer(value);

    delayMicroseconds(10);

    digitalWrite(PIN_CS, HIGH);

    SPI.endTransaction();

    delay(2);
}

uint8_t readRegister(uint8_t reg)
{
    SPI.beginTransaction(adsSPI);

    digitalWrite(PIN_CS, LOW);

    delayMicroseconds(10);

    SPI.transfer(
        ADS1292_CMD_RREG |
        reg
    );

    SPI.transfer(0x00);

    delayMicroseconds(100);

    uint8_t value =
        SPI.transfer(0x00);

    delayMicroseconds(10);

    digitalWrite(PIN_CS, HIGH);

    SPI.endTransaction();

    return value;
}

int32_t make24(
    uint8_t a,
    uint8_t b,
    uint8_t c
)
{
    int32_t value =
        ((int32_t)a << 16) |
        ((int32_t)b << 8) |
        c;

    if (value & 0x800000)
    {
        value |= 0xFF000000;
    }

    return value;
}

void pack24(
    int32_t value,
    uint8_t* out
)
{
    if (value > 8388607)
        value = 8388607;

    if (value < -8388608)
        value = -8388608;

    uint32_t packed =
        ((uint32_t)value) &
        0xFFFFFF;

    out[0] =
        (packed >> 16) &
        0xFF;

    out[1] =
        (packed >> 8) &
        0xFF;

    out[2] =
        packed &
        0xFF;
}

float shapeForDisplay(float ecg)
{
    morphSlow +=
        0.08f *
        (ecg - morphSlow);

    return
        ecg -
        0.08f *
        morphSlow;
}

void IRAM_ATTR drdyInterruptHandler()
{
    BaseType_t wake = pdFALSE;

    if (adcTaskHandle != nullptr)
    {
        vTaskNotifyGiveFromISR(
            adcTaskHandle,
            &wake
        );

        if (wake)
        {
            portYIELD_FROM_ISR();
        }
    }
}

void adcTask(void* parameter)
{
    uint32_t warmup = 0;

    while (true)
    {
        ulTaskNotifyTake(
            pdTRUE,
            portMAX_DELAY
        );

        SPI.beginTransaction(
            adsSPI
        );

        digitalWrite(
            PIN_CS,
            LOW
        );

        delayMicroseconds(5);

        uint8_t status1 =
            SPI.transfer(0x00);

        uint8_t status2 =
            SPI.transfer(0x00);

        uint8_t status3 =
            SPI.transfer(0x00);

        SPI.transfer(0x00);
        SPI.transfer(0x00);
        SPI.transfer(0x00);

        uint8_t ch2a =
            SPI.transfer(0x00);

        uint8_t ch2b =
            SPI.transfer(0x00);

        uint8_t ch2c =
            SPI.transfer(0x00);

        digitalWrite(
            PIN_CS,
            HIGH
        );

        SPI.endTransaction();

        if (
            (status1 & 0xF0)
            !=
            0xC0
        )
        {
            continue;
        }

        int32_t raw =
            make24(
                ch2a,
                ch2b,
                ch2c
            );

        if (
            raw >= 8300000 ||
            raw <= -8300000
        )
        {
            continue;
        }

        float ecg =
            highPass.process(
                (float)raw
            );

        ecg =
            notch50.process(
                ecg
            );

        ecg =
            lowPass.process(
                ecg
            );

        if (warmup < 300)
        {
            warmup++;
            continue;
        }

        float displayed =
            shapeForDisplay(
                ecg
            );

        int32_t sample =
            (int32_t)displayed;

        if (
            xQueueSend(
                sampleQueue,
                &sample,
                0
            )
            !=
            pdTRUE
        )
        {
            int32_t oldSample;

            xQueueReceive(
                sampleQueue,
                &oldSample,
                0
            );

            xQueueSend(
                sampleQueue,
                &sample,
                0
            );
        }
    }
}

void bleTask(void* parameter)
{
    uint8_t sampleIndex = 0;

    while (true)
    {
        int32_t sample;

        if (
            xQueueReceive(
                sampleQueue,
                &sample,
                portMAX_DELAY
            )
            ==
            pdTRUE
        )
        {
            int offset =
                sampleIndex *
                BYTES_PER_SAMPLE;

            bleBuffer[
                offset + 0
            ] = 0xC0;

            bleBuffer[
                offset + 1
            ] = 0x00;

            bleBuffer[
                offset + 2
            ] = 0x00;

            pack24(
                sample,
                &bleBuffer[
                    offset + 3
                ]
            );

            bleBuffer[
                offset + 6
            ] = 0x00;

            bleBuffer[
                offset + 7
            ] = 0x00;

            bleBuffer[
                offset + 8
            ] = 0x00;

            sampleIndex++;

            if (
                sampleIndex >=
                SAMPLES_PER_PACKET
            )
            {
                sampleIndex = 0;

                if (
                    deviceConnected &&
                    pCharacteristic != nullptr
                )
                {
                    pCharacteristic->setValue(
                        bleBuffer,
                        BLE_PACKET_SIZE
                    );

                    pCharacteristic->notify();
                }
            }
        }
    }
}

bool initADS1292R()
{
    adsReset();

    adsCommand(
        ADS1292_CMD_SDATAC
    );

    delay(20);

    uint8_t id =
        readRegister(
            ADS1292_REG_ID
        );

    Serial.print(
        "ADS1292R ID = 0x"
    );

    Serial.println(
        id,
        HEX
    );

    if (id != 0x73)
    {
        return false;
    }

    writeRegister(
        ADS1292_REG_CONFIG1,
        0x01
    );

    writeRegister(
        ADS1292_REG_CONFIG2,
        0xA0
    );

    writeRegister(
        ADS1292_REG_LOFF,
        0x10
    );

    writeRegister(
        ADS1292_REG_CH1SET,
        0x81
    );

    writeRegister(
        ADS1292_REG_CH2SET,
        0x60
    );

    writeRegister(
        ADS1292_REG_RLD_SENS,
        0x2C
    );

    writeRegister(
        ADS1292_REG_LOFF_SENS,
        0x00
    );

    writeRegister(
        ADS1292_REG_RESP1,
        0x02
    );

    writeRegister(
        ADS1292_REG_RESP2,
        0x03
    );

    delay(50);

    Serial.print(
        "CONFIG1 = 0x"
    );

    Serial.println(
        readRegister(
            ADS1292_REG_CONFIG1
        ),
        HEX
    );

    Serial.print(
        "CH2SET = 0x"
    );

    Serial.println(
        readRegister(
            ADS1292_REG_CH2SET
        ),
        HEX
    );

    Serial.print(
        "RLD = 0x"
    );

    Serial.println(
        readRegister(
            ADS1292_REG_RLD_SENS
        ),
        HEX
    );

    return true;
}

void setup()
{
    Serial.begin(115200);

    delay(1000);

    pinMode(
        LED_PIN,
        OUTPUT
    );

    digitalWrite(
        LED_PIN,
        LOW
    );

    pinMode(
        PIN_CS,
        OUTPUT
    );

    pinMode(
        PIN_DRDY,
        INPUT
    );

    pinMode(
        PIN_START,
        OUTPUT
    );

    pinMode(
        PIN_RESET,
        OUTPUT
    );

    digitalWrite(
        PIN_CS,
        HIGH
    );

    digitalWrite(
        PIN_START,
        LOW
    );

    digitalWrite(
        PIN_RESET,
        HIGH
    );

    SPI.begin(
        PIN_CLK,
        PIN_MISO,
        PIN_MOSI,
        PIN_CS
    );

    if (!initADS1292R())
    {
        Serial.println(
            "ADS1292R FAILED"
        );

        while (true)
        {
            delay(1000);
        }
    }

    sampleQueue =
        xQueueCreate(
            256,
            sizeof(int32_t)
        );

    xTaskCreatePinnedToCore(
        adcTask,
        "ADS_ADC",
        4096,
        nullptr,
        5,
        &adcTaskHandle,
        0
    );

    xTaskCreatePinnedToCore(
        bleTask,
        "BLE_SEND",
        4096,
        nullptr,
        2,
        &bleTaskHandle,
        1
    );

    attachInterrupt(
        digitalPinToInterrupt(
            PIN_DRDY
        ),
        drdyInterruptHandler,
        FALLING
    );

    NimBLEDevice::init(
        "ApexCardio"
    );

    NimBLEDevice::setMTU(
        185
    );

    pServer =
        NimBLEDevice::createServer();

    pServer->setCallbacks(
        new ServerCallbacks()
    );

    NimBLEService* pService =
        pServer->createService(
            SERVICE_UUID
        );

    pCharacteristic =
        pService->createCharacteristic(
            CHARACTERISTIC_UUID,
            NIMBLE_PROPERTY::READ |
            NIMBLE_PROPERTY::NOTIFY
        );

    pService->start();

    NimBLEAdvertising* pAdvertising =
        NimBLEDevice::getAdvertising();

    pAdvertising->addServiceUUID(
        SERVICE_UUID
    );

    pAdvertising->start();

    adsCommand(
        ADS1292_CMD_START
    );

    delay(100);

    adsCommand(
        ADS1292_CMD_RDATAC
    );

    delay(20);

    Serial.println(
        "APEXCARDIO REAL ECG READY"
    );
}

void loop()
{
    delay(1000);
}