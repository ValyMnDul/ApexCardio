import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/recording_database.dart';
import '../services/recording_background_service.dart';
import '../services/recording_live_activity_service.dart';
import 'ble.dart';

enum RecordingSessionState {
  idle,
  starting,
  recording,
  paused,
  stopping,
  error,
}

enum RecordingGapReason { paused, bluetoothDisconnected, processRestart }

extension RecordingGapReasonValue on RecordingGapReason {
  String get databaseValue {
    switch (this) {
      case RecordingGapReason.paused:
        return 'paused';
      case RecordingGapReason.bluetoothDisconnected:
        return 'bluetooth_disconnected';
      case RecordingGapReason.processRestart:
        return 'process_restart';
    }
  }
}

class _PendingChunk {
  final int recordingId;
  final int chunkIndex;
  final int startElapsedUs;
  final int endElapsedUs;
  final int sampleCount;
  final Uint8List signalData;

  const _PendingChunk({
    required this.recordingId,
    required this.chunkIndex,
    required this.startElapsedUs,
    required this.endElapsedUs,
    required this.sampleCount,
    required this.signalData,
  });
}

class RecordingProvider extends ChangeNotifier with WidgetsBindingObserver {
  final BleProvider _ble;
  final RecordingDatabase _database;
  final RecordingBackgroundService _backgroundService;
  final RecordingLiveActivityService _liveActivityService;

  late final StreamSubscription<List<SensorSample>> _sampleSubscription;
  late final StreamSubscription<bool> _connectionSubscription;

  final Queue<_PendingChunk> _writeQueue = Queue<_PendingChunk>();
  final List<Completer<void>> _writeDrainWaiters = <Completer<void>>[];
  final Stopwatch _timelineClock = Stopwatch();
  final List<SensorSample> _chunkBuffer = <SensorSample>[];

  int _timelineBaseUs = 0;

  static const int targetChunkSamples = 250;
  static const int bytesPerSample = 8;
  static const int encodingVersion = 1;
  static const Duration heartbeatInterval = Duration(seconds: 5);
  static const int maxWriteAttempts = 3;

  RecordingSessionState _state = RecordingSessionState.idle;
  RecordingSessionState get state => _state;

  bool _initialized = false;
  bool get initialized => _initialized;

  bool _disposed = false;
  bool _bleConnected = false;
  bool get bleConnected => _bleConnected;

  bool _writerRunning = false;
  bool _writerBlocked = false;
  bool get hasPendingWrites => _writeQueue.isNotEmpty || _writerRunning;
  int get pendingChunkWrites => _writeQueue.length;

  int? _recordingId;
  int? get recordingId => _recordingId;

  String? _recordingName;
  String? get recordingName => _recordingName;

  String? _notes;
  String? get notes => _notes;

  DateTime? _startedAt;
  DateTime? get startedAt => _startedAt;

  int? _activeGapId;
  RecordingGapReason? _activeGapReason;
  RecordingGapReason? get activeGapReason => _activeGapReason;

  int _chunkIndex = 0;
  int? _chunkStartElapsedUs;
  int? _nextSampleElapsedUs;

  int _receivedSampleCount = 0;
  int get receivedSampleCount => _receivedSampleCount;

  int _persistedSampleCount = 0;
  int get persistedSampleCount => _persistedSampleCount;

  String? _lastError;
  String? get lastError => _lastError;

  Timer? _heartbeatTimer;
  Future<void>? _initializationFuture;
  Future<void> _controlChain = Future<void>.value();

  RecordingProvider(
    this._ble, {
    RecordingDatabase? database,
    RecordingBackgroundService? backgroundService,
    RecordingLiveActivityService? liveActivityService,
  }) : _database = database ?? RecordingDatabase.instance,
       _backgroundService =
           backgroundService ?? RecordingBackgroundService.instance,
       _liveActivityService =
           liveActivityService ?? RecordingLiveActivityService.instance {
    _bleConnected = _ble.isConnected;

    _sampleSubscription = _ble.sampleBatches.listen(_onSampleBatch);
    _connectionSubscription = _ble.connectionChanges.listen(
      _onConnectionChanged,
    );

    _backgroundService.bindCommands(
      onPause: pauseRecording,
      onResume: resumeRecording,
      onStop: stopRecording,
    );

    _liveActivityService.bindCommands(
      onPause: pauseRecording,
      onResume: resumeRecording,
      onStop: stopRecording,
    );

    WidgetsBinding.instance.addObserver(this);
    _initializationFuture = _initialize();
  }

