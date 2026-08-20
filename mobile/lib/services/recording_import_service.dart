import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'recording_database.dart';

class RecordingImportService {
  static final RecordingImportService instance =
      RecordingImportService._internal();

  RecordingImportService._internal();

  final RecordingDatabase _database = RecordingDatabase.instance;

  static const int _defaultSampleRate = 250;
  static const int _chunkSamples = 250;
  static const int _batchChunkCount = 300;

  Future<int?> pickAndImport() async {
    final XTypeGroup typeGroup;

    if (Platform.isIOS) {
      typeGroup = const XTypeGroup(
        label: 'ApexCardio recordings',
        uniformTypeIdentifiers: <String>[
          'public.data',
          'public.comma-separated-values-text',
        ],
      );
    } else {
      typeGroup = const XTypeGroup(
        label: 'ApexCardio recordings',
        extensions: <String>['apex', 'csv', 'db', 'sqlite', 'sqlite3'],
      );
    }

    final file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);

    if (file == null) {
      return null;
    }

    return importFile(file);
  }

  Future<int> importFile(XFile file) async {
    await _database.initialize();

    final extension = p.extension(file.name).toLowerCase();

    if (extension == '.csv') {
      return _importCsv(file);
    }

    if (extension == '.apex' ||
        extension == '.db' ||
        extension == '.sqlite' ||
        extension == '.sqlite3') {
      return _importApexDatabase(file);
    }

    final prefix = await _readPrefix(file, 16);

    if (_isSqliteHeader(prefix)) {
      return _importApexDatabase(file);
    }

    return _importCsv(file);
  }

  Future<int> _importApexDatabase(XFile file) async {
    String? temporaryPath;
    Database? sourceDatabase;
    int? destinationRecordingId;

    try {
      final sourcePath = await _resolveReadableDatabasePath(file);

      if (sourcePath != file.path) {
        temporaryPath = sourcePath;
      }

      sourceDatabase = await openDatabase(
        sourcePath,
        readOnly: true,
        singleInstance: false,
      );

      await _validateApexDatabase(sourceDatabase);

      final sourceRecordings = await sourceDatabase.query(
        'recordings',
        orderBy: 'id ASC',
      );

      if (sourceRecordings.length != 1) {
        throw const FormatException(
          'An .apex file must contain exactly one recording.',
        );
      }

      final sourceRecording = sourceRecordings.first;
      final sourceRecordingId = _readRequiredInt(sourceRecording, 'id');

      final sourceName =
          _readString(sourceRecording['name']) ??
          _baseNameWithoutExtension(file.name);

      final sourceNotes = _readString(sourceRecording['notes']);

      final sourceMetadata = _readString(sourceRecording['metadata_json']);

      final sourceStartedAtMs =
          _readInt(sourceRecording['started_at_ms']) ??
          DateTime.now().millisecondsSinceEpoch;

      final sourceEndedAtMs = _readInt(sourceRecording['ended_at_ms']);

      final sourceSampleRate =
          _readDouble(sourceRecording['sample_rate']) ??
          _defaultSampleRate.toDouble();

      if (!sourceSampleRate.isFinite ||
          sourceSampleRate <= 0 ||
          sourceSampleRate > 10000) {
        throw const FormatException('Invalid sample rate in ApexCardio file.');
      }

      final sourceDeviceName = _readString(sourceRecording['device_name']);

      final sourceUid = _readString(sourceRecording['recording_uid']);

      String? importUid = sourceUid;

      if (importUid != null) {
        final duplicate = await _database.getRecordingByUid(importUid);

        if (duplicate != null) {
          importUid = null;
        }
      }

      destinationRecordingId = await _database.createRecording(
        name: sourceName,
        notes: sourceNotes,
        metadataJson: sourceMetadata,
        startedAtMs: sourceStartedAtMs,
        sampleRate: sourceSampleRate,
        deviceName: sourceDeviceName,
        recordingUid: importUid,
      );

      final destinationDb = await _database.database;

      var copiedSamples = 0;
      var maximumElapsedUs = 0;
      var expectedChunkIndex = 0;
      var offset = 0;

      while (true) {
        final rows = await sourceDatabase.query(
          'signal_chunks',
          where: 'recording_id = ?',
          whereArgs: <Object?>[sourceRecordingId],
          orderBy: 'chunk_index ASC',
          limit: _batchChunkCount,
          offset: offset,
        );

        if (rows.isEmpty) {
          break;
        }

        final batch = destinationDb.batch();

        for (final row in rows) {
          final chunkIndex = _readRequiredInt(row, 'chunk_index');

          final startUs = _readRequiredInt(row, 'start_elapsed_us');

          final sampleCount = _readRequiredInt(row, 'sample_count');

          final encodingVersion = _readInt(row['encoding_version']) ?? 1;

          final rawSignal = row['signal_data'];

          if (chunkIndex != expectedChunkIndex) {
            throw const FormatException(
              'ApexCardio chunk sequence is invalid.',
            );
          }

          if (startUs < 0 || sampleCount <= 0 || encodingVersion != 1) {
            throw const FormatException('Unsupported ApexCardio signal chunk.');
          }

          final signalData = _asUint8List(rawSignal);

          if (signalData == null || signalData.length != sampleCount * 8) {
            throw const FormatException('Corrupted ApexCardio signal data.');
          }

          final calculatedEndUs =
              startUs +
              (sampleCount * Duration.microsecondsPerSecond / sourceSampleRate)
                  .round();

          final storedEndUs = _readInt(row['end_elapsed_us']);

          final endUs = storedEndUs == null
              ? calculatedEndUs
              : math.max(calculatedEndUs, storedEndUs);

          batch.insert('signal_chunks', <String, Object?>{
            'recording_id': destinationRecordingId,
            'chunk_index': chunkIndex,
            'start_elapsed_us': startUs,
            'end_elapsed_us': endUs,
            'sample_count': sampleCount,
            'encoding_version': 1,
            'signal_data': signalData,
          }, conflictAlgorithm: ConflictAlgorithm.abort);

          copiedSamples += sampleCount;
          maximumElapsedUs = math.max(maximumElapsedUs, endUs);

          expectedChunkIndex++;
        }

        await batch.commit(noResult: true, continueOnError: false);

        offset += rows.length;
      }

      final gapRows = await sourceDatabase.query(
        'recording_gaps',
        where: 'recording_id = ?',
        whereArgs: <Object?>[sourceRecordingId],
        orderBy: 'start_elapsed_us ASC',
      );

      if (gapRows.isNotEmpty) {
        final gapBatch = destinationDb.batch();

        for (final row in gapRows) {
          final startUs = _readRequiredInt(row, 'start_elapsed_us');

          final endUs = _readInt(row['end_elapsed_us']);

          final reason = _readString(row['reason']) ?? 'unknown';

          final details = _readString(row['details']);

          if (startUs < 0 || (endUs != null && endUs < startUs)) {
            throw const FormatException('Corrupted ApexCardio gap data.');
          }

          gapBatch.insert('recording_gaps', <String, Object?>{
            'recording_id': destinationRecordingId,
            'start_elapsed_us': startUs,
            'end_elapsed_us': endUs,
            'reason': reason,
            'details': details,
          });

          maximumElapsedUs = math.max(maximumElapsedUs, endUs ?? startUs);
        }

        await gapBatch.commit(noResult: true, continueOnError: false);
      }

      final sourceTimelineUs =
          _readInt(sourceRecording['timeline_duration_us']) ?? 0;

      final finalTimelineUs = math.max(sourceTimelineUs, maximumElapsedUs);

      final sourceStatus =
          _readString(sourceRecording['status']) ?? 'completed';

      final finalStatus = sourceStatus == 'completed'
          ? 'completed'
          : 'interrupted';

      final now = DateTime.now().millisecondsSinceEpoch;
      final finalEndedAtMs =
          sourceEndedAtMs ??
          _readInt(sourceRecording['last_heartbeat_at_ms']) ??
          now;

      await destinationDb.update(
        'recordings',
        <String, Object?>{
          'ended_at_ms': finalEndedAtMs,
          'status': finalStatus,
          'timeline_duration_us': finalTimelineUs,
          'recorded_sample_count': copiedSamples,
          'last_committed_elapsed_us': maximumElapsedUs,
          'last_heartbeat_at_ms': finalEndedAtMs,
          'updated_at_ms': now,
        },
        where: 'id = ?',
        whereArgs: <Object?>[destinationRecordingId],
      );

      await _database.checkpoint();

      return destinationRecordingId;
    } catch (_) {
      if (destinationRecordingId != null) {
        try {
          await _database.deleteRecording(destinationRecordingId);
        } catch (_) {}
      }

      rethrow;
    } finally {
      if (sourceDatabase != null) {
        await sourceDatabase.close();
      }

      if (temporaryPath != null) {
        try {
          await File(temporaryPath).delete();
        } catch (_) {}
      }
    }
  }

  Future<int> _importCsv(XFile file) async {
    int? recordingId;

    try {
      final iterator = StreamIterator<String>(
        utf8.decoder.bind(file.openRead()).transform(const LineSplitter()),
      );

      if (!await iterator.moveNext()) {
        throw const FormatException('CSV file is empty.');
      }

      final firstLine = _stripBom(iterator.current);

      final delimiter = _detectDelimiter(firstLine);

      final firstRow = _parseCsvLine(firstLine, delimiter);

      if (firstRow.isEmpty) {
        throw const FormatException('CSV file has no columns.');
      }

      final columnMap = _detectColumns(firstRow);

      final prefetched = <_CsvInputRow>[];

      if (!columnMap.hasHeader) {
        final parsed = _parseCsvDataRow(firstRow, columnMap);

        if (parsed != null) {
          prefetched.add(parsed);
        }
      }

      while (prefetched.length < 80 && await iterator.moveNext()) {
        final row = _parseCsvLine(iterator.current, delimiter);

        if (_isEmptyRow(row)) {
          continue;
        }

        final parsed = _parseCsvDataRow(row, columnMap);

        if (parsed != null) {
          prefetched.add(parsed);
        }
      }

      if (prefetched.isEmpty) {
        throw const FormatException(
          'CSV does not contain readable signal samples.',
        );
      }

      final timing = _inferCsvTiming(prefetched, columnMap.timeHeader);

      final now = DateTime.now();
      final importStartMs =
          timing.absoluteStartMs ?? now.millisecondsSinceEpoch;

      final metadata = <String, Object?>{
        'imported_from': file.name,
        'format': 'csv',
      };

      if (timing.absoluteStartMs == null) {
        metadata['original_start_time_available'] = false;
      }

      final newRecordingId = await _database.createRecording(
        name: _baseNameWithoutExtension(file.name),
        metadataJson: jsonEncode(metadata),
        startedAtMs: importStartMs,
        sampleRate: timing.sampleRate,
        deviceName: 'Imported CSV',
      );

      recordingId = newRecordingId;

      final destinationDb = await _database.database;

      final writer = _CsvRecordingWriter(
        database: destinationDb,
        recordingId: newRecordingId,
        sampleRate: timing.sampleRate,
      );

      for (final row in prefetched) {
        await writer.add(row, timing);
      }

      while (await iterator.moveNext()) {
        final row = _parseCsvLine(iterator.current, delimiter);

        if (_isEmptyRow(row)) {
          continue;
        }

        final parsed = _parseCsvDataRow(row, columnMap);

        if (parsed == null) {
          continue;
        }

        await writer.add(parsed, timing);
      }

      await iterator.cancel();
      await writer.finish();

      if (writer.sampleCount <= 0) {
        throw const FormatException(
          'CSV does not contain valid signal samples.',
        );
      }

      final finalTimelineUs = writer.timelineDurationUs;
      final endedAtMs = timing.absoluteStartMs == null
          ? now.millisecondsSinceEpoch
          : importStartMs +
                (finalTimelineUs / Duration.microsecondsPerMillisecond).round();

      final updateTime = DateTime.now().millisecondsSinceEpoch;

      await destinationDb.update(
        'recordings',
        <String, Object?>{
          'ended_at_ms': endedAtMs,
          'status': 'completed',
          'timeline_duration_us': finalTimelineUs,
          'recorded_sample_count': writer.sampleCount,
          'last_committed_elapsed_us': writer.lastCommittedElapsedUs,
          'last_heartbeat_at_ms': endedAtMs,
          'updated_at_ms': updateTime,
        },
        where: 'id = ?',
        whereArgs: <Object?>[newRecordingId],
      );

      await _database.checkpoint();

      return newRecordingId;
    } catch (_) {
      if (recordingId != null) {
        try {
          await _database.deleteRecording(recordingId);
        } catch (_) {}
      }

      rethrow;
    }
  }

  Future<void> _validateApexDatabase(Database database) async {
    final tableRows = await database.rawQuery('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
        AND name IN (
          'recordings',
          'signal_chunks',
          'recording_gaps'
        )
      ''');

    final tables = tableRows
        .map((row) => row['name'] as String?)
        .whereType<String>()
        .toSet();

    if (!tables.contains('recordings') ||
        !tables.contains('signal_chunks') ||
        !tables.contains('recording_gaps')) {
      throw const FormatException(
        'This is not a valid ApexCardio recording file.',
      );
    }

    final recordingColumns = await database.rawQuery(
      'PRAGMA table_info(recordings)',
    );

    final chunkColumns = await database.rawQuery(
      'PRAGMA table_info(signal_chunks)',
    );

    final gapColumns = await database.rawQuery(
      'PRAGMA table_info(recording_gaps)',
    );

    final recordingColumnNames = recordingColumns
        .map((row) => row['name'] as String?)
        .whereType<String>()
        .toSet();

    final chunkColumnNames = chunkColumns
        .map((row) => row['name'] as String?)
        .whereType<String>()
        .toSet();

    final gapColumnNames = gapColumns
        .map((row) => row['name'] as String?)
        .whereType<String>()
        .toSet();

    const requiredRecordingColumns = <String>{
      'id',
      'name',
      'started_at_ms',
      'sample_rate',
      'status',
      'timeline_duration_us',
      'recorded_sample_count',
    };

    const requiredChunkColumns = <String>{
      'recording_id',
      'chunk_index',
      'start_elapsed_us',
      'sample_count',
      'signal_data',
    };

    const requiredGapColumns = <String>{
      'recording_id',
      'start_elapsed_us',
      'reason',
    };

    if (!recordingColumnNames.containsAll(requiredRecordingColumns) ||
        !chunkColumnNames.containsAll(requiredChunkColumns) ||
        !gapColumnNames.containsAll(requiredGapColumns)) {
      throw const FormatException('Unsupported ApexCardio database schema.');
    }

    final quickCheck = await database.rawQuery('PRAGMA quick_check(1)');

    if (quickCheck.isEmpty ||
        quickCheck.first.values.first?.toString().toLowerCase() != 'ok') {
      throw const FormatException('The ApexCardio file is corrupted.');
    }
  }

  Future<String> _resolveReadableDatabasePath(XFile file) async {
    final sourcePath = file.path;

    if (sourcePath.isNotEmpty) {
      final source = File(sourcePath);

      if (await source.exists()) {
        return sourcePath;
      }
    }

    final databaseDirectory = await getDatabasesPath();

    final temporaryPath = p.join(
      databaseDirectory,
      'apex_import_${DateTime.now().microsecondsSinceEpoch}.db',
    );

    await file.saveTo(temporaryPath);

    return temporaryPath;
  }

  Future<Uint8List> _readPrefix(XFile file, int byteCount) async {
    final builder = BytesBuilder(copy: false);

    await for (final chunk in file.openRead()) {
      final remaining = byteCount - builder.length;

      if (remaining <= 0) {
        break;
      }

      if (chunk.length <= remaining) {
        builder.add(chunk);
      } else {
        builder.add(chunk.sublist(0, remaining));
      }

      if (builder.length >= byteCount) {
        break;
      }
    }

    return builder.takeBytes();
  }

  bool _isSqliteHeader(Uint8List bytes) {
    const header = <int>[
      0x53,
      0x51,
      0x4C,
      0x69,
      0x74,
      0x65,
      0x20,
      0x66,
      0x6F,
      0x72,
      0x6D,
      0x61,
      0x74,
      0x20,
      0x33,
      0x00,
    ];

    if (bytes.length < header.length) {
      return false;
    }

    for (int i = 0; i < header.length; i++) {
      if (bytes[i] != header[i]) {
        return false;
      }
    }

    return true;
  }

  String _stripBom(String value) {
    if (value.isNotEmpty && value.codeUnitAt(0) == 0xFEFF) {
      return value.substring(1);
    }

    return value;
  }

  String _detectDelimiter(String line) {
    const candidates = <String>[',', ';', '\t'];

    var best = ',';
    var bestCount = -1;

    for (final candidate in candidates) {
      final count = _countDelimiterOutsideQuotes(line, candidate);

      if (count > bestCount) {
        best = candidate;
        bestCount = count;
      }
    }

    return best;
  }

  int _countDelimiterOutsideQuotes(String line, String delimiter) {
    var count = 0;
    var inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final character = line[i];

      if (character == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          i++;
          continue;
        }

        inQuotes = !inQuotes;
        continue;
      }

      if (!inQuotes && character == delimiter) {
        count++;
      }
    }

    return count;
  }

  List<String> _parseCsvLine(String line, String delimiter) {
    final fields = <String>[];
    final field = StringBuffer();
    var inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final character = line[i];

      if (character == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          field.write('"');
          i++;
          continue;
        }

        inQuotes = !inQuotes;
        continue;
      }

      if (!inQuotes && character == delimiter) {
        fields.add(field.toString().trim());
        field.clear();
        continue;
      }

      field.write(character);
    }

    fields.add(field.toString().trim());

    return fields;
  }

  bool _isEmptyRow(List<String> row) {
    if (row.isEmpty) {
      return true;
    }

    for (final value in row) {
      if (value.trim().isNotEmpty) {
        return false;
      }
    }

    return true;
  }

  _CsvColumnMap _detectColumns(List<String> firstRow) {
    final normalized = firstRow.map(_normalizeHeader).toList(growable: false);

    int? find(Set<String> aliases) {
      for (int i = 0; i < normalized.length; i++) {
        if (aliases.contains(normalized[i])) {
          return i;
        }
      }

      return null;
    }

    final ecgIndex = find(const <String>{
      'ecg',
      'ecgraw',
      'ecgsignal',
      'ch1',
      'channel1',
      'lead1',
      'lead',
    });

    final respirationIndex = find(const <String>{
      'respiration',
      'resp',
      'respraw',
      'respiratory',
      'breathing',
      'ch2',
      'channel2',
    });

    final timeIndex = find(const <String>{
      'time',
      'timestamp',
      'elapsed',
      'elapsedtime',
      'elapsedms',
      'elapsedus',
      'times',
      'timems',
      'timeus',
      'timestampms',
      'timestampus',
      'seconds',
      'milliseconds',
      'microseconds',
      't',
    });

    final hasHeader =
        ecgIndex != null ||
        respirationIndex != null ||
        timeIndex != null ||
        firstRow.any(
          (value) => double.tryParse(_normalizeNumber(value)) == null,
        );

    if (hasHeader) {
      final resolvedEcg =
          ecgIndex ??
          _firstSignalColumn(
            firstRow.length,
            excluded: <int?>{timeIndex, respirationIndex},
          );

      if (resolvedEcg == null) {
        throw const FormatException('CSV does not contain an ECG column.');
      }

      return _CsvColumnMap(
        hasHeader: true,
        timeIndex: timeIndex,
        ecgIndex: resolvedEcg,
        respirationIndex: respirationIndex,
        timeHeader: timeIndex == null ? null : normalized[timeIndex],
      );
    }

    if (firstRow.length >= 3) {
      return const _CsvColumnMap(
        hasHeader: false,
        timeIndex: 0,
        ecgIndex: 1,
        respirationIndex: 2,
        timeHeader: null,
      );
    }

    if (firstRow.length == 2) {
      return const _CsvColumnMap(
        hasHeader: false,
        timeIndex: null,
        ecgIndex: 0,
        respirationIndex: 1,
        timeHeader: null,
      );
    }

    return const _CsvColumnMap(
      hasHeader: false,
      timeIndex: null,
      ecgIndex: 0,
      respirationIndex: null,
      timeHeader: null,
    );
  }

  int? _firstSignalColumn(int columnCount, {required Set<int?> excluded}) {
    for (int i = 0; i < columnCount; i++) {
      if (!excluded.contains(i)) {
        return i;
      }
    }

    return null;
  }

  String _normalizeHeader(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  String _normalizeNumber(String value) {
    final trimmed = value.trim();

    if (trimmed.contains(',') && !trimmed.contains('.')) {
      return trimmed.replaceAll(',', '.');
    }

    return trimmed;
  }

  _CsvInputRow? _parseCsvDataRow(List<String> row, _CsvColumnMap columns) {
    if (columns.ecgIndex >= row.length) {
      return null;
    }

    final ecg = double.tryParse(_normalizeNumber(row[columns.ecgIndex]));

    if (ecg == null || !ecg.isFinite) {
      return null;
    }

    double respiration = 0;

    final respirationIndex = columns.respirationIndex;

    if (respirationIndex != null && respirationIndex < row.length) {
      respiration =
          double.tryParse(_normalizeNumber(row[respirationIndex])) ?? 0;
    }

    double? time;

    final timeIndex = columns.timeIndex;

    if (timeIndex != null && timeIndex < row.length) {
      time = double.tryParse(_normalizeNumber(row[timeIndex]));
    }

    return _CsvInputRow(
      rawTime: time,
      ecg: ecg.round(),
      respiration: respiration.round(),
    );
  }

  _CsvTiming _inferCsvTiming(List<_CsvInputRow> rows, String? timeHeader) {
    final rawTimes = rows
        .map((row) => row.rawTime)
        .whereType<double>()
        .where((value) => value.isFinite)
        .toList(growable: false);

    if (rawTimes.length < 2) {
      return const _CsvTiming(
        sampleRate: 250.0,
        timeMultiplierUs: null,
        rawStartTime: null,
        absoluteStartMs: null,
      );
    }

    final positiveDeltas = <double>[];

    for (int i = 1; i < rawTimes.length; i++) {
      final delta = rawTimes[i] - rawTimes[i - 1];

      if (delta > 0 && delta.isFinite) {
        positiveDeltas.add(delta);
      }
    }

    if (positiveDeltas.isEmpty) {
      return const _CsvTiming(
        sampleRate: 250.0,
        timeMultiplierUs: null,
        rawStartTime: null,
        absoluteStartMs: null,
      );
    }

    positiveDeltas.sort();

    final medianDelta = positiveDeltas[positiveDeltas.length ~/ 2];

    final multiplier = _inferTimeMultiplierUs(medianDelta, timeHeader);

    final samplePeriodUs = medianDelta * multiplier;

    var sampleRate = Duration.microsecondsPerSecond / samplePeriodUs;

    if (!sampleRate.isFinite || sampleRate < 1 || sampleRate > 10000) {
      sampleRate = _defaultSampleRate.toDouble();
    }

    final rawStart = rawTimes.first;
    final absoluteStartMs = _inferAbsoluteStartMs(rawStart, multiplier);

    return _CsvTiming(
      sampleRate: sampleRate,
      timeMultiplierUs: multiplier,
      rawStartTime: rawStart,
      absoluteStartMs: absoluteStartMs,
    );
  }

  double _inferTimeMultiplierUs(double medianDelta, String? header) {
    if (header != null) {
      if (header.contains('microsecond') ||
          header.contains('timeus') ||
          header.contains('elapsedus') ||
          header.contains('timestampus')) {
        return 1;
      }

      if (header.contains('millisecond') ||
          header.contains('timems') ||
          header.contains('elapsedms') ||
          header.contains('timestampms')) {
        return 1000;
      }

      if (header == 'seconds' || header == 'times') {
        return 1000000;
      }
    }

    if (medianDelta < 0.5) {
      return 1000000;
    }

    if (medianDelta < 500) {
      return 1000;
    }

    return 1;
  }

  int? _inferAbsoluteStartMs(double rawStart, double multiplierUs) {
    final microseconds = rawStart * multiplierUs;

    final milliseconds = microseconds / Duration.microsecondsPerMillisecond;

    final earliest = DateTime.utc(2000).millisecondsSinceEpoch;

    final latest = DateTime.utc(2200).millisecondsSinceEpoch;

    if (milliseconds >= earliest && milliseconds <= latest) {
      return milliseconds.round();
    }

    return null;
  }

  String _baseNameWithoutExtension(String name) {
    final base = p.basenameWithoutExtension(name).trim();

    if (base.isEmpty) {
      return 'Imported recording';
    }

    return base;
  }

  int _readRequiredInt(Map<String, Object?> row, String key) {
    final value = _readInt(row[key]);

    if (value == null) {
      throw FormatException('Missing integer field: $key');
    }

    return value;
  }

  int? _readInt(Object? value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    if (value is String) {
      return int.tryParse(value);
    }

    return null;
  }

  double? _readDouble(Object? value) {
    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    if (value is String) {
      return double.tryParse(value);
    }

    return null;
  }

  String? _readString(Object? value) {
    if (value == null) {
      return null;
    }

    return value.toString();
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
}

class _CsvRecordingWriter {
  final Database database;
  final int recordingId;
  final double sampleRate;

  final List<_CsvStoredSample> _chunk = <_CsvStoredSample>[];

  final List<_GapToInsert> _pendingGaps = <_GapToInsert>[];

  int _chunkIndex = 0;
  int _sampleCount = 0;
  int _lastCommittedElapsedUs = 0;
  int _timelineDurationUs = 0;

  int? _firstInputTimeUs;
  int? _previousInputTimeUs;
  int? _nextLogicalTimeUs;
  int? _chunkStartUs;

  int _pendingBatchOperations = 0;
  Batch? _batch;

  _CsvRecordingWriter({
    required this.database,
    required this.recordingId,
    required this.sampleRate,
  });

  int get sampleCount => _sampleCount;
  int get lastCommittedElapsedUs => _lastCommittedElapsedUs;
  int get timelineDurationUs => _timelineDurationUs;

  int get _samplePeriodUs =>
      (Duration.microsecondsPerSecond / sampleRate).round();

  Future<void> add(_CsvInputRow row, _CsvTiming timing) async {
    final inputTimeUs = _resolveInputTimeUs(row, timing);

    if (_firstInputTimeUs == null) {
      _firstInputTimeUs = inputTimeUs;
      _previousInputTimeUs = inputTimeUs;
      _nextLogicalTimeUs = 0;
    }

    var relativeTimeUs = inputTimeUs == null
        ? _nextLogicalTimeUs ?? 0
        : inputTimeUs - (_firstInputTimeUs ?? inputTimeUs);

    if (relativeTimeUs < 0) {
      throw const FormatException('CSV timestamps must be monotonic.');
    }

    final previousInput = _previousInputTimeUs;

    if (inputTimeUs != null &&
        previousInput != null &&
        inputTimeUs < previousInput) {
      throw const FormatException('CSV timestamps must be monotonic.');
    }

    final expectedTimeUs = _nextLogicalTimeUs ?? relativeTimeUs;

    final gapThreshold = math.max(_samplePeriodUs * 3, 20000);

    if (_sampleCount > 0 && relativeTimeUs - expectedTimeUs > gapThreshold) {
      await _flushChunk();

      _pendingGaps.add(
        _GapToInsert(
          startUs: expectedTimeUs,
          endUs: relativeTimeUs,
          reason: 'imported_gap',
        ),
      );

      _timelineDurationUs = math.max(_timelineDurationUs, relativeTimeUs);

      _nextLogicalTimeUs = relativeTimeUs;
    } else if (_sampleCount > 0) {
      relativeTimeUs = expectedTimeUs;
    }

    _chunkStartUs ??= _nextLogicalTimeUs ?? relativeTimeUs;

    _chunk.add(_CsvStoredSample(ecg: row.ecg, respiration: row.respiration));

    _sampleCount++;
    _previousInputTimeUs = inputTimeUs ?? _previousInputTimeUs;

    _nextLogicalTimeUs =
        (_nextLogicalTimeUs ?? relativeTimeUs) + _samplePeriodUs;

    _timelineDurationUs = math.max(_timelineDurationUs, _nextLogicalTimeUs!);

    if (_chunk.length >= RecordingImportService._chunkSamples) {
      await _flushChunk();
    }
  }

  int? _resolveInputTimeUs(_CsvInputRow row, _CsvTiming timing) {
    final rawTime = row.rawTime;
    final multiplier = timing.timeMultiplierUs;

    if (rawTime == null || multiplier == null) {
      return null;
    }

    return (rawTime * multiplier).round();
  }

  Future<void> finish() async {
    await _flushChunk();
    await _flushDatabaseBatch();
  }

  Future<void> _flushChunk() async {
    if (_chunk.isEmpty) {
      return;
    }

    final startUs = _chunkStartUs ?? _lastCommittedElapsedUs;

    final signalData = _encodeSamples(_chunk);

    final endUs = startUs + _chunk.length * _samplePeriodUs;

    final batch = _batch ??= database.batch();

    batch.insert('signal_chunks', <String, Object?>{
      'recording_id': recordingId,
      'chunk_index': _chunkIndex,
      'start_elapsed_us': startUs,
      'end_elapsed_us': endUs,
      'sample_count': _chunk.length,
      'encoding_version': 1,
      'signal_data': signalData,
    }, conflictAlgorithm: ConflictAlgorithm.abort);

    _pendingBatchOperations++;
    _chunkIndex++;
    _lastCommittedElapsedUs = math.max(_lastCommittedElapsedUs, endUs);

    _chunk.clear();
    _chunkStartUs = null;

    while (_pendingGaps.isNotEmpty) {
      final gap = _pendingGaps.removeAt(0);

      batch.insert('recording_gaps', <String, Object?>{
        'recording_id': recordingId,
        'start_elapsed_us': gap.startUs,
        'end_elapsed_us': gap.endUs,
        'reason': gap.reason,
        'details': null,
      });

      _pendingBatchOperations++;
    }

    if (_pendingBatchOperations >= RecordingImportService._batchChunkCount) {
      await _flushDatabaseBatch();
    }
  }

  Future<void> _flushDatabaseBatch() async {
    final batch = _batch;

    if (batch == null || _pendingBatchOperations == 0) {
      return;
    }

    await batch.commit(noResult: true, continueOnError: false);

    _batch = null;
    _pendingBatchOperations = 0;
  }

  Uint8List _encodeSamples(List<_CsvStoredSample> samples) {
    final data = ByteData(samples.length * 8);

    for (int i = 0; i < samples.length; i++) {
      final offset = i * 8;
      final sample = samples[i];

      data.setInt32(offset, sample.ecg, Endian.little);

      data.setInt32(offset + 4, sample.respiration, Endian.little);
    }

    return data.buffer.asUint8List();
  }
}

class _CsvColumnMap {
  final bool hasHeader;
  final int? timeIndex;
  final int ecgIndex;
  final int? respirationIndex;
  final String? timeHeader;

  const _CsvColumnMap({
    required this.hasHeader,
    required this.timeIndex,
    required this.ecgIndex,
    required this.respirationIndex,
    required this.timeHeader,
  });
}

class _CsvInputRow {
  final double? rawTime;
  final int ecg;
  final int respiration;

  const _CsvInputRow({
    required this.rawTime,
    required this.ecg,
    required this.respiration,
  });
}

class _CsvTiming {
  final double sampleRate;
  final double? timeMultiplierUs;
  final double? rawStartTime;
  final int? absoluteStartMs;

  const _CsvTiming({
    required this.sampleRate,
    required this.timeMultiplierUs,
    required this.rawStartTime,
    required this.absoluteStartMs,
  });
}

class _CsvStoredSample {
  final int ecg;
  final int respiration;

  const _CsvStoredSample({required this.ecg, required this.respiration});
}

class _GapToInsert {
  final int startUs;
  final int endUs;
  final String reason;

  const _GapToInsert({
    required this.startUs,
    required this.endUs,
    required this.reason,
  });
}
