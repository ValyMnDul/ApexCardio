#include <Arduino.h>
#include <SPI.h>
#include <Wire.h>
#include <U8g2lib.h>
#include <NimBLEDevice.h>
#include <math.h>

#define PIN_SCK 18
#define PIN_MISO 19
#define PIN_MOSI 23
#define PIN_CS 5
#define PIN_DRDY 22
#define PIN_START 4
#define PIN_RESET 33

#define OLED_SDA 21
#define OLED_SCL 25

#define CMD_START 0x08
#define CMD_RDATAC 0x10
#define CMD_SDATAC 0x11
#define CMD_RREG 0x20
#define CMD_WREG 0x40

#define DISP_W 128
#define DISP_H 64

#define FS 250
#define MWI_SIZE 38
#define SLOPE_SIZE 25
#define DETECTOR_CALIBRATION 500

#define LED_PIN 2
#define SAMPLES_PER_PACKET 10
#define BYTES_PER_SAMPLE 9
#define BLE_PACKET_SIZE (SAMPLES_PER_PACKET * BYTES_PER_SAMPLE)

#define SERVICE_UUID "12345678-1234-1234-1234-123456789abc"
#define CHARACTERISTIC_UUID "87654321-4321-4321-4321-cba987654321"

SPISettings adsSPI(100000, MSBFIRST, SPI_MODE1);

U8G2_SH1106_128X64_NONAME_F_HW_I2C u8g2(
    U8G2_R0,
    U8X8_PIN_NONE
);

const int TOP_UI_H = 19;
const int PLOT_TOP = 21;
const int PLOT_BOTTOM = 63;
const int PLOT_CENTER = (PLOT_TOP + PLOT_BOTTOM) / 2;

const float DISPLAY_RANGE = 8050.0f;

const int PIXEL_DECIMATION = 3;
const unsigned long FRAME_INTERVAL = 36;

volatile bool adcRunning = false;

TaskHandle_t adcTaskHandle = nullptr;
QueueHandle_t ecgQueue = nullptr;

NimBLEServer* pServer = nullptr;
NimBLECharacteristic* pCaracteristic = nullptr;

bool deviceConnected = false;

uint8_t bleBuffer[BLE_PACKET_SIZE];
uint8_t bleSamplesCounter = 0;

uint8_t screenWave[DISP_W];

float pixelSamples[PIXEL_DECIMATION];
int pixelSampleCount = 0;

uint8_t pendingPixels[16];
int pendingCount = 0;

float morphSlow = 0.0f;

volatile float bpmValue = 0.0f;
volatile uint32_t beatCount = 0;
volatile unsigned long heartFlashUntil = 0;

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

Biquad qrsHighPass(
    0.91496914f,
    -1.82993829f,
    0.91496914f,
    -1.82269493f,
    0.83718165f
);

Biquad qrsLowPass(
    0.02785977f,
    0.05571953f,
    0.02785977f,
    -1.47548044f,
    0.58691951f
);

float q1 = 0;
float q2 = 0;
float q3 = 0;
float q4 = 0;

float mwiBuffer[MWI_SIZE];
int mwiIndex = 0;
float mwiSum = 0;

float slopeBuffer[SLOPE_SIZE];
int slopeIndex = 0;

float mwiPrev2 = 0;
float mwiPrev1 = 0;

float slopePrev2 = 0;
float slopePrev1 = 0;

uint32_t detectorSamples = 0;

bool detectorReady = false;

float calibrationMax = 0;
float calibrationSum = 0;
uint32_t calibrationPeaks = 0;

float signalLevel = 0;
float noiseLevel = 0;
float detectionThreshold = 0;

uint32_t lastQrsSample = 0;
float lastQrsSlope = 0;
float averageRR = 0;

uint16_t rrHistory[5];
int rrCount = 0;
int rrIndex = 0;

const int8_t startupECG[] = {
    0,0,0,0,0,
    1,2,3,4,4,3,2,1,0,
    0,-1,-2,-4,-2,0,
    3,8,17,21,8,
    -13,-9,-4,-1,0,
    0,1,2,3,4,6,8,9,10,
    10,10,9,8,7,6,5,4,3,2,1,
    0,0,0,0,0,0
};

const int startupCount =
    sizeof(startupECG) /
    sizeof(startupECG[0]);

class ServerCallbacks: public NimBLEServerCallbacks
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

