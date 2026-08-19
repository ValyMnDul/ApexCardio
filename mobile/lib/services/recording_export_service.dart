import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import 'recording_database.dart';

enum RecordingExportFormat { apex, csv }

class RecordingExportResult {
  final RecordingExportFormat format;
  final String fileName;
  final String filePath;

  const RecordingExportResult({
    required this.format,
    required this.fileName,
    required this.filePath,
  });
}

class RecordingExportService {
  static final RecordingExportService instance =
      RecordingExportService._internal();

  RecordingExportService._internal();

  final RecordingDatabase _database = RecordingDatabase.instance;

  static const int _chunkPageSize = 400;

  Future<RecordingExportResult> exportToTemporaryFile({
    required int recordingId,
    required RecordingExportFormat format,
  }) async {
    await _database.initialize();

    final recording = await _database.getRecordingById(recordingId);

    if (recording == null) {
      throw StateError('Recording not found.');
    }

    final status = recording['status'] as String? ?? 'completed';

    if (status == 'recording' || status == 'paused') {
      throw StateError('Stop the active recording before exporting it.');
    }

    final tempDirectory = await getTemporaryDirectory();
    final exportDirectory = Directory(
      p.join(tempDirectory.path, 'apexcardio_exports'),
    );

    if (!await exportDirectory.exists()) {
      await exportDirectory.create(recursive: true);
    }

    final name = _safeFileName(recording['name'] as String? ?? 'recording');

    final uid = recording['recording_uid'] as String?;
    final suffix = uid == null || uid.isEmpty
        ? recordingId.toString()
        : _shortUid(uid);

    switch (format) {
      case RecordingExportFormat.apex:
        final fileName = '${name}_$suffix.apex';
        final filePath = p.join(exportDirectory.path, fileName);

        await _exportApexDatabase(
          recordingId: recordingId,
          recording: recording,
          destinationPath: filePath,
        );

        return RecordingExportResult(
          format: format,
          fileName: fileName,
          filePath: filePath,
        );

      case RecordingExportFormat.csv:
        final fileName = '${name}_$suffix.csv';
        final filePath = p.join(exportDirectory.path, fileName);

        await _exportCsv(
          recordingId: recordingId,
          recording: recording,
          destinationPath: filePath,
        );

        return RecordingExportResult(
          format: format,
          fileName: fileName,
          filePath: filePath,
        );
    }
  }

  Future<bool> export({
    required int recordingId,
    required RecordingExportFormat format,
    Rect? sharePositionOrigin,
  }) async {
    final result = await exportToTemporaryFile(
      recordingId: recordingId,
      format: format,
    );

    if (Platform.isAndroid || Platform.isIOS) {
      final shareResult = await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[
            XFile(result.filePath, mimeType: _mimeType(result.format)),
          ],
          fileNameOverrides: <String>[result.fileName],
          title: 'ApexCardio recording',
          subject: result.fileName,
          sharePositionOrigin: sharePositionOrigin,
        ),
      );

