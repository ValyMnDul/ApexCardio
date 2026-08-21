import 'dart:io';
import 'dart:math' as math;
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

  final RecordingDatabase _database =
      RecordingDatabase.instance;

  final RecordingAnalysisService _analysis =
      RecordingAnalysisService.instance;

  Future<RecordingReportResult>
      generateReportFile({
    required int recordingId,
    String languageCode = 'EN',
  }) async {
    final bytes = await buildReportBytes(
      recordingId: recordingId,
      languageCode: languageCode,
    );

    final recording =
        await _database.getRecordingById(
      recordingId,
    );

    if (recording == null) {
      throw StateError(
        'Recording not found.',
      );
    }

    final directory = Directory(
      p.join(
        (await getTemporaryDirectory())
            .path,
        'apexcardio_reports',
      ),
    );

    if (!await directory.exists()) {
      await directory.create(
        recursive: true,
      );
    }

    final fileName =
        '${_safeFileName(
      recording['name'] as String? ??
          'recording',
    )}_report.pdf';

    final filePath = p.join(
      directory.path,
      fileName,
    );

    final file = File(filePath);

    if (await file.exists()) {
      await file.delete();
    }

    await file.writeAsBytes(
      bytes,
      flush: true,
    );

    return RecordingReportResult(
      fileName: fileName,
      filePath: filePath,
      bytes: bytes,
    );
  }

  Future<void> shareReport({
    required int recordingId,
    String languageCode = 'EN',
    ui.Rect? sharePositionOrigin,
  }) async {
    final result =
        await generateReportFile(
      recordingId: recordingId,
      languageCode: languageCode,
    );

    final shareResult =
        await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[
          XFile(
            result.filePath,
            mimeType:
                'application/pdf',
          ),
        ],
        fileNameOverrides:
            <String>[
          result.fileName,
        ],
        title: 'ApexCardio',
        subject: result.fileName,
        sharePositionOrigin:
            sharePositionOrigin,
      ),
    );

    if (shareResult.status ==
        ShareResultStatus.unavailable) {
      throw StateError(
        'The system share sheet is unavailable.',
      );
    }
  }

  Future<void> printReport({
    required int recordingId,
    String languageCode = 'EN',
  }) async {
    final bytes =
        await buildReportBytes(
      recordingId: recordingId,
      languageCode: languageCode,
    );

    await Printing.layoutPdf(
      name: 'ApexCardio report',
      onLayout: (_) async => bytes,
    );
  }

  Future<Uint8List> buildReportBytes({
    required int recordingId,
    String languageCode = 'EN',
  }) async {
    await _database.initialize();

    final recording =
        await _database.getRecordingById(
      recordingId,
    );

    if (recording == null) {
      throw StateError(
        'Recording not found.',
      );
    }

    final summary =
        await _analysis.analyze(
      recordingId: recordingId,
      recording: recording,
    );

    final sampleRate =
        (recording['sample_rate']
                    as num?)
                ?.toDouble() ??
            250.0;

    final sampleCount =
        recording[
                'recorded_sample_count']
            as int? ??
        0;

    final timelineUs =
        recording[
                'timeline_duration_us']
            as int? ??
        0;

    final measuredUs =
        sampleRate <= 0
            ? 0
            : (sampleCount /
                    sampleRate *
                    1000000)
                .round();

    final startedAtMs =
        recording['started_at_ms']
            as int? ??
        0;

    final endedAtMs =
        recording['ended_at_ms']
            as int?;

    final status =
        recording['status']
            as String? ??
        'completed';

    final notes =
        recording['notes']
            as String?;

    final device =
        recording['device_name']
            as String?;

    final language =
        _ReportLanguage(
      languageCode,
    );

    final ecgExcerpts =
        await _analysis.loadExcerpts(
      recordingId: recordingId,
      timelineUs: timelineUs,
      sampleRate: sampleRate,
      desiredCount: 8,
      windowUs: 20000000,
    );

    final respirationExcerpts =
        await _analysis.loadExcerpts(
      recordingId: recordingId,
      timelineUs: timelineUs,
      sampleRate: sampleRate,
      desiredCount: 6,
      windowUs: 20000000,
    );

    final ecgStats =
        _analysis.calculateStats(
      ecgExcerpts.expand(
        (excerpt) => excerpt.ecg,
      ),
    );

    final respirationStats =
        _analysis.calculateStats(
      respirationExcerpts.expand(
        (excerpt) =>
            excerpt.respiration,
      ),
    );

    final document = pw.Document(
      title: 'ApexCardio Report',
      author: 'ApexCardio',
      creator: 'ApexCardio',
      compress: true,
    );

    final teal =
        PdfColor.fromHex(
      '#0F766E',
    );

    final red =
        PdfColor.fromHex(
      '#D94848',
    );

    final muted =
        PdfColor.fromHex(
      '#5F6B6A',
    );

    final line =
        PdfColor.fromHex(
      '#D8DEDD',
    );

    final recordingName =
        recording['name'] as String? ??
        language.text(
          'recording',
        );

    document.addPage(
      pw.Page(
        pageFormat:
            PdfPageFormat.a4,
        margin:
            const pw.EdgeInsets.fromLTRB(
          32,
          28,
          32,
          28,
        ),
        build: (_) {
          return pw.Column(
            crossAxisAlignment:
                pw.CrossAxisAlignment
                    .stretch,
            children: [
              _pageHeader(
                title: 'APEX CARDIO',
                trailing:
                    language.text(
                  'report',
                ),
                teal: teal,
                muted: muted,
                line: line,
              ),
              pw.SizedBox(
                height: 14,
              ),
              pw.Text(
                recordingName,
                maxLines: 2,
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight:
                      pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(
                height: 5,
              ),
              pw.Text(
                '${_formatDateTime(
                  startedAtMs,
                )}  ·  '
                '${_formatDurationUs(
                  timelineUs,
                )}',
                style: pw.TextStyle(
                  fontSize: 9.5,
                  color: muted,
                ),
              ),
              pw.SizedBox(
                height: 18,
              ),
              pw.Row(
                children: [
                  pw.Expanded(
                    child: _vital(
                      value: summary
                                  .averageHeartRateBpm ==
                              null
                          ? '--'
                          : summary
                              .averageHeartRateBpm!
                              .round()
                              .toString(),
                      unit: 'BPM',
                      label:
                          language.text(
                        'average',
                      ),
                      color: red,
                    ),
                  ),
                  pw.SizedBox(
                    width: 22,
                  ),
                  pw.Expanded(
                    child: _vital(
                      value: summary
                                  .averageRespirationRateBrpm ==
                              null
                          ? '--'
                          : summary
                              .averageRespirationRateBrpm!
                              .round()
                              .toString(),
                      unit: 'BRPM',
                      label:
                          language.text(
                        'average',
                      ),
                      color: teal,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(
                height: 18,
              ),
              pw.Text(
                language.text(
                  'recording',
                ),
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight:
                      pw.FontWeight.bold,
                  color: teal,
                ),
              ),
              pw.SizedBox(
                height: 6,
              ),
              _compactTable(
                line: line,
                muted: muted,
                rows: [
                  [
                    language.text(
                      'status',
                    ),
                    _status(
                      language,
                      status,
                    ),
                  ],
                  [
                    language.text(
                      'started',
                    ),
                    _formatDateTime(
                      startedAtMs,
                    ),
                  ],
                  [
                    language.text(
                      'ended',
                    ),
                    endedAtMs == null
                        ? '--'
                        : _formatDateTime(
                            endedAtMs,
                          ),
                  ],
                  [
                    language.text(
                      'timeline',
                    ),
                    _formatDurationUs(
                      timelineUs,
                    ),
                  ],
                  [
                    language.text(
                      'measured',
                    ),
                    _formatDurationUs(
                      measuredUs,
                    ),
                  ],
                  [
                    language.text(
                      'sample_rate',
                    ),
                    '${sampleRate.toStringAsFixed(0)} Hz',
                  ],
                  [
                    language.text(
                      'samples',
                    ),
                    _formatNumber(
                      sampleCount,
                    ),
                  ],
                  [
                    language.text(
                      'device',
                    ),
                    device == null ||
                            device
                                .trim()
                                .isEmpty
                        ? '--'
                        : device,
                  ],
                ],
              ),
              pw.SizedBox(
                height: 16,
              ),
              pw.Text(
                language.text(
                  'signal',
                ),
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight:
                      pw.FontWeight.bold,
                  color: teal,
                ),
              ),
              pw.SizedBox(
                height: 6,
              ),
              _compactTable(
                line: line,
                muted: muted,
                rows: [
                  [
                    language.text(
                      'rr',
                    ),
                    summary.averageRrMs ==
                            null
                        ? '--'
                        : '${summary.averageRrMs!.toStringAsFixed(0)} ms',
                  ],
                  [
                    language.text(
                      'breath',
                    ),
                    summary.averageBreathIntervalMs ==
                            null
                        ? '--'
                        : '${summary.averageBreathIntervalMs!.toStringAsFixed(0)} ms',
                  ],
                  [
                    language.text(
                      'gaps',
                    ),
                    '${summary.gapCount}',
                  ],
                  [
                    language.text(
                      'gap_duration',
                    ),
                    _formatDurationUs(
                      summary
                          .gapDurationUs,
                    ),
                  ],
                  [
                    language.text(
                      'analysis_windows',
                    ),
                    '${summary.analyzedWindows}',
                  ],
                ],
              ),
              if (notes != null &&
                  notes.trim().isNotEmpty) ...[
                pw.SizedBox(
                  height: 14,
                ),
                pw.Text(
                  language.text(
                    'notes',
                  ),
                  style:
                      pw.TextStyle(
                    fontSize: 11,
                    fontWeight:
                        pw.FontWeight
                            .bold,
                    color: teal,
                  ),
                ),
                pw.SizedBox(
                  height: 4,
                ),
                pw.Text(
                  _truncate(
                    notes,
                    420,
                  ),
                  style:
                      const pw.TextStyle(
                    fontSize: 9,
                  ),
                ),
              ],
              pw.Spacer(),
              _footer(
                language:
                    language,
                muted: muted,
                line: line,
              ),
            ],
          );
        },
      ),
    );

    document.addPage(
      _detailedSignalPage(
        pageTitle:
            language.text(
          'ecg_details',
        ),
        recordingName:
            recordingName,
        startedAtMs:
            startedAtMs,
        excerpts:
            ecgExcerpts,
        channel:
            _ReportChannel.ecg,
        color: red,
        graphColor: '#D94848',
        teal: teal,
        muted: muted,
        line: line,
        language:
            language,
        summaryRows: [
          [
            language.text(
              'heart_rate',
            ),
            summary.averageHeartRateBpm ==
                    null
                ? '--'
                : '${summary.averageHeartRateBpm!.toStringAsFixed(1)} BPM',
          ],
          [
            language.text(
              'rr',
            ),
            summary.averageRrMs ==
                    null
                ? '--'
                : '${summary.averageRrMs!.toStringAsFixed(0)} ms',
          ],
          [
            language.text(
              'sample_rate',
            ),
            '${sampleRate.toStringAsFixed(0)} Hz',
          ],
          [
            language.text(
              'signal_range',
            ),
            _formatSignalNumber(
              ecgStats.range,
            ),
          ],
          [
            language.text(
              'signal_mean',
            ),
            _formatSignalNumber(
              ecgStats.mean,
            ),
          ],
          [
            language.text(
              'signal_rms',
            ),
            _formatSignalNumber(
              ecgStats.rms,
            ),
          ],
        ],
      ),
    );

    document.addPage(
      _detailedSignalPage(
        pageTitle:
            language.text(
          'respiration_details',
        ),
        recordingName:
            recordingName,
        startedAtMs:
            startedAtMs,
        excerpts:
            respirationExcerpts,
        channel:
            _ReportChannel.respiration,
        color: teal,
        graphColor: '#0F766E',
        teal: teal,
        muted: muted,
        line: line,
        language:
            language,
        summaryRows: [
          [
            language.text(
              'respiration_rate',
            ),
            summary.averageRespirationRateBrpm ==
                    null
                ? '--'
                : '${summary.averageRespirationRateBrpm!.toStringAsFixed(1)} BRPM',
          ],
          [
            language.text(
              'breath',
            ),
            summary.averageBreathIntervalMs ==
                    null
                ? '--'
                : '${summary.averageBreathIntervalMs!.toStringAsFixed(0)} ms',
          ],
          [
            language.text(
              'sample_rate',
            ),
            '${sampleRate.toStringAsFixed(0)} Hz',
          ],
          [
            language.text(
              'signal_range',
            ),
            _formatSignalNumber(
              respirationStats.range,
            ),
          ],
          [
            language.text(
              'signal_mean',
            ),
            _formatSignalNumber(
              respirationStats.mean,
            ),
          ],
          [
            language.text(
              'signal_rms',
            ),
            _formatSignalNumber(
              respirationStats.rms,
            ),
          ],
        ],
      ),
    );

    return document.save();
  }

  pw.Page _detailedSignalPage({
    required String pageTitle,
    required String recordingName,
    required int startedAtMs,
    required List<RecordingSignalExcerpt>
        excerpts,
    required _ReportChannel channel,
    required PdfColor color,
    required String graphColor,
    required PdfColor teal,
    required PdfColor muted,
    required PdfColor line,
    required _ReportLanguage language,
    required List<List<String>>
        summaryRows,
  }) {
    return pw.Page(
      pageFormat:
          PdfPageFormat.a4,
      margin:
          const pw.EdgeInsets.fromLTRB(
        28,
        24,
        28,
        24,
      ),
      build: (_) {
        final widgets =
            <pw.Widget>[
          _pageHeader(
            title: pageTitle,
            trailing: recordingName,
            teal: teal,
            muted: muted,
            line: line,
          ),
          pw.SizedBox(
            height: 10,
          ),
          _compactTable(
            line: line,
            muted: muted,
            rows: summaryRows,
          ),
          pw.SizedBox(
            height: 10,
          ),
        ];

        if (excerpts.isEmpty) {
          widgets.add(
            pw.Padding(
              padding:
                  const pw.EdgeInsets
                      .symmetric(
                vertical: 24,
              ),
              child: pw.Text(
                language.text(
                  'no_signal',
                ),
                style: pw.TextStyle(
                  fontSize: 10,
                  color: muted,
                ),
              ),
            ),
          );
        } else {
          for (int index = 0;
              index < excerpts.length;
              index++) {
            final excerpt =
                excerpts[index];

            final values = channel ==
                    _ReportChannel.ecg
                ? excerpt.ecg
                : excerpt.respiration;

            widgets.add(
              _signalStrip(
                index: index,
                excerpt: excerpt,
                values: values,
                startedAtMs:
                    startedAtMs,
                color: color,
                graphColor: graphColor,
                muted: muted,
                line: line,
                language: language,
              ),
            );

            if (index !=
                excerpts.length - 1) {
              widgets.add(
                pw.SizedBox(
                  height: 5,
                ),
              );
            }
          }
        }

        widgets.add(
          pw.Spacer(),
        );

        widgets.add(
          _footer(
            language:
                language,
            muted: muted,
            line: line,
          ),
        );

        return pw.Column(
          crossAxisAlignment:
              pw.CrossAxisAlignment
                  .stretch,
          children: widgets,
        );
      },
    );
  }

  pw.Widget _signalStrip({
    required int index,
    required RecordingSignalExcerpt
        excerpt,
    required List<double> values,
    required int startedAtMs,
    required PdfColor color,
    required String graphColor,
    required PdfColor muted,
    required PdfColor line,
    required _ReportLanguage language,
  }) {
    final durationSeconds =
        (excerpt.endUs -
                excerpt.startUs) /
            Duration
                .microsecondsPerSecond;

    return pw.Container(
      padding:
          const pw.EdgeInsets.fromLTRB(
        7,
        5,
        7,
        5,
      ),
      decoration:
          pw.BoxDecoration(
        border: pw.Border.all(
          color: line,
          width: 0.55,
        ),
        borderRadius:
            pw.BorderRadius.circular(
          5,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment:
            pw.CrossAxisAlignment
                .stretch,
        children: [
          pw.Row(
            children: [
              pw.Text(
                '${language.text('excerpt')} ${index + 1}',
                style:
                    pw.TextStyle(
                  fontSize: 7.7,
                  fontWeight:
                      pw.FontWeight
                          .bold,
                ),
              ),
              pw.SizedBox(width: 7),
              pw.Text(
                _formatExcerptTimestamp(
                  startedAtMs,
                  excerpt.startUs,
                ),
                style:
                    pw.TextStyle(
                  fontSize: 7.3,
                  color: muted,
                ),
              ),
              pw.Spacer(),
              pw.Text(
                '${durationSeconds.toStringAsFixed(1)} s · ${values.length} ${language.text('samples').toLowerCase()}',
                style:
                    pw.TextStyle(
                  fontSize: 6.9,
                  color: muted,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 3),
          pw.SizedBox(
            height: 43,
            child: values.length < 2
                ? pw.Center(
                    child: pw.Text(
                      language.text(
                        'no_signal',
                      ),
                      style:
                          pw.TextStyle(
                        fontSize: 7,
                        color: muted,
                      ),
                    ),
                  )
                : pw.SvgImage(
                    svg:
                        _signalSvg(
                      values,
                      color:
                          graphColor,
                    ),
                    fit:
                        pw.BoxFit.fill,
                  ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pageHeader({
    required String title,
    required String trailing,
    required PdfColor teal,
    required PdfColor muted,
    required PdfColor line,
  }) {
    return pw.Column(
      children: [
        pw.Row(
          children: [
            pw.Text(
              title,
              style:
                  pw.TextStyle(
                fontSize: 14,
                fontWeight:
                    pw.FontWeight.bold,
                color: teal,
              ),
            ),
            pw.SizedBox(
              width: 16,
            ),
            pw.Expanded(
              child: pw.Text(
                trailing,
                maxLines: 1,
                textAlign:
                    pw.TextAlign.right,
                style:
                    pw.TextStyle(
                  fontSize: 8,
                  color: muted,
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 7),
        pw.Container(
          height: 0.8,
          color: line,
        ),
      ],
    );
  }

  pw.Widget _footer({
    required _ReportLanguage language,
    required PdfColor muted,
    required PdfColor line,
  }) {
    return pw.Column(
      crossAxisAlignment:
          pw.CrossAxisAlignment
              .stretch,
      children: [
        pw.Container(
          height: 0.8,
          color: line,
        ),
        pw.SizedBox(
          height: 7,
        ),
        pw.Text(
          language.text(
            'disclaimer',
          ),
          style: pw.TextStyle(
            fontSize: 7.2,
            color: muted,
          ),
        ),
      ],
    );
  }

  String _signalSvg(
    List<double> values, {
    required String color,
  }) {
    const width = 1000.0;
    const height = 110.0;

    final sampled =
        _downsample(
      values,
      420,
    );

    if (sampled.length < 2) {
      return '''
<svg viewBox="0 0 1000 110" xmlns="http://www.w3.org/2000/svg">
  <line x1="0" y1="55" x2="1000" y2="55" stroke="#D8DEDD" stroke-width="1"/>
</svg>
''';
    }

    final sorted =
        List<double>.from(
      sampled,
    )..sort();

    final lowIndex =
        ((sorted.length - 1) *
                0.02)
            .round();

    final highIndex =
        ((sorted.length - 1) *
                0.98)
            .round();

    var low =
        sorted[lowIndex];
    var high =
        sorted[highIndex];

    if (!low.isFinite ||
        !high.isFinite ||
        (high - low).abs() <
            1e-9) {
      low =
          sorted.first;
      high =
          sorted.last;
    }

    if ((high - low).abs() <
        1e-9) {
      high = low + 1;
    }

    final range =
        high - low;

    final points =
        StringBuffer();

    for (int i = 0;
        i < sampled.length;
        i++) {
      final x =
          i /
              (sampled.length - 1) *
              width;

      final normalized =
          ((sampled[i] - low) /
                  range)
              .clamp(
        0.0,
        1.0,
      );

      final y =
          height -
          8 -
          normalized *
              (height - 16);

      if (i > 0) {
        points.write(' ');
      }

      points.write(
        '${x.toStringAsFixed(1)},${y.toStringAsFixed(1)}',
      );
    }

    return '''
<svg viewBox="0 0 1000 110" xmlns="http://www.w3.org/2000/svg">
  <line x1="0" y1="27.5" x2="1000" y2="27.5" stroke="#EEF1F0" stroke-width="1"/>
  <line x1="0" y1="55" x2="1000" y2="55" stroke="#D8DEDD" stroke-width="1"/>
  <line x1="0" y1="82.5" x2="1000" y2="82.5" stroke="#EEF1F0" stroke-width="1"/>
  <line x1="250" y1="0" x2="250" y2="110" stroke="#F2F4F4" stroke-width="1"/>
  <line x1="500" y1="0" x2="500" y2="110" stroke="#F2F4F4" stroke-width="1"/>
  <line x1="750" y1="0" x2="750" y2="110" stroke="#F2F4F4" stroke-width="1"/>
  <polyline points="${points.toString()}" fill="none" stroke="$color" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
''';
  }

  List<double> _downsample(
    List<double> values,
    int maximumPoints,
  ) {
    if (values.length <=
        maximumPoints) {
      return values;
    }

    final output =
        <double>[];

    final stride =
        values.length /
        maximumPoints;

    for (int i = 0;
        i < maximumPoints;
        i++) {
      final start =
          (i * stride).floor();

      final end = math.min(
        values.length,
        ((i + 1) * stride)
            .ceil(),
      );

      if (end <= start) {
        output.add(
          values[start],
        );
        continue;
      }

      var sum = 0.0;
      var count = 0;

      for (int j = start;
          j < end;
          j++) {
        final value =
            values[j];

        if (!value.isFinite) {
          continue;
        }

        sum += value;
        count++;
      }

      output.add(
        count == 0
            ? 0
            : sum / count,
      );
    }

    return output;
  }


  pw.Widget _vital({
    required String value,
    required String unit,
    required String label,
    required PdfColor color,
  }) {
    return pw.Container(
      padding:
          const pw.EdgeInsets.all(
        10,
      ),
      decoration:
          pw.BoxDecoration(
        border: pw.Border.all(
          color:
              PdfColor.fromHex(
            '#D8DEDD',
          ),
          width: 0.7,
        ),
        borderRadius:
            pw.BorderRadius.circular(
          8,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment:
            pw.CrossAxisAlignment
                .start,
        children: [
          pw.Row(
            crossAxisAlignment:
                pw.CrossAxisAlignment
                    .end,
            children: [
              pw.Text(
                value,
                style:
                    pw.TextStyle(
                  fontSize: 28,
                  fontWeight:
                      pw.FontWeight
                          .bold,
                  color: color,
                ),
              ),
              pw.SizedBox(width: 5),
              pw.Padding(
                padding:
                    const pw.EdgeInsets
                        .only(
                  bottom: 4,
                ),
                child: pw.Text(
                  unit,
                  style:
                      const pw.TextStyle(
                    fontSize: 8,
                  ),
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            label,
            style:
                const pw.TextStyle(
              fontSize: 8,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _compactTable({
    required List<List<String>> rows,
    required PdfColor line,
    required PdfColor muted,
  }) {
    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(
          1.15,
        ),
        1: pw.FlexColumnWidth(
          1.85,
        ),
      },
      border: pw.TableBorder(
        horizontalInside:
            pw.BorderSide(
          color: line,
          width: 0.55,
        ),
        bottom: pw.BorderSide(
          color: line,
          width: 0.55,
        ),
      ),
      children: rows.map((row) {
        return pw.TableRow(
          children: [
            pw.Padding(
              padding:
                  const pw.EdgeInsets
                      .symmetric(
                vertical: 5,
                horizontal: 2,
              ),
              child: pw.Text(
                row[0],
                style:
                    pw.TextStyle(
                  fontSize: 8.4,
                  color: muted,
                ),
              ),
            ),
            pw.Padding(
              padding:
                  const pw.EdgeInsets
                      .symmetric(
                vertical: 5,
                horizontal: 2,
              ),
              child: pw.Text(
                row[1],
                textAlign:
                    pw.TextAlign.right,
                style:
                    pw.TextStyle(
                  fontSize: 8.4,
                  fontWeight:
                      pw.FontWeight
                          .bold,
                ),
              ),
            ),
          ],
        );
      }).toList(
        growable: false,
      ),
    );
  }

  String _status(
    _ReportLanguage language,
    String status,
  ) {
    switch (status) {
      case 'recording':
        return language.text(
          'recording_active',
        );
      case 'paused':
        return language.text(
          'paused',
        );
      case 'interrupted':
        return language.text(
          'interrupted',
        );
      default:
        return language.text(
          'completed',
        );
    }
  }

  String _safeFileName(
    String value,
  ) {
    var result = value
        .trim()
        .replaceAll(
          RegExp(
            r'[\\/:*?"<>|]',
          ),
          '_',
        )
        .replaceAll(
          RegExp(r'\s+'),
          ' ',
        );

    if (result.isEmpty) {
      result = 'recording';
    }

    if (result.length > 80) {
      result =
          result.substring(
        0,
        80,
      );
    }

    return result;
  }

  String _truncate(
    String value,
    int maximum,
  ) {
    final cleaned =
        value.trim();

    if (cleaned.length <= maximum) {
      return cleaned;
    }

    return '${cleaned.substring(
      0,
      maximum,
    )}…';
  }
}

enum _ReportChannel {
  ecg,
  respiration,
}

class _ReportLanguage {
  final String code;

  const _ReportLanguage(
    String languageCode,
  ) : code = languageCode;

  static const Map<
      String,
      Map<String, String>> _data = {
    'EN': {
      'report': 'Recording report',
      'average': 'Average',
      'recording': 'Recording',
      'status': 'Status',
      'started': 'Started',
      'ended': 'Ended',
      'timeline': 'Timeline',
      'measured': 'Measured signal',
      'sample_rate': 'Sample rate',
      'samples': 'Samples',
      'device': 'Device',
      'signal': 'Signal summary',
      'rr': 'R-R interval',
      'breath': 'Breath interval',
      'gaps': 'Acquisition gaps',
      'gap_duration': 'Gap duration',
      'analysis_windows': 'Analysis windows',
      'notes': 'Notes',
      'recording_active': 'Recording',
      'paused': 'Paused',
      'interrupted': 'Interrupted',
      'completed': 'Completed',
      'ecg_details': 'Detailed ECG',
      'respiration_details': 'Detailed Respiration',
      'heart_rate': 'Average heart rate',
      'respiration_rate': 'Average respiration rate',
      'signal_range': 'Signal range',
      'signal_mean': 'Signal mean',
      'signal_rms': 'Signal RMS',
      'excerpt': 'Excerpt',
      'no_signal': 'No signal samples in this interval',
      'disclaimer':
          'Heart-rate and respiration-rate values are derived from the recorded signal for review and do not constitute a medical diagnosis.',
    },
    'RO': {
      'report': 'Raport înregistrare',
      'average': 'Medie',
      'recording': 'Înregistrare',
      'status': 'Stare',
      'started': 'Pornită',
      'ended': 'Oprită',
      'timeline': 'Cronologie',
      'measured': 'Semnal măsurat',
      'sample_rate': 'Rată eșantionare',
      'samples': 'Mostre',
      'device': 'Dispozitiv',
      'signal': 'Rezumat semnal',
      'rr': 'Interval R-R',
      'breath': 'Interval respirator',
      'gaps': 'Întreruperi',
      'gap_duration': 'Durata întreruperilor',
      'analysis_windows': 'Ferestre analizate',
      'notes': 'Notițe',
      'recording_active': 'Înregistrare',
      'paused': 'Pauză',
      'interrupted': 'Întreruptă',
      'completed': 'Finalizată',
      'ecg_details': 'ECG detaliat',
      'respiration_details': 'Respirație detaliată',
      'heart_rate': 'Ritm cardiac mediu',
      'respiration_rate': 'Ritm respirator mediu',
      'signal_range': 'Amplitudine semnal',
      'signal_mean': 'Media semnalului',
      'signal_rms': 'RMS semnal',
      'excerpt': 'Secvență',
      'no_signal': 'Nu există mostre în acest interval',
      'disclaimer':
          'Valorile ritmului cardiac și respirator sunt derivate din semnalul înregistrat pentru analiză și nu reprezintă un diagnostic medical.',
    },
    'DE': {
      'report': 'Aufnahmebericht',
      'average': 'Durchschnitt',
      'recording': 'Aufnahme',
      'status': 'Status',
      'started': 'Gestartet',
      'ended': 'Beendet',
      'timeline': 'Zeitleiste',
      'measured': 'Gemessenes Signal',
      'sample_rate': 'Abtastrate',
      'samples': 'Samples',
      'device': 'Gerät',
      'signal': 'Signalübersicht',
      'rr': 'R-R-Intervall',
      'breath': 'Atemintervall',
      'gaps': 'Signallücken',
      'gap_duration': 'Lückendauer',
      'analysis_windows': 'Analysefenster',
      'notes': 'Notizen',
      'recording_active': 'Aufnahme',
      'paused': 'Pausiert',
      'interrupted': 'Unterbrochen',
      'completed': 'Abgeschlossen',
      'ecg_details': 'Detailliertes EKG',
      'respiration_details': 'Detaillierte Atmung',
      'heart_rate': 'Durchschnittliche Herzfrequenz',
      'respiration_rate': 'Durchschnittliche Atemfrequenz',
      'signal_range': 'Signalbereich',
      'signal_mean': 'Signalmittelwert',
      'signal_rms': 'Signal-RMS',
      'excerpt': 'Ausschnitt',
      'no_signal': 'Keine Signalwerte in diesem Intervall',
      'disclaimer':
          'Herz- und Atemfrequenz werden aus dem aufgezeichneten Signal zur Überprüfung abgeleitet und stellen keine medizinische Diagnose dar.',
    },
    'RU': {
      'report': 'Recording report',
      'average': 'Average',
      'recording': 'Recording',
      'status': 'Status',
      'started': 'Started',
      'ended': 'Ended',
      'timeline': 'Timeline',
      'measured': 'Measured signal',
      'sample_rate': 'Sample rate',
      'samples': 'Samples',
      'device': 'Device',
      'signal': 'Signal summary',
      'rr': 'R-R interval',
      'breath': 'Breath interval',
      'gaps': 'Signal gaps',
      'gap_duration': 'Gap duration',
      'analysis_windows': 'Analysis windows',
      'notes': 'Notes',
      'recording_active': 'Recording',
      'paused': 'Paused',
      'interrupted': 'Interrupted',
      'completed': 'Completed',
      'ecg_details': 'Detailed ECG',
      'respiration_details': 'Detailed Respiration',
      'heart_rate': 'Average heart rate',
      'respiration_rate': 'Average respiration rate',
      'signal_range': 'Signal range',
      'signal_mean': 'Signal mean',
      'signal_rms': 'Signal RMS',
      'excerpt': 'Excerpt',
      'no_signal': 'No signal samples in this interval',
      'disclaimer':
          'Heart-rate and respiration-rate values are derived from the recorded signal for review and do not constitute a medical diagnosis.',
    },
    'ES': {
      'report': 'Informe de grabación',
      'average': 'Promedio',
      'recording': 'Grabación',
      'status': 'Estado',
      'started': 'Inicio',
      'ended': 'Fin',
      'timeline': 'Cronología',
      'measured': 'Señal medida',
      'sample_rate': 'Frecuencia de muestreo',
      'samples': 'Muestras',
      'device': 'Dispositivo',
      'signal': 'Resumen de señal',
      'rr': 'Intervalo R-R',
      'breath': 'Intervalo respiratorio',
      'gaps': 'Interrupciones',
      'gap_duration': 'Duración de interrupciones',
      'analysis_windows': 'Ventanas analizadas',
      'notes': 'Notas',
      'recording_active': 'Grabación',
      'paused': 'Pausada',
      'interrupted': 'Interrumpida',
      'completed': 'Completada',
      'ecg_details': 'ECG detallado',
      'respiration_details': 'Respiración detallada',
      'heart_rate': 'Frecuencia cardíaca promedio',
      'respiration_rate': 'Respiración promedio',
      'signal_range': 'Rango de señal',
      'signal_mean': 'Media de señal',
      'signal_rms': 'RMS de señal',
      'excerpt': 'Fragmento',
      'no_signal': 'No hay muestras en este intervalo',
      'disclaimer':
          'La frecuencia cardíaca y respiratoria se deriva de la señal grabada para revisión y no constituye un diagnóstico médico.',
    },
  };

  String text(
    String key,
  ) {
    return _data[code]?[key] ??
        _data['EN']![key] ??
        key;
  }
}

String _formatDurationUs(
  int microseconds,
) {
  final duration = Duration(
    microseconds: microseconds,
  );

  final totalSeconds =
      duration.inSeconds;

  final days =
      totalSeconds ~/ 86400;

  final hours =
      (totalSeconds % 86400) ~/ 3600;

  final minutes =
      (totalSeconds % 3600) ~/ 60;

  final seconds =
      totalSeconds % 60;

  if (days > 0) {
    return '${days}d ${_two(hours)}:${_two(minutes)}:${_two(seconds)}';
  }

  if (hours > 0) {
    return '${_two(hours)}:${_two(minutes)}:${_two(seconds)}';
  }

  return '${_two(minutes)}:${_two(seconds)}';
}

String _formatDateTime(
  int millisecondsSinceEpoch,
) {
  final date =
      DateTime.fromMillisecondsSinceEpoch(
    millisecondsSinceEpoch,
  );

  return '${date.year}-'
      '${_two(date.month)}-'
      '${_two(date.day)} '
      '${_two(date.hour)}:'
      '${_two(date.minute)}';
}

String _formatExcerptTimestamp(
  int startedAtMs,
  int elapsedUs,
) {
  final date =
      DateTime.fromMillisecondsSinceEpoch(
    startedAtMs,
  ).add(
    Duration(
      microseconds: elapsedUs,
    ),
  );

  return '${_two(date.month)}-'
      '${_two(date.day)} '
      '${_two(date.hour)}:'
      '${_two(date.minute)}:'
      '${_two(date.second)}';
}

String _formatNumber(
  int value,
) {
  final source =
      value.toString();

  final buffer =
      StringBuffer();

  for (int i = 0;
      i < source.length;
      i++) {
    if (i > 0 &&
        (source.length - i) % 3 ==
            0) {
      buffer.write(' ');
    }

    buffer.write(
      source[i],
    );
  }

  return buffer.toString();
}

String _formatSignalNumber(
  double value,
) {
  if (!value.isFinite) {
    return '--';
  }

  final absolute =
      value.abs();

  if (absolute >= 1000000) {
    return value
        .toStringAsExponential(
          3,
        );
  }

  if (absolute >= 1000) {
    return value
        .toStringAsFixed(
          0,
        );
  }

  if (absolute >= 10) {
    return value
        .toStringAsFixed(
          1,
        );
  }

  return value
      .toStringAsFixed(
        3,
      );
}

String _two(
  int value,
) {
  return value
      .toString()
      .padLeft(
        2,
        '0',
      );
}