void pack24(int32_t value, uint8_t* output)
{
    if (value > 8388607)
        value = 8388607;

    if (value < -8388608)
        value = -8388608;

    uint32_t packed =
        ((uint32_t)value) &
        0xFFFFFF;

    output[0] =
        (packed >> 16) &
        0xFF;

    output[1] =
        (packed >> 8) &
        0xFF;

    output[2] =
        packed &
        0xFF;
}

void sendBLESample(float displayedECG)
{
    int offset =
        bleSamplesCounter *
        BYTES_PER_SAMPLE;

    bleBuffer[offset + 0] = 0xC0;
    bleBuffer[offset + 1] = 0x00;
    bleBuffer[offset + 2] = 0x00;

    pack24(
        (int32_t)displayedECG,
        &bleBuffer[offset + 3]
    );

    bleBuffer[offset + 6] = 0x00;
    bleBuffer[offset + 7] = 0x00;
    bleBuffer[offset + 8] = 0x00;

    bleSamplesCounter++;

    if (bleSamplesCounter >= SAMPLES_PER_PACKET)
    {
        bleSamplesCounter = 0;

        if (deviceConnected && pCaracteristic != nullptr)
        {
            pCaracteristic->setValue(
                bleBuffer,
                BLE_PACKET_SIZE
            );

            pCaracteristic->notify();
        }
    }
}

void initBLE()
{
    NimBLEDevice::init("ApexCardio");

    pServer =
        NimBLEDevice::createServer();

    pServer->setCallbacks(
        new ServerCallbacks()
    );

    NimBLEService* pService =
        pServer->createService(
            SERVICE_UUID
        );

    pCaracteristic =
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
}

