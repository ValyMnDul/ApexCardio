import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'recording_analysis_service.dart';
import 'recording_database.dart';

class RecordingReportResult {
  final String fileName;
  final String filePath;
  final Uint8List bytes;

  const RecordingReportResult({
    required this.fileName,
    required this.filePath,
    required this.bytes,
  });
}

class RecordingReportService {
  static final RecordingReportService instance =
      RecordingReportService._internal();

  RecordingReportService._internal();

  final RecordingDatabase _database = RecordingDatabase.instance;
  final RecordingAnalysisService _analysis = RecordingAnalysisService.instance;

  Future<RecordingReportResult> generateReportFile({
    required int recordingId,
  }) async {
    final bytes = await buildReportBytes(recordingId: recordingId);

    final recording = await _database.getRecordingById(recordingId);

    if (recording == null) {
      throw StateError('Recording not found.');
    }

    final directory = Directory(
      p.join((await getTemporaryDirectory()).path, 'apexcardio_reports'),
    );

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    final fileName =
        '${_safeFileName(recording['name'] as String? ?? 'recording')}_report.pdf';
    final filePath = p.join(directory.path, fileName);
    final file = File(filePath);

    if (await file.exists()) {
      await file.delete();
    }

    await file.writeAsBytes(bytes, flush: true);

    return RecordingReportResult(
      fileName: fileName,
      filePath: filePath,
      bytes: bytes,
    );
  }

