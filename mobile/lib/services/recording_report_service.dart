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

    final baseFont =
        await PdfGoogleFonts.notoSansRegular();

    final boldFont =
        await PdfGoogleFonts.notoSansBold();

    final theme =
        pw.ThemeData.withFont(
      base: baseFont,
      bold: boldFont,
    );

    final document = pw.Document(
      title: 'ApexCardio Report',
      author: 'ApexCardio',
      creator: 'ApexCardio',
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

    document.addPage(
      pw.Page(
        pageTheme:
            pw.PageTheme(
          theme: theme,
          pageFormat:
              PdfPageFormat.a4,
          margin:
              const pw.EdgeInsets.fromLTRB(
            32,
            28,
            32,
            28,
          ),
        ),
        build: (_) {
          return pw.Column(
            crossAxisAlignment:
                pw.CrossAxisAlignment
                    .stretch,
            children: [
              pw.Row(
                children: [
                  pw.Text(
                    'APEX CARDIO',
                    style:
                        pw.TextStyle(
                      fontSize: 15,
                      fontWeight:
                          pw.FontWeight
                              .bold,
                      color: teal,
                    ),
                  ),
                  pw.Spacer(),
                  pw.Text(
                    language.text(
                      'report',
                    ),
                    style:
                        pw.TextStyle(
                      fontSize: 9,
                      color: muted,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(
                height: 8,
              ),
              pw.Container(
                height: 0.8,
                color: line,
              ),
              pw.SizedBox(
                height: 14,
              ),
              pw.Text(
                recording['name']
                        as String? ??
                    language.text(
                      'recording',
                    ),
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
                  fontSize: 7.7,
                  color: muted,
                ),
              ),
            ],
          );
        },
      ),
    );

    return document.save();
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
      'disclaimer':
          'Herz- und Atemfrequenz werden aus dem aufgezeichneten Signal zur Überprüfung abgeleitet und stellen keine medizinische Diagnose dar.',
    },
    'RU': {
      'report': 'Отчёт о записи',
      'average': 'Среднее',
      'recording': 'Запись',
      'status': 'Статус',
      'started': 'Начало',
      'ended': 'Конец',
      'timeline': 'Шкала времени',
      'measured': 'Измеренный сигнал',
      'sample_rate': 'Частота дискретизации',
      'samples': 'Сэмплы',
      'device': 'Устройство',
      'signal': 'Сводка сигнала',
      'rr': 'Интервал R-R',
      'breath': 'Интервал дыхания',
      'gaps': 'Разрывы сигнала',
      'gap_duration': 'Длительность разрывов',
      'analysis_windows': 'Окна анализа',
      'notes': 'Заметки',
      'recording_active': 'Запись',
      'paused': 'Пауза',
      'interrupted': 'Прервано',
      'completed': 'Завершено',
      'disclaimer':
          'Частота сердцебиения и дыхания рассчитывается по записанному сигналу для просмотра и не является медицинским диагнозом.',
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