void adsCommand(uint8_t cmd)
{
    digitalWrite(PIN_CS, LOW);
    delayMicroseconds(10);
    SPI.transfer(cmd);
    delayMicroseconds(20);
    digitalWrite(PIN_CS, HIGH);
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

void writeRegister(uint8_t reg, uint8_t value)
{
    digitalWrite(PIN_CS, LOW);
    delayMicroseconds(10);

    SPI.transfer(CMD_SDATAC);
    delayMicroseconds(100);

    SPI.transfer(CMD_WREG | reg);
    SPI.transfer(0x00);

    delayMicroseconds(100);

    SPI.transfer(value);

    delayMicroseconds(10);

    digitalWrite(PIN_CS, HIGH);

    delay(2);
}

uint8_t readRegister(uint8_t reg)
{
    digitalWrite(PIN_CS, LOW);
    delayMicroseconds(10);

    SPI.transfer(CMD_SDATAC);
    delayMicroseconds(100);

    SPI.transfer(CMD_RREG | reg);
    SPI.transfer(0x00);

    delayMicroseconds(100);

    uint8_t value = SPI.transfer(0x00);

    delayMicroseconds(10);

    digitalWrite(PIN_CS, HIGH);

    return value;
}

int32_t make24(uint8_t a, uint8_t b, uint8_t c)
{
    int32_t value =
        ((int32_t)a << 16) |
        ((int32_t)b << 8) |
        c;

    if (value & 0x800000)
        value |= 0xFF000000;

    return value;
}

float shapeForDisplay(float ecg)
{
    morphSlow +=
        0.08f *
        (ecg - morphSlow);

    return
        ecg -
        0.08f * morphSlow;
}

uint8_t ecgToPixel(float value)
{
    if (value > DISPLAY_RANGE)
        value = DISPLAY_RANGE;

    if (value < -DISPLAY_RANGE)
        value = -DISPLAY_RANGE;

    float normalized =
        value /
        DISPLAY_RANGE;

    int halfHeight =
        (PLOT_BOTTOM - PLOT_TOP) / 2;

    int y =
        PLOT_CENTER -
        (int)(
            normalized *
            halfHeight
        );

    return constrain(
        y,
        PLOT_TOP,
        PLOT_BOTTOM
    );
}

void drawHeartOutline(int x, int y)
{
    u8g2.drawCircle(
        x + 2,
        y + 2,
        2
    );

    u8g2.drawCircle(
        x + 6,
        y + 2,
        2
    );

    u8g2.drawLine(
        x,
        y + 3,
        x + 4,
        y + 9
    );

    u8g2.drawLine(
        x + 8,
        y + 3,
        x + 4,
        y + 9
    );
}

void drawHeartFilled(int x, int y)
{
    u8g2.drawDisc(
        x + 2,
        y + 2,
        2
    );

    u8g2.drawDisc(
        x + 6,
        y + 2,
        2
    );

    u8g2.drawTriangle(
        x,
        y + 3,
        x + 8,
        y + 3,
        x + 4,
        y + 9
    );
}

void drawTopInfo()
{
    bool flash =
        millis() <
        heartFlashUntil;

    if (flash)
        drawHeartFilled(2, 1);
    else
        drawHeartOutline(2, 1);

    u8g2.setFont(
        u8g2_font_6x10_tf
    );

    u8g2.drawStr(
        15,
        8,
        "HR"
    );

    char bpmBuf[8];

    if (bpmValue >= 1.0f)
    {
        snprintf(
            bpmBuf,
            sizeof(bpmBuf),
            "%d",
            (int)(
                bpmValue +
                0.5f
            )
        );
    }
    else
    {
        snprintf(
            bpmBuf,
            sizeof(bpmBuf),
            "--"
        );
    }

    u8g2.setFont(
        u8g2_font_logisoso16_tn
    );

    u8g2.drawStr(
        33,
        16,
        bpmBuf
    );

    u8g2.setFont(
        u8g2_font_5x7_tf
    );

    char countBuf[14];

    snprintf(
        countBuf,
        sizeof(countBuf),
        "%lu",
        (unsigned long)beatCount
    );

    int width =
        u8g2.getStrWidth(
            countBuf
        );

    u8g2.drawStr(
        126 - width,
        7,
        countBuf
    );

    u8g2.drawHLine(
        0,
        TOP_UI_H,
        128
    );
}

void updateBPM(uint32_t rrSamples)
{
    if (
        rrSamples < 75 ||
        rrSamples > 500
    )
    {
        return;
    }

    rrHistory[
        rrIndex
    ] =
        (uint16_t)rrSamples;

    rrIndex++;

    if (rrIndex >= 5)
        rrIndex = 0;

    if (rrCount < 5)
        rrCount++;

    uint16_t temp[5];

    for (
        int i = 0;
        i < rrCount;
        i++
    )
    {
        temp[i] =
            rrHistory[i];
    }

    for (
        int i = 0;
        i < rrCount - 1;
        i++
    )
    {
        for (
            int j = i + 1;
            j < rrCount;
            j++
        )
        {
            if (
                temp[j] <
                temp[i]
            )
            {
                uint16_t t =
                    temp[i];

                temp[i] =
                    temp[j];

                temp[j] =
                    t;
            }
        }
    }

    float rr;

    if (rrCount == 1)
    {
        rr =
            temp[0];
    }
    else if (
        rrCount % 2
        ==
        1
    )
    {
        rr =
            temp[
                rrCount / 2
            ];
    }
    else
    {
        rr =
            (
                temp[
                    rrCount / 2 - 1
                ]
                +
                temp[
                    rrCount / 2
                ]
            )
            *
            0.5f;
    }

    bpmValue =
        15000.0f /
        rr;
}

void acceptBeat(
    uint32_t sample,
    float slope
)
{
    if (
        lastQrsSample != 0
    )
    {
        uint32_t rr =
            sample -
            lastQrsSample;

        updateBPM(
            rr
        );

        if (
            averageRR <=
            0.0f
        )
        {
            averageRR =
                rr;
        }
        else
        {
            averageRR =
                0.80f *
                averageRR +
                0.20f *
                rr;
        }
    }

    lastQrsSample =
        sample;

    lastQrsSlope =
        slope;

    beatCount++;

    heartFlashUntil =
        millis() +
        120;
}

float getMaxSlope()
{
    float maximum = 0;

    for (
        int i = 0;
        i < SLOPE_SIZE;
        i++
    )
    {
        if (
            slopeBuffer[i] >
            maximum
        )
        {
            maximum =
                slopeBuffer[i];
        }
    }

    return maximum;
}

void processQRSDetector(
    float ecg
)
{
    float qrs =
        qrsHighPass.process(
            ecg
        );

    qrs =
        qrsLowPass.process(
            qrs
        );

    float derivative =
        (
            2.0f * qrs +
            q1 -
            q3 -
            2.0f * q4
        )
        *
        0.125f;

    q4 = q3;
    q3 = q2;
    q2 = q1;
    q1 = qrs;

    float absSlope =
        fabsf(
            derivative
        );

    slopeBuffer[
        slopeIndex
    ] =
        absSlope;

    slopeIndex++;

    if (
        slopeIndex >=
        SLOPE_SIZE
    )
    {
        slopeIndex = 0;
    }

    float squared =
        derivative *
        derivative;

    mwiSum -=
        mwiBuffer[
            mwiIndex
        ];

    mwiBuffer[
        mwiIndex
    ] =
        squared;

    mwiSum +=
        squared;

    mwiIndex++;

    if (
        mwiIndex >=
        MWI_SIZE
    )
    {
        mwiIndex = 0;
    }

    float mwi =
        mwiSum /
        (float)MWI_SIZE;

    float slope =
        getMaxSlope();

    detectorSamples++;

    bool localPeak =
        mwiPrev1 >
        mwiPrev2
        &&
        mwiPrev1 >=
        mwi;

    if (!detectorReady)
    {
        if (localPeak)
        {
            calibrationSum +=
                mwiPrev1;

            calibrationPeaks++;

            if (
                mwiPrev1 >
                calibrationMax
            )
            {
                calibrationMax =
                    mwiPrev1;
            }
        }

        if (
            detectorSamples >=
            DETECTOR_CALIBRATION
        )
        {
            float meanPeak =
                calibrationPeaks >
                0
                ?
                calibrationSum /
                calibrationPeaks
                :
                calibrationMax *
                0.25f;

            noiseLevel =
                meanPeak *
                0.50f;

            signalLevel =
                calibrationMax *
                0.70f;

            if (
                signalLevel <=
                noiseLevel
            )
            {
                signalLevel =
                    noiseLevel *
                    2.0f +
                    1.0f;
            }

            detectionThreshold =
                noiseLevel +
                0.25f *
                (
                    signalLevel -
                    noiseLevel
                );

            detectorReady = true;
        }

        mwiPrev2 = mwiPrev1;
        mwiPrev1 = mwi;

        slopePrev2 =
            slopePrev1;

        slopePrev1 =
            slope;

        return;
    }

    if (localPeak)
    {
        float peak =
            mwiPrev1;

        float candidateSlope =
            slopePrev1;

        uint32_t candidateSample =
            detectorSamples -
            1;

        uint32_t distance =
            lastQrsSample ==
            0
            ?
            1000000
            :
            candidateSample -
            lastQrsSample;

        bool refractory =
            lastQrsSample !=
            0
            &&
            distance <
            60;

        bool possibleTWave =
            lastQrsSample !=
            0
            &&
            distance <
            90
            &&
            lastQrsSlope >
            0
            &&
            candidateSlope <
            lastQrsSlope *
            0.50f;

        bool earlyLowSlope =
            lastQrsSample !=
            0
            &&
            averageRR >
            0
            &&
            distance <
            averageRR *
            0.62f
            &&
            lastQrsSlope >
            0
            &&
            candidateSlope <
            lastQrsSlope *
            0.70f;

        detectionThreshold =
            noiseLevel +
            0.25f *
            (
                signalLevel -
                noiseLevel
            );

        if (
            peak >
            detectionThreshold
            &&
            !refractory
            &&
            !possibleTWave
            &&
            !earlyLowSlope
        )
        {
            signalLevel =
                0.875f *
                signalLevel +
                0.125f *
                peak;

            acceptBeat(
                candidateSample,
                candidateSlope
            );
        }
        else
        {
            float alpha =
                (
                    refractory ||
                    possibleTWave ||
                    earlyLowSlope
                )
                ?
                0.03f
                :
                0.125f;

            noiseLevel =
                (
                    1.0f -
                    alpha
                )
                *
                noiseLevel +
                alpha *
                peak;
        }
    }

    mwiPrev2 =
        mwiPrev1;

    mwiPrev1 =
        mwi;

    slopePrev2 =
        slopePrev1;

    slopePrev1 =
        slope;
}

void drawStartupWave(
    int endIndex
)
{
    const int x0 = 8;
    const int x1 = 120;
    const int baseline = 35;
    const float verticalScale = 0.80f;

    float dx =
        (float)(x1 - x0) /
        (float)(startupCount - 1);

    int previousX =
        x0;

    int previousY =
        baseline -
        (int)(
            startupECG[0] *
            verticalScale
        );

    for (
        int i = 1;
        i <= endIndex &&
        i < startupCount;
        i++
    )
    {
        int x =
            x0 +
            (int)(
                dx * i
            );

        int y =
            baseline -
            (int)(
                startupECG[i] *
                verticalScale
            );

        u8g2.drawLine(
            previousX,
            previousY,
            x,
            y
        );

        previousX = x;
        previousY = y;
    }
}

void bootAnimation()
{
    const char *title =
        "ApexCardio";

    for (
        int frame = 0;
        frame < 24;
        frame++
    )
    {
        u8g2.clearBuffer();

        u8g2.setFont(
            u8g2_font_logisoso18_tf
        );

        int textWidth =
            u8g2.getStrWidth(
                title
            );

        u8g2.drawStr(
            (128 - textWidth) / 2,
            17,
            title
        );

        int waveProgress =
            map(
                frame,
                0,
                23,
                1,
                startupCount - 1
            );

        drawStartupWave(
            waveProgress
        );

        u8g2.drawFrame(
            24,
            56,
            80,
            4
        );

        int progress =
            map(
                frame,
                0,
                23,
                0,
                78
            );

        if (progress > 0)
        {
            u8g2.drawBox(
                25,
                57,
                progress,
                2
            );
        }

        u8g2.sendBuffer();

        delay(85);
    }
}

void showMessage(
    const char *msg
)
{
    u8g2.clearBuffer();

    u8g2.setFont(
        u8g2_font_6x10_tf
    );

    int w =
        u8g2.getStrWidth(
            msg
        );

    u8g2.drawStr(
        (128 - w) / 2,
        36,
        msg
    );

    u8g2.sendBuffer();
}

void IRAM_ATTR drdyISR()
{
    BaseType_t wake =
        pdFALSE;

    if (
        adcTaskHandle !=
        nullptr
    )
    {
        vTaskNotifyGiveFromISR(
            adcTaskHandle,
            &wake
        );

        if (wake)
            portYIELD_FROM_ISR();
    }
}

void adcTask(void *parameter)
{
    uint32_t warmup = 0;

    while (true)
    {
        ulTaskNotifyTake(
            pdTRUE,
            portMAX_DELAY
        );

        if (!adcRunning)
            continue;

        SPI.beginTransaction(
            adsSPI
        );

        digitalWrite(
            PIN_CS,
            LOW
        );

        delayMicroseconds(5);

        uint8_t s1 =
            SPI.transfer(0x00);

        SPI.transfer(0x00);
        SPI.transfer(0x00);

        SPI.transfer(0x00);
        SPI.transfer(0x00);
        SPI.transfer(0x00);

        uint8_t a =
            SPI.transfer(0x00);

        uint8_t b =
            SPI.transfer(0x00);

        uint8_t c =
            SPI.transfer(0x00);

        digitalWrite(
            PIN_CS,
            HIGH
        );

        SPI.endTransaction();

        if (
            (s1 & 0xF0)
            !=
            0xC0
        )
        {
            continue;
        }

        int32_t raw =
            make24(
                a,
                b,
                c
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

        if (
            warmup <
            300
        )
        {
            warmup++;
            continue;
        }

        processQRSDetector(
            ecg
        );

        if (
            xQueueSend(
                ecgQueue,
                &ecg,
                0
            )
            !=
            pdTRUE
        )
        {
            float oldValue;

            xQueueReceive(
                ecgQueue,
                &oldValue,
                0
            );

            xQueueSend(
                ecgQueue,
                &ecg,
                0
            );
        }
    }
}

void createDisplayPixel(
    float ecg
)
{
    float displayedECG =
        shapeForDisplay(
            ecg
        );

    sendBLESample(
        displayedECG
    );

    pixelSamples[
        pixelSampleCount
    ] =
        displayedECG;

    pixelSampleCount++;

    if (
        pixelSampleCount <
        PIXEL_DECIMATION
    )
    {
        return;
    }

    float pixelValue =
        pixelSamples[
            PIXEL_DECIMATION / 2
        ];

    pixelSampleCount = 0;

    uint8_t y =
        ecgToPixel(
            pixelValue
        );

    if (
        pendingCount <
        16
    )
    {
        pendingPixels[
            pendingCount
        ] = y;

        pendingCount++;
    }
}

void scrollWave()
{
    if (
        pendingCount <= 0
    )
    {
        return;
    }

    int shift =
        pendingCount;

    if (shift > 8)
        shift = 8;

    memmove(
        screenWave,
        screenWave + shift,
        DISP_W - shift
    );

    for (
        int i = 0;
        i < shift;
        i++
    )
    {
        screenWave[
            DISP_W -
            shift +
            i
        ] =
            pendingPixels[i];
    }

    if (
        pendingCount >
        shift
    )
    {
        memmove(
            pendingPixels,
            pendingPixels + shift,
            pendingCount - shift
        );
    }

    pendingCount -=
        shift;
}

void renderFrame()
{
    u8g2.clearBuffer();

    drawTopInfo();

    int previousY =
        screenWave[0];

    for (
        int x = 1;
        x < DISP_W;
        x++
    )
    {
        int y =
            screenWave[x];

        u8g2.drawLine(
            x - 1,
            previousY,
            x,
            y
        );

        previousY = y;
    }

    u8g2.sendBuffer();
}

void setup()
{
    Serial.begin(115200);

    delay(300);

    pinMode(LED_PIN, OUTPUT);
    digitalWrite(LED_PIN, LOW);

    Wire.begin(
        OLED_SDA,
        OLED_SCL
    );

    u8g2.begin();

    u8g2.setBusClock(
        800000
    );

    bootAnimation();

    showMessage(
        "SYNC"
    );

    pinMode(PIN_SCK, OUTPUT);
    pinMode(PIN_MISO, INPUT);
    pinMode(PIN_MOSI, OUTPUT);
    pinMode(PIN_CS, OUTPUT);
    pinMode(PIN_DRDY, INPUT);
    pinMode(PIN_START, OUTPUT);
    pinMode(PIN_RESET, OUTPUT);

    digitalWrite(PIN_CS, HIGH);
    digitalWrite(PIN_SCK, LOW);
    digitalWrite(PIN_MOSI, LOW);
    digitalWrite(PIN_START, LOW);
    digitalWrite(PIN_RESET, HIGH);

    SPI.begin(
        PIN_SCK,
        PIN_MISO,
        PIN_MOSI,
        PIN_CS
    );

    SPI.beginTransaction(
        adsSPI
    );

    adsReset();

    uint8_t id =
        readRegister(
            0x00
        );

    if (id != 0x73)
    {
        showMessage(
            "ADS FAILED"
        );

        SPI.endTransaction();

        while (true)
            delay(1000);
    }

    adsCommand(
        CMD_SDATAC
    );

    delay(20);

    writeRegister(0x01, 0x01);
    writeRegister(0x02, 0xA0);
    writeRegister(0x03, 0x10);
    writeRegister(0x04, 0x81);
    writeRegister(0x05, 0x60);
    writeRegister(0x06, 0x2C);
    writeRegister(0x07, 0x00);
    writeRegister(0x09, 0x02);
    writeRegister(0x0A, 0x03);

    bool configOK =
        readRegister(0x01) == 0x01 &&
        readRegister(0x02) == 0xA0 &&
        readRegister(0x04) == 0x81 &&
        readRegister(0x05) == 0x60 &&
        readRegister(0x06) == 0x2C &&
        readRegister(0x09) == 0x02 &&
        readRegister(0x0A) == 0x03;

    if (!configOK)
    {
        showMessage(
            "CONFIG FAILED"
        );

        SPI.endTransaction();

        while (true)
            delay(1000);
    }

    SPI.endTransaction();

    initBLE();

    for (
        int i = 0;
        i < MWI_SIZE;
        i++
    )
    {
        mwiBuffer[i] = 0;
    }

    for (
        int i = 0;
        i < SLOPE_SIZE;
        i++
    )
    {
        slopeBuffer[i] = 0;
    }

    for (
        int i = 0;
        i < DISP_W;
        i++
    )
    {
        screenWave[i] =
            PLOT_CENTER;
    }

    ecgQueue =
        xQueueCreate(
            128,
            sizeof(float)
        );

    xTaskCreatePinnedToCore(
        adcTask,
        "ADS1292R_ADC",
        4096,
        nullptr,
        4,
        &adcTaskHandle,
        0
    );

    attachInterrupt(
        digitalPinToInterrupt(
            PIN_DRDY
        ),
        drdyISR,
        FALLING
    );

    SPI.beginTransaction(
        adsSPI
    );

    adsCommand(
        CMD_START
    );

    delay(100);

    adsCommand(
        CMD_RDATAC
    );

    delay(20);

    SPI.endTransaction();

    adcRunning = true;

    renderFrame();
}

void loop()
{
    float ecg;

    while (
        xQueueReceive(
            ecgQueue,
            &ecg,
            0
        )
        ==
        pdTRUE
    )
    {
        createDisplayPixel(
            ecg
        );
    }

    static unsigned long
        lastFrame = 0;

    if (
        millis() -
        lastFrame >=
        FRAME_INTERVAL
    )
    {
        lastFrame =
            millis();

        scrollWave();

        renderFrame();
    }

    delay(1);
}