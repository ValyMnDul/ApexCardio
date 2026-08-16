import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class _SensorSample {
  final double ecg;
  final double respiration;

  _SensorSample(this.ecg, this.respiration);
}

class BleProvider extends ChangeNotifier {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _ecgCharacteristic;

  bool _isConnected = false;
  bool _isScanning = false;

  List<ScanResult> _scanResults = [];

  StreamSubscription<List<int>>? _valueSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

  final String serviceUuid = "12345678-1234-1234-1234-123456789abc";

  final String characteristicUuid = "87654321-4321-4321-4321-cba987654321";

  static const double sampleRate = 250.0;

  static const int ecgVisiblePoints = 300;

  static const int respirationDecimation = 5;
  static const int respirationVisiblePoints = 600;

  static const int prebufferSamples = 20;
  static const int maxPendingSamples = 100;

  bool get isConnected => _isConnected;
  bool get isScanning => _isScanning;

  List<ScanResult> get scanResults => _scanResults;

  String get deviceName => _connectedDevice?.platformName ?? "unknown_device";

  BluetoothCharacteristic? get ecgCaracteristics => _ecgCharacteristic;

  List<int> _ecgRawData = [];

  List<int> get ecgRawData => _ecgRawData;

  final List<double> _ecgPoints = [];

  List<double> get ecgPoints => _ecgPoints;

  final List<double> _respirationPoints = [];

  List<double> get respirationPoints => _respirationPoints;

  final Queue<_SensorSample> _pendingSamples = Queue<_SensorSample>();

  Ticker? _displayTicker;

  Duration _lastTickerElapsed = Duration.zero;

  double _sampleAccumulator = 0.0;

  bool _playbackStarted = false;

  bool _respirationInitialized = false;

  double _respirationBaseline = 0.0;

  double _respirationSmooth = 0.0;

  double _respirationDisplayRange = 1.0;

  int _respirationDecimationCounter = 0;

  double get respirationDisplayRange => _respirationDisplayRange;

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

      if (!hasPermission) {
        return;
      }
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

      _ecgCharacteristic = null;

      for (var service in services) {
        if (service.uuid.toString().toLowerCase() ==
            serviceUuid.toLowerCase()) {
          for (var characteristic in service.characteristics) {
            if (characteristic.uuid.toString().toLowerCase() ==
                characteristicUuid.toLowerCase()) {
              _ecgCharacteristic = characteristic;
            }
          }
        }
      }

      if (_ecgCharacteristic == null) {
        await device.disconnect();

        return false;
      }

      _connectedDevice = device;

      _isConnected = true;