      return shareResult.status != ShareResultStatus.unavailable;
    }

    const apexType = XTypeGroup(
      label: 'ApexCardio recording',
      extensions: <String>['apex'],
    );

    const csvType = XTypeGroup(label: 'CSV', extensions: <String>['csv']);

    final location = await getSaveLocation(
      suggestedName: result.fileName,
      acceptedTypeGroups: <XTypeGroup>[
        result.format == RecordingExportFormat.apex ? apexType : csvType,
      ],
    );

    if (location == null) {
      return false;
    }

    final destination = File(location.path);

    if (await destination.exists()) {
      await destination.delete();
    }

    await File(result.filePath).copy(destination.path);

    return true;
  }

  Future<void> _exportApexDatabase({
    required int recordingId,
    required Map<String, Object?> recording,
    required String destinationPath,
  }) async {
    final destinationFile = File(destinationPath);

    if (await destinationFile.exists()) {
      await destinationFile.delete();
    }

    final sourceDb = await _database.database;
    Database? destinationDb;

    try {
      destinationDb = await openDatabase(
        destinationPath,
        version: RecordingDatabase.schemaVersion,
        singleInstance: false,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          await db.execute('PRAGMA journal_mode = DELETE');
        },
        onCreate: (db, version) async {
          await _createExportSchema(db);
        },
      );

      final exportedRecording = Map<String, Object?>.from(recording);

      exportedRecording['id'] = 1;

      await destinationDb.insert(
        'recordings',
        exportedRecording,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      var lastChunkIndex = -1;

      while (true) {
        final rows = await sourceDb.query(
          'signal_chunks',
          where: '''
            recording_id = ?
            AND chunk_index > ?
          ''',
          whereArgs: <Object?>[recordingId, lastChunkIndex],
          orderBy: 'chunk_index ASC',
          limit: _chunkPageSize,
        );

        if (rows.isEmpty) {
          break;
        }

        final batch = destinationDb.batch();

        for (final row in rows) {
          final copy = Map<String, Object?>.from(row);

          copy.remove('id');
          copy['recording_id'] = 1;

          batch.insert(
            'signal_chunks',
            copy,
            conflictAlgorithm: ConflictAlgorithm.abort,
          );

          final chunkIndex = row['chunk_index'];

          if (chunkIndex is int) {
            lastChunkIndex = chunkIndex;
          } else if (chunkIndex is num) {
            lastChunkIndex = chunkIndex.toInt();
          }
        }

        await batch.commit(noResult: true, continueOnError: false);
      }

      var lastGapId = 0;

      while (true) {
        final rows = await sourceDb.query(
          'recording_gaps',
          where: '''
            recording_id = ?
            AND id > ?
          ''',
          whereArgs: <Object?>[recordingId, lastGapId],
          orderBy: 'id ASC',
          limit: _chunkPageSize,
        );

        if (rows.isEmpty) {
          break;
        }

        final batch = destinationDb.batch();

        for (final row in rows) {
          final copy = Map<String, Object?>.from(row);

          copy.remove('id');
          copy['recording_id'] = 1;

          batch.insert(
            'recording_gaps',
            copy,
            conflictAlgorithm: ConflictAlgorithm.abort,
          );

          final gapId = row['id'];

          if (gapId is int) {
            lastGapId = gapId;
          } else if (gapId is num) {
            lastGapId = gapId.toInt();
          }
        }

        await batch.commit(noResult: true, continueOnError: false);
      }

      final check = await destinationDb.rawQuery('PRAGMA quick_check(1)');

      if (check.isEmpty ||
          check.first.values.first?.toString().toLowerCase() != 'ok') {
        throw StateError(
          'Exported ApexCardio database failed integrity check.',
        );
      }

      await destinationDb.close();
      destinationDb = null;

      final wal = File('$destinationPath-wal');
      final shm = File('$destinationPath-shm');

      if (await wal.exists()) {
        await wal.delete();
      }

      if (await shm.exists()) {
        await shm.delete();
      }
    } catch (_) {
      if (destinationDb != null && destinationDb.isOpen) {
        await destinationDb.close();
      }

      if (await destinationFile.exists()) {
        await destinationFile.delete();
      }

      rethrow;
    }
  }

  Future<void> _exportCsv({
    required int recordingId,
    required Map<String, Object?> recording,
    required String destinationPath,
  }) async {
    final file = File(destinationPath);

    if (await file.exists()) {
      await file.delete();
    }

    final sampleRate = (recording['sample_rate'] as num?)?.toDouble() ?? 250.0;

    if (!sampleRate.isFinite || sampleRate <= 0) {
      throw StateError('Recording has an invalid sample rate.');
    }

    final samplePeriodUs = Duration.microsecondsPerSecond / sampleRate;

    final db = await _database.database;
    final sink = file.openWrite(mode: FileMode.writeOnly, encoding: utf8);

    try {
      sink.writeln('elapsed_us,elapsed_s,ecg,respiration');

      var lastChunkIndex = -1;

      while (true) {
        final rows = await db.query(
          'signal_chunks',
          where: '''
            recording_id = ?
            AND chunk_index > ?
          ''',
          whereArgs: <Object?>[recordingId, lastChunkIndex],
          orderBy: 'chunk_index ASC',
          limit: _chunkPageSize,
        );

        if (rows.isEmpty) {
          break;
        }

        for (final row in rows) {
          final encodingVersion = row['encoding_version'] as int? ?? 1;

          if (encodingVersion != 1) {
            throw StateError(
              'Unsupported signal encoding version: $encodingVersion',
            );
          }

          final sampleCount = row['sample_count'] as int? ?? 0;

          final startElapsedUs = row['start_elapsed_us'] as int? ?? 0;

          final bytes = _asUint8List(row['signal_data']);

          if (sampleCount <= 0 ||
              bytes == null ||
              bytes.length != sampleCount * 8) {
            throw StateError('Corrupted signal chunk.');
          }

          final byteData = ByteData.sublistView(bytes);

          final buffer = StringBuffer();

          for (int index = 0; index < sampleCount; index++) {
            final offset = index * 8;

            final ecg = byteData.getInt32(offset, Endian.little);

            final respiration = byteData.getInt32(offset + 4, Endian.little);

            final elapsedUs = startElapsedUs + (index * samplePeriodUs).round();

            final elapsedSeconds = elapsedUs / Duration.microsecondsPerSecond;

            buffer
              ..write(elapsedUs)
              ..write(',')
              ..write(elapsedSeconds.toStringAsFixed(6))
              ..write(',')
              ..write(ecg)
              ..write(',')
              ..writeln(respiration);
          }

          sink.write(buffer.toString());

          final chunkIndex = row['chunk_index'];

          if (chunkIndex is int) {
            lastChunkIndex = chunkIndex;
          } else if (chunkIndex is num) {
            lastChunkIndex = chunkIndex.toInt();
          }
        }

        await sink.flush();
      }

      await sink.flush();
      await sink.close();
    } catch (_) {
      await sink.close();

      if (await file.exists()) {
        await file.delete();
      }

      rethrow;
    }
  }

  Future<void> _createExportSchema(Database db) async {
    await db.execute('''
      CREATE TABLE recordings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recording_uid TEXT NOT NULL UNIQUE,
        name TEXT NOT NULL,
        notes TEXT,
        metadata_json TEXT,
        started_at_ms INTEGER NOT NULL,
        ended_at_ms INTEGER,
        sample_rate REAL NOT NULL CHECK(sample_rate > 0),
        device_name TEXT,
        status TEXT NOT NULL CHECK(
          status IN ('recording', 'paused', 'completed', 'interrupted')
        ),
        timeline_duration_us INTEGER NOT NULL DEFAULT 0 CHECK(
          timeline_duration_us >= 0
        ),
        recorded_sample_count INTEGER NOT NULL DEFAULT 0 CHECK(
          recorded_sample_count >= 0
        ),
        last_committed_elapsed_us INTEGER NOT NULL DEFAULT 0 CHECK(
          last_committed_elapsed_us >= 0
        ),
        last_heartbeat_at_ms INTEGER NOT NULL,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE signal_chunks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recording_id INTEGER NOT NULL,
        chunk_index INTEGER NOT NULL CHECK(chunk_index >= 0),
        start_elapsed_us INTEGER NOT NULL CHECK(start_elapsed_us >= 0),
        end_elapsed_us INTEGER NOT NULL CHECK(end_elapsed_us >= start_elapsed_us),
        sample_count INTEGER NOT NULL CHECK(sample_count > 0),
        encoding_version INTEGER NOT NULL DEFAULT 1,
        signal_data BLOB NOT NULL,
        FOREIGN KEY(recording_id)
          REFERENCES recordings(id)
          ON DELETE CASCADE,
        UNIQUE(recording_id, chunk_index)
      )
    ''');

    await db.execute('''
      CREATE TABLE recording_gaps (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recording_id INTEGER NOT NULL,
        start_elapsed_us INTEGER NOT NULL CHECK(start_elapsed_us >= 0),
        end_elapsed_us INTEGER,
        reason TEXT NOT NULL,
        details TEXT,
        FOREIGN KEY(recording_id)
          REFERENCES recordings(id)
          ON DELETE CASCADE,
        CHECK(
          end_elapsed_us IS NULL OR end_elapsed_us >= start_elapsed_us
        )
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_recordings_started_at
      ON recordings(started_at_ms DESC)
    ''');

    await db.execute('''
      CREATE INDEX idx_recordings_status
      ON recordings(status)
    ''');

    await db.execute('''
      CREATE INDEX idx_signal_chunks_recording_start
      ON signal_chunks(recording_id, start_elapsed_us)
    ''');

    await db.execute('''
      CREATE INDEX idx_signal_chunks_recording_end
      ON signal_chunks(recording_id, end_elapsed_us)
    ''');

    await db.execute('''
      CREATE INDEX idx_recording_gaps_recording_start
      ON recording_gaps(recording_id, start_elapsed_us)
    ''');
  }

  String _mimeType(RecordingExportFormat format) {
    switch (format) {
      case RecordingExportFormat.apex:
        return 'application/vnd.sqlite3';
      case RecordingExportFormat.csv:
        return 'text/csv';
    }
  }

  String _safeFileName(String value) {
    var result = value
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ');

    if (result.isEmpty) {
      result = 'recording';
    }

    if (result.length > 80) {
      result = result.substring(0, 80);
    }

    return result;
  }

  String _shortUid(String uid) {
    final cleaned = uid.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');

    if (cleaned.length <= 10) {
      return cleaned.isEmpty ? 'recording' : cleaned;
    }

    return cleaned.substring(cleaned.length - 10);
  }

  Uint8List? _asUint8List(Object? value) {
    if (value is Uint8List) {
      return value;
    }

    if (value is List<int>) {
      return Uint8List.fromList(value);
    }

    return null;
  }

  Future<void> cleanupTemporaryExports({
    Duration olderThan = const Duration(days: 1),
  }) async {
    final tempDirectory = await getTemporaryDirectory();
    final exportDirectory = Directory(
      p.join(tempDirectory.path, 'apexcardio_exports'),
    );

    if (!await exportDirectory.exists()) {
      return;
    }

    final threshold = DateTime.now().subtract(olderThan);

    await for (final entity in exportDirectory.list()) {
      if (entity is! File) {
        continue;
      }

      try {
        final stat = await entity.stat();

        if (stat.modified.isBefore(threshold)) {
          await entity.delete();
        }
      } catch (_) {}
    }
  }
}
