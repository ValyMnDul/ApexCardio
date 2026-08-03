import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BleProvider extends ChangeNotifier {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _ecgCharacteristic;
  bool _isConnected = false;
  bool _isScanning = false;
  List<ScanResult> _scanResult = [];

  StreamSubscription<List<int>>? _valueSubscription;

  final String serviceUuid = "12345678-1234-1234-1234-123456789abc";
  final String characteristicUuid = "87654321-4321-4321-4321-cba987654321";

  bool get isConnected => _isConnected;
  bool get isScanning => _isScanning;
  List<ScanResult> get scanResult => _scanResult;
  String get deviceName => _connectedDevice?.platformName ?? "unknown_device";
  BluetoothCharacteristic? get ecgCaracteristics => _ecgCharacteristic;

  BleProvider() {
    FlutterBluePlus.isScanning.listen((scanning) {
      _isScanning = scanning;
      notifyListeners();
    });

    FlutterBluePlus.scanResults.listen((results) {
      _scanResult = results
          .where((r) => r.device.platformName.isNotEmpty)
          .toList();

      notifyListeners();
    });
  }

  Future<void> startScan() async {
    _scanResult.clear();
    notifyListeners();
    await FlutterBluePlus.startScan(timeout: Duration(seconds: 4));
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.startScan();
  }
}
