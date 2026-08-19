import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class RecordingDatabase {
  static final RecordingDatabase instance = RecordingDatabase._internal();
  RecordingDatabase._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) {
      return _database!;
    }

    _database = await _openDatabase();

    return _database!;
  }

  Future<Database> _openDatabase() async {
    final databasePath = p.join(
      await getDatabasesPath(),
      "apexcardio_recordings.db",
    );

    return openDatabase(
      databasePath,
      version: 1,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createTables(db);
      },
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE recordings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        notes TEXT,
        started_at_ms INTEGER NOT NULL,
        ended_at_ms INTEGER,
        sample_rate REAL NOT NULL,
        device_name TEXT,
        status TEXT NOT NULL,
        timeline_duration_us INTEGER NOT NULL DEFAULT 0,
        recorded_sample_count INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE signal_chunks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        recording_id INTEGER NOT NULL,
        chunk_index INTEGER NOT NULL,
        start_elapsed_us INTEGER NOT NULL,
        sample_count INTEGER NOT NULL,
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

        FOREIGN KEY(recording_id)
          REFERENCES recordings(id)
          ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_signal_chunks_recording_time
      ON signal_chunks(recording_id, start_elapsed_us)
    ''');

    await db.execute('''
      CREATE INDEX idx_recording_gaps_recording_time
      ON recording_gaps(recording_id, start_elapsed_us)
    ''');
  }

  Future<void> close() async {
    final db = _database;

    if (db == null) {
      return;
    }

    await db.close();

    _database = null;
  }
}