  Future<void> shareReport({
    required int recordingId,
    ui.Rect? sharePositionOrigin,
  }) async {
    final result = await generateReportFile(recordingId: recordingId);

    final shareResult = await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(result.filePath, mimeType: 'application/pdf')],
        fileNameOverrides: <String>[result.fileName],
        title: 'ApexCardio report',
        subject: result.fileName,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );

    if (shareResult.status == ShareResultStatus.unavailable) {
      throw StateError('The system share sheet is unavailable.');
    }
  }

  Future<void> printReport({required int recordingId}) async {
    final bytes = await buildReportBytes(recordingId: recordingId);

    await Printing.layoutPdf(
      name: 'ApexCardio report',
      onLayout: (_) async => bytes,
    );
  }

  Future<Uint8List> buildReportBytes({required int recordingId}) async {
    await _database.initialize();

    final recording = await _database.getRecordingById(recordingId);

    if (recording == null) {
      throw StateError('Recording not found.');
    }

    final summary = await _analysis.analyze(
      recordingId: recordingId,
      recording: recording,
    );
    final gaps = await _database.getAllGaps(recordingId);

    final document = pw.Document(
      title: 'ApexCardio Report',
      author: 'ApexCardio',
      creator: 'ApexCardio',
    );

    final sampleRate = (recording['sample_rate'] as num?)?.toDouble() ?? 250.0;
    final sampleCount = recording['recorded_sample_count'] as int? ?? 0;
    final timelineUs = recording['timeline_duration_us'] as int? ?? 0;
    final measuredUs = sampleRate <= 0
        ? 0
        : (sampleCount / sampleRate * 1000000).round();
    final startedAtMs = recording['started_at_ms'] as int? ?? 0;
    final endedAtMs = recording['ended_at_ms'] as int?;
    final status = recording['status'] as String? ?? 'completed';
    final notes = recording['notes'] as String?;
    final device = recording['device_name'] as String?;

    final teal = PdfColor.fromHex('#0F766E');
    final red = PdfColor.fromHex('#D94848');
    final muted = PdfColor.fromHex('#5F6B6A');
    final line = PdfColor.fromHex('#D8DEDD');

    document.addPage(
      pw.MultiPage(
        maxPages: 6,
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(34, 32, 34, 32),
        ),
        header: (_) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 10),
          decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: line, width: 0.7)),
          ),
          child: pw.Row(
            children: [
              pw.Text(
                'APEX CARDIO',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: teal,
                ),
              ),
              pw.Spacer(),
              pw.Text(
                'Recording report',
                style: pw.TextStyle(fontSize: 9, color: muted),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 8),
          decoration: pw.BoxDecoration(
            border: pw.Border(top: pw.BorderSide(color: line, width: 0.7)),
          ),
          child: pw.Row(
            children: [
              pw.Text(
                'ApexCardio',
                style: pw.TextStyle(fontSize: 8, color: muted),
              ),
              pw.Spacer(),
              pw.Text(
                '${context.pageNumber}/${context.pagesCount}',
                style: pw.TextStyle(fontSize: 8, color: muted),
              ),
            ],
          ),
        ),
        build: (_) => [
          pw.SizedBox(height: 12),
          pw.Text(
            recording['name'] as String? ?? 'Recording',
            style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            '${_formatDateTime(startedAtMs)} · ${_formatDurationUs(timelineUs)} timeline',
            style: pw.TextStyle(fontSize: 10, color: muted),
          ),
          pw.SizedBox(height: 24),
          pw.Row(
            children: [
              pw.Expanded(
                child: _vital(
                  label: 'AVERAGE HEART RATE',
                  value: summary.averageHeartRateBpm == null
                      ? '--'
                      : summary.averageHeartRateBpm!.round().toString(),
                  unit: 'BPM',
                  color: red,
                ),
              ),
              pw.SizedBox(width: 26),
              pw.Expanded(
                child: _vital(
                  label: 'AVERAGE RESPIRATION',
                  value: summary.averageRespirationRateBrpm == null
                      ? '--'
                      : summary.averageRespirationRateBrpm!.round().toString(),
                  unit: 'BRPM',
                  color: teal,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 24),
          _sectionTitle('Recording', teal),
          pw.SizedBox(height: 8),
          _table(
            line: line,
            rows: [
              ['Status', _titleCase(status)],
              ['Started', _formatDateTime(startedAtMs)],
              ['Ended', endedAtMs == null ? '-' : _formatDateTime(endedAtMs)],
              ['Timeline', _formatDurationUs(timelineUs)],
              ['Measured signal', _formatDurationUs(measuredUs)],
              ['Sample rate', '${sampleRate.toStringAsFixed(0)} Hz'],
              ['Recorded samples', _formatNumber(sampleCount)],
              ['Device', device?.trim().isEmpty == false ? device! : '-'],
            ],
          ),
          pw.SizedBox(height: 18),
          _sectionTitle('Signal summary', teal),
          pw.SizedBox(height: 8),
          _table(
            line: line,
            rows: [
              [
                'Average R-R interval',
                summary.averageRrMs == null
                    ? '-'
                    : '${summary.averageRrMs!.toStringAsFixed(0)} ms',
              ],
              [
                'Average breath interval',
                summary.averageBreathIntervalMs == null
                    ? '-'
                    : '${summary.averageBreathIntervalMs!.toStringAsFixed(0)} ms',
              ],
              ['Acquisition gaps', '${summary.gapCount}'],
              ['Gap duration', _formatDurationUs(summary.gapDurationUs)],
              ['Analysis windows', '${summary.analyzedWindows}'],
            ],
          ),
          if (notes != null && notes.trim().isNotEmpty) ...[
            pw.SizedBox(height: 18),
            _sectionTitle('Notes', teal),
            pw.SizedBox(height: 7),
            pw.Text(notes, style: const pw.TextStyle(fontSize: 10.5)),
          ],
          if (gaps.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            _sectionTitle('Gaps', teal),
            pw.SizedBox(height: 8),
            _gapTable(gaps.take(20).toList(), line),
            if (gaps.length > 20)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 6),
                child: pw.Text(
                  '${gaps.length - 20} additional gaps are not shown in this compact report.',
                  style: pw.TextStyle(fontSize: 8.5, color: muted),
                ),
              ),
          ],
          pw.SizedBox(height: 20),
          pw.Container(
            padding: const pw.EdgeInsets.only(top: 10),
            decoration: pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: line, width: 0.7)),
            ),
            child: pw.Text(
              'Heart-rate and respiration-rate values are signal-derived estimates for recording review. ApexCardio does not provide a clinical diagnosis and these values should not replace validated medical equipment or professional interpretation.',
              style: pw.TextStyle(fontSize: 8.5, color: muted),
            ),
          ),
        ],
      ),
    );

    return document.save();
  }

  pw.Widget _vital({
    required String label,
    required String value,
    required String unit,
    required PdfColor color,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 8,
            color: color,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              value,
              style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(width: 5),
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Text(unit, style: const pw.TextStyle(fontSize: 9)),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _sectionTitle(String text, PdfColor color) {
    return pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 13,
        fontWeight: pw.FontWeight.bold,
        color: color,
      ),
    );
  }

  pw.Widget _table({required List<List<String>> rows, required PdfColor line}) {
    return pw.Table(
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: line, width: 0.5),
      ),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.2),
        1: pw.FlexColumnWidth(1.8),
      },
      children: rows
          .map(
            (row) => pw.TableRow(
              children: [_cell(row[0], muted: true), _cell(row[1])],
            ),
          )
          .toList(growable: false),
    );
  }

  pw.Widget _gapTable(List<Map<String, Object?>> gaps, PdfColor line) {
    return pw.Table(
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: line, width: 0.5),
      ),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.4),
        1: pw.FlexColumnWidth(1),
        2: pw.FlexColumnWidth(1),
      },
      children: [
        pw.TableRow(
          children: [
            _cell('Reason', header: true),
            _cell('Start', header: true),
            _cell('Duration', header: true),
          ],
        ),
        ...gaps.map((gap) {
          final start = gap['start_elapsed_us'] as int? ?? 0;
          final end = gap['end_elapsed_us'] as int? ?? start;
          return pw.TableRow(
            children: [
              _cell(
                _titleCase(
                  (gap['reason'] as String? ?? 'unknown').replaceAll('_', ' '),
                ),
              ),
              _cell(_formatDurationUs(start)),
              _cell(_formatDurationUs((end - start).clamp(0, 1 << 62).toInt())),
            ],
          );
        }),
      ],
    );
  }

  pw.Widget _cell(String text, {bool header = false, bool muted = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: header ? 9 : 9.5,
          fontWeight: header ? pw.FontWeight.bold : null,
          color: muted ? PdfColor.fromHex('#5F6B6A') : null,
        ),
      ),
    );
  }

  String _formatDateTime(int ms) {
    final date = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
  }

  String _formatDurationUs(int microseconds) {
    final duration = Duration(microseconds: microseconds);
    final seconds = duration.inSeconds;
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    String two(int value) => value.toString().padLeft(2, '0');

    if (days > 0) {
      return '${days}d ${two(hours)}:${two(minutes)}:${two(secs)}';
    }

    return '${two(hours)}:${two(minutes)}:${two(secs)}';
  }

  String _formatNumber(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(2)}M';
    }
    if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return '$value';
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

  String _titleCase(String value) {
    return value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }
}
