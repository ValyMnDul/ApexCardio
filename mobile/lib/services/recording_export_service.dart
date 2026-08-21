import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import 'recording_database.dart';

enum RecordingExportFormat {
  apex,
  csv,
}

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

  static const int _pageSize = 250;

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
      throw StateError('Stop the recording before exporting it.');
    }

    final root = Directory(
      p.join(
        (await getTemporaryDirectory()).path,
        'apexcardio_exports',
      ),
    );

    if (!await root.exists()) {
      await root.create(recursive: true);
    }

    final name = _safeFileName(
      recording['name'] as String? ?? 'recording',
    );
    final uid = recording['recording_uid'] as String?;
    final suffix = uid == null || uid.isEmpty
        ? recordingId.toString()
        : _shortUid(uid);

    if (format == RecordingExportFormat.apex) {
      final fileName = '${name}_$suffix.apex';
      final filePath = p.join(root.path, fileName);

      await _exportApex(
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

    final fileName = '${name}_$suffix.csv';
    final filePath = p.join(root.path, fileName);

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

  Future<void> export({
    required int recordingId,
    required RecordingExportFormat format,
    Rect? sharePositionOrigin,
  }) async {
    final result = await exportToTemporaryFile(
      recordingId: recordingId,
      format: format,
    );

    final file = File(result.filePath);

    if (!await file.exists() || await file.length() <= 0) {
      throw StateError('The export file was not created correctly.');
    }

    if (Platform.isAndroid || Platform.isIOS) {
      final shareResult = await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[
            XFile(
              result.filePath,
              mimeType: format == RecordingExportFormat.csv
                  ? 'text/csv'
                  : 'application/x-apexcardio',
            ),
          ],
          fileNameOverrides: <String>[result.fileName],
          title: format == RecordingExportFormat.apex
              ? 'ApexCardio recording'
              : 'ApexCardio CSV',
          subject: result.fileName,
          sharePositionOrigin: sharePositionOrigin,
        ),
      );

      if (shareResult.status == ShareResultStatus.unavailable) {
        throw StateError('The system share sheet is unavailable.');
      }

      return;
    }

    final type = XTypeGroup(
      label: format == RecordingExportFormat.apex
          ? 'ApexCardio recording'
          : 'CSV',
      extensions: <String>[
        format == RecordingExportFormat.apex ? 'apex' : 'csv',
      ],
    );

    final location = await getSaveLocation(
      suggestedName: result.fileName,
      acceptedTypeGroups: <XTypeGroup>[type],
    );

    if (location == null) {
      return;
    }

    final destination = File(location.path);

    if (await destination.exists()) {
      await destination.delete();
    }

    await file.copy(destination.path);
  }

  Future<void> _exportApex({
    required int recordingId,
    required Map<String, Object?> recording,
    required String destinationPath,
  }) async {
    final output = File(destinationPath);

    if (await output.exists()) {
      await output.delete();
    }

    final source = await _database.database;
    Database? destination;

    try {
      destination = await openDatabase(
        destinationPath,
        version: 1,
        singleInstance: false,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await _createApexSchema(db);
        },
      );

      final recordingCopy = Map<String, Object?>.from(recording);
      recordingCopy['id'] = 1;

      await destination.insert(
        'recordings',
        recordingCopy,
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      await destination.insert(
        'apex_manifest',
        <String, Object?>{
          'format': 'ApexCardio Recording',
          'format_version': 1,
          'created_at_ms': DateTime.now().millisecondsSinceEpoch,
        },
      );

      var lastChunkIndex = -1;

      while (true) {
        final rows = await source.query(
          'signal_chunks',
          where: 'recording_id = ? AND chunk_index > ?',
          whereArgs: <Object?>[
            recordingId,
            lastChunkIndex,
          ],
          orderBy: 'chunk_index ASC',
          limit: _pageSize,
        );

        if (rows.isEmpty) {
          break;
        }

        final batch = destination.batch();

        for (final row in rows) {
          final copy = Map<String, Object?>.from(row);
          copy.remove('id');
          copy['recording_id'] = 1;

          batch.insert(
            'signal_chunks',
            copy,
            conflictAlgorithm: ConflictAlgorithm.abort,
          );

          lastChunkIndex =
              (row['chunk_index'] as num?)?.toInt() ?? lastChunkIndex;
        }

        await batch.commit(
          noResult: true,
          continueOnError: false,
        );
      }

      var lastGapId = 0;

      while (true) {
        final rows = await source.query(
          'recording_gaps',
          where: 'recording_id = ? AND id > ?',
          whereArgs: <Object?>[
            recordingId,
            lastGapId,
          ],
          orderBy: 'id ASC',
          limit: _pageSize,
        );

        if (rows.isEmpty) {
          break;
        }

        final batch = destination.batch();

        for (final row in rows) {
          final copy = Map<String, Object?>.from(row);
          copy.remove('id');
          copy['recording_id'] = 1;

          batch.insert(
            'recording_gaps',
            copy,
            conflictAlgorithm: ConflictAlgorithm.abort,
          );

          lastGapId = (row['id'] as num?)?.toInt() ?? lastGapId;
        }

        await batch.commit(
          noResult: true,
          continueOnError: false,
        );
      }

      await destination.execute('PRAGMA user_version = 1');

      final check = await destination.rawQuery('PRAGMA quick_check(1)');

      if (check.isEmpty ||
          check.first.values.first?.toString().toLowerCase() != 'ok') {
        throw StateError('The ApexCardio export failed its integrity check.');
      }

      await destination.close();
      destination = null;

      if (!await output.exists() || await output.length() <= 0) {
        throw StateError('The ApexCardio export file is empty.');
      }
    } catch (_) {
      if (destination != null && destination.isOpen) {
        await destination.close();
      }

      if (await output.exists()) {
        await output.delete();
      }

      rethrow;
    }
  }

  Future<void> _exportCsv({
    required int recordingId,
    required Map<String, Object?> recording,
    required String destinationPath,
  }) async {
    final output = File(destinationPath);

    if (await output.exists()) {
      await output.delete();
    }

    final sampleRate =
        (recording['sample_rate'] as num?)?.toDouble() ?? 250.0;

    if (!sampleRate.isFinite || sampleRate <= 0) {
      throw StateError('Invalid sample rate.');
    }

    final db = await _database.database;
    final sink = output.openWrite(
      mode: FileMode.writeOnly,
      encoding: utf8,
    );
    final samplePeriodUs = 1000000.0 / sampleRate;

    try {
      sink.writeln('elapsed_us,elapsed_s,ecg,respiration');
      var lastChunkIndex = -1;

      while (true) {
        final rows = await db.query(
          'signal_chunks',
          where: 'recording_id = ? AND chunk_index > ?',
          whereArgs: <Object?>[
            recordingId,
            lastChunkIndex,
          ],
          orderBy: 'chunk_index ASC',
          limit: _pageSize,
        );

        if (rows.isEmpty) {
          break;
        }

        for (final row in rows) {
          final sampleCount = row['sample_count'] as int? ?? 0;
          final startUs = row['start_elapsed_us'] as int? ?? 0;
          final raw = row['signal_data'];
          final bytes = switch (raw) {
            Uint8List value => value,
            List<int> value => Uint8List.fromList(value),
            _ => null,
          };

          if (bytes == null ||
              sampleCount <= 0 ||
              bytes.length < sampleCount * 8) {
            throw StateError('Corrupted signal chunk.');
          }

          final data = ByteData.sublistView(bytes);
          final buffer = StringBuffer();

          for (int i = 0; i < sampleCount; i++) {
            final offset = i * 8;
            final elapsedUs = startUs + (i * samplePeriodUs).round();
            buffer
              ..write(elapsedUs)
              ..write(',')
              ..write((elapsedUs / 1000000.0).toStringAsFixed(6))
              ..write(',')
              ..write(data.getInt32(offset, Endian.little))
              ..write(',')
              ..writeln(data.getInt32(offset + 4, Endian.little));
          }

          sink.write(buffer.toString());
          lastChunkIndex =
              (row['chunk_index'] as num?)?.toInt() ?? lastChunkIndex;
        }

        await sink.flush();
      }

      await sink.flush();
      await sink.close();
    } catch (_) {
      await sink.close();

      if (await output.exists()) {
        await output.delete();
      }

      rethrow;
    }
  }

  Future<void> _createApexSchema(Database db) async {
    await db.execute('''
      CREATE TABLE apex_manifest (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        format TEXT NOT NULL,
        format_version INTEGER NOT NULL,
        created_at_ms INTEGER NOT NULL
      )
    ''');

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
        timeline_duration_us INTEGER NOT NULL DEFAULT 0,
        recorded_sample_count INTEGER NOT NULL DEFAULT 0,
        last_committed_elapsed_us INTEGER NOT NULL DEFAULT 0,
        last_heartbeat_at_ms INTEGER NOT NULL,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE signal_chunks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recording_id INTEGER NOT NULL,
        chunk_index INTEGER NOT NULL,
        start_elapsed_us INTEGER NOT NULL,
        end_elapsed_us INTEGER NOT NULL,
        sample_count INTEGER NOT NULL,
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
        start_elapsed_us INTEGER NOT NULL,
        end_elapsed_us INTEGER,
        reason TEXT NOT NULL,
        details TEXT,
        FOREIGN KEY(recording_id)
          REFERENCES recordings(id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_signal_chunks_recording_start
      ON signal_chunks(recording_id, start_elapsed_us)
    ''');

    await db.execute('''
      CREATE INDEX idx_recording_gaps_recording_start
      ON recording_gaps(recording_id, start_elapsed_us)
    ''');
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

    if (cleaned.isEmpty) {
      return 'recording';
    }

    if (cleaned.length <= 10) {
      return cleaned;
    }

    return cleaned.substring(cleaned.length - 10);
  }
}
