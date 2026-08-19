import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

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

  static const int _chunkPageSize = 400;
  static const int _chartTargetPoints = 1400;
  static const int _excerptRows = 120;
  static const int _analysisMaxSamples = 75000;
  static const int _detailChartSeconds = 12;

  Future<RecordingReportResult> generateReportFile({
    required int recordingId,
  }) async {
    final report = await buildReportBytes(recordingId: recordingId);

    final tempDirectory = await getTemporaryDirectory();
    final exportDirectory = Directory(
      p.join(tempDirectory.path, 'apexcardio_reports'),
    );

    if (!await exportDirectory.exists()) {
      await exportDirectory.create(recursive: true);
    }

    final safeName = _safeFileName(report.baseName);

    final fileName = '${safeName}_report.pdf';
    final filePath = p.join(exportDirectory.path, fileName);

    final file = File(filePath);

    if (await file.exists()) {
      await file.delete();
    }

    await file.writeAsBytes(report.bytes, flush: true);

    return RecordingReportResult(
      fileName: fileName,
      filePath: filePath,
      bytes: report.bytes,
    );
  }

  Future<void> shareReport({required int recordingId}) async {
    final result = await generateReportFile(recordingId: recordingId);

    await Printing.sharePdf(bytes: result.bytes, filename: result.fileName);
  }

  Future<void> printReport({required int recordingId}) async {
    final report = await buildReportBytes(recordingId: recordingId);

    await Printing.layoutPdf(
      onLayout: (_) async => report.bytes,
      name: '${report.baseName}_report.pdf',
    );
  }

  Future<_BuiltReport> buildReportBytes({required int recordingId}) async {
    await _database.initialize();

    final recording = await _database.getRecordingById(recordingId);

    if (recording == null) {
      throw StateError('Recording not found.');
    }

    final gaps = await _database.getAllGaps(recordingId);

    final analysis = await _analyzeRecording(
      recordingId: recordingId,
      recording: recording,
      gaps: gaps,
    );

    final document = pw.Document(
      title: 'ApexCardio Report',
      author: 'ApexCardio',
      creator: 'ApexCardio',
      subject: 'ECG and Respiration Recording Report',
    );

    final theme = pw.ThemeData.withFont(
      base: pw.Font.helvetica(),
      bold: pw.Font.helveticaBold(),
      italic: pw.Font.helveticaOblique(),
      boldItalic: pw.Font.helveticaBoldOblique(),
    );

    final accent = PdfColor.fromHex('#0F766E');
    final accentDark = PdfColor.fromHex('#115E59');
    final soft = PdfColor.fromHex('#E6F4F1');
    final line = PdfColor.fromHex('#D5DEDC');
    final textMuted = PdfColor.fromHex('#4B5B5A');
    final danger = PdfColor.fromHex('#B91C1C');

    document.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(28, 28, 28, 28),
        ),
        header: (context) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(bottom: 14),
            padding: const pw.EdgeInsets.only(bottom: 10),
            decoration: pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: line, width: 1)),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  width: 34,
                  height: 34,
                  decoration: pw.BoxDecoration(
                    color: accent,
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  alignment: pw.Alignment.center,
                  child: pw.Text(
                    'A',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontWeight: pw.FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'APEX CARDIO',
                      style: pw.TextStyle(
                        color: accentDark,
                        fontSize: 17,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      'Professional ECG & Respiration Recording Report',
                      style: pw.TextStyle(color: textMuted, fontSize: 9.5),
                    ),
                  ],
                ),
                pw.Spacer(),
                pw.Text(
                  'Generated ${_formatDateTime(DateTime.now())}',
                  style: pw.TextStyle(color: textMuted, fontSize: 9),
                ),
              ],
            ),
          );
        },
        footer: (context) {
          return pw.Container(
            margin: const pw.EdgeInsets.only(top: 12),
            padding: const pw.EdgeInsets.only(top: 8),
            decoration: pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: line, width: 0.8)),
            ),
            child: pw.Row(
              children: [
                pw.Text(
                  'ApexCardio Report',
                  style: pw.TextStyle(fontSize: 9, color: textMuted),
                ),
                pw.Spacer(),
                pw.Text(
                  'Page ${context.pageNumber} / ${context.pagesCount}',
                  style: pw.TextStyle(fontSize: 9, color: textMuted),
                ),
              ],
            ),
          );
        },
        build: (context) {
          return [
            _buildTitleSection(recording, analysis, accent, accentDark, soft),
            pw.SizedBox(height: 18),
            _buildSectionTitle('Acquisition Summary', accentDark),
            pw.SizedBox(height: 8),
            _buildSummaryGrid(
              recording,
              analysis,
              accent,
              soft,
              line,
              textMuted,
            ),
            pw.SizedBox(height: 16),
            _buildSectionTitle('Derived Medical & Signal Metrics', accentDark),
            pw.SizedBox(height: 8),
            _buildMetricsTables(analysis, line, soft, textMuted),
            pw.SizedBox(height: 16),
            _buildSectionTitle('Gap Analysis', accentDark),
            pw.SizedBox(height: 8),
            _buildGapSummary(analysis, line, soft, textMuted, danger),
            pw.SizedBox(height: 16),
            _buildSectionTitle('Waveform Overview', accentDark),
            pw.SizedBox(height: 8),
            if (analysis.ecgOverviewChart != null)
              _buildChartCard(
                title: 'ECG Overview',
                subtitle: 'Whole-recording compressed waveform overview',
                image: analysis.ecgOverviewChart!,
                border: line,
                accent: accent,
              ),
            if (analysis.ecgOverviewChart != null) pw.SizedBox(height: 12),
            if (analysis.respOverviewChart != null)
              _buildChartCard(
                title: 'Respiration Overview',
                subtitle: 'Whole-recording compressed waveform overview',
                image: analysis.respOverviewChart!,
                border: line,
                accent: accent,
              ),
            if (analysis.respOverviewChart != null) pw.SizedBox(height: 12),
            if (analysis.ecgDetailChart != null)
              _buildChartCard(
                title: 'Detailed ECG Segment',
                subtitle:
                    'Detailed waveform excerpt (${_detailChartSeconds}s window)',
                image: analysis.ecgDetailChart!,
                border: line,
                accent: accent,
              ),
            if (analysis.ecgDetailChart != null) pw.SizedBox(height: 12),
            if (analysis.respDetailChart != null)
              _buildChartCard(
                title: 'Detailed Respiration Segment',
                subtitle:
                    'Detailed waveform excerpt (${_detailChartSeconds}s window)',
                image: analysis.respDetailChart!,
                border: line,
                accent: accent,
              ),
            pw.SizedBox(height: 18),
            _buildSectionTitle('Aligned Reading Excerpt', accentDark),
            pw.SizedBox(height: 8),
            _buildAlignedReadingsTable(analysis, line, soft, textMuted),
            pw.SizedBox(height: 16),
            _buildSectionTitle('ECG Reading Extract', accentDark),
            pw.SizedBox(height: 8),
            _buildChannelExcerptTable(
              title: 'ECG samples (raw ADC counts)',
              units: 'raw',
              samples: analysis.firstExcerpt,
              extractor: (sample) => sample.ecg,
              line: line,
              soft: soft,
            ),
            pw.SizedBox(height: 16),
            _buildSectionTitle('Respiration Reading Extract', accentDark),
            pw.SizedBox(height: 8),
            _buildChannelExcerptTable(
              title: 'Respiration samples (raw ADC counts)',
              units: 'raw',
              samples: analysis.firstExcerpt,
              extractor: (sample) => sample.respiration,
              line: line,
              soft: soft,
            ),
            if (analysis.lastExcerpt.isNotEmpty) ...[
              pw.SizedBox(height: 16),
              _buildSectionTitle('Ending Segment Extract', accentDark),
              pw.SizedBox(height: 8),
              _buildTailExcerptTable(analysis, line, soft, textMuted),
            ],
            pw.SizedBox(height: 12),
            _buildDisclaimer(textMuted),
          ];
        },
      ),
    );

    return _BuiltReport(
      baseName: _safeFileName(recording['name'] as String? ?? 'recording'),
      bytes: await document.save(),
    );
  }

  pw.Widget _buildTitleSection(
    Map<String, Object?> recording,
    _ReportAnalysis analysis,
    PdfColor accent,
    PdfColor accentDark,
    PdfColor soft,
  ) {
    final name = recording['name'] as String? ?? 'Recording';
    final startedAtMs = recording['started_at_ms'] as int? ?? 0;
    final status = recording['status'] as String? ?? 'completed';
    final sampleRate = (recording['sample_rate'] as num?)?.toDouble() ?? 250.0;
    final notes = recording['notes'] as String?;
    final deviceName = recording['device_name'] as String?;
    final metadata = recording['metadata_json'] as String?;

    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: soft,
        borderRadius: pw.BorderRadius.circular(14),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            name,
            style: pw.TextStyle(
              color: accentDark,
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _labelValue('Status', _titleCase(status), accent),
              _labelValue(
                'Sample rate',
                '${sampleRate.toStringAsFixed(0)} Hz',
                accent,
              ),
              _labelValue(
                'Started',
                _formatDateTimeFromMs(startedAtMs),
                accent,
              ),
              if (deviceName != null && deviceName.trim().isNotEmpty)
                _labelValue('Device', deviceName, accent),
            ],
          ),
          if (notes != null && notes.trim().isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text(
              'Notes',
              style: pw.TextStyle(
                color: accentDark,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(notes),
          ],
          if (metadata != null && metadata.trim().isNotEmpty) ...[
            pw.SizedBox(height: 10),
            pw.Text(
              'Additional Data',
              style: pw.TextStyle(
                color: accentDark,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(metadata, style: const pw.TextStyle(fontSize: 9)),
          ],
          pw.SizedBox(height: 10),
          pw.Text(
            'This report includes signal-derived estimates, waveform summaries, reading excerpts, acquisition timing, and gap analysis for both ECG and respiration.',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildSectionTitle(String title, PdfColor color) {
    return pw.Text(
      title,
      style: pw.TextStyle(
        color: color,
        fontSize: 14,
        fontWeight: pw.FontWeight.bold,
      ),
    );
  }

  pw.Widget _buildSummaryGrid(
    Map<String, Object?> recording,
    _ReportAnalysis analysis,
    PdfColor accent,
    PdfColor soft,
    PdfColor line,
    PdfColor muted,
  ) {
    final startedAtMs = recording['started_at_ms'] as int? ?? 0;
    final endedAtMs = recording['ended_at_ms'] as int?;
    final status = recording['status'] as String? ?? 'completed';
    final sampleRate = (recording['sample_rate'] as num?)?.toDouble() ?? 250.0;
    final recordedSamples = recording['recorded_sample_count'] as int? ?? 0;

    final summaryItems = <_SummaryItem>[
      _SummaryItem(label: 'Recording ID', value: '${recording['id'] ?? '-'}'),
      _SummaryItem(label: 'Status', value: _titleCase(status)),
      _SummaryItem(
        label: 'Start time',
        value: _formatDateTimeFromMs(startedAtMs),
      ),
      _SummaryItem(
        label: 'End time',
        value: endedAtMs == null ? '-' : _formatDateTimeFromMs(endedAtMs),
      ),
      _SummaryItem(
        label: 'Timeline duration',
        value: _formatDurationUs(analysis.timelineDurationUs),
      ),
      _SummaryItem(
        label: 'Measured duration',
        value: _formatDurationUs(analysis.measuredDurationUs),
      ),
      _SummaryItem(label: 'Recorded samples', value: '$recordedSamples'),
      _SummaryItem(
        label: 'Sample rate',
        value: '${sampleRate.toStringAsFixed(0)} Hz',
      ),
      _SummaryItem(label: 'Total gaps', value: '${analysis.gapCount}'),
      _SummaryItem(
        label: 'Gap duration',
        value: _formatDurationUs(analysis.totalGapDurationUs),
      ),
      _SummaryItem(
        label: 'Estimated HR',
        value: analysis.estimatedHeartRateBpm == null
            ? 'Not enough signal'
            : '${analysis.estimatedHeartRateBpm!.toStringAsFixed(1)} bpm',
      ),
      _SummaryItem(
        label: 'Estimated RR',
        value: analysis.estimatedRespirationRateBpm == null
            ? 'Not enough signal'
            : '${analysis.estimatedRespirationRateBpm!.toStringAsFixed(1)} br/min',
      ),
    ];

    return pw.Wrap(
      spacing: 10,
      runSpacing: 10,
      children: summaryItems
          .map((item) {
            return pw.Container(
              width: 165,
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: pw.BorderRadius.circular(10),
                border: pw.Border.all(color: line, width: 0.8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    item.label,
                    style: pw.TextStyle(color: muted, fontSize: 9),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    item.value,
                    style: pw.TextStyle(
                      color: accent,
                      fontSize: 10.5,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          })
          .toList(growable: false),
    );
  }

  pw.Widget _buildMetricsTables(
    _ReportAnalysis analysis,
    PdfColor line,
    PdfColor soft,
    PdfColor muted,
  ) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _buildMetricTable(
            title: 'ECG Metrics',
            rows: [
              ['Minimum', analysis.ecgStats.min.toStringAsFixed(0)],
              ['Maximum', analysis.ecgStats.max.toStringAsFixed(0)],
              ['Mean', analysis.ecgStats.mean.toStringAsFixed(2)],
              [
                'Standard deviation',
                analysis.ecgStats.stddev.toStringAsFixed(2),
              ],
              ['RMS', analysis.ecgStats.rms.toStringAsFixed(2)],
              ['Amplitude range', analysis.ecgStats.range.toStringAsFixed(0)],
              [
                'Estimated HR',
                analysis.estimatedHeartRateBpm == null
                    ? 'N/A'
                    : '${analysis.estimatedHeartRateBpm!.toStringAsFixed(1)} bpm',
              ],
              [
                'Estimated RR interval',
                analysis.estimatedMeanRrMs == null
                    ? 'N/A'
                    : '${analysis.estimatedMeanRrMs!.toStringAsFixed(0)} ms',
              ],
              ['Detected ECG peaks', '${analysis.detectedEcgPeaks}'],
            ],
            line: line,
            soft: soft,
            muted: muted,
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          child: _buildMetricTable(
            title: 'Respiration Metrics',
            rows: [
              ['Minimum', analysis.respStats.min.toStringAsFixed(0)],
              ['Maximum', analysis.respStats.max.toStringAsFixed(0)],
              ['Mean', analysis.respStats.mean.toStringAsFixed(2)],
              [
                'Standard deviation',
                analysis.respStats.stddev.toStringAsFixed(2),
              ],
              ['RMS', analysis.respStats.rms.toStringAsFixed(2)],
              ['Amplitude range', analysis.respStats.range.toStringAsFixed(0)],
              [
                'Estimated respiration rate',
                analysis.estimatedRespirationRateBpm == null
                    ? 'N/A'
                    : '${analysis.estimatedRespirationRateBpm!.toStringAsFixed(1)} br/min',
              ],
              [
                'Estimated breath interval',
                analysis.estimatedMeanBreathMs == null
                    ? 'N/A'
                    : '${analysis.estimatedMeanBreathMs!.toStringAsFixed(0)} ms',
              ],
              ['Detected respiration peaks', '${analysis.detectedRespPeaks}'],
            ],
            line: line,
            soft: soft,
            muted: muted,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildMetricTable({
    required String title,
    required List<List<String>> rows,
    required PdfColor line,
    required PdfColor soft,
    required PdfColor muted,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: line, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
          ),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: line, width: 0.6),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.6),
              1: pw.FlexColumnWidth(1.1),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: soft),
                children: [
                  _cell('Metric', header: true),
                  _cell('Value', header: true),
                ],
              ),
              ...rows.map(
                (row) => pw.TableRow(
                  children: [
                    _cell(row[0], muted: muted),
                    _cell(row[1]),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildGapSummary(
    _ReportAnalysis analysis,
    PdfColor line,
    PdfColor soft,
    PdfColor muted,
    PdfColor danger,
  ) {
    final summaryRows = <List<String>>[
      ['Total gaps', '${analysis.gapCount}'],
      ['Total gap duration', _formatDurationUs(analysis.totalGapDurationUs)],
      ['Paused gaps', '${analysis.pausedGapCount}'],
      ['Bluetooth gaps', '${analysis.bluetoothGapCount}'],
      ['Other gaps', '${analysis.otherGapCount}'],
    ];

    final detailedRows = analysis.gaps
        .take(30)
        .map((gap) {
          final durationUs =
              (gap.endElapsedUs ?? gap.startElapsedUs) - gap.startElapsedUs;
          return [
            _titleCase(gap.reason.replaceAll('_', ' ')),
            _formatDurationUs(gap.startElapsedUs),
            gap.endElapsedUs == null
                ? 'Open'
                : _formatDurationUs(gap.endElapsedUs!),
            _formatDurationUs(durationUs),
          ];
        })
        .toList(growable: false);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _buildMetricTable(
                title: 'Gap summary',
                rows: summaryRows,
                line: line,
                soft: soft,
                muted: muted,
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  borderRadius: pw.BorderRadius.circular(12),
                  border: pw.Border.all(color: line, width: 0.8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Clinical note',
                      style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      analysis.totalGapDurationUs == 0
                          ? 'No acquisition gaps were detected during this recording.'
                          : 'Acquisition gaps were detected and are preserved in the timeline. Gap durations are excluded from measured signal statistics but remain visible in time-based review.',
                      style: const pw.TextStyle(fontSize: 10),
                    ),
                    if (analysis.totalGapDurationUs > 0) ...[
                      pw.SizedBox(height: 10),
                      pw.Text(
                        'Attention: signal interruptions may affect clinical interpretation of interval and rate estimates.',
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: danger,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        if (detailedRows.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Text(
            'Gap detail',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
          ),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: line, width: 0.6),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.6),
              1: pw.FlexColumnWidth(1.1),
              2: pw.FlexColumnWidth(1.1),
              3: pw.FlexColumnWidth(1.1),
            },
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: soft),
                children: [
                  _cell('Reason', header: true),
                  _cell('Start', header: true),
                  _cell('End', header: true),
                  _cell('Duration', header: true),
                ],
              ),
              ...detailedRows.map(
                (row) => pw.TableRow(
                  children: [
                    _cell(row[0]),
                    _cell(row[1]),
                    _cell(row[2]),
                    _cell(row[3]),
                  ],
                ),
              ),
            ],
          ),
          if (analysis.gaps.length > 30)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text(
                'Only the first 30 gaps are shown in detail.',
                style: pw.TextStyle(fontSize: 8.5, color: muted),
              ),
            ),
        ],
      ],
    );
  }

  pw.Widget _buildChartCard({
    required String title,
    required String subtitle,
    required Uint8List image,
    required PdfColor border,
    required PdfColor accent,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: border, width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              fontSize: 11.5,
              color: accent,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(subtitle, style: const pw.TextStyle(fontSize: 9)),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Image(pw.MemoryImage(image), fit: pw.BoxFit.contain),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildAlignedReadingsTable(
    _ReportAnalysis analysis,
    PdfColor line,
    PdfColor soft,
    PdfColor muted,
  ) {
    final rows = analysis.firstExcerpt
        .take(60)
        .map((sample) {
          return [
            sample.index.toString(),
            sample.elapsedSeconds.toStringAsFixed(3),
            sample.ecg.toString(),
            sample.respiration.toString(),
          ];
        })
        .toList(growable: false);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Aligned multi-channel excerpt from the beginning of the recording',
          style: pw.TextStyle(fontSize: 9.5, color: muted),
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: line, width: 0.6),
          columnWidths: const {
            0: pw.FlexColumnWidth(0.7),
            1: pw.FlexColumnWidth(1),
            2: pw.FlexColumnWidth(1),
            3: pw.FlexColumnWidth(1),
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: soft),
              children: [
                _cell('Index', header: true),
                _cell('Time (s)', header: true),
                _cell('ECG', header: true),
                _cell('Resp', header: true),
              ],
            ),
            ...rows.map(
              (row) => pw.TableRow(
                children: row.map((value) => _cell(value)).toList(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildChannelExcerptTable({
    required String title,
    required String units,
    required List<_ExcerptSample> samples,
    required int Function(_ExcerptSample sample) extractor,
    required PdfColor line,
    required PdfColor soft,
  }) {
    final rows = samples
        .take(_excerptRows)
        .map((sample) {
          return [
            sample.index.toString(),
            sample.elapsedSeconds.toStringAsFixed(3),
            extractor(sample).toString(),
          ];
        })
        .toList(growable: false);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title, style: const pw.TextStyle(fontSize: 9.5)),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: line, width: 0.6),
          columnWidths: const {
            0: pw.FlexColumnWidth(0.8),
            1: pw.FlexColumnWidth(1),
            2: pw.FlexColumnWidth(1.2),
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: soft),
              children: [
                _cell('Index', header: true),
                _cell('Time (s)', header: true),
                _cell('Value ($units)', header: true),
              ],
            ),
            ...rows.map(
              (row) => pw.TableRow(
                children: row.map((value) => _cell(value)).toList(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildTailExcerptTable(
    _ReportAnalysis analysis,
    PdfColor line,
    PdfColor soft,
    PdfColor muted,
  ) {
    final rows = analysis.lastExcerpt
        .take(60)
        .map((sample) {
          return [
            sample.index.toString(),
            sample.elapsedSeconds.toStringAsFixed(3),
            sample.ecg.toString(),
            sample.respiration.toString(),
          ];
        })
        .toList(growable: false);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Ending aligned excerpt',
          style: pw.TextStyle(fontSize: 9.5, color: muted),
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: line, width: 0.6),
          columnWidths: const {
            0: pw.FlexColumnWidth(0.7),
            1: pw.FlexColumnWidth(1),
            2: pw.FlexColumnWidth(1),
            3: pw.FlexColumnWidth(1),
          },
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: soft),
              children: [
                _cell('Index', header: true),
                _cell('Time (s)', header: true),
                _cell('ECG', header: true),
                _cell('Resp', header: true),
              ],
            ),
            ...rows.map(
              (row) => pw.TableRow(
                children: row.map((value) => _cell(value)).toList(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildDisclaimer(PdfColor muted) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F8FAF9'),
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Text(
        'Interpretation note: all numeric waveform values are raw signal counts captured by ApexCardio. Derived heart-rate and respiration-rate values are signal-derived estimates intended to support review. Final clinical interpretation should always be made by a qualified professional and, when necessary, confirmed against validated medical equipment.',
        style: pw.TextStyle(fontSize: 8.8, color: muted),
      ),
    );
  }

  pw.Widget _cell(String value, {bool header = false, PdfColor? muted}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(
        value,
        style: pw.TextStyle(
          fontSize: header ? 9.5 : 8.8,
          fontWeight: header ? pw.FontWeight.bold : null,
          color: muted,
        ),
      ),
    );
  }

  pw.Widget _labelValue(String label, String value, PdfColor accent) {
    return pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$label: ',
            style: const pw.TextStyle(fontSize: 9.5),
          ),
          pw.TextSpan(
            text: value,
            style: pw.TextStyle(
              fontSize: 9.5,
              fontWeight: pw.FontWeight.bold,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }

  Future<_ReportAnalysis> _analyzeRecording({
    required int recordingId,
    required Map<String, Object?> recording,
    required List<Map<String, Object?>> gaps,
  }) async {
    final db = await _database.database;

    final recordedSampleCount = recording['recorded_sample_count'] as int? ?? 0;
    final sampleRate = (recording['sample_rate'] as num?)?.toDouble() ?? 250.0;

    final ecgStats = _RunningStats();
    final respStats = _RunningStats();

    final stride = math.max(
      1,
      recordedSampleCount <= 0
          ? 1
          : (recordedSampleCount / _chartTargetPoints).ceil(),
    );

    final overviewEcg = <_Point>[];
    final overviewResp = <_Point>[];
    final detailEcg = <_Point>[];
    final detailResp = <_Point>[];
    final analysisEcg = <double>[];
    final analysisResp = <double>[];

    final firstExcerpt = <_ExcerptSample>[];
    final lastExcerpt = ListQueue<_ExcerptSample>();

    final detailLimitUs = _detailChartSeconds * Duration.microsecondsPerSecond;
    final samplePeriodUs = Duration.microsecondsPerSecond / sampleRate;

    var globalIndex = 0;
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
        final sampleCount = row['sample_count'] as int? ?? 0;
        final startElapsedUs = row['start_elapsed_us'] as int? ?? 0;
        final chunkIndex = row['chunk_index'] as int? ?? 0;
        final rawBytes = row['signal_data'];

        lastChunkIndex = chunkIndex;

        final bytes = _asUint8List(rawBytes);

        if (bytes == null ||
            sampleCount <= 0 ||
            bytes.length < sampleCount * 8) {
          continue;
        }

        final data = ByteData.sublistView(bytes);

        for (int i = 0; i < sampleCount; i++) {
          final offset = i * 8;
          final ecg = data.getInt32(offset, Endian.little);
          final resp = data.getInt32(offset + 4, Endian.little);

          final elapsedUs = startElapsedUs + (i * samplePeriodUs).round();
          final elapsedSeconds = elapsedUs / Duration.microsecondsPerSecond;

          ecgStats.add(ecg.toDouble());
          respStats.add(resp.toDouble());

          if (globalIndex % stride == 0) {
            overviewEcg.add(_Point(elapsedSeconds, ecg.toDouble()));
            overviewResp.add(_Point(elapsedSeconds, resp.toDouble()));
          }

          if (elapsedUs <= detailLimitUs) {
            detailEcg.add(_Point(elapsedSeconds, ecg.toDouble()));
            detailResp.add(_Point(elapsedSeconds, resp.toDouble()));
          }

          if (analysisEcg.length < _analysisMaxSamples) {
            analysisEcg.add(ecg.toDouble());
            analysisResp.add(resp.toDouble());
          }

          final excerpt = _ExcerptSample(
            index: globalIndex,
            elapsedUs: elapsedUs,
            ecg: ecg,
            respiration: resp,
          );

          if (firstExcerpt.length < _excerptRows) {
            firstExcerpt.add(excerpt);
          }

          if (lastExcerpt.length >= _excerptRows) {
            lastExcerpt.removeFirst();
          }

          lastExcerpt.add(excerpt);

          globalIndex++;
        }
      }
    }

    final gapObjects = gaps
        .map((row) {
          return _GapRecord(
            startElapsedUs: row['start_elapsed_us'] as int? ?? 0,
            endElapsedUs: row['end_elapsed_us'] as int?,
            reason: row['reason'] as String? ?? 'unknown',
          );
        })
        .toList(growable: false);

    final totalGapDurationUs = gapObjects.fold<int>(
      0,
      (sum, gap) =>
          sum +
          math.max(
            0,
            (gap.endElapsedUs ?? gap.startElapsedUs) - gap.startElapsedUs,
          ),
    );

    final timelineDurationUs = recording['timeline_duration_us'] as int? ?? 0;
    final measuredDurationUs = (recordedSampleCount * samplePeriodUs).round();

    final ecgPeakSummary = _estimatePeakRate(
      values: analysisEcg,
      sampleRate: sampleRate,
      minimumDistanceSeconds: 0.28,
      thresholdMultiplier: 0.95,
      smoothingRadius: 2,
    );

    final respPeakSummary = _estimatePeakRate(
      values: analysisResp,
      sampleRate: sampleRate,
      minimumDistanceSeconds: 1.20,
      thresholdMultiplier: 0.30,
      smoothingRadius: 8,
    );

    final ecgOverviewChart = overviewEcg.isEmpty
        ? null
        : await _buildChartImage(
            title: 'ECG Overview',
            points: overviewEcg,
            color: const ui.Color(0xFF0F766E),
            width: 1000,
            height: 220,
          );

    final respOverviewChart = overviewResp.isEmpty
        ? null
        : await _buildChartImage(
            title: 'Respiration Overview',
            points: overviewResp,
            color: const ui.Color(0xFF7C3AED),
            width: 1000,
            height: 220,
          );

    final ecgDetailChart = detailEcg.isEmpty
        ? null
        : await _buildChartImage(
            title: 'Detailed ECG Segment',
            points: detailEcg,
            color: const ui.Color(0xFF0F766E),
            width: 1000,
            height: 220,
          );

    final respDetailChart = detailResp.isEmpty
        ? null
        : await _buildChartImage(
            title: 'Detailed Respiration Segment',
            points: detailResp,
            color: const ui.Color(0xFF7C3AED),
            width: 1000,
            height: 220,
          );

    final pausedGapCount = gapObjects
        .where((gap) => gap.reason == 'paused')
        .length;

    final bluetoothGapCount = gapObjects
        .where((gap) => gap.reason == 'bluetooth_disconnected')
        .length;

    final otherGapCount =
        gapObjects.length - pausedGapCount - bluetoothGapCount;

    return _ReportAnalysis(
      timelineDurationUs: timelineDurationUs,
      measuredDurationUs: measuredDurationUs,
      gapCount: gapObjects.length,
      totalGapDurationUs: totalGapDurationUs,
      pausedGapCount: pausedGapCount,
      bluetoothGapCount: bluetoothGapCount,
      otherGapCount: math.max(0, otherGapCount),
      ecgStats: ecgStats,
      respStats: respStats,
      estimatedHeartRateBpm: ecgPeakSummary.rateBpm,
      estimatedMeanRrMs: ecgPeakSummary.intervalMs,
      detectedEcgPeaks: ecgPeakSummary.peakCount,
      estimatedRespirationRateBpm: respPeakSummary.rateBpm,
      estimatedMeanBreathMs: respPeakSummary.intervalMs,
      detectedRespPeaks: respPeakSummary.peakCount,
      gaps: gapObjects,
      firstExcerpt: firstExcerpt,
      lastExcerpt: lastExcerpt.toList(growable: false),
      ecgOverviewChart: ecgOverviewChart,
      respOverviewChart: respOverviewChart,
      ecgDetailChart: ecgDetailChart,
      respDetailChart: respDetailChart,
    );
  }

  _PeakSummary _estimatePeakRate({
    required List<double> values,
    required double sampleRate,
    required double minimumDistanceSeconds,
    required double thresholdMultiplier,
    required int smoothingRadius,
  }) {
    if (values.length < 6 || sampleRate <= 0) {
      return const _PeakSummary(rateBpm: null, intervalMs: null, peakCount: 0);
    }

    final smoothed = _smooth(values, radius: smoothingRadius);

    final mean = smoothed.reduce((a, b) => a + b) / smoothed.length;

    var variance = 0.0;

    for (final value in smoothed) {
      final diff = value - mean;
      variance += diff * diff;
    }

    variance /= smoothed.length;
    final stddev = math.sqrt(variance);

    if (!stddev.isFinite || stddev <= 0) {
      return const _PeakSummary(rateBpm: null, intervalMs: null, peakCount: 0);
    }

    final threshold = mean + stddev * thresholdMultiplier;
    final minimumDistanceSamples = math.max(
      1,
      (minimumDistanceSeconds * sampleRate).round(),
    );

    final peaks = <int>[];
    var lastPeakIndex = -minimumDistanceSamples;

    for (int i = 1; i < smoothed.length - 1; i++) {
      final current = smoothed[i];

      if (current < threshold) {
        continue;
      }

      if (current < smoothed[i - 1] || current < smoothed[i + 1]) {
        continue;
      }

      if (i - lastPeakIndex < minimumDistanceSamples) {
        if (peaks.isNotEmpty && smoothed[i] > smoothed[peaks.last]) {
          peaks[peaks.length - 1] = i;
          lastPeakIndex = i;
        }

        continue;
      }

      peaks.add(i);
      lastPeakIndex = i;
    }

    if (peaks.length < 2) {
      return _PeakSummary(
        rateBpm: null,
        intervalMs: null,
        peakCount: peaks.length,
      );
    }

    final intervalsSeconds = <double>[];

    for (int i = 1; i < peaks.length; i++) {
      final deltaSamples = peaks[i] - peaks[i - 1];
      if (deltaSamples <= 0) {
        continue;
      }

      intervalsSeconds.add(deltaSamples / sampleRate);
    }

    if (intervalsSeconds.isEmpty) {
      return _PeakSummary(
        rateBpm: null,
        intervalMs: null,
        peakCount: peaks.length,
      );
    }

    final meanIntervalSeconds =
        intervalsSeconds.reduce((a, b) => a + b) / intervalsSeconds.length;

    if (meanIntervalSeconds <= 0) {
      return _PeakSummary(
        rateBpm: null,
        intervalMs: null,
        peakCount: peaks.length,
      );
    }

    final rateBpm = 60.0 / meanIntervalSeconds;

    return _PeakSummary(
      rateBpm: rateBpm.isFinite ? rateBpm : null,
      intervalMs: meanIntervalSeconds * 1000.0,
      peakCount: peaks.length,
    );
  }

  List<double> _smooth(List<double> values, {required int radius}) {
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
      final sum = prefix[end + 1] - prefix[start];
      output[i] = sum / (end - start + 1);
    }

    return output;
  }

  Future<Uint8List> _buildChartImage({
    required String title,
    required List<_Point> points,
    required ui.Color color,
    required int width,
    required int height,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final size = ui.Size(width.toDouble(), height.toDouble());

    final background = ui.Paint()..color = const ui.Color(0xFFFFFFFF);
    canvas.drawRect(ui.Offset.zero & size, background);

    final marginLeft = 56.0;
    final marginRight = 20.0;
    final marginTop = 26.0;
    final marginBottom = 30.0;

    final plotRect = ui.Rect.fromLTWH(
      marginLeft,
      marginTop,
      size.width - marginLeft - marginRight,
      size.height - marginTop - marginBottom,
    );

    final borderPaint = ui.Paint()
      ..color = const ui.Color(0xFFD5DEDC)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(plotRect, borderPaint);

    final gridPaint = ui.Paint()
      ..color = const ui.Color(0xFFE7EFEE)
      ..strokeWidth = 1;

    for (int i = 1; i < 5; i++) {
      final y = plotRect.top + plotRect.height * i / 5;
      canvas.drawLine(
        ui.Offset(plotRect.left, y),
        ui.Offset(plotRect.right, y),
        gridPaint,
      );
    }

    for (int i = 1; i < 8; i++) {
      final x = plotRect.left + plotRect.width * i / 8;
      canvas.drawLine(
        ui.Offset(x, plotRect.top),
        ui.Offset(x, plotRect.bottom),
        gridPaint,
      );
    }

    final textPainter = _SimpleTextPainter();

    textPainter.paint(
      canvas,
      title,
      const ui.Offset(12, 6),
      fontSize: 15,
      color: const ui.Color(0xFF115E59),
      fontWeight: ui.FontWeight.w700,
    );

    if (points.isNotEmpty) {
      final xMin = points.first.x;
      final xMax = points.last.x;
      final yValues = points.map((point) => point.y).toList(growable: false);
      final center = _median(yValues);
      final scale = _robustScale(yValues, center);

      final path = ui.Path();
      bool started = false;

      final step = math.max(1, (points.length / 1800).floor());

      for (int i = 0; i < points.length; i += step) {
        final point = points[i];
        final normalizedX = xMax - xMin <= 0
            ? 0.0
            : (point.x - xMin) / (xMax - xMin);

        final normalizedY = scale <= 0
            ? 0.0
            : ((point.y - center) / scale).clamp(-1.0, 1.0);

        final x = plotRect.left + normalizedX * plotRect.width;
        final y = plotRect.center.dy - normalizedY * plotRect.height * 0.44;

        if (!started) {
          path.moveTo(x, y);
          started = true;
        } else {
          path.lineTo(x, y);
        }
      }

      final signalPaint = ui.Paint()
        ..color = color
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = ui.StrokeCap.round
        ..strokeJoin = ui.StrokeJoin.round
        ..isAntiAlias = true;
      canvas.drawPath(path, signalPaint);

      final baselinePaint = ui.Paint()
        ..color = const ui.Color(0xFF98AAA8)
        ..strokeWidth = 1;
      canvas.drawLine(
        ui.Offset(plotRect.left, plotRect.center.dy),
        ui.Offset(plotRect.right, plotRect.center.dy),
        baselinePaint,
      );

      textPainter.paint(
        canvas,
        '0 s',
        ui.Offset(plotRect.left - 6, plotRect.bottom + 6),
        fontSize: 10,
        color: const ui.Color(0xFF4B5B5A),
      );

      textPainter.paint(
        canvas,
        '${xMax.toStringAsFixed(1)} s',
        ui.Offset(plotRect.right - 40, plotRect.bottom + 6),
        fontSize: 10,
        color: const ui.Color(0xFF4B5B5A),
      );

      textPainter.paint(
        canvas,
        'raw counts',
        ui.Offset(8, plotRect.top + 8),
        fontSize: 10,
        color: const ui.Color(0xFF4B5B5A),
      );
    }

    final image = await recorder.endRecording().toImage(width, height);

    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    if (byteData == null) {
      throw StateError('Could not encode chart image.');
    }

    return byteData.buffer.asUint8List();
  }

  double _median(List<double> values) {
    if (values.isEmpty) {
      return 0;
    }

    final sorted = List<double>.from(values)..sort();
    final middle = sorted.length ~/ 2;

    if (sorted.length.isOdd) {
      return sorted[middle];
    }

    return (sorted[middle - 1] + sorted[middle]) / 2.0;
  }

  double _robustScale(List<double> values, double center) {
    if (values.isEmpty) {
      return 1;
    }

    final deviations = values.map((value) => (value - center).abs()).toList()
      ..sort();

    final index = ((deviations.length - 1) * 0.97).round().clamp(
      0,
      deviations.length - 1,
    );

    final amplitude = deviations[index];

    if (!amplitude.isFinite || amplitude < 1) {
      return 1;
    }

    return amplitude * 1.15;
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

class _BuiltReport {
  final String baseName;
  final Uint8List bytes;

  const _BuiltReport({required this.baseName, required this.bytes});
}

class _ReportAnalysis {
  final int timelineDurationUs;
  final int measuredDurationUs;
  final int gapCount;
  final int totalGapDurationUs;
  final int pausedGapCount;
  final int bluetoothGapCount;
  final int otherGapCount;
  final _RunningStats ecgStats;
  final _RunningStats respStats;
  final double? estimatedHeartRateBpm;
  final double? estimatedMeanRrMs;
  final int detectedEcgPeaks;
  final double? estimatedRespirationRateBpm;
  final double? estimatedMeanBreathMs;
  final int detectedRespPeaks;
  final List<_GapRecord> gaps;
  final List<_ExcerptSample> firstExcerpt;
  final List<_ExcerptSample> lastExcerpt;
  final Uint8List? ecgOverviewChart;
  final Uint8List? respOverviewChart;
  final Uint8List? ecgDetailChart;
  final Uint8List? respDetailChart;

  const _ReportAnalysis({
    required this.timelineDurationUs,
    required this.measuredDurationUs,
    required this.gapCount,
    required this.totalGapDurationUs,
    required this.pausedGapCount,
    required this.bluetoothGapCount,
    required this.otherGapCount,
    required this.ecgStats,
    required this.respStats,
    required this.estimatedHeartRateBpm,
    required this.estimatedMeanRrMs,
    required this.detectedEcgPeaks,
    required this.estimatedRespirationRateBpm,
    required this.estimatedMeanBreathMs,
    required this.detectedRespPeaks,
    required this.gaps,
    required this.firstExcerpt,
    required this.lastExcerpt,
    required this.ecgOverviewChart,
    required this.respOverviewChart,
    required this.ecgDetailChart,
    required this.respDetailChart,
  });
}

class _GapRecord {
  final int startElapsedUs;
  final int? endElapsedUs;
  final String reason;

  const _GapRecord({
    required this.startElapsedUs,
    required this.endElapsedUs,
    required this.reason,
  });
}

class _ExcerptSample {
  final int index;
  final int elapsedUs;
  final int ecg;
  final int respiration;

  const _ExcerptSample({
    required this.index,
    required this.elapsedUs,
    required this.ecg,
    required this.respiration,
  });

  double get elapsedSeconds => elapsedUs / Duration.microsecondsPerSecond;
}

class _RunningStats {
  int _count = 0;
  double _mean = 0;
  double _m2 = 0;
  double _sumSquares = 0;
  double _min = double.infinity;
  double _max = double.negativeInfinity;

  void add(double value) {
    _count++;
    final delta = value - _mean;
    _mean += delta / _count;
    final delta2 = value - _mean;
    _m2 += delta * delta2;
    _sumSquares += value * value;
    if (value < _min) {
      _min = value;
    }
    if (value > _max) {
      _max = value;
    }
  }

  int get count => _count;
  double get min => _count == 0 ? 0 : _min;
  double get max => _count == 0 ? 0 : _max;
  double get mean => _count == 0 ? 0 : _mean;
  double get variance => _count < 2 ? 0 : _m2 / (_count - 1);
  double get stddev => math.sqrt(variance);
  double get rms => _count == 0 ? 0 : math.sqrt(_sumSquares / _count);
  double get range => _count == 0 ? 0 : _max - _min;
}

class _PeakSummary {
  final double? rateBpm;
  final double? intervalMs;
  final int peakCount;

  const _PeakSummary({
    required this.rateBpm,
    required this.intervalMs,
    required this.peakCount,
  });
}

class _Point {
  final double x;
  final double y;

  const _Point(this.x, this.y);
}

class _SummaryItem {
  final String label;
  final String value;

  const _SummaryItem({required this.label, required this.value});
}

class _SimpleTextPainter {
  void paint(
    ui.Canvas canvas,
    String text,
    ui.Offset offset, {
    double fontSize = 12,
    ui.Color color = const ui.Color(0xFF000000),
    ui.FontWeight fontWeight = ui.FontWeight.w400,
  }) {
    final paragraphBuilder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(fontSize: fontSize, fontWeight: fontWeight),
          )
          ..pushStyle(
            ui.TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: fontWeight,
            ),
          )
          ..addText(text);

    final paragraph = paragraphBuilder.build()
      ..layout(const ui.ParagraphConstraints(width: 500));

    canvas.drawParagraph(paragraph, offset);
  }
}

String _formatDurationUs(int microseconds) {
  final duration = Duration(microseconds: microseconds);

  final totalSeconds = duration.inSeconds;
  final days = totalSeconds ~/ 86400;
  final hours = (totalSeconds % 86400) ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  if (days > 0) {
    return '${days}d ${_two(hours)}:${_two(minutes)}:${_two(seconds)}';
  }

  if (hours > 0) {
    return '${_two(hours)}:${_two(minutes)}:${_two(seconds)}';
  }

  return '${_two(minutes)}:${_two(seconds)}';
}

String _formatDateTimeFromMs(int millisecondsSinceEpoch) {
  return _formatDateTime(
    DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch),
  );
}

String _formatDateTime(DateTime date) {
  return '${date.year}-${_two(date.month)}-${_two(date.day)} '
      '${_two(date.hour)}:${_two(date.minute)}:${_two(date.second)}';
}

String _titleCase(String value) {
  if (value.trim().isEmpty) {
    return value;
  }

  return value
      .split(RegExp(r'[\s_]+'))
      .where((part) => part.isNotEmpty)
      .map(
        (part) => '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}

String _two(int value) {
  return value.toString().padLeft(2, '0');
}
