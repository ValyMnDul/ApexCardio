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
    await FlutterBluePlus.stopScan();
  }

  Future<bool> connectToDevice(BluetoothDevice device) async {
    try {
      await stopScan();
      await device.connect(autoConnect: false, license: License.nonprofit);

      List<BluetoothService> services = await device.discoverServices();

      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == serviceUuid) {
          for (var char in service.characteristics) {
            if (char.uuid.toString().toLowerCase() == characteristicUuid) {
              _ecgCharacteristic = char;
            }
          }
        }
      }

      if (_ecgCharacteristic != null) {
        _connectedDevice = device;
        _isConnected = true;

        device.connectionState.listen((state) {
          if (state == BluetoothConnectionState.disconnected) {
            _handleDisconnect();
          }
        });

        notifyListeners();
        return true;
      } else {
        await device.disconnect();
        return false;
      }
    } catch (e) {
      _handleDisconnect();
      return false;
    }
  }

  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
    }
    _handleDisconnect();
  }

  void _handleDisconnect() {
    _valueSubscription?.cancel();
    _connectedDevice = null;
    _ecgCharacteristic = null;
    _isConnected = false;
    notifyListeners();
  }
}
