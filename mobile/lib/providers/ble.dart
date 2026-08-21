import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SensorSample {
  final double ecg;
  final double respiration;

  const SensorSample(this.ecg, this.respiration);
}

class _Biquad {
  final double b0;
  final double b1;
  final double b2;
  final double a1;
  final double a2;

  double x1 = 0.0;
  double x2 = 0.0;
  double y1 = 0.0;
  double y2 = 0.0;

  _Biquad(this.b0, this.b1, this.b2, this.a1, this.a2);

  double process(double x) {
    final y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;

    x2 = x1;
    x1 = x;

    y2 = y1;
    y1 = y;

    return y;
  }

  void reset() {
    x1 = 0.0;
    x2 = 0.0;
    y1 = 0.0;
    y2 = 0.0;
  }
}

class BleProvider extends ChangeNotifier {
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _ecgCharacteristic;

  bool _isConnected = false;
  bool _isScanning = false;

  List<ScanResult> _scanResults = [];
  List<ScanResult> _latestScanResults = [];

  StreamSubscription<List<int>>? _valueSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<dynamic>? _servicesResetSubscription;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSubscription;
  StreamSubscription<bool>? _scanStateSubscription;
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;

  Timer? _reconnectRetryTimer;

  bool _manualDisconnect = false;
  Future<bool>? _activationFuture;
  bool _autoReconnectArmed = false;
  bool _autoReconnectEnabled = true;
  bool _showOnlyApexDevices = false;
  DateTime? _lastManualDisconnectAt;
  bool _restorationRunning = false;
  bool _disposed = false;

  final String serviceUuid = "12345678-1234-1234-1234-123456789abc";

  final String characteristicUuid = "87654321-4321-4321-4321-cba987654321";

  static const double sampleRate = 250.0;

  static const int ecgVisiblePoints = 600;
  static const int respirationVisiblePoints = 600;

  static const int respirationDecimation = 5;

  static const int prebufferSamples = 20;
  static const int maxPendingSamples = 120;

  static const int qrsMwiSize = 38;
  static const int qrsSlopeSize = 25;
  static const int qrsCalibrationSamples = 500;

  bool get isConnected => _isConnected;
  bool get isScanning => _isScanning;
  bool get autoReconnectEnabled => _autoReconnectEnabled;
  bool get showOnlyApexDevices => _showOnlyApexDevices;

  List<ScanResult> get scanResults => _scanResults;

  String get deviceName => _connectedDevice?.platformName ?? "unknown_device";

  BluetoothCharacteristic? get ecgCaracteristics => _ecgCharacteristic;

  List<int> _ecgRawData = [];

  List<int> get ecgRawData => _ecgRawData;

  final List<double> _ecgPoints = [];

  List<double> get ecgPoints => _ecgPoints;

  final List<double> _respirationPoints = [];

  List<double> get respirationPoints => _respirationPoints;

  final StreamController<List<SensorSample>> _sampleBatchController =
      StreamController<List<SensorSample>>.broadcast();

  Stream<List<SensorSample>> get sampleBatches => _sampleBatchController.stream;

  final StreamController<bool> _connectionStateController =
      StreamController<bool>.broadcast();

  Stream<bool> get connectionChanges => _connectionStateController.stream;

  final Queue<SensorSample> _pendingSamples = Queue<SensorSample>();

  Ticker? _displayTicker;

  Duration _lastTickerElapsed = Duration.zero;

  double _sampleAccumulator = 0.0;

  bool _playbackStarted = false;

  double _respirationDisplayRange = 1.0;

  double get respirationDisplayRange => _respirationDisplayRange;

  bool _respirationInitialized = false;

  double _respirationBaseline = 0.0;

  double _respirationSmooth = 0.0;

  double _respirationPrevious = 0.0;

  double _respirationSlope = 0.0;

  double _respirationLevel = 0.5;

  double get respirationLevel => _respirationLevel;

  bool _isInhaling = false;

  bool get isInhaling => _isInhaling;

  int _respirationDecimationCounter = 0;

  double _respDetectionEnvelope = 1.0;

