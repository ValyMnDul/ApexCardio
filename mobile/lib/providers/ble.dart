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

  StreamSubscription<List<int>>? _valueSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;

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

      final services = await device.discoverServices();

      _ecgCharacteristic = null;

      for (final service in services) {
        if (service.uuid.toString().toLowerCase() ==
            serviceUuid.toLowerCase()) {
          for (final characteristic in service.characteristics) {
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

      if (_connectionSubscription != null) {
        await _connectionSubscription!.cancel();
      }

      _connectionSubscription = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnect();
        }
      });

      await startListeningValues();

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

    _valueSubscription = _ecgCharacteristic!.lastValueStream.listen((data) {
      if (data.isEmpty) {
        return;
      }

      _ecgRawData = List<int>.from(data);

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
    _valueSubscription?.cancel();

    _connectionSubscription?.cancel();

    _displayTicker?.dispose();

    super.dispose();
  }
}
