import 'dart:math' as math;
import 'dart:typed_data';

import 'recording_database.dart';

class RecordingAnalysisSummary {
  final double? averageHeartRateBpm;
  final double? averageRespirationRateBrpm;
  final double? averageRrMs;
  final double? averageBreathIntervalMs;
  final int gapCount;
  final int gapDurationUs;
  final int analyzedWindows;

  const RecordingAnalysisSummary({
    required this.averageHeartRateBpm,
    required this.averageRespirationRateBrpm,
    required this.averageRrMs,
    required this.averageBreathIntervalMs,
    required this.gapCount,
    required this.gapDurationUs,
    required this.analyzedWindows,
  });
}

class RecordingAnalysisService {
  static final RecordingAnalysisService instance =
      RecordingAnalysisService._internal();

  RecordingAnalysisService._internal();

  final RecordingDatabase _database = RecordingDatabase.instance;

  static const int _analysisWindowUs = 20 * 1000000;
  static const int _maximumWindows = 8;
  static const int _chunkPageSize = 160;

  Future<RecordingAnalysisSummary> analyze({
    required int recordingId,
    Map<String, Object?>? recording,
  }) async {
    await _database.initialize();

    final row = recording ?? await _database.getRecordingById(recordingId);

    if (row == null) {
      throw StateError('Recording not found.');
    }

    final sampleRate = (row['sample_rate'] as num?)?.toDouble() ?? 250.0;
    final timelineUs = row['timeline_duration_us'] as int? ?? 0;
    final gaps = await _database.getAllGaps(recordingId);

    var gapDurationUs = 0;

    for (final gap in gaps) {
      final start = gap['start_elapsed_us'] as int? ?? 0;
      final end = gap['end_elapsed_us'] as int? ?? start;
      gapDurationUs += math.max(0, end - start);
    }

    if (timelineUs <= 0 || sampleRate <= 0) {
      return RecordingAnalysisSummary(
        averageHeartRateBpm: null,
        averageRespirationRateBrpm: null,
        averageRrMs: null,
        averageBreathIntervalMs: null,
        gapCount: gaps.length,
        gapDurationUs: gapDurationUs,
        analyzedWindows: 0,
      );
    }

    final starts = _analysisWindowStarts(timelineUs);
    final heartRates = <double>[];
    final respirationRates = <double>[];

    for (final startUs in starts) {
      final endUs = math.min(timelineUs, startUs + _analysisWindowUs);

      final signals = await _loadSignals(
        recordingId: recordingId,
        startUs: startUs,
        endUs: endUs,
        sampleRate: sampleRate,
      );

      if (signals.ecg.length >= sampleRate * 4) {
        final heart = _estimateRate(
          values: signals.ecg,
          sampleRate: sampleRate,
          minimumDistanceSeconds: 0.28,
          thresholdMultiplier: 0.95,
          smoothingRadius: 2,
        );

        if (heart != null && heart >= 25 && heart <= 240) {
          heartRates.add(heart);
        }
      }

      if (signals.respiration.length >= sampleRate * 8) {
        final respiration = _estimateRate(
          values: signals.respiration,
          sampleRate: sampleRate,
          minimumDistanceSeconds: 1.20,
          thresholdMultiplier: 0.30,
          smoothingRadius: 8,
        );

        if (respiration != null && respiration >= 3 && respiration <= 60) {
          respirationRates.add(respiration);
        }
      }
    }

    final averageHeartRate = _meanOrNull(heartRates);
    final averageRespiration = _meanOrNull(respirationRates);

    return RecordingAnalysisSummary(
      averageHeartRateBpm: averageHeartRate,
      averageRespirationRateBrpm: averageRespiration,
      averageRrMs: averageHeartRate == null || averageHeartRate <= 0
          ? null
          : 60000.0 / averageHeartRate,
      averageBreathIntervalMs:
          averageRespiration == null || averageRespiration <= 0
          ? null
          : 60000.0 / averageRespiration,
      gapCount: gaps.length,
      gapDurationUs: gapDurationUs,
      analyzedWindows: starts.length,
    );
  }

  List<int> _analysisWindowStarts(int timelineUs) {
    if (timelineUs <= _analysisWindowUs) {
      return const <int>[0];
    }

    final availableStart = timelineUs - _analysisWindowUs;
    final count = math.min(
      _maximumWindows,
      math.max(2, (timelineUs / _analysisWindowUs).ceil()),
    );

    if (count <= 1) {
      return const <int>[0];
    }

    return List<int>.generate(
      count,
      (index) => (availableStart * index / (count - 1)).round(),
      growable: false,
    );
  }