  bool _breathArmed = false;

  int _respirationSampleIndex = 0;

  int _lastBreathSample = 0;

  final List<int> _respirationIntervals = [];

  double _respiratoryRate = 0.0;

  double get respiratoryRate => _respiratoryRate;

  int _breathCount = 0;

  int get breathCount => _breathCount;

  final _qrsHighPass = _Biquad(
    0.91496914,
    -1.82993829,
    0.91496914,
    -1.82269493,
    0.83718165,
  );

  final _qrsLowPass = _Biquad(
    0.02785977,
    0.05571953,
    0.02785977,
    -1.47548044,
    0.58691951,
  );

  double _q1 = 0.0;
  double _q2 = 0.0;
  double _q3 = 0.0;
  double _q4 = 0.0;

  final List<double> _qrsMwiBuffer = List<double>.filled(qrsMwiSize, 0.0);

  int _qrsMwiIndex = 0;

  double _qrsMwiSum = 0.0;

  final List<double> _qrsSlopeBuffer = List<double>.filled(qrsSlopeSize, 0.0);

  int _qrsSlopeIndex = 0;

  double _qrsMwiPrev2 = 0.0;

  double _qrsMwiPrev1 = 0.0;

  double _qrsSlopePrev2 = 0.0;

  double _qrsSlopePrev1 = 0.0;

  int _qrsDetectorSamples = 0;

  bool _qrsDetectorReady = false;

  double _qrsCalibrationMax = 0.0;

  double _qrsCalibrationSum = 0.0;

  int _qrsCalibrationPeaks = 0;

  double _qrsSignalLevel = 0.0;

  double _qrsNoiseLevel = 0.0;

  double _qrsDetectionThreshold = 0.0;

  int _lastQrsSample = 0;

  double _lastQrsSlope = 0.0;

  double _averageRR = 0.0;

  final List<int> _heartRRHistory = [];

  double _heartRate = 0.0;

  double get heartRate => _heartRate;

  int _heartBeatSerial = 0;

  int get heartBeatSerial => _heartBeatSerial;

  BleProvider() {
    unawaited(_loadPreferences());

    _adapterStateSubscription =
        FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on) {
        unawaited(_restoreOrReconnect());
        return;
      }

      _isScanning = false;

      if (_connectedDevice != null || _isConnected) {
        _handleUnexpectedDisconnect(
          _connectedDevice,
          scheduleReconnect: false,
        );
      }

