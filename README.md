# ApexCardio

A portable cardiac and respiratory monitoring system built with an ESP32, ADS1292R and a Flutter mobile application.

![Body](/assets/expedition (1).jpeg)

## Features

- Real-time ECG monitoring
- Real-time respiratory monitoring
- Heart rate and respiratory rate
- Bluetooth Low Energy communication
- Live data visualization
- Recording and local storage with SQLite
- PDF and CSV export
- Automatic Bluetooth reconnection
- OLED display on the device

## Mobile App

The Flutter application is used to connect to the device, display ECG and respiratory data in real time, record measurements and manage saved recordings.

The app can work offline and stores recordings locally using SQLite.

## Hardware

The device uses:

- ESP32
- ADS1292R
- OLED display
- Rechargeable 18650 batteries
- ECG electrodes
- RGB status LED

The ADS1292R allows the device to acquire ECG and impedance-based respiratory signals using the same electrodes.

## Development

Most of my documented development time was spent working on the Flutter application, including the interface, Bluetooth communication, data buffering, live graphs, recording system, SQLite storage and export features.

I was not able to properly track the hardware development time because I did not have a good enough webcam to document the work, and recording the hardware work was difficult.

## Project Goal

The goal of ApexCardio is to create a compact and portable monitoring device that can acquire, process and display physiological signals without requiring a computer or external power source.
