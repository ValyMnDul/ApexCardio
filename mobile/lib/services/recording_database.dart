import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class RecordingDatabase {
  static const int schemaVersion = 1;

  static final RecordingDatabase instance = RecordingDatabase._internal();

  RecordingDatabase._internal();

  final Random _secureRandom = Random.secure();

  Database? _database;
  Future<Database>? _openingDatabase;

  Future<Database> get database async {
    final existing = _database;

    if (existing != null && existing.isOpen) {
      return existing;
    }

    final opening = _openingDatabase;

    if (opening != null) {
      return opening;
    }

    final future = _openDatabase();
    _openingDatabase = future;

    try {
      final db = await future;
      _database = db;
      return db;
    } finally {
      _openingDatabase = null;
    }
  }

  Future<void> initialize() async {
    await database;
  }

  Future<String> get databasePath async {
    final directory = await getDatabasesPath();
    return p.join(directory, 'apexcardio_recordings.db');
  }

  Future<Database> _openDatabase() async {
    final path = await databasePath;

    return openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createSchema(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _upgradeSchema(db, oldVersion, newVersion);
      },
    );
  }

  Future<void> _createSchema(Database db) async {
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

  Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {}

  String _generateRecordingUid() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    final a = _secureRandom.nextInt(0x7fffffff).toRadixString(16);
    final b = _secureRandom.nextInt(0x7fffffff).toRadixString(16);
    return 'apex_$now$a$b';
  }

  Future<int> createRecording({
    required String name,
    String? notes,
    String? metadataJson,
    required int startedAtMs,
    required double sampleRate,
    String? deviceName,
    String? recordingUid,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    return db.insert('recordings', {
      'recording_uid': recordingUid ?? _generateRecordingUid(),
      'name': name,
      'notes': notes,
      'metadata_json': metadataJson,
      'started_at_ms': startedAtMs,
      'ended_at_ms': null,
      'sample_rate': sampleRate,
      'device_name': deviceName,
      'status': 'recording',
      'timeline_duration_us': 0,
      'recorded_sample_count': 0,
      'last_committed_elapsed_us': 0,
      'last_heartbeat_at_ms': now,
      'created_at_ms': now,
      'updated_at_ms': now,
    }, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  Future<void> insertSignalChunk({
    required int recordingId,
    required int chunkIndex,
    required int startElapsedUs,
    required int endElapsedUs,
    required int sampleCount,
    required List<int> signalData,
    int encodingVersion = 1,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      await txn.insert('signal_chunks', {
        'recording_id': recordingId,
        'chunk_index': chunkIndex,
        'start_elapsed_us': startElapsedUs,
        'end_elapsed_us': endElapsedUs,
        'sample_count': sampleCount,
        'encoding_version': encodingVersion,
        'signal_data': signalData,
      }, conflictAlgorithm: ConflictAlgorithm.abort);

      await txn.rawUpdate(
        '''
        UPDATE recordings
        SET
          recorded_sample_count = recorded_sample_count + ?,
          timeline_duration_us =
            CASE
              WHEN timeline_duration_us < ? THEN ?
              ELSE timeline_duration_us
            END,
          last_committed_elapsed_us =
            CASE
              WHEN last_committed_elapsed_us < ? THEN ?
              ELSE last_committed_elapsed_us
            END,
          last_heartbeat_at_ms = ?,
          updated_at_ms = ?
        WHERE id = ?
        ''',
        [
          sampleCount,
          endElapsedUs,
          endElapsedUs,
          endElapsedUs,
          endElapsedUs,
          now,
          now,
          recordingId,
        ],
      );
    });
  }

  Future<int> openGap({
    required int recordingId,
    required int startElapsedUs,
    required String reason,
    String? details,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    return db.transaction((txn) async {
      final gapId = await txn.insert('recording_gaps', {
        'recording_id': recordingId,
        'start_elapsed_us': startElapsedUs,
        'end_elapsed_us': null,
        'reason': reason,
        'details': details,
      });

      await txn.rawUpdate(
        '''
        UPDATE recordings
        SET
          timeline_duration_us =
            CASE
              WHEN timeline_duration_us < ? THEN ?
              ELSE timeline_duration_us
            END,
          last_heartbeat_at_ms = ?,
          updated_at_ms = ?
        WHERE id = ?
        ''',
        [startElapsedUs, startElapsedUs, now, now, recordingId],
      );

      return gapId;
    });
  }

  Future<void> closeGap({
    required int gapId,
    required int recordingId,
    required int endElapsedUs,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      await txn.update(
        'recording_gaps',
        {'end_elapsed_us': endElapsedUs},
        where: 'id = ? AND recording_id = ?',
        whereArgs: [gapId, recordingId],
      );

      await txn.rawUpdate(
        '''
        UPDATE recordings
        SET
          timeline_duration_us =
            CASE
              WHEN timeline_duration_us < ? THEN ?
              ELSE timeline_duration_us
            END,
          last_heartbeat_at_ms = ?,
          updated_at_ms = ?
        WHERE id = ?
        ''',
        [endElapsedUs, endElapsedUs, now, now, recordingId],
      );
    });
  }

  Future<void> updateRecordingProgress({
    required int recordingId,
    required int timelineDurationUs,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.rawUpdate(
      '''
      UPDATE recordings
      SET
        timeline_duration_us =
          CASE
            WHEN timeline_duration_us < ? THEN ?
            ELSE timeline_duration_us
          END,
        last_heartbeat_at_ms = ?,
        updated_at_ms = ?
      WHERE id = ?
      ''',
      [timelineDurationUs, timelineDurationUs, now, now, recordingId],
    );
  }

  Future<void> setRecordingStatus({
    required int recordingId,
    required String status,
  }) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.update(
      'recordings',
      {'status': status, 'last_heartbeat_at_ms': now, 'updated_at_ms': now},
      where: 'id = ?',
      whereArgs: [recordingId],
    );
  }

  Future<void> finishRecording({
    required int recordingId,
    required int endedAtMs,
    required int timelineDurationUs,
  }) async {
    final db = await database;

    await db.transaction((txn) async {
      await txn.rawUpdate(
        '''
        UPDATE recording_gaps
        SET end_elapsed_us = ?
        WHERE recording_id = ?
          AND end_elapsed_us IS NULL
        ''',
        [timelineDurationUs, recordingId],
      );

      await txn.rawUpdate(
        '''
        UPDATE recordings
        SET
          ended_at_ms = ?,
          status = 'completed',
          timeline_duration_us =
            CASE
              WHEN timeline_duration_us < ? THEN ?
              ELSE timeline_duration_us
            END,
          last_heartbeat_at_ms = ?,
          updated_at_ms = ?
        WHERE id = ?
        ''',
        [
          endedAtMs,
          timelineDurationUs,
          timelineDurationUs,
          endedAtMs,
          endedAtMs,
          recordingId,
        ],
      );
    });
  }

  Future<int> recoverInterruptedRecordings() async {
    final db = await database;

    return db.transaction((txn) async {
      final activeRows = await txn.query(
        'recordings',
        columns: ['id', 'timeline_duration_us', 'last_heartbeat_at_ms'],
        where: "status IN ('recording', 'paused')",
      );

      for (final row in activeRows) {
        final recordingId = row['id'] as int;
        final timelineDurationUs = row['timeline_duration_us'] as int;
        final heartbeatMs = row['last_heartbeat_at_ms'] as int;

        await txn.rawUpdate(
          '''
          UPDATE recording_gaps
          SET end_elapsed_us = ?
          WHERE recording_id = ?
            AND end_elapsed_us IS NULL
          ''',
          [timelineDurationUs, recordingId],
        );

        await txn.update(
          'recordings',
          {
            'ended_at_ms': heartbeatMs,
            'status': 'interrupted',
            'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [recordingId],
        );
      }

      return activeRows.length;
    });
  }

  Future<List<Map<String, Object?>>> getRecordings({
    int? limit,
    int? offset,
  }) async {
    final db = await database;

    return db.query(
      'recordings',
      orderBy: 'started_at_ms DESC, id DESC',
      limit: limit,
      offset: offset,
    );
  }

  Future<Map<String, Object?>?> getRecordingById(int recordingId) async {
    final db = await database;

    final rows = await db.query(
      'recordings',
      where: 'id = ?',
      whereArgs: [recordingId],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first;
  }

  Future<Map<String, Object?>?> getRecordingByUid(String recordingUid) async {
    final db = await database;

    final rows = await db.query(
      'recordings',
      where: 'recording_uid = ?',
      whereArgs: [recordingUid],
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return rows.first;
  }

  Future<List<Map<String, Object?>>> getSignalChunksInRange({
    required int recordingId,
    required int startElapsedUs,
    required int endElapsedUs,
  }) async {
    final db = await database;

    return db.query(
      'signal_chunks',
      where: '''
        recording_id = ?
        AND start_elapsed_us < ?
        AND end_elapsed_us > ?
      ''',
      whereArgs: [recordingId, endElapsedUs, startElapsedUs],
      orderBy: 'chunk_index ASC',
    );
  }

  Future<List<Map<String, Object?>>> getAllSignalChunks(int recordingId) async {
    final db = await database;

    return db.query(
      'signal_chunks',
      where: 'recording_id = ?',
      whereArgs: [recordingId],
      orderBy: 'chunk_index ASC',
    );
  }

  Future<List<Map<String, Object?>>> getGapsInRange({
    required int recordingId,
    required int startElapsedUs,
    required int endElapsedUs,
  }) async {
    final db = await database;

    return db.query(
      'recording_gaps',
      where: '''
        recording_id = ?
        AND start_elapsed_us < ?
        AND COALESCE(end_elapsed_us, ?) > ?
      ''',
      whereArgs: [recordingId, endElapsedUs, endElapsedUs, startElapsedUs],
      orderBy: 'start_elapsed_us ASC',
    );
  }

  Future<List<Map<String, Object?>>> getAllGaps(int recordingId) async {
    final db = await database;

    return db.query(
      'recording_gaps',
      where: 'recording_id = ?',
      whereArgs: [recordingId],
      orderBy: 'start_elapsed_us ASC',
    );
  }

  Future<void> updateRecordingDetails({
    required int recordingId,
    String? name,
    String? notes,
    String? metadataJson,
    bool replaceNotes = false,
    bool replaceMetadata = false,
  }) async {
    final db = await database;
    final values = <String, Object?>{};

    if (name != null) {
      values['name'] = name;
    }

    if (replaceNotes) {
      values['notes'] = notes;
    } else if (notes != null) {
      values['notes'] = notes;
    }

    if (replaceMetadata) {
      values['metadata_json'] = metadataJson;
    } else if (metadataJson != null) {
      values['metadata_json'] = metadataJson;
    }

    if (values.isEmpty) {
      return;
    }

    values['updated_at_ms'] = DateTime.now().millisecondsSinceEpoch;

    await db.update(
      'recordings',
      values,
      where: 'id = ?',
      whereArgs: [recordingId],
    );
  }

  Future<void> deleteRecording(int recordingId) async {
    final db = await database;

    await db.delete('recordings', where: 'id = ?', whereArgs: [recordingId]);
  }

  Future<int> getRecordingCount() async {
    final db = await database;

    final result = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM recordings',
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<int> getChunkCount(int recordingId) async {
    final db = await database;

    final result = await db.rawQuery(
      '''
      SELECT COUNT(*) AS count
      FROM signal_chunks
      WHERE recording_id = ?
      ''',
      [recordingId],
    );

    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> checkpoint() async {
    final db = await database;
    await db.rawQuery('PRAGMA wal_checkpoint(FULL)');
  }

  Future<void> close() async {
    final opening = _openingDatabase;

    if (opening != null) {
      await opening;
    }

    final db = _database;

    if (db == null || !db.isOpen) {
      _database = null;
      return;
    }

    await db.close();
    _database = null;
  }
}
