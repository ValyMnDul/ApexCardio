import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BleProvider extends ChangeNotifier {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _ecgCharacteristic;
  bool _isConnected = false;
  bool _isScanning = false;
  List<ScanResult> _scanResults = [];

  StreamSubscription<List<int>>? _valueSubscription;

  final String serviceUuid = "12345678-1234-1234-1234-123456789abc";
  final String characteristicUuid = "87654321-4321-4321-4321-cba987654321";

  bool get isConnected => _isConnected;
  bool get isScanning => _isScanning;
  List<ScanResult> get scanResults => _scanResults;
  String get deviceName => _connectedDevice?.platformName ?? "unknown_device";
  BluetoothCharacteristic? get ecgCaracteristics => _ecgCharacteristic;

  List<int> _ecgRawData = [];
  List<int> get ecgRawData => _ecgRawData;

  BleProvider() {
    FlutterBluePlus.adapterState.listen((state) {
      if (state != BluetoothAdapterState.on) {
        _isScanning = false;
        _isConnected = false;
        _handleDisconnect();
      }
    });

    FlutterBluePlus.isScanning.listen((scanning) {
      _isScanning = scanning;
      notifyListeners();
    });

    FlutterBluePlus.scanResults.listen((results) {
      _scanResults = results
          .where((r) => r.device.platformName.isNotEmpty)
          .toList();

      notifyListeners();
    });
  }

  Future<void> startScan() async {
    if (Platform.isAndroid) {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();

      bool hasPermission =
          statuses[Permission.bluetoothScan]?.isGranted == true ||
          await Permission.bluetoothScan.isGranted;

      if (!hasPermission) return;
    }

    _scanResults.clear();
    notifyListeners();
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 4));
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
    _ecgRawData = [];
    notifyListeners();
  }

  void startListeningValues() {
    if (_ecgCharacteristic == null) return;

    _ecgCharacteristic!.setNotifyValue(true);

    _valueSubscription = _ecgCharacteristic!.lastValueStream.listen((data) {
      _ecgRawData = data;
      notifyListeners();
    });
  }
}