  bool get isIdle => _state == RecordingSessionState.idle;
  bool get isStarting => _state == RecordingSessionState.starting;
  bool get isRecording => _state == RecordingSessionState.recording;
  bool get isPaused => _state == RecordingSessionState.paused;
  bool get isStopping => _state == RecordingSessionState.stopping;
  bool get hasError => _state == RecordingSessionState.error;
  bool get hasActiveRecording =>
      _state != RecordingSessionState.idle && _recordingId != null;

  int get timelineElapsedUs {
    if (_recordingId == null) {
      return 0;
    }

    return _safeTimelinePositionUs();
  }

  Duration get timelineDuration => Duration(microseconds: timelineElapsedUs);

  double get measuredDurationSeconds =>
      _receivedSampleCount / BleProvider.sampleRate;

  Future<void> _initialize() async {
    try {
      await _database.initialize();
      await _backgroundService.initialize();

      final restored = await _restoreActiveSession();

      if (!restored) {
        await _database.recoverInterruptedRecordings();
      }

      _initialized = true;
      _notify();
    } catch (error) {
      _lastError = error.toString();
      _state = RecordingSessionState.error;
      _notify();
    }
  }

  Future<bool> _restoreActiveSession() async {
    final db = await _database.database;

    final activeRows = await db.query(
      'recordings',
      where: "status IN ('recording', 'paused')",
      orderBy: 'updated_at_ms DESC, id DESC',
    );

    if (activeRows.isEmpty) {
      return false;
    }

    final row = activeRows.first;

    if (activeRows.length > 1) {
      await _markOlderActiveRowsInterrupted(
        activeRows.skip(1).toList(growable: false),
      );
    }

    final id = row['id'] as int;
    final name = row['name'] as String? ?? 'ApexCardio Recording';
    final notes = row['notes'] as String?;
    final startedAtMs = row['started_at_ms'] as int;
    final status = row['status'] as String? ?? 'recording';
    final persistedTimelineUs = row['timeline_duration_us'] as int? ?? 0;
    final recordedSampleCount = row['recorded_sample_count'] as int? ?? 0;
    final lastCommittedElapsedUs =
        row['last_committed_elapsed_us'] as int? ?? 0;
    final lastHeartbeatAtMs =
        row['last_heartbeat_at_ms'] as int? ?? startedAtMs;

    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final missingWallTimeUs =
        math.max(0, nowMs - lastHeartbeatAtMs) *
        Duration.microsecondsPerMillisecond;

    final recoveredTimelineUs = math.max(
      math.max(persistedTimelineUs + missingWallTimeUs, persistedTimelineUs),
      lastCommittedElapsedUs,
    );

    final maxChunkRows = await db.rawQuery(
      '''
      SELECT
        COALESCE(MAX(chunk_index), -1) AS max_chunk_index
      FROM signal_chunks
      WHERE recording_id = ?
      ''',
      <Object?>[id],
    );

    final maxChunkIndex =
        (maxChunkRows.first['max_chunk_index'] as num?)?.toInt() ?? -1;

    final openGapRows = await db.query(
      'recording_gaps',
      where: '''
        recording_id = ?
        AND end_elapsed_us IS NULL
      ''',
      whereArgs: <Object?>[id],
      orderBy: 'start_elapsed_us DESC, id DESC',
    );

    if (openGapRows.length > 1) {
      for (final staleGap in openGapRows.skip(1)) {
        await _database.closeGap(
          gapId: staleGap['id'] as int,
          recordingId: id,
          endElapsedUs: recoveredTimelineUs,
        );
      }
    }

    _recordingId = id;
    _recordingName = name;
    _notes = notes;
    _startedAt = DateTime.fromMillisecondsSinceEpoch(startedAtMs);

    _chunkIndex = maxChunkIndex + 1;
    _chunkStartElapsedUs = null;
    _nextSampleElapsedUs = null;

    _receivedSampleCount = recordedSampleCount;
    _persistedSampleCount = recordedSampleCount;

    _chunkBuffer.clear();
    _writeQueue.clear();
    _writerBlocked = false;
    _lastError = null;

    _timelineBaseUs = recoveredTimelineUs;

    _timelineClock
      ..reset()
      ..start();

    _activeGapId = null;
    _activeGapReason = null;

    if (openGapRows.isNotEmpty) {
      final openGap = openGapRows.first;

      _activeGapId = openGap['id'] as int;
      _activeGapReason = _gapReasonFromDatabase(openGap['reason'] as String?);
    }

    if (status == 'paused') {
      _state = RecordingSessionState.paused;

      if (_activeGapReason != RecordingGapReason.paused) {
        if (_activeGapId != null) {
          await _closeActiveGap(recoveredTimelineUs);
        }

        await _openGap(
          RecordingGapReason.paused,
          math.max(persistedTimelineUs, lastCommittedElapsedUs),
        );
      }
    } else {
      _state = RecordingSessionState.recording;

      if (_activeGapReason == RecordingGapReason.paused) {
        await _closeActiveGap(recoveredTimelineUs);
      }

      if (_activeGapId == null &&
          recoveredTimelineUs > lastCommittedElapsedUs) {
        await _openGap(
          RecordingGapReason.processRestart,
          lastCommittedElapsedUs,
        );
      }

      if (_bleConnected && _activeGapReason != RecordingGapReason.paused) {
        await _closeActiveGap(recoveredTimelineUs);

        _nextSampleElapsedUs = recoveredTimelineUs;
      }
    }

    await _database.updateRecordingProgress(
      recordingId: id,
      timelineDurationUs: recoveredTimelineUs,
    );

    _startHeartbeat();

    await _backgroundService.start(
      recordingId: id,
      recordingName: name,
      startedAtMs: startedAtMs,
      paused: _state == RecordingSessionState.paused,
      connected: _bleConnected,
    );

    await _startLiveActivity();

    return true;
  }