      notifyListeners();
    });

    _scanStateSubscription =
        FlutterBluePlus.isScanning.listen((scanning) {
      _isScanning = scanning;
      notifyListeners();
    });

    _scanResultsSubscription =
        FlutterBluePlus.scanResults.listen((results) {
      _latestScanResults =
          List<ScanResult>.from(
        results,
        growable: false,
      );
      _scanResults =
          _filterScanResults(
        _latestScanResults,
      );
      notifyListeners();
    });

    unawaited(_restoreOrReconnect());
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs =
          await SharedPreferences.getInstance();

      _autoReconnectEnabled =
          prefs.getBool(
            'ble_auto_reconnect',
          ) ??
          true;

      _showOnlyApexDevices =
          prefs.getBool(
            'ble_apex_only_v2',
          ) ??
          false;

      if (!_disposed) {
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> setAutoReconnectEnabled(
    bool value,
  ) async {
    _autoReconnectEnabled = value;

    if (!value) {
      _reconnectRetryTimer?.cancel();
      _autoReconnectArmed = false;
    } else if (!_isConnected &&
        _connectedDevice != null &&
        !_manualDisconnect) {
      _scheduleAutoReconnect(
        _connectedDevice!,
      );
    }

    notifyListeners();

    try {
      final prefs =
          await SharedPreferences.getInstance();

      await prefs.setBool(
        'ble_auto_reconnect',
        value,
      );
    } catch (_) {}
  }

  Future<void> setShowOnlyApexDevices(
    bool value,
  ) async {
    _showOnlyApexDevices = value;

    _scanResults =
        _filterScanResults(
      _latestScanResults,
    );

    notifyListeners();

    try {
      final prefs =
          await SharedPreferences.getInstance();

      await prefs.setBool(
        'ble_apex_only_v2',
        value,
      );
    } catch (_) {}
  }

  List<ScanResult> _filterScanResults(
    List<ScanResult> results,
  ) {
    if (!_showOnlyApexDevices) {
      return List<ScanResult>.from(
        results,
        growable: false,
      );
    }

    return results.where((result) {
      final name =
          result.device.platformName
              .trim()
              .toLowerCase();

      if (name.isEmpty) {
        return true;
      }

      return name.contains(
        'apexcardio',
      ) ||
      name.contains(
        'apex cardio',
      );
    }).toList(
      growable: false,
    );
  }

  Future<void> startScan() async {
    if (Platform.isAndroid) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.location,
      ].request();

      final hasPermission =
          statuses[Permission.bluetoothScan]?.isGranted == true ||
          await Permission.bluetoothScan.isGranted;

      if (!hasPermission) {
        return;
      }
    }

    await stopScan();

    final lastDisconnect =
        _lastManualDisconnectAt;

    if (lastDisconnect != null) {
      final elapsed =
          DateTime.now().difference(
        lastDisconnect,
      );

      if (elapsed <
          const Duration(
            milliseconds: 650,
          )) {
        await Future<void>.delayed(
          const Duration(
            milliseconds: 650,
          ) -
              elapsed,
        );
      }
    }

    _latestScanResults = [];
    _scanResults.clear();

    notifyListeners();

    await FlutterBluePlus.startScan(
      timeout:
          const Duration(
        seconds: 8,
      ),
    );
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  Future<bool> connectToDevice(
    BluetoothDevice device,
  ) async {
    try {
      _manualDisconnect = false;
      _reconnectRetryTimer?.cancel();
      _autoReconnectArmed = false;

      await stopScan();

      final previous =
          _connectedDevice;

      if (previous != null) {
        await _detachCurrentDevice(
          disconnectDevice:
              previous != device &&
              previous.isConnected,
        );
      }

      _connectedDevice = device;

      await _bindDeviceListeners(
        device,
      );

      final lastDisconnect =
          _lastManualDisconnectAt;

      if (lastDisconnect != null) {
        final elapsed =
            DateTime.now().difference(
          lastDisconnect,
        );

        if (elapsed <
            const Duration(
              milliseconds: 750,
            )) {
          await Future<void>.delayed(
            const Duration(
              milliseconds: 750,
            ) -
                elapsed,
          );
        }
      }

      if (!device.isConnected) {
        try {
          await device.connect(
            autoConnect: false,
            license: License.nonprofit,
          );
        } catch (_) {
          if (!device.isConnected) {
            await Future<void>.delayed(
              const Duration(
                milliseconds: 450,
              ),
            );

            await device.connect(
              autoConnect: false,
              license: License.nonprofit,
            );
          }
        }
      }

      if (!device.isConnected) {
        await Future<void>.delayed(
          const Duration(
            milliseconds: 180,
          ),
        );
      }

      final activated =
          await _activateDevice(
        device,
        forceRediscovery: true,
      );

      if (!activated) {
        await _detachCurrentDevice(
          disconnectDevice:
              device.isConnected,
        );

        return false;
      }

      return true;
    } catch (_) {
      if (_connectedDevice ==
          device) {
        await _detachCurrentDevice(
          disconnectDevice:
              device.isConnected,
        );
      }

      return false;
    }
  }

  Future<void> disconnect() async {
    _manualDisconnect = true;
    _lastManualDisconnectAt =
        DateTime.now();
    _reconnectRetryTimer?.cancel();
    _autoReconnectArmed = false;

    try {
      await _detachCurrentDevice(
        disconnectDevice: true,
      );

      await Future<void>.delayed(
        const Duration(
          milliseconds: 150,
        ),
      );
    } finally {
      _manualDisconnect = false;
    }
  }

  Future<void> _bindDeviceListeners(
    BluetoothDevice device,
  ) async {
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;

    await _servicesResetSubscription?.cancel();
    _servicesResetSubscription = null;

    _connectionSubscription =
        device.connectionState.listen((state) {
      if (_connectedDevice != device) {
        return;
      }

      if (state == BluetoothConnectionState.connected) {
        _autoReconnectArmed = false;
        _reconnectRetryTimer?.cancel();

        unawaited(
          _activateDevice(device),
        );
      } else if (state ==
          BluetoothConnectionState.disconnected) {
        _handleUnexpectedDisconnect(
          device,
          scheduleReconnect: !_manualDisconnect,
        );
      }
    });

    _servicesResetSubscription =
        device.onServicesReset.listen((_) {
      if (_connectedDevice != device ||
          !device.isConnected) {
        return;
      }

      unawaited(
        _activateDevice(
          device,
          forceRediscovery: true,
        ),
      );
    });
  }

  Future<bool> _activateDevice(
    BluetoothDevice device, {
    bool forceRediscovery = false,
  }) async {
    if (_disposed ||
        _connectedDevice != device ||
        !device.isConnected) {
      return false;
    }

    final running = _activationFuture;

    if (running != null) {
      return running;
    }

    final future = _performDeviceActivation(
      device,
      forceRediscovery: forceRediscovery,
    );

    _activationFuture = future;

    try {
      return await future;
    } finally {
      if (identical(_activationFuture, future)) {
        _activationFuture = null;
      }
    }
  }

  Future<bool> _performDeviceActivation(
    BluetoothDevice device, {
    required bool forceRediscovery,
  }) async {
    try {
      final services = forceRediscovery ||
              device.servicesList.isEmpty
          ? await device.discoverServices()
          : device.servicesList;

      if (_disposed ||
          _connectedDevice != device ||
          !device.isConnected) {
        return false;
      }

      BluetoothCharacteristic? characteristic;

      for (final service in services) {
        if (service.uuid.toString().toLowerCase() !=
            serviceUuid.toLowerCase()) {
          continue;
        }

        for (final candidate in service.characteristics) {
          if (candidate.uuid.toString().toLowerCase() ==
              characteristicUuid.toLowerCase()) {
            characteristic = candidate;
            break;
          }
        }

        if (characteristic != null) {
          break;
        }
      }

      if (characteristic == null) {
        return false;
      }

      final wasConnected = _isConnected;

      _ecgCharacteristic = characteristic;
      _isConnected = true;
      _autoReconnectArmed = false;

      await startListeningValues();

      if (!wasConnected) {
        _connectionStateController.add(true);
      }

      notifyListeners();

      return true;
    } catch (_) {
      _handleUnexpectedDisconnect(
        device,
        scheduleReconnect: !_manualDisconnect,
      );

      return false;
    }
  }

  void _handleUnexpectedDisconnect(
    BluetoothDevice? device, {
    required bool scheduleReconnect,
  }) {
    if (_disposed) {
      return;
    }

    final wasConnected = _isConnected;

    _valueSubscription?.cancel();
    _valueSubscription = null;

    _displayTicker?.dispose();
    _displayTicker = null;

    _ecgCharacteristic = null;
    _isConnected = false;

    if (wasConnected) {
      _connectionStateController.add(false);
    }

    _resetSignalState();
    notifyListeners();

    if (scheduleReconnect &&
        !_manualDisconnect &&
        device != null &&
        _connectedDevice == device) {
      _scheduleAutoReconnect(device);
    }
  }

  void _scheduleAutoReconnect(
    BluetoothDevice device,
  ) {
    if (_disposed ||
        _manualDisconnect ||
        !_autoReconnectEnabled ||
        _autoReconnectArmed ||
        _connectedDevice != device) {
      return;
    }

    _reconnectRetryTimer?.cancel();

    _reconnectRetryTimer = Timer(
      const Duration(seconds: 2),
      () {
        unawaited(
          _armAutoReconnect(device),
        );
      },
    );
  }

  Future<void> _armAutoReconnect(
    BluetoothDevice device,
  ) async {
    if (_disposed ||
        _manualDisconnect ||
        !_autoReconnectEnabled ||
        _autoReconnectArmed ||
        _connectedDevice != device) {
      return;
    }

    if (device.isConnected) {
      await _activateDevice(device);
      return;
    }

    _autoReconnectArmed = true;

    try {
      await device.connect(
        autoConnect: true,
        mtu: null,
        license: License.nonprofit,
      );
    } catch (_) {
      _autoReconnectArmed = false;

      if (!_manualDisconnect &&
          _autoReconnectEnabled &&
          _connectedDevice == device) {
        _scheduleAutoReconnect(device);
      }
    }
  }

  Future<void> _restoreOrReconnect() async {
    if (_disposed ||
        _manualDisconnect ||
        _restorationRunning ||
        _isConnected) {
      return;
    }

    _restorationRunning = true;

    try {
      final existing = _connectedDevice;

      if (existing != null) {
        if (existing.isConnected) {
          await _bindDeviceListeners(existing);
          await _activateDevice(existing);
        } else {
          await _bindDeviceListeners(existing);
          _scheduleAutoReconnect(existing);
        }

        if (_isConnected ||
            _autoReconnectArmed ||
            _reconnectRetryTimer?.isActive == true) {
          return;
        }
      }

      final connectedDevices =
          FlutterBluePlus.connectedDevices;

      for (final device in connectedDevices) {
        if (_disposed ||
            _manualDisconnect ||
            _isConnected) {
          return;
        }

        _connectedDevice = device;
        await _bindDeviceListeners(device);

        final activated =
            await _activateDevice(device);

        if (activated) {
          return;
        }

        await _detachCurrentDevice(
          disconnectDevice: false,
        );
      }

      if (!Platform.isIOS ||
          _disposed ||
          _manualDisconnect ||
          _isConnected) {
        return;
      }

      final systemDevices =
          await FlutterBluePlus.systemDevices(
        <Guid>[
          Guid(serviceUuid),
        ],
      );

      for (final device in systemDevices) {
        if (_disposed ||
            _manualDisconnect ||
            _isConnected) {
          return;
        }

        _connectedDevice = device;
        await _bindDeviceListeners(device);

        try {
          if (!device.isConnected) {
            await device.connect(
              autoConnect: false,
              license: License.nonprofit,
            );
          }

          final activated =
              await _activateDevice(device);

          if (activated) {
            return;
          }
        } catch (_) {}

        await _detachCurrentDevice(
          disconnectDevice: false,
        );
      }
    } finally {
      _restorationRunning = false;
    }
  }

  Future<void> _detachCurrentDevice({
    required bool disconnectDevice,
  }) async {
    final device = _connectedDevice;
    final wasConnected = _isConnected;

    _reconnectRetryTimer?.cancel();
    _autoReconnectArmed = false;

    await _valueSubscription?.cancel();
    _valueSubscription = null;

    await _servicesResetSubscription?.cancel();
    _servicesResetSubscription = null;

    await _connectionSubscription?.cancel();
    _connectionSubscription = null;

    _displayTicker?.dispose();
    _displayTicker = null;

    _ecgCharacteristic = null;
    _isConnected = false;
    _connectedDevice = null;

    if (disconnectDevice &&
        device != null) {
      try {
        await device.disconnect();
      } catch (_) {}
    }

    if (wasConnected) {
      _connectionStateController.add(false);
    }

    _resetSignalState();
    notifyListeners();
  }

  void _resetSignalState() {
    _ecgRawData = [];

    _ecgPoints.clear();

    _respirationPoints.clear();

    _pendingSamples.clear();

    _playbackStarted = false;

    _sampleAccumulator = 0.0;

    _lastTickerElapsed = Duration.zero;

    _respirationDisplayRange = 1.0;

    _respirationInitialized = false;

    _respirationBaseline = 0.0;

    _respirationSmooth = 0.0;

    _respirationPrevious = 0.0;

    _respirationSlope = 0.0;

    _respirationLevel = 0.5;

    _isInhaling = false;

    _respirationDecimationCounter = 0;

    _respDetectionEnvelope = 1.0;

    _breathArmed = false;

    _respirationSampleIndex = 0;

    _lastBreathSample = 0;

    _respirationIntervals.clear();

    _respiratoryRate = 0.0;

    _breathCount = 0;

    _qrsHighPass.reset();

    _qrsLowPass.reset();

    _q1 = 0.0;
    _q2 = 0.0;
    _q3 = 0.0;
    _q4 = 0.0;

    for (int i = 0; i < qrsMwiSize; i++) {
      _qrsMwiBuffer[i] = 0.0;
    }

    _qrsMwiIndex = 0;

    _qrsMwiSum = 0.0;

    for (int i = 0; i < qrsSlopeSize; i++) {
      _qrsSlopeBuffer[i] = 0.0;
    }

    _qrsSlopeIndex = 0;

    _qrsMwiPrev2 = 0.0;

    _qrsMwiPrev1 = 0.0;

    _qrsSlopePrev2 = 0.0;

    _qrsSlopePrev1 = 0.0;

    _qrsDetectorSamples = 0;

    _qrsDetectorReady = false;

    _qrsCalibrationMax = 0.0;

    _qrsCalibrationSum = 0.0;

    _qrsCalibrationPeaks = 0;

    _qrsSignalLevel = 0.0;

    _qrsNoiseLevel = 0.0;

    _qrsDetectionThreshold = 0.0;

    _lastQrsSample = 0;

    _lastQrsSlope = 0.0;

    _averageRR = 0.0;

    _heartRRHistory.clear();

    _heartRate = 0.0;

    _heartBeatSerial = 0;
  }

  Future<void> startListeningValues() async {
    if (_ecgCharacteristic == null) {
      return;
    }

    if (_valueSubscription != null) {
      await _valueSubscription!.cancel();

      _valueSubscription = null;
    }

    _displayTicker?.dispose();

    _displayTicker = null;

    _resetSignalState();

    await _ecgCharacteristic!.setNotifyValue(true);

    _startDisplayTicker();

    _valueSubscription = _ecgCharacteristic!.onValueReceived.listen((data) {
      if (data.isEmpty) {
        return;
      }

      _ecgRawData = List<int>.from(data);

      final List<SensorSample> batch = [];

      for (int offset = 0; offset + 8 < data.length; offset += 9) {
        final ecg = parseSample(
          data[offset + 3],
          data[offset + 4],
          data[offset + 5],
        );

        final respiration = parseSample(
          data[offset + 6],
          data[offset + 7],
          data[offset + 8],
        );

        final sample = SensorSample(ecg, respiration);

        _pendingSamples.add(sample);
        batch.add(sample);
      }

      if (batch.isNotEmpty) {
        _sampleBatchController.add(batch);
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

    final elapsedMicroseconds = (elapsed - _lastTickerElapsed).inMicroseconds;

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

    final samplesToDisplay = _sampleAccumulator.floor();

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

      final sample = _pendingSamples.removeFirst();

      _processHeartRate(sample.ecg);

      final respiration = _processRespiration(sample.respiration);

      _appendEcgSample(sample.ecg);

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

      _respirationPrevious = 0.0;

      return 0.0;
    }

    _respirationBaseline += 0.002 * (raw - _respirationBaseline);

    final centered = raw - _respirationBaseline;

    _respirationSmooth += 0.05 * (centered - _respirationSmooth);

    final instantaneousSlope = _respirationSmooth - _respirationPrevious;

    _respirationSlope += 0.12 * (instantaneousSlope - _respirationSlope);

    _respirationPrevious = _respirationSmooth;

    _isInhaling = _respirationSlope >= 0.0;

    _processRespirationRate(_respirationSmooth);

    return _respirationSmooth;
  }

  void _appendRespirationSample(double sample) {
    final amplitude = sample.abs();

    double wantedRange = amplitude * 1.35;

    if (wantedRange < 1.0) {
      wantedRange = 1.0;
    }

    if (wantedRange > _respirationDisplayRange) {
      _respirationDisplayRange +=
          0.45 * (wantedRange - _respirationDisplayRange);
    } else {
      _respirationDisplayRange +=
          0.006 * (wantedRange - _respirationDisplayRange);
    }

    if (_respirationDisplayRange < 1.0) {
      _respirationDisplayRange = 1.0;
    }

    double normalized = sample / _respirationDisplayRange;

    normalized = normalized.clamp(-1.0, 1.0);

    _respirationLevel = (normalized + 1.0) / 2.0;

    _respirationPoints.add(sample);

    if (_respirationPoints.length > respirationVisiblePoints) {
      _respirationPoints.removeAt(0);
    }
  }

  void _processRespirationRate(double respiration) {
    _respirationSampleIndex++;

    final amplitude = respiration.abs();

    if (amplitude > _respDetectionEnvelope) {
      _respDetectionEnvelope += 0.08 * (amplitude - _respDetectionEnvelope);
    } else {
      _respDetectionEnvelope += 0.004 * (amplitude - _respDetectionEnvelope);
    }

    if (_respDetectionEnvelope < 1.0) {
      _respDetectionEnvelope = 1.0;
    }

    final threshold = _respDetectionEnvelope * 0.18;

    if (respiration < -threshold) {
      _breathArmed = true;
    }

    if (_breathArmed && respiration > threshold) {
      final distance = _lastBreathSample == 0
          ? 1000000
          : _respirationSampleIndex - _lastBreathSample;

      if (_lastBreathSample == 0 || distance >= 150) {
        if (_lastBreathSample != 0 && distance <= 5000) {
          _respirationIntervals.add(distance);

          if (_respirationIntervals.length > 5) {
            _respirationIntervals.removeAt(0);
          }

          final median = _medianInt(_respirationIntervals);

          if (median > 0) {
            _respiratoryRate = 15000.0 / median;
          }
        }

        _lastBreathSample = _respirationSampleIndex;

        _breathCount++;

        _breathArmed = false;
      }
    }
  }

  double _getMaxQrsSlope() {
    double maximum = 0.0;

    for (final value in _qrsSlopeBuffer) {
      if (value > maximum) {
        maximum = value;
      }
    }

    return maximum;
  }

  void _processHeartRate(double ecg) {
    double qrs = _qrsHighPass.process(ecg);

    qrs = _qrsLowPass.process(qrs);

    final derivative = (2.0 * qrs + _q1 - _q3 - 2.0 * _q4) * 0.125;

    _q4 = _q3;

    _q3 = _q2;

    _q2 = _q1;

    _q1 = qrs;

    final absSlope = derivative.abs();

    _qrsSlopeBuffer[_qrsSlopeIndex] = absSlope;

    _qrsSlopeIndex++;

    if (_qrsSlopeIndex >= qrsSlopeSize) {
      _qrsSlopeIndex = 0;
    }

    final squared = derivative * derivative;

    _qrsMwiSum -= _qrsMwiBuffer[_qrsMwiIndex];

    _qrsMwiBuffer[_qrsMwiIndex] = squared;

    _qrsMwiSum += squared;

    _qrsMwiIndex++;

    if (_qrsMwiIndex >= qrsMwiSize) {
      _qrsMwiIndex = 0;
    }

    final mwi = _qrsMwiSum / qrsMwiSize;

    final slope = _getMaxQrsSlope();

    _qrsDetectorSamples++;

    final localPeak = _qrsMwiPrev1 > _qrsMwiPrev2 && _qrsMwiPrev1 >= mwi;

    if (!_qrsDetectorReady) {
      if (localPeak) {
        _qrsCalibrationSum += _qrsMwiPrev1;

        _qrsCalibrationPeaks++;

        if (_qrsMwiPrev1 > _qrsCalibrationMax) {
          _qrsCalibrationMax = _qrsMwiPrev1;
        }
      }

      if (_qrsDetectorSamples >= qrsCalibrationSamples) {
        final meanPeak = _qrsCalibrationPeaks > 0
            ? _qrsCalibrationSum / _qrsCalibrationPeaks
            : _qrsCalibrationMax * 0.25;

        _qrsNoiseLevel = meanPeak * 0.50;

        _qrsSignalLevel = _qrsCalibrationMax * 0.70;

        if (_qrsSignalLevel <= _qrsNoiseLevel) {
          _qrsSignalLevel = _qrsNoiseLevel * 2.0 + 1.0;
        }

        _qrsDetectionThreshold =
            _qrsNoiseLevel + 0.25 * (_qrsSignalLevel - _qrsNoiseLevel);

        _qrsDetectorReady = true;
      }

      _qrsMwiPrev2 = _qrsMwiPrev1;

      _qrsMwiPrev1 = mwi;

      _qrsSlopePrev2 = _qrsSlopePrev1;

      _qrsSlopePrev1 = slope;

      return;
    }

    if (localPeak) {
      final peak = _qrsMwiPrev1;

      final candidateSlope = _qrsSlopePrev1;

      final candidateSample = _qrsDetectorSamples - 1;

      final distance = _lastQrsSample == 0
          ? 1000000
          : candidateSample - _lastQrsSample;

      final refractory = _lastQrsSample != 0 && distance < 60;

      final possibleTWave =
          _lastQrsSample != 0 &&
          distance < 90 &&
          _lastQrsSlope > 0 &&
          candidateSlope < _lastQrsSlope * 0.50;

      final earlyLowSlope =
          _lastQrsSample != 0 &&
          _averageRR > 0 &&
          distance < _averageRR * 0.62 &&
          _lastQrsSlope > 0 &&
          candidateSlope < _lastQrsSlope * 0.70;

      _qrsDetectionThreshold =
          _qrsNoiseLevel + 0.25 * (_qrsSignalLevel - _qrsNoiseLevel);

      if (peak > _qrsDetectionThreshold &&
          !refractory &&
          !possibleTWave &&
          !earlyLowSlope) {
        _qrsSignalLevel = 0.875 * _qrsSignalLevel + 0.125 * peak;

        _acceptHeartBeat(candidateSample, candidateSlope);
      } else {
        final alpha = (refractory || possibleTWave || earlyLowSlope)
            ? 0.03
            : 0.125;

        _qrsNoiseLevel = (1.0 - alpha) * _qrsNoiseLevel + alpha * peak;
      }
    }

    _qrsMwiPrev2 = _qrsMwiPrev1;

    _qrsMwiPrev1 = mwi;

    _qrsSlopePrev2 = _qrsSlopePrev1;

    _qrsSlopePrev1 = slope;
  }

  void _acceptHeartBeat(int sample, double slope) {
    if (_lastQrsSample != 0) {
      final rr = sample - _lastQrsSample;

      if (rr >= 75 && rr <= 500) {
        _heartRRHistory.add(rr);

        if (_heartRRHistory.length > 5) {
          _heartRRHistory.removeAt(0);
        }

        final median = _medianInt(_heartRRHistory);

        if (median > 0) {
          _heartRate = 15000.0 / median;
        }
      }

      if (_averageRR <= 0.0) {
        _averageRR = rr.toDouble();
      } else {
        _averageRR = 0.80 * _averageRR + 0.20 * rr;
      }
    }

    _lastQrsSample = sample;

    _lastQrsSlope = slope;

    _heartBeatSerial++;
  }

  double _medianInt(List<int> values) {
    if (values.isEmpty) {
      return 0.0;
    }

    final copy = List<int>.from(values);

    copy.sort();

    if (copy.length.isOdd) {
      return copy[copy.length ~/ 2].toDouble();
    }

    final right = copy.length ~/ 2;

    final left = right - 1;

    return (copy[left] + copy[right]) / 2.0;
  }

  @override
  void dispose() {
    _disposed = true;

    _reconnectRetryTimer?.cancel();

    _adapterStateSubscription?.cancel();
    _scanStateSubscription?.cancel();
    _scanResultsSubscription?.cancel();

    _valueSubscription?.cancel();
    _servicesResetSubscription?.cancel();
    _connectionSubscription?.cancel();

    _displayTicker?.dispose();

    _sampleBatchController.close();
    _connectionStateController.close();

    super.dispose();
  }
}