      await _connectionSubscription?.cancel();

      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnect();
        }
      });

      notifyListeners();

      return true;
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

  void _resetSignalState() {
    _ecgRawData = [];

    _ecgPoints.clear();
    _respirationPoints.clear();

    _pendingSamples.clear();

    _playbackStarted = false;

    _sampleAccumulator = 0.0;

    _lastTickerElapsed = Duration.zero;

    _respirationInitialized = false;

    _respirationBaseline = 0.0;

    _respirationSmooth = 0.0;

    _respirationDisplayRange = 1.0;

    _respirationDecimationCounter = 0;
  }

  void _handleDisconnect() {
    _valueSubscription?.cancel();

    _valueSubscription = null;

    _connectionSubscription?.cancel();

    _connectionSubscription = null;

    _displayTicker?.dispose();

    _displayTicker = null;

    _connectedDevice = null;

    _ecgCharacteristic = null;

    _isConnected = false;

    _resetSignalState();

    notifyListeners();
  }

  void startListeningValues() {
    if (_ecgCharacteristic == null) {
      return;
    }

    _valueSubscription?.cancel();

    _displayTicker?.dispose();

    _displayTicker = null;

    _resetSignalState();

    _ecgCharacteristic!.setNotifyValue(true);

    _startDisplayTicker();

    _valueSubscription = _ecgCharacteristic!.lastValueStream.listen((data) {
      if (data.isEmpty) {
        return;
      }

      _ecgRawData = List<int>.from(data);

      for (int offset = 0; offset + 8 < data.length; offset += 9) {
        double ecg = parseSample(
          data[offset + 3],
          data[offset + 4],
          data[offset + 5],
        );

        double respiration = parseSample(
          data[offset + 6],
          data[offset + 7],
          data[offset + 8],
        );

        _pendingSamples.add(_SensorSample(ecg, respiration));
      }

      if (_pendingSamples.length > maxPendingSamples) {
        while (_pendingSamples.length > prebufferSamples * 2) {
          _pendingSamples.removeFirst();
        }

        _playbackStarted = false;

        _sampleAccumulator = 0.0;
      }
    });
  }

  double parseSample(int b1, int b2, int b3) {
    int raw = ((b1 & 0xFF) << 16) | ((b2 & 0xFF) << 8) | (b3 & 0xFF);

    if ((raw & 0x800000) != 0) {
      raw -= 0x1000000;
    }

    return raw.toDouble();
  }

  void _startDisplayTicker() {
    _displayTicker = Ticker(_onDisplayTick);

    _displayTicker!.start();
  }

  void _onDisplayTick(Duration elapsed) {
    if (!_playbackStarted) {
      if (_pendingSamples.length < prebufferSamples) {
        return;
      }

      _playbackStarted = true;

      _lastTickerElapsed = elapsed;

      _sampleAccumulator = 0.0;

      return;
    }

    int elapsedMicroseconds = (elapsed - _lastTickerElapsed).inMicroseconds;

    _lastTickerElapsed = elapsed;

    if (elapsedMicroseconds <= 0) {
      return;
    }

    if (elapsedMicroseconds > 100000) {
      _playbackStarted = false;

      _sampleAccumulator = 0.0;

      return;
    }

    _sampleAccumulator += elapsedMicroseconds * sampleRate / 1000000.0;

    int samplesToDisplay = _sampleAccumulator.floor();

    if (samplesToDisplay <= 0) {
      return;
    }

    _sampleAccumulator -= samplesToDisplay;

    bool changed = false;

    for (int i = 0; i < samplesToDisplay; i++) {
      if (_pendingSamples.isEmpty) {
        _playbackStarted = false;

        _sampleAccumulator = 0.0;

        break;
      }

      _SensorSample sample = _pendingSamples.removeFirst();

      _appendEcgSample(sample.ecg);

      double respiration = _processRespiration(sample.respiration);

      _respirationDecimationCounter++;

      if (_respirationDecimationCounter >= respirationDecimation) {
        _respirationDecimationCounter = 0;

        _appendRespirationSample(respiration);
      }

      changed = true;
    }

    if (changed) {
      notifyListeners();
    }
  }

  void _appendEcgSample(double sample) {
    _ecgPoints.add(sample);

    if (_ecgPoints.length > ecgVisiblePoints) {
      _ecgPoints.removeAt(0);
    }
  }

  double _processRespiration(double raw) {
    if (raw >= 8300000 || raw <= -8300000) {
      return _respirationSmooth;
    }

    if (!_respirationInitialized) {
      _respirationInitialized = true;

      _respirationBaseline = raw;

      _respirationSmooth = 0.0;

      return 0.0;
    }

    _respirationBaseline += 0.002 * (raw - _respirationBaseline);

    double centered = raw - _respirationBaseline;

    _respirationSmooth += 0.05 * (centered - _respirationSmooth);

    double amplitude = _respirationSmooth.abs();

    if (amplitude > _respirationDisplayRange * 0.8) {
      _respirationDisplayRange = amplitude * 1.25;
    }

    if (_respirationDisplayRange < 1.0) {
      _respirationDisplayRange = 1.0;
    }

    return _respirationSmooth;
  }

  void _appendRespirationSample(double sample) {
    _respirationPoints.add(sample);

    if (_respirationPoints.length > respirationVisiblePoints) {
      _respirationPoints.removeAt(0);
    }
  }

  @override
  void dispose() {
    _valueSubscription?.cancel();

    _connectionSubscription?.cancel();

    _displayTicker?.dispose();

    super.dispose();
  }
}