  Future<void> _markOlderActiveRowsInterrupted(
    List<Map<String, Object?>> rows,
  ) async {
    if (rows.isEmpty) {
      return;
    }

    final db = await _database.database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      for (final row in rows) {
        final id = row['id'] as int;
        final timelineUs = row['timeline_duration_us'] as int? ?? 0;
        final heartbeatMs = row['last_heartbeat_at_ms'] as int? ?? now;

        await txn.rawUpdate(
          '''
          UPDATE recording_gaps
          SET end_elapsed_us = ?
          WHERE recording_id = ?
            AND end_elapsed_us IS NULL
          ''',
          <Object?>[timelineUs, id],
        );

        await txn.update(
          'recordings',
          <String, Object?>{
            'ended_at_ms': heartbeatMs,
            'status': 'interrupted',
            'updated_at_ms': now,
          },
          where: 'id = ?',
          whereArgs: <Object?>[id],
        );
      }
    });
  }

  RecordingGapReason _gapReasonFromDatabase(String? value) {
    switch (value) {
      case 'paused':
        return RecordingGapReason.paused;
      case 'bluetooth_disconnected':
        return RecordingGapReason.bluetoothDisconnected;
      case 'process_restart':
        return RecordingGapReason.processRestart;
      default:
        return RecordingGapReason.processRestart;
    }
  }

  Future<void> ensureInitialized() async {
    final future = _initializationFuture;

    if (future != null) {
      await future;
    }

    if (!_initialized) {
      throw StateError(
        _lastError ?? 'Recording database initialization failed.',
      );
    }
  }

  Future<void> startRecording({
    required String name,
    String? notes,
    Map<String, Object?>? additionalData,
  }) {
    return _serializeControl(() async {
      await ensureInitialized();

      if (_state != RecordingSessionState.idle) {
        return;
      }

      _state = RecordingSessionState.starting;
      _lastError = null;
      _notify();

      int? createdRecordingId;

      try {
        await _backgroundService.requestNotificationPermission();

        final now = DateTime.now();
        final cleanedName = name.trim().isEmpty
            ? _defaultRecordingName(now)
            : name.trim();
        final cleanedNotes = notes?.trim();
        final metadataJson = additionalData == null || additionalData.isEmpty
            ? null
            : jsonEncode(additionalData);

        final id = await _database.createRecording(
          name: cleanedName,
          notes: cleanedNotes == null || cleanedNotes.isEmpty
              ? null
              : cleanedNotes,
          metadataJson: metadataJson,
          startedAtMs: now.millisecondsSinceEpoch,
          sampleRate: BleProvider.sampleRate,
          deviceName: _ble.deviceName,
        );

        createdRecordingId = id;

        _recordingId = id;
        _recordingName = cleanedName;
        _notes = cleanedNotes == null || cleanedNotes.isEmpty
            ? null
            : cleanedNotes;
        _startedAt = now;
        _chunkIndex = 0;
        _chunkStartElapsedUs = null;
        _nextSampleElapsedUs = null;
        _activeGapId = null;
        _activeGapReason = null;
        _receivedSampleCount = 0;
        _persistedSampleCount = 0;
        _chunkBuffer.clear();
        _writeQueue.clear();
        _writerBlocked = false;

        _timelineBaseUs = 0;

        _timelineClock
          ..reset()
          ..start();

        _state = RecordingSessionState.recording;
        _startHeartbeat();

        if (!_bleConnected) {
          await _openGap(RecordingGapReason.bluetoothDisconnected, 0);
        }

        await _backgroundService.start(
          recordingId: id,
          recordingName: cleanedName,
          startedAtMs: now.millisecondsSinceEpoch,
          paused: false,
          connected: _bleConnected,
        );

        await _startLiveActivity();

        _notify();
      } catch (error) {
        _stopHeartbeat();
        _timelineClock.stop();

        if (createdRecordingId != null) {
          try {
            await _database.deleteRecording(createdRecordingId);
          } catch (_) {}
        }

        try {
          await _backgroundService.stop();
        } catch (_) {}

        if (createdRecordingId != null) {
          await _endLiveActivity(
            recordingId: createdRecordingId,
            finalStatus: 'Cancelled',
          );
        }

        _clearActiveSession();
        _lastError = error.toString();
        _state = RecordingSessionState.error;
        _notify();
        rethrow;
      }
    });
  }

  Future<void> pauseRecording() {
    return _serializeControl(() async {
      if (_state != RecordingSessionState.recording) {
        return;
      }

      _state = RecordingSessionState.paused;
      _notify();

      _flushChunk();
      final position = _safeTimelinePositionUs();

      await _waitForWrites();

      if (_activeGapId != null) {
        await _closeActiveGap(position);
      }

      await _database.setRecordingStatus(
        recordingId: _recordingId!,
        status: 'paused',
      );

      await _openGap(RecordingGapReason.paused, position);

      _nextSampleElapsedUs = null;

      await _syncExternalRecordingState();

      _notify();
    });
  }

  Future<void> resumeRecording() {
    return _serializeControl(() async {
      if (_state != RecordingSessionState.paused) {
        return;
      }

      final position = _clockTimelinePositionUs();

      await _closeActiveGap(position);

      await _database.setRecordingStatus(
        recordingId: _recordingId!,
        status: 'recording',
      );

      _state = RecordingSessionState.recording;
      _nextSampleElapsedUs = position;

      if (!_bleConnected) {
        await _openGap(RecordingGapReason.bluetoothDisconnected, position);
      }

      await _syncExternalRecordingState();

      _notify();
    });
  }

  Future<void> stopRecording() {
    return _serializeControl(() async {
      if (_recordingId == null ||
          _state == RecordingSessionState.idle ||
          _state == RecordingSessionState.stopping) {
        return;
      }

      final id = _recordingId!;
      final name = _recordingName ?? 'ApexCardio Recording';

      _state = RecordingSessionState.stopping;
      _notify();

      try {
        await _backgroundService.showStopping(recordingName: name);
      } catch (_) {}

      await _syncLiveActivityState(statusOverride: 'Saving');

      _flushChunk();
      final finalPosition = _safeTimelinePositionUs();

      try {
        await _waitForWrites();
        await _closeActiveGap(finalPosition);

        _timelineClock.stop();
        _stopHeartbeat();

        await _database.finishRecording(
          recordingId: id,
          endedAtMs: DateTime.now().millisecondsSinceEpoch,
          timelineDurationUs: finalPosition,
        );

        await _database.checkpoint();

        try {
          await _backgroundService.stop();
        } catch (_) {}

        await _endLiveActivity(recordingId: id, finalStatus: 'Saved');

        _clearActiveSession();
        _state = RecordingSessionState.idle;
        _lastError = null;
        _notify();
      } catch (error) {
        _lastError = error.toString();
        _state = RecordingSessionState.error;

        try {
          await _syncExternalRecordingState();
        } catch (_) {}

        _notify();
        rethrow;
      }
    });
  }

  Future<void> retryPendingWrites() async {
    if (!_writerBlocked || _writeQueue.isEmpty) {
      return;
    }

    _lastError = null;
    _writerBlocked = false;
    _startWriter();
    await _waitForWrites();
    _notify();
  }

  void clearError() {
    if (_state == RecordingSessionState.error && _recordingId == null) {
      _state = RecordingSessionState.idle;
    }

    _lastError = null;
    _notify();
  }

  void _onSampleBatch(List<SensorSample> batch) {
    if (_state != RecordingSessionState.recording ||
        !_bleConnected ||
        _activeGapId != null ||
        batch.isEmpty ||
        _writerBlocked) {
      return;
    }

    _nextSampleElapsedUs ??= _clockTimelinePositionUs();

    for (final sample in batch) {
      _chunkStartElapsedUs ??= _nextSampleElapsedUs;
      _chunkBuffer.add(sample);
      _receivedSampleCount++;
      _nextSampleElapsedUs = _nextSampleElapsedUs! + _samplePeriodUs;

      if (_chunkBuffer.length >= targetChunkSamples) {
        _flushChunk();
      }
    }
  }

  void _flushChunk() {
    if (_chunkBuffer.isEmpty) {
      return;
    }

    final recordingId = _recordingId;
    final startElapsedUs = _chunkStartElapsedUs;

    if (recordingId == null || startElapsedUs == null) {
      return;
    }

    final samples = List<SensorSample>.from(_chunkBuffer);
    final endElapsedUs = startElapsedUs + samples.length * _samplePeriodUs;
    final encodedData = _encodeSamples(samples);

    final chunk = _PendingChunk(
      recordingId: recordingId,
      chunkIndex: _chunkIndex,
      startElapsedUs: startElapsedUs,
      endElapsedUs: endElapsedUs,
      sampleCount: samples.length,
      signalData: encodedData,
    );

    _chunkBuffer.clear();
    _chunkStartElapsedUs = null;
    _chunkIndex++;

    _writeQueue.add(chunk);
    _startWriter();
  }

  void _startWriter() {
    if (_writerRunning || _writerBlocked || _disposed) {
      return;
    }

    _writerRunning = true;
    unawaited(_processWriteQueue());
  }

  Future<void> _processWriteQueue() async {
    try {
      while (_writeQueue.isNotEmpty && !_writerBlocked && !_disposed) {
        final chunk = _writeQueue.first;
        Object? lastFailure;

        for (int attempt = 1; attempt <= maxWriteAttempts; attempt++) {
          try {
            await _database.insertSignalChunk(
              recordingId: chunk.recordingId,
              chunkIndex: chunk.chunkIndex,
              startElapsedUs: chunk.startElapsedUs,
              endElapsedUs: chunk.endElapsedUs,
              sampleCount: chunk.sampleCount,
              signalData: chunk.signalData,
              encodingVersion: encodingVersion,
            );

            lastFailure = null;
            break;
          } catch (error) {
            lastFailure = error;

            if (attempt < maxWriteAttempts) {
              await Future<void>.delayed(Duration(milliseconds: 150 * attempt));
            }
          }
        }

        if (lastFailure != null) {
          _lastError = lastFailure.toString();
          _writerBlocked = true;
          _failWriteDrainWaiters(
            StateError(_lastError ?? 'Recording write failed.'),
          );
          _notify();
          break;
        }

        _writeQueue.removeFirst();
        _persistedSampleCount += chunk.sampleCount;
      }
    } finally {
      _writerRunning = false;

      if (_writeQueue.isEmpty) {
        _completeWriteDrainWaiters();
      } else if (!_writerBlocked && !_disposed) {
        _startWriter();
      }
    }
  }

  Future<void> _waitForWrites() async {
    if (_writeQueue.isEmpty && !_writerRunning) {
      return;
    }

    if (_writerBlocked) {
      throw StateError(_lastError ?? 'Recording write queue is blocked.');
    }

    final completer = Completer<void>();
    _writeDrainWaiters.add(completer);
    await completer.future;

    if (_writerBlocked) {
      throw StateError(_lastError ?? 'Recording write queue is blocked.');
    }
  }

  void _completeWriteDrainWaiters() {
    if (_writeDrainWaiters.isEmpty) {
      return;
    }

    final waiters = List<Completer<void>>.from(_writeDrainWaiters);
    _writeDrainWaiters.clear();

    for (final waiter in waiters) {
      if (!waiter.isCompleted) {
        waiter.complete();
      }
    }
  }

  void _failWriteDrainWaiters(Object error) {
    if (_writeDrainWaiters.isEmpty) {
      return;
    }

    final waiters = List<Completer<void>>.from(_writeDrainWaiters);
    _writeDrainWaiters.clear();

    for (final waiter in waiters) {
      if (!waiter.isCompleted) {
        waiter.completeError(error);
      }
    }
  }

  Uint8List _encodeSamples(List<SensorSample> samples) {
    final data = ByteData(samples.length * bytesPerSample);

    for (int i = 0; i < samples.length; i++) {
      final offset = i * bytesPerSample;
      final sample = samples[i];

      data.setInt32(offset, sample.ecg.round(), Endian.little);

      data.setInt32(offset + 4, sample.respiration.round(), Endian.little);
    }

    return data.buffer.asUint8List();
  }

  int get _samplePeriodUs =>
      (Duration.microsecondsPerSecond / BleProvider.sampleRate).round();

  Future<void> _syncBackgroundServiceState() async {
    final id = _recordingId;
    final name = _recordingName;
    final startedAt = _startedAt;

    if (id == null || name == null || startedAt == null) {
      return;
    }

    await _backgroundService.update(
      recordingName: name,
      startedAtMs: startedAt.millisecondsSinceEpoch,
      paused: _state == RecordingSessionState.paused,
      connected: _bleConnected,
    );
  }

  Future<void> _syncExternalRecordingState() async {
    try {
      await _syncBackgroundServiceState();
    } catch (_) {}

    await _syncLiveActivityState();
  }

  Future<void> _startLiveActivity() async {
    final id = _recordingId;
    final name = _recordingName;
    final startedAt = _startedAt;

    if (id == null || name == null || startedAt == null) {
      return;
    }

    try {
      await _liveActivityService.start(
        recordingId: id,
        recordingName: name,
        startedAt: startedAt,
        isPaused: _state == RecordingSessionState.paused,
        isConnected: _bleConnected,
        statusText: _liveActivityStatusText(),
      );
    } catch (_) {}
  }

  Future<void> _syncLiveActivityState({String? statusOverride}) async {
    final id = _recordingId;

    if (id == null) {
      return;
    }

    try {
      final updated = await _liveActivityService.update(
        recordingId: id,
        isPaused: _state == RecordingSessionState.paused,
        isConnected: _bleConnected,
        statusText: statusOverride ?? _liveActivityStatusText(),
      );

      if (!updated &&
          _state != RecordingSessionState.stopping &&
          _state != RecordingSessionState.idle) {
        await _startLiveActivity();
      }
    } catch (_) {}
  }

  Future<void> _endLiveActivity({
    required int recordingId,
    required String finalStatus,
  }) async {
    try {
      await _liveActivityService.end(
        recordingId: recordingId,
        finalStatus: finalStatus,
      );
    } catch (_) {}
  }

  String _liveActivityStatusText() {
    if (_state == RecordingSessionState.paused) {
      return 'Paused';
    }

    if (!_bleConnected) {
      return 'Signal gap';
    }

    if (_state == RecordingSessionState.stopping) {
      return 'Saving';
    }

    return 'Recording';
  }

  void _onConnectionChanged(bool connected) {
    if (_bleConnected == connected) {
      return;
    }

    _bleConnected = connected;
    _notify();

    if (_recordingId == null) {
      return;
    }

    unawaited(
      _serializeControl(() async {
        if (!connected) {
          await _handleBluetoothDisconnected();
        } else {
          await _handleBluetoothReconnected();
        }

        await _syncExternalRecordingState();
      }).catchError((Object error, StackTrace stackTrace) {
        _lastError = error.toString();
        _notify();
      }),
    );
  }

  Future<void> _handleBluetoothDisconnected() async {
    if (_state != RecordingSessionState.recording) {
      return;
    }

    _flushChunk();
    final position = _safeTimelinePositionUs();
    await _waitForWrites();

    if (_activeGapId == null) {
      await _openGap(RecordingGapReason.bluetoothDisconnected, position);
    }

    _nextSampleElapsedUs = null;
    _notify();
  }

  Future<void> _handleBluetoothReconnected() async {
    if (_state != RecordingSessionState.recording) {
      return;
    }

    if (_activeGapReason != RecordingGapReason.bluetoothDisconnected &&
        _activeGapReason != RecordingGapReason.processRestart) {
      return;
    }

    final position = _clockTimelinePositionUs();
    await _closeActiveGap(position);
    _nextSampleElapsedUs = position;
    _notify();
  }

  Future<void> _openGap(RecordingGapReason reason, int startElapsedUs) async {
    final recordingId = _recordingId;

    if (recordingId == null || _activeGapId != null) {
      return;
    }

    final gapId = await _database.openGap(
      recordingId: recordingId,
      startElapsedUs: startElapsedUs,
      reason: reason.databaseValue,
    );

    _activeGapId = gapId;
    _activeGapReason = reason;
  }

  Future<void> _closeActiveGap(int endElapsedUs) async {
    final gapId = _activeGapId;
    final recordingId = _recordingId;

    if (gapId == null || recordingId == null) {
      return;
    }

    await _database.closeGap(
      gapId: gapId,
      recordingId: recordingId,
      endElapsedUs: endElapsedUs,
    );

    _activeGapId = null;
    _activeGapReason = null;
  }

  int _clockTimelinePositionUs() {
    return _timelineBaseUs + _timelineClock.elapsedMicroseconds;
  }

  int _safeTimelinePositionUs() {
    final clockPosition = _clockTimelinePositionUs();
    final samplePosition = _nextSampleElapsedUs;

    if (samplePosition != null && samplePosition > clockPosition) {
      return samplePosition;
    }

    return clockPosition;
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();

    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      unawaited(_persistHeartbeat());
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> _persistHeartbeat() async {
    final id = _recordingId;

    if (id == null || _state == RecordingSessionState.idle) {
      return;
    }

    try {
      await _database.updateRecordingProgress(
        recordingId: id,
        timelineDurationUs: _safeTimelinePositionUs(),
      );
    } catch (error) {
      _lastError = error.toString();
      _notify();
    }
  }

  Future<void> _serializeControl(Future<void> Function() operation) {
    final completer = Completer<void>();

    _controlChain = _controlChain.then((_) async {
      try {
        await operation();
        if (!completer.isCompleted) {
          completer.complete();
        }
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    });

    return completer.future;
  }

  String _defaultRecordingName(DateTime dateTime) {
    String two(int value) => value.toString().padLeft(2, '0');

    return 'Recording ${dateTime.year}-${two(dateTime.month)}-${two(dateTime.day)} ${two(dateTime.hour)}:${two(dateTime.minute)}:${two(dateTime.second)}';
  }

  void _clearActiveSession() {
    _recordingId = null;
    _recordingName = null;
    _notes = null;
    _startedAt = null;
    _activeGapId = null;
    _activeGapReason = null;
    _chunkIndex = 0;
    _chunkStartElapsedUs = null;
    _nextSampleElapsedUs = null;
    _receivedSampleCount = 0;
    _persistedSampleCount = 0;
    _chunkBuffer.clear();
    _writeQueue.clear();
    _writerBlocked = false;
    _timelineBaseUs = 0;
    _timelineClock
      ..stop()
      ..reset();
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> _persistLifecycleSnapshot() async {
    if (_recordingId == null) {
      return;
    }

    _flushChunk();

    try {
      await _waitForWrites();
      await _persistHeartbeat();
      await _database.checkpoint();
    } catch (error) {
      _lastError = error.toString();
      _notify();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_persistLifecycleSnapshot());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stopHeartbeat();
    _backgroundService.unbindCommands();
    _liveActivityService.unbindCommands();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_sampleSubscription.cancel());
    unawaited(_connectionSubscription.cancel());
    super.dispose();
  }
}