  Future<_SignalWindow> _loadSignals({
    required int recordingId,
    required int startUs,
    required int endUs,
    required double sampleRate,
  }) async {
    final db = await _database.database;
    final ecg = <double>[];
    final respiration = <double>[];
    var lastChunkIndex = -1;

    while (true) {
      final rows = await db.query(
        'signal_chunks',
        where: '''
          recording_id = ?
          AND chunk_index > ?
          AND start_elapsed_us < ?
          AND end_elapsed_us > ?
        ''',
        whereArgs: <Object?>[recordingId, lastChunkIndex, endUs, startUs],
        orderBy: 'chunk_index ASC',
        limit: _chunkPageSize,
      );

      if (rows.isEmpty) {
        break;
      }

      for (final row in rows) {
        final chunkIndex = row['chunk_index'] as int? ?? lastChunkIndex;
        lastChunkIndex = chunkIndex;

        final sampleCount = row['sample_count'] as int? ?? 0;
        final chunkStartUs = row['start_elapsed_us'] as int? ?? 0;
        final raw = row['signal_data'];
        final bytes = switch (raw) {
          Uint8List value => value,
          List<int> value => Uint8List.fromList(value),
          _ => null,
        };

        if (bytes == null ||
            sampleCount <= 0 ||
            bytes.length < sampleCount * 8) {
          continue;
        }

        final data = ByteData.sublistView(bytes);
        final samplePeriodUs = 1000000.0 / sampleRate;

        for (int i = 0; i < sampleCount; i++) {
          final elapsedUs = chunkStartUs + (i * samplePeriodUs).round();

          if (elapsedUs < startUs) {
            continue;
          }

          if (elapsedUs >= endUs) {
            break;
          }

          final offset = i * 8;
          ecg.add(data.getInt32(offset, Endian.little).toDouble());
          respiration.add(data.getInt32(offset + 4, Endian.little).toDouble());
        }
      }
    }

    return _SignalWindow(ecg: ecg, respiration: respiration);
  }

  double? _estimateRate({
    required List<double> values,
    required double sampleRate,
    required double minimumDistanceSeconds,
    required double thresholdMultiplier,
    required int smoothingRadius,
  }) {
    if (values.length < 6 || sampleRate <= 0) {
      return null;
    }

    final smoothed = _smooth(values, smoothingRadius);

    final mean = smoothed.reduce((a, b) => a + b) / smoothed.length;
    var variance = 0.0;

    for (final value in smoothed) {
      final difference = value - mean;
      variance += difference * difference;
    }

    variance /= smoothed.length;
    final standardDeviation = math.sqrt(variance);

    if (!standardDeviation.isFinite || standardDeviation <= 0) {
      return null;
    }

    final threshold = mean + standardDeviation * thresholdMultiplier;
    final minimumDistanceSamples = math.max(
      1,
      (minimumDistanceSeconds * sampleRate).round(),
    );

    final peaks = <int>[];
    var lastPeak = -minimumDistanceSamples;

    for (int i = 1; i < smoothed.length - 1; i++) {
      final current = smoothed[i];

      if (current < threshold ||
          current < smoothed[i - 1] ||
          current < smoothed[i + 1]) {
        continue;
      }

      if (i - lastPeak < minimumDistanceSamples) {
        if (peaks.isNotEmpty && current > smoothed[peaks.last]) {
          peaks[peaks.length - 1] = i;
          lastPeak = i;
        }
        continue;
      }

      peaks.add(i);
      lastPeak = i;
    }

    if (peaks.length < 2) {
      return null;
    }

    var intervalSum = 0.0;
    var intervalCount = 0;

    for (int i = 1; i < peaks.length; i++) {
      final delta = peaks[i] - peaks[i - 1];
      if (delta <= 0) {
        continue;
      }
      intervalSum += delta / sampleRate;
      intervalCount++;
    }

    if (intervalCount == 0) {
      return null;
    }

    final averageInterval = intervalSum / intervalCount;

    if (!averageInterval.isFinite || averageInterval <= 0) {
      return null;
    }

    return 60.0 / averageInterval;
  }

  List<double> _smooth(List<double> values, int radius) {
    if (radius <= 0 || values.length < 3) {
      return List<double>.from(values);
    }

    final output = List<double>.filled(values.length, 0, growable: false);
    final prefix = List<double>.filled(values.length + 1, 0, growable: false);

    for (int i = 0; i < values.length; i++) {
      prefix[i + 1] = prefix[i] + values[i];
    }

    for (int i = 0; i < values.length; i++) {
      final start = math.max(0, i - radius);
      final end = math.min(values.length - 1, i + radius);
      output[i] = (prefix[end + 1] - prefix[start]) / (end - start + 1);
    }

    return output;
  }

  double? _meanOrNull(List<double> values) {
    if (values.isEmpty) {
      return null;
    }

    return values.reduce((a, b) => a + b) / values.length;
  }
}

class _SignalWindow {
  final List<double> ecg;
  final List<double> respiration;

  const _SignalWindow({required this.ecg, required this.respiration});
}
