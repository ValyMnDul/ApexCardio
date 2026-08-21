import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/language.dart';
import '../services/recording_analysis_service.dart';
import '../services/recording_database.dart';
import '../services/recording_export_service.dart';
import '../services/recording_report_service.dart';

class RecordingViewer extends StatefulWidget {
  final int recordingId;

  const RecordingViewer({
    super.key,
    required this.recordingId,
  });

  @override
  State<RecordingViewer> createState() => _RecordingViewerState();
}

class _RecordingViewerState extends State<RecordingViewer> {
  final RecordingDatabase _database = RecordingDatabase.instance;

  Map<String, Object?>? _recording;
  List<_DecodedSample> _samples = const [];
  List<_RecordingGap> _gaps = const [];

  bool _loadingRecording = true;
  bool _loadingWindow = false;
  bool _loadingMetrics = false;
  bool _workingAction = false;
  String? _error;

  _ViewerMetrics? _metrics;

  int _timelineDurationUs = 0;
  int _windowStartUs = 0;
  int _windowDurationUs = 10 * 1000000;
  int _intervalBaseStartUs = 0;
  int _intervalBaseDurationUs = 10 * 1000000;

  double _sampleRate = 250.0;

  Timer? _windowLoadDebounce;
  int _windowRequestSerial = 0;

  double _gestureWidth = 1.0;
  int _gestureStartWindowUs = 0;
  int _gestureStartDurationUs = 10 * 1000000;
  double _gestureStartFocalX = 0.0;
  int _gestureAnchorTimeUs = 0;

  static const int _minimumWindowUs = 2 * 1000000;
  static const int _maximumDetailedWindowUs = 20 * 1000000;

  @override
  void initState() {
    super.initState();
    _loadRecording();
  }

  @override
  void dispose() {
    _windowLoadDebounce?.cancel();
    super.dispose();
  }

  int get _windowEndUs {
    return math.min(
      _timelineDurationUs,
      _windowStartUs + _windowDurationUs,
    );
  }

  Future<void> _loadRecording() async {
    setState(() {
      _loadingRecording = true;
      _error = null;
    });

    try {
      final recording = await _database.getRecordingById(
        widget.recordingId,
      );

      if (recording == null) {
        throw StateError('Recording not found.');
      }

      final timelineDurationUs =
          recording['timeline_duration_us'] as int? ?? 0;

      final sampleRate =
          (recording['sample_rate'] as num?)?.toDouble() ?? 250.0;

      final initialWindow = timelineDurationUs <= 0
          ? 10 * 1000000
          : math.min(
              timelineDurationUs,
              10 * 1000000,
            );

      if (!mounted) {
        return;
      }

      setState(() {
        _recording = recording;
        _timelineDurationUs = timelineDurationUs;
        _sampleRate = sampleRate > 0 ? sampleRate : 250.0;
        _windowStartUs = 0;
        _windowDurationUs = math.max(
          _minimumWindowUs,
          initialWindow,
        );
        _intervalBaseStartUs = 0;
        _intervalBaseDurationUs =
            _windowDurationUs;
        _loadingRecording = false;
      });

      await Future.wait<void>([
        _loadVisibleWindow(),
        _loadOverviewMetrics(),
      ]);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingRecording = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadOverviewMetrics() async {
    if (_loadingMetrics) {
      return;
    }

    if (mounted) {
      setState(() {
        _loadingMetrics = true;
      });
    }

    try {
      final summary =
          await RecordingAnalysisService.instance.analyze(
        recordingId: widget.recordingId,
        recording: _recording,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _metrics = _ViewerMetrics(
          estimatedHeartRateBpm:
              summary.averageHeartRateBpm,
          estimatedMeanRrMs:
              summary.averageRrMs,
          estimatedRespirationRateBpm:
              summary.averageRespirationRateBrpm,
          estimatedMeanBreathMs:
              summary.averageBreathIntervalMs,
          analyzedSamples: 0,
        );
        _loadingMetrics = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingMetrics = false;
      });
    }
  }

  _ViewerRateEstimate _estimateRate({
    required List<double> values,
    required double sampleRate,
    required double minimumDistanceSeconds,
    required double thresholdMultiplier,
    required int smoothingRadius,
  }) {
    if (values.length < 6 || sampleRate <= 0) {
      return const _ViewerRateEstimate(
        rateBpm: null,
        intervalMs: null,
      );
    }

    final smoothed = _smoothValues(
      values,
      radius: smoothingRadius,
    );

    final mean =
        smoothed.reduce((a, b) => a + b) /
        smoothed.length;

    var variance = 0.0;

    for (final value in smoothed) {
      final difference = value - mean;
      variance += difference * difference;
    }

    variance /= smoothed.length;
    final standardDeviation = math.sqrt(variance);

    if (!standardDeviation.isFinite ||
        standardDeviation <= 0) {
      return const _ViewerRateEstimate(
        rateBpm: null,
        intervalMs: null,
      );
    }

    final threshold =
        mean + standardDeviation * thresholdMultiplier;

    final minimumDistanceSamples = math.max(
      1,
      (minimumDistanceSeconds * sampleRate).round(),
    );

    final peaks = <int>[];
    var lastPeak = -minimumDistanceSamples;

    for (int i = 1; i < smoothed.length - 1; i++) {
      final current = smoothed[i];

      if (current < threshold ||
          current < smoothed[i - 1] ||
          current < smoothed[i + 1]) {
        continue;
      }

      if (i - lastPeak < minimumDistanceSamples) {
        if (peaks.isNotEmpty &&
            current > smoothed[peaks.last]) {
          peaks[peaks.length - 1] = i;
          lastPeak = i;
        }

        continue;
      }

      peaks.add(i);
      lastPeak = i;
    }

    if (peaks.length < 2) {
      return const _ViewerRateEstimate(
        rateBpm: null,
        intervalMs: null,
      );
    }

    var intervalSumSeconds = 0.0;
    var intervalCount = 0;

    for (int i = 1; i < peaks.length; i++) {
      final delta = peaks[i] - peaks[i - 1];

      if (delta <= 0) {
        continue;
      }

      intervalSumSeconds += delta / sampleRate;
      intervalCount++;
    }

    if (intervalCount == 0) {
      return const _ViewerRateEstimate(
        rateBpm: null,
        intervalMs: null,
      );
    }

    final averageIntervalSeconds =
        intervalSumSeconds / intervalCount;

    if (!averageIntervalSeconds.isFinite ||
        averageIntervalSeconds <= 0) {
      return const _ViewerRateEstimate(
        rateBpm: null,
        intervalMs: null,
      );
    }

    return _ViewerRateEstimate(
      rateBpm: 60.0 / averageIntervalSeconds,
      intervalMs: averageIntervalSeconds * 1000,
    );
  }

  List<double> _smoothValues(
    List<double> values, {
    required int radius,
  }) {
    if (radius <= 0 || values.length < 3) {
      return List<double>.from(values);
    }

    final output = List<double>.filled(
      values.length,
      0,
      growable: false,
    );

    final prefix = List<double>.filled(
      values.length + 1,
      0,
      growable: false,
    );

    for (int i = 0; i < values.length; i++) {
      prefix[i + 1] = prefix[i] + values[i];
    }

    for (int i = 0; i < values.length; i++) {
      final start = math.max(0, i - radius);
      final end = math.min(
        values.length - 1,
        i + radius,
      );

      output[i] =
          (prefix[end + 1] - prefix[start]) /
          (end - start + 1);
    }

    return output;
  }

  Future<void> _loadVisibleWindow() async {
    final serial = ++_windowRequestSerial;

    if (_timelineDurationUs <= 0) {
      if (!mounted) {
        return;
      }

      setState(() {
        _samples = const [];
        _gaps = const [];
        _loadingWindow = false;
      });

      return;
    }

    if (mounted) {
      setState(() {
        _loadingWindow = true;
      });
    }

    try {
      final startUs = _windowStartUs;
      final endUs = _windowEndUs;

      final results = await Future.wait([
        _database.getSignalChunksInRange(
          recordingId: widget.recordingId,
          startElapsedUs: startUs,
          endElapsedUs: endUs,
        ),
        _database.getGapsInRange(
          recordingId: widget.recordingId,
          startElapsedUs: startUs,
          endElapsedUs: endUs,
        ),
      ]);

      if (!mounted || serial != _windowRequestSerial) {
        return;
      }

      final chunks =
          results[0] as List<Map<String, Object?>>;
      final gapRows =
          results[1] as List<Map<String, Object?>>;

      final decoded = _decodeChunks(
        chunks,
        startUs,
        endUs,
      );

      final gaps = gapRows.map(_RecordingGap.fromRow).toList(
            growable: false,
          );

      setState(() {
        _samples = decoded;
        _gaps = gaps;
        _loadingWindow = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted || serial != _windowRequestSerial) {
        return;
      }

      setState(() {
        _loadingWindow = false;
        _error = error.toString();
      });
    }
  }

  List<_DecodedSample> _decodeChunks(
    List<Map<String, Object?>> chunks,
    int visibleStartUs,
    int visibleEndUs,
  ) {
    final result = <_DecodedSample>[];
    final samplePeriodUs = 1000000.0 / _sampleRate;

    for (final chunk in chunks) {
      final encodingVersion =
          chunk['encoding_version'] as int? ?? 1;

      if (encodingVersion != 1) {
        continue;
      }

      final sampleCount =
          chunk['sample_count'] as int? ?? 0;

      final chunkStartUs =
          chunk['start_elapsed_us'] as int? ?? 0;

      final raw = chunk['signal_data'];

      final bytes = switch (raw) {
        Uint8List value => value,
        List<int> value => Uint8List.fromList(value),
        _ => null,
      };

      if (bytes == null ||
          sampleCount <= 0 ||
          bytes.length < sampleCount * 8) {
        continue;
      }

      final data = ByteData.sublistView(bytes);

      for (int index = 0; index < sampleCount; index++) {
        final elapsedUs =
            chunkStartUs + (index * samplePeriodUs).round();

        if (elapsedUs < visibleStartUs) {
          continue;
        }

        if (elapsedUs >= visibleEndUs) {
          break;
        }

        final offset = index * 8;

        final ecg = data.getInt32(
          offset,
          Endian.little,
        );

        final respiration = data.getInt32(
          offset + 4,
          Endian.little,
        );

        result.add(
          _DecodedSample(
            elapsedUs: elapsedUs,
            ecg: ecg.toDouble(),
            respiration: respiration.toDouble(),
          ),
        );
      }
    }

    return result;
  }

  void _scheduleWindowLoad() {
    _windowLoadDebounce?.cancel();

    _windowLoadDebounce = Timer(
      const Duration(milliseconds: 120),
      _loadVisibleWindow,
    );
  }

  void _onScaleStart(
    ScaleStartDetails details,
    double width,
  ) {
    _gestureWidth = math.max(width, 1.0);
    _gestureStartWindowUs = _windowStartUs;
    _gestureStartDurationUs = _windowDurationUs;
    _gestureStartFocalX = details.localFocalPoint.dx.clamp(
      0.0,
      _gestureWidth,
    );

    final fraction =
        _gestureStartFocalX / _gestureWidth;

    _gestureAnchorTimeUs = (
      _gestureStartWindowUs +
      fraction * _gestureStartDurationUs
    ).round();
  }

  void _onScaleUpdate(
    ScaleUpdateDetails details,
  ) {
    if (_timelineDurationUs <= 0) {
      return;
    }

    final maxWindow = math.max(
      _minimumWindowUs,
      math.min(
        _timelineDurationUs,
        _maximumDetailedWindowUs,
      ),
    );

    final newDuration = (
      _gestureStartDurationUs /
      math.max(details.scale, 0.01)
    ).round().clamp(
          _minimumWindowUs,
          maxWindow,
        ).toInt();

    final currentFocalX =
        details.localFocalPoint.dx.clamp(
      0.0,
      _gestureWidth,
    );

    final focalFraction =
        currentFocalX / _gestureWidth;

    var newStart = (
      _gestureAnchorTimeUs -
      focalFraction * newDuration
    ).round();

    newStart = _clampWindowStart(
      newStart,
      newDuration,
    );

    if (newStart == _windowStartUs &&
        newDuration == _windowDurationUs) {
      return;
    }

    setState(() {
      _windowStartUs = newStart;
      _windowDurationUs = newDuration;
    });

    _scheduleWindowLoad();
  }

  int _clampWindowStart(
    int startUs,
    int durationUs,
  ) {
    final maximumStart = math.max(
      0,
      _timelineDurationUs - durationUs,
    );

    return startUs.clamp(
      0,
      maximumStart,
    ).toInt();
  }

  void _zoomBy(double factor) {
    if (_timelineDurationUs <= 0) {
      return;
    }

    final maxWindow = math.max(
      _minimumWindowUs,
      math.min(
        _timelineDurationUs,
        _maximumDetailedWindowUs,
      ),
    );

    final center =
        _windowStartUs + _windowDurationUs / 2;

    final newDuration = (
      _windowDurationUs * factor
    ).round().clamp(
          _minimumWindowUs,
          maxWindow,
        ).toInt();

    final newStart = _clampWindowStart(
      (center - newDuration / 2).round(),
      newDuration,
    );

    setState(() {
      _windowDurationUs = newDuration;
      _windowStartUs = newStart;
    });

    _scheduleWindowLoad();
  }

  void _resetWindow() {
    if (_timelineDurationUs <= 0) {
      return;
    }

    setState(() {
      _windowStartUs =
          _clampWindowStart(
        _intervalBaseStartUs,
        _intervalBaseDurationUs,
      );
      _windowDurationUs =
          _intervalBaseDurationUs.clamp(
        _minimumWindowUs,
        math.min(
          _timelineDurationUs,
          _maximumDetailedWindowUs,
        ),
      ).toInt();
    });

    _scheduleWindowLoad();
  }

  Future<void> _chooseInterval() async {
    if (_timelineDurationUs <= 0) {
      return;
    }

    final selected =
        await showModalBottomSheet<_SelectedInterval>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return _IntervalPickerSheet(
          timelineUs:
              _timelineDurationUs,
          startUs:
              _windowStartUs,
          endUs:
              _windowEndUs,
          maximumIntervalUs:
              _maximumDetailedWindowUs,
        );
      },
    );

    if (selected == null ||
        !mounted) {
      return;
    }

    final duration =
        selected.endUs -
        selected.startUs;

    setState(() {
      _intervalBaseStartUs =
          selected.startUs;
      _intervalBaseDurationUs =
          duration;
      _windowStartUs =
          selected.startUs;
      _windowDurationUs =
          duration;
    });

    await _loadVisibleWindow();
  }

  Rect? _shareOrigin() {
    final box =
        context.findRenderObject()
            as RenderBox?;

    if (box == null ||
        !box.hasSize) {
      return null;
    }

    return box.localToGlobal(
          Offset.zero,
        ) &
        box.size;
  }

  void _jumpToTimelineFraction(double fraction) {
    if (_timelineDurationUs <= 0) {
      return;
    }

    final targetUs =
        (_timelineDurationUs * fraction).round();

    final newStart = _clampWindowStart(
      targetUs - _windowDurationUs ~/ 2,
      _windowDurationUs,
    );

    setState(() {
      _windowStartUs = newStart;
    });

    _scheduleWindowLoad();
  }


  Future<void> _runViewerAction(
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    if (_workingAction) {
      return;
    }

    setState(() {
      _workingAction = true;
    });

    try {
      await action();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(successMessage),
          ),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              context
                  .read<LanguageProvider>()
                  .translate(
                    "action_failed",
                    <String, Object?>{
                      "error": error,
                    },
                  ),
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _workingAction = false;
        });
      }
    }
  }

  Future<void> _exportApex() async {
    final language =
        context.read<LanguageProvider>();

    await _runViewerAction(
      () async {
        await RecordingExportService.instance.export(
          recordingId: widget.recordingId,
          format: RecordingExportFormat.apex,
          sharePositionOrigin:
              _shareOrigin(),
        );
      },
      successMessage:
          language.translate(
        "apex_export_ready",
      ),
    );
  }

  Future<void> _exportCsv() async {
    final language =
        context.read<LanguageProvider>();

    await _runViewerAction(
      () async {
        await RecordingExportService.instance.export(
          recordingId: widget.recordingId,
          format: RecordingExportFormat.csv,
          sharePositionOrigin:
              _shareOrigin(),
        );
      },
      successMessage:
          language.translate(
        "csv_export_ready",
      ),
    );
  }

  Future<void> _sharePdfReport() async {
    final language =
        context.read<LanguageProvider>();

    await _runViewerAction(
      () async {
        await RecordingReportService.instance.shareReport(
          recordingId: widget.recordingId,
          languageCode:
              language.currentLang,
          sharePositionOrigin:
              _shareOrigin(),
        );
      },
      successMessage:
          language.translate(
        "pdf_ready",
      ),
    );
  }

  Future<void> _printPdfReport() async {
    await _runViewerAction(
      () async {
        final language =
            context.read<LanguageProvider>();

        await RecordingReportService.instance.printReport(
          recordingId: widget.recordingId,
          languageCode:
              language.currentLang,
        );
      },
      successMessage:
          context
              .read<LanguageProvider>()
              .translate(
                "print_opened",
              ),
    );
  }

  Future<void> _showViewerActions() async {
    final language =
        context.read<LanguageProvider>();

    final action =
        await showModalBottomSheet<
            _ViewerAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.fromLTRB(
              20,
              2,
              20,
              18,
            ),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              crossAxisAlignment:
                  CrossAxisAlignment
                      .stretch,
              children: [
                Text(
                  language.translate(
                    "recording_actions",
                  ),
                  style:
                      Theme.of(
                    sheetContext,
                  )
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                            fontWeight:
                                FontWeight
                                    .w600,
                          ),
                ),
                const SizedBox(
                  height: 8,
                ),
                _ViewerActionRow(
                  label:
                      language.translate(
                    "generate_share_pdf",
                  ),
                  onTap: () {
                    Navigator.pop(
                      sheetContext,
                      _ViewerAction
                          .sharePdf,
                    );
                  },
                ),
                _ViewerActionRow(
                  label:
                      language.translate(
                    "print_pdf",
                  ),
                  onTap: () {
                    Navigator.pop(
                      sheetContext,
                      _ViewerAction
                          .printPdf,
                    );
                  },
                ),
                _ViewerActionRow(
                  label:
                      language.translate(
                    "export_apex",
                  ),
                  onTap: () {
                    Navigator.pop(
                      sheetContext,
                      _ViewerAction
                          .exportApex,
                    );
                  },
                ),
                _ViewerActionRow(
                  label:
                      language.translate(
                    "export_csv",
                  ),
                  onTap: () {
                    Navigator.pop(
                      sheetContext,
                      _ViewerAction
                          .exportCsv,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );

    if (action == null ||
        !mounted) {
      return;
    }

    switch (action) {
      case _ViewerAction.exportApex:
        await _exportApex();
        break;
      case _ViewerAction.exportCsv:
        await _exportCsv();
        break;
      case _ViewerAction.sharePdf:
        await _sharePdfReport();
        break;
      case _ViewerAction.printPdf:
        await _printPdfReport();
        break;
    }
  }

  Future<void> _editDetails() async {
    final recording = _recording;

    if (recording == null) {
      return;
    }

    final nameController = TextEditingController(
      text: recording['name'] as String? ?? '',
    );

    final notesController = TextEditingController(
      text: recording['notes'] as String? ?? '',
    );

    final language =
        context.read<LanguageProvider>();

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            language.translate(
              "edit_recording",
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText:
                        language.translate(
                      "recording_name",
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: notesController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText:
                        language.translate(
                      "notes",
                    ),
                    hintText:
                        language.translate(
                      "optional",
                    ),
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: Text(
                language.translate(
                  "cancel",
                ),
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: Text(
                language.translate(
                  "save",
                ),
              ),
            ),
          ],
        );
      },
    );

    if (save != true) {
      nameController.dispose();
      notesController.dispose();
      return;
    }

    final cleanedName = nameController.text.trim();
    final notes = notesController.text.trim();

    nameController.dispose();
    notesController.dispose();

    if (cleanedName.isEmpty) {
      return;
    }

    await _database.updateRecordingDetails(
      recordingId: widget.recordingId,
      name: cleanedName,
      notes: notes.isEmpty ? null : notes,
      replaceNotes: true,
    );

    await _loadRecording();
  }

  String _formatDurationUs(int microseconds) {
    return _formatDuration(
      Duration(microseconds: microseconds),
    );
  }

  String _formatDuration(Duration duration) {
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

  String _formatDateTime(int milliseconds) {
    final date = DateTime.fromMillisecondsSinceEpoch(
      milliseconds,
    );

    return '${date.year}-${_two(date.month)}-${_two(date.day)} '
        '${_two(date.hour)}:${_two(date.minute)}:${_two(date.second)}';
  }

  String _two(int value) {
    return value.toString().padLeft(2, '0');
  }

  @override
  Widget build(BuildContext context) {
    final recording =
        _recording;
    final language =
        context.watch<LanguageProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          recording?['name'] as String? ??
              language.translate(
                "recording",
              ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_workingAction)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox(
                  width: 19,
                  height: 19,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
          SizedBox(
            width: 74,
            child: TextButton(
              onPressed:
                  recording == null ||
                          _workingAction
                      ? null
                      : _editDetails,
              child: FittedBox(
                fit:
                    BoxFit.scaleDown,
                child: Text(
                  language.translate(
                    "edit",
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 68,
            child: TextButton(
              onPressed:
                  recording == null ||
                          _workingAction
                      ? null
                      : _showViewerActions,
              child: FittedBox(
                fit:
                    BoxFit.scaleDown,
                child: Text(
                  language.translate(
                    "more",
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
        ],
      ),
      body: _loadingRecording
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _error != null && recording == null
              ? _ErrorBody(
                  message: _error!,
                  onRetry: _loadRecording,
                )
              : recording == null
                  ? Center(
                      child: Text(
                        language.translate(
                          "recording_not_found",
                        ),
                      ),
                    )
                  : _buildContent(context, recording),
    );
  }

  Widget _buildContent(
    BuildContext context,
    Map<String, Object?> recording,
  ) {
    final scheme =
        Theme.of(context).colorScheme;
    final language =
        context.watch<LanguageProvider>();

    final startedAtMs =
        recording['started_at_ms']
            as int? ??
        0;
    final timelineUs =
        recording['timeline_duration_us']
            as int? ??
        0;
    final sampleCount =
        recording['recorded_sample_count']
            as int? ??
        0;
    final status =
        recording['status'] as String? ??
        'completed';
    final notes =
        recording['notes'] as String?;
    final deviceName =
        recording['device_name']
            as String?;

    final measuredDuration =
        Duration(
      microseconds: (
        sampleCount /
        _sampleRate *
        1000000
      ).round(),
    );

    return RefreshIndicator(
      onRefresh: _loadRecording,
      child: ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        padding:
            const EdgeInsets.fromLTRB(
          16,
          12,
          16,
          28,
        ),
        children: [
          _VitalsCard(
            metrics: _metrics,
            loading:
                _loadingMetrics,
            averageLabel:
                language.translate(
              "average",
            ),
            rrLabel:
                language.translate(
              "rr_interval",
            ),
            breathLabel:
                language.translate(
              "breath_interval",
            ),
          ),
          const SizedBox(height: 10),
          _RecordingContextCard(
            statusLabel:
                language.translate(
              "status",
            ),
            notesLabel:
                language.translate(
              "notes",
            ),
            status:
                _localizedStatus(
              language,
              status,
            ),
            notes: notes,
          ),
          const SizedBox(height: 16),
          _IntervalSelector(
            title:
                language.translate(
              "interval",
            ),
            start:
                _formatDurationUs(
              _windowStartUs,
            ),
            end:
                _formatDurationUs(
              _windowEndUs,
            ),
            changeLabel:
                language.translate(
              "change",
            ),
            onChange:
                _chooseInterval,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                language.translate(
                  "signal_viewer",
                ),
                style:
                    Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(
                          fontWeight:
                              FontWeight
                                  .w600,
                        ),
              ),
              const Spacer(),
              if (_loadingWindow)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child:
                      CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          _SignalViewer(
            samples: _samples,
            gaps: _gaps,
            windowStartUs:
                _windowStartUs,
            windowEndUs:
                _windowEndUs,
            onScaleStart:
                _onScaleStart,
            onScaleUpdate:
                _onScaleUpdate,
            respirationTitle:
                language.translate(
              "respiration",
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 48,
                child:
                    OutlinedButton(
                  onPressed: () {
                    _zoomBy(0.5);
                  },
                  style:
                      OutlinedButton.styleFrom(
                    padding:
                        EdgeInsets.zero,
                  ),
                  child: const Icon(
                    Icons.zoom_in_rounded,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 48,
                child:
                    OutlinedButton(
                  onPressed:
                      _windowDurationUs >=
                              _maximumDetailedWindowUs ||
                          _windowDurationUs >=
                              _timelineDurationUs
                      ? null
                      : () {
                          _zoomBy(2.0);
                        },
                  style:
                      OutlinedButton.styleFrom(
                    padding:
                        EdgeInsets.zero,
                  ),
                  child: const Icon(
                    Icons.zoom_out_rounded,
                    size: 20,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: TextButton(
                  onPressed:
                      _resetWindow,
                  child: FittedBox(
                    fit:
                        BoxFit.scaleDown,
                    child: Text(
                      language.translate(
                        "reset",
                      ),
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  language.translate(
                    "samples",
                    <String, Object?>{
                      "count":
                          _samples.length,
                    },
                  ),
                  maxLines: 1,
                  overflow:
                      TextOverflow
                          .ellipsis,
                  textAlign:
                      TextAlign.right,
                  style:
                      Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(
                            color: scheme
                                .onSurfaceVariant,
                          ),
                ),
              ),
            ],
          ),
          if (_gaps.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              language.translate(
                "gaps_visible_range",
              ),
              style:
                  Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(
                        fontWeight:
                            FontWeight
                                .w600,
                      ),
            ),
            const SizedBox(height: 8),
            ..._gaps.map(
              (gap) => Padding(
                padding:
                    const EdgeInsets.only(
                  bottom: 8,
                ),
                child: _GapTile(
                  gap: gap,
                  formatDurationUs:
                      _formatDurationUs,
                  gapLabel:
                      language.translate(
                    "gap",
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          _TechnicalDetailsCard(
            title:
                language.translate(
              "technical_details",
            ),
            sampleRateLabel:
                language.translate(
              "sample_rate",
            ),
            samplesLabel:
                language.translate(
              "samples_label",
            ),
            coverageLabel:
                language.translate(
              "signal_coverage",
            ),
            measuredLabel:
                language.translate(
              "measured_label",
            ),
            timelineLabel:
                language.translate(
              "timeline",
            ),
            startedLabel:
                language.translate(
              "started",
            ),
            deviceLabel:
                language.translate(
              "device",
            ),
            disclaimer:
                language.translate(
              "rate_disclaimer",
            ),
            sampleRate:
                _sampleRate,
            sampleCount:
                sampleCount,
            timelineDurationUs:
                timelineUs,
            measuredDuration:
                _formatDuration(
              measuredDuration,
            ),
            timelineDuration:
                _formatDurationUs(
              timelineUs,
            ),
            started:
                _formatDateTime(
              startedAtMs,
            ),
            device:
                deviceName,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding:
                  const EdgeInsets.all(
                12,
              ),
              decoration:
                  BoxDecoration(
                color:
                    scheme.errorContainer,
                borderRadius:
                    BorderRadius.circular(
                  12,
                ),
              ),
              child: Text(
                _error!,
                style:
                    Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                          color: scheme
                              .onErrorContainer,
                        ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _localizedStatus(
    LanguageProvider language,
    String status,
  ) {
    switch (status) {
      case 'recording':
        return language.translate(
          "recording",
        );
      case 'paused':
        return language.translate(
          "paused",
        );
      case 'interrupted':
        return language.translate(
          "interrupted",
        );
      default:
        return language.translate(
          "completed",
        );
    }
  }
}

class _SignalViewer extends StatelessWidget {
  final List<_DecodedSample> samples;
  final List<_RecordingGap> gaps;
  final int windowStartUs;
  final int windowEndUs;
  final void Function(
    ScaleStartDetails details,
    double width,
  ) onScaleStart;
  final void Function(
    ScaleUpdateDetails details,
  ) onScaleUpdate;
  final String respirationTitle;

  const _SignalViewer({
    required this.samples,
    required this.gaps,
    required this.windowStartUs,
    required this.windowEndUs,
    required this.onScaleStart,
    required this.onScaleUpdate,
    required this.respirationTitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (details) {
            onScaleStart(
              details,
              constraints.maxWidth,
            );
          },
          onScaleUpdate: onScaleUpdate,
          child: Column(
            children: [
              _GraphCard(
                title: 'ECG',
                child: CustomPaint(
                  painter: _RecordingSignalPainter(
                    samples: samples,
                    gaps: gaps,
                    windowStartUs: windowStartUs,
                    windowEndUs: windowEndUs,
                    channel: _SignalChannel.ecg,
                    lineColor: scheme.primary,
                    gridColor: scheme.outlineVariant,
                    baselineColor: scheme.outlineVariant.withValues(
                      alpha: 0.75,
                    ),
                    gapColor: scheme.error.withValues(
                      alpha: 0.10,
                    ),
                  ),
                  size: const Size(
                    double.infinity,
                    230,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _GraphCard(
                title: respirationTitle,
                child: CustomPaint(
                  painter: _RecordingSignalPainter(
                    samples: samples,
                    gaps: gaps,
                    windowStartUs: windowStartUs,
                    windowEndUs: windowEndUs,
                    channel: _SignalChannel.respiration,
                    lineColor: scheme.tertiary,
                    gridColor: scheme.outlineVariant,
                    baselineColor: scheme.outlineVariant.withValues(
                      alpha: 0.75,
                    ),
                    gapColor: scheme.error.withValues(
                      alpha: 0.10,
                    ),
                  ),
                  size: const Size(
                    double.infinity,
                    180,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GraphCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _GraphCard({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        const SizedBox(height: 7),
        Container(
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: scheme.outlineVariant,
            ),
            color: scheme.surfaceContainer,
          ),
          child: child,
        ),
      ],
    );
  }
}

enum _IntervalEdge {
  start,
  end,
}

class _IntervalPickerSheet
    extends StatefulWidget {
  final int timelineUs;
  final int startUs;
  final int endUs;
  final int maximumIntervalUs;

  const _IntervalPickerSheet({
    required this.timelineUs,
    required this.startUs,
    required this.endUs,
    required this.maximumIntervalUs,
  });

  @override
  State<_IntervalPickerSheet> createState() =>
      _IntervalPickerSheetState();
}

class _IntervalPickerSheetState
    extends State<_IntervalPickerSheet> {
  late int _startSeconds;
  late int _endSeconds;
  _IntervalEdge _edge =
      _IntervalEdge.start;
  String? _errorKey;

  @override
  void initState() {
    super.initState();

    _startSeconds =
        widget.startUs ~/
        Duration.microsecondsPerSecond;

    _endSeconds =
        math.max(
      _startSeconds + 1,
      widget.endUs ~/
          Duration.microsecondsPerSecond,
    );
  }

  void _apply() {
    final startUs =
        _startSeconds *
        Duration.microsecondsPerSecond;
    final endUs =
        _endSeconds *
        Duration.microsecondsPerSecond;

    if (endUs <= startUs) {
      setState(() {
        _errorKey =
            "end_after_start";
      });
      return;
    }

    if (endUs >
        widget.timelineUs) {
      setState(() {
        _errorKey =
            "end_outside_recording";
      });
      return;
    }

    if (endUs - startUs >
        widget.maximumIntervalUs) {
      setState(() {
        _errorKey =
            "interval_too_long";
      });
      return;
    }

    Navigator.pop(
      context,
      _SelectedInterval(
        startUs: startUs,
        endUs: endUs,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final language =
        context.watch<LanguageProvider>();
    final maxSeconds = math.max(
      0,
      widget.timelineUs ~/
          Duration.microsecondsPerSecond,
    );

    final current =
        _edge == _IntervalEdge.start
            ? _startSeconds
            : _endSeconds;

    return SafeArea(
      top: false,
      child: Padding(
        padding:
            EdgeInsets.only(
          left: 16,
          right: 16,
          bottom:
              MediaQuery.of(context)
                      .viewInsets
                      .bottom +
                  16,
        ),
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Text(
              language.translate(
                "select_start_end",
              ),
              style:
                  Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(
                        fontWeight:
                            FontWeight.w600,
                      ),
            ),
            const SizedBox(height: 8),
            Text(
              '${language.translate(
                "recording_length",
                <String, Object?>{
                  "duration":
                      _formatPickerDuration(
                    maxSeconds,
                  ),
                },
              )} · 20 s max',
              textAlign:
                  TextAlign.center,
              style:
                  Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(
                        color: Theme.of(
                          context,
                        )
                            .colorScheme
                            .onSurfaceVariant,
                      ),
            ),
            const SizedBox(height: 14),
            CupertinoSlidingSegmentedControl<
                _IntervalEdge>(
              groupValue: _edge,
              children: {
                _IntervalEdge.start:
                    Padding(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  child: Text(
                    '${language.translate("start")}  ${_formatPickerDuration(_startSeconds)}',
                    maxLines: 1,
                  ),
                ),
                _IntervalEdge.end:
                    Padding(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  child: Text(
                    '${language.translate("end")}  ${_formatPickerDuration(_endSeconds)}',
                    maxLines: 1,
                  ),
                ),
              },
              onValueChanged: (value) {
                if (value == null) {
                  return;
                }

                setState(() {
                  _edge = value;
                  _errorKey = null;
                });
              },
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 176,
              child: _DurationWheelPicker(
                key: ValueKey(
                  _edge,
                ),
                valueSeconds: current,
                maximumSeconds:
                    maxSeconds,
                onChanged: (value) {
                  setState(() {
                    if (_edge ==
                        _IntervalEdge.start) {
                      _startSeconds =
                          value;
                    } else {
                      _endSeconds =
                          value;
                    }

                    _errorKey = null;
                  });
                },
              ),
            ),
            if (_errorKey != null) ...[
              const SizedBox(height: 8),
              Text(
                language.translate(
                  _errorKey!,
                ),
                textAlign:
                    TextAlign.center,
                style: TextStyle(
                  color:
                      Theme.of(context)
                          .colorScheme
                          .error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      Navigator.pop(
                        context,
                      );
                    },
                    child: FittedBox(
                      fit:
                          BoxFit.scaleDown,
                      child: Text(
                        language.translate(
                          "cancel",
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _apply,
                    child: FittedBox(
                      fit:
                          BoxFit.scaleDown,
                      child: Text(
                        language.translate(
                          "show_interval",
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DurationWheelPicker
    extends StatefulWidget {
  final int valueSeconds;
  final int maximumSeconds;
  final ValueChanged<int> onChanged;

  const _DurationWheelPicker({
    super.key,
    required this.valueSeconds,
    required this.maximumSeconds,
    required this.onChanged,
  });

  @override
  State<_DurationWheelPicker> createState() =>
      _DurationWheelPickerState();
}

class _DurationWheelPickerState
    extends State<_DurationWheelPicker> {
  late int _days;
  late int _hours;
  late int _minutes;
  late int _seconds;

  late FixedExtentScrollController
      _daysController;
  late FixedExtentScrollController
      _hoursController;
  late FixedExtentScrollController
      _minutesController;
  late FixedExtentScrollController
      _secondsController;

  int get _maximumDays =>
      math.max(
        0,
        widget.maximumSeconds ~/
            86400,
      );

  @override
  void initState() {
    super.initState();
    _setFromSeconds(
      widget.valueSeconds,
    );
    _createControllers();
  }

  void _setFromSeconds(
    int total,
  ) {
    final safe =
        total.clamp(
      0,
      widget.maximumSeconds,
    ).toInt();

    _days = safe ~/ 86400;
    _hours =
        (safe % 86400) ~/ 3600;
    _minutes =
        (safe % 3600) ~/ 60;
    _seconds =
        safe % 60;
  }

  void _createControllers() {
    _daysController =
        FixedExtentScrollController(
      initialItem: _days,
    );
    _hoursController =
        FixedExtentScrollController(
      initialItem: _hours,
    );
    _minutesController =
        FixedExtentScrollController(
      initialItem: _minutes,
    );
    _secondsController =
        FixedExtentScrollController(
      initialItem: _seconds,
    );
  }

  @override
  void dispose() {
    _daysController.dispose();
    _hoursController.dispose();
    _minutesController.dispose();
    _secondsController.dispose();
    super.dispose();
  }

  void _emit() {
    final total =
        (((_days * 24 + _hours) * 60 +
                    _minutes) *
                60 +
            _seconds)
            .clamp(
      0,
      widget.maximumSeconds,
    )
            .toInt();

    widget.onChanged(
      total,
    );
  }

  @override
  Widget build(BuildContext context) {
    final language =
        context.watch<LanguageProvider>();

    return Row(
      children: [
        _WheelColumn(
          controller:
              _daysController,
          itemCount:
              _maximumDays + 1,
          suffix:
              language.translate(
            "day_short",
          ),
          onChanged: (value) {
            _days = value;
            _emit();
          },
        ),
        _WheelColumn(
          controller:
              _hoursController,
          itemCount: 24,
          suffix:
              language.translate(
            "hour_short",
          ),
          onChanged: (value) {
            _hours = value;
            _emit();
          },
        ),
        _WheelColumn(
          controller:
              _minutesController,
          itemCount: 60,
          suffix:
              language.translate(
            "minute_short",
          ),
          onChanged: (value) {
            _minutes = value;
            _emit();
          },
        ),
        _WheelColumn(
          controller:
              _secondsController,
          itemCount: 60,
          suffix:
              language.translate(
            "second_short",
          ),
          onChanged: (value) {
            _seconds = value;
            _emit();
          },
        ),
      ],
    );
  }
}

class _WheelColumn
    extends StatelessWidget {
  final FixedExtentScrollController
      controller;
  final int itemCount;
  final String suffix;
  final ValueChanged<int> onChanged;

  const _WheelColumn({
    required this.controller,
    required this.itemCount,
    required this.suffix,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: CupertinoPicker.builder(
        scrollController:
            controller,
        itemExtent: 36,
        useMagnifier: true,
        magnification: 1.08,
        squeeze: 1.08,
        selectionOverlay:
            const CupertinoPickerDefaultSelectionOverlay(),
        onSelectedItemChanged:
            onChanged,
        childCount: itemCount,
        itemBuilder: (
          context,
          index,
        ) {
          return Center(
            child: FittedBox(
              fit:
                  BoxFit.scaleDown,
              child: Text(
                '$index $suffix',
                maxLines: 1,
              ),
            ),
          );
        },
      ),
    );
  }
}

String _formatPickerDuration(
  int totalSeconds,
) {
  final days =
      totalSeconds ~/ 86400;
  final hours =
      (totalSeconds % 86400) ~/ 3600;
  final minutes =
      (totalSeconds % 3600) ~/ 60;
  final seconds =
      totalSeconds % 60;

  String two(
    int value,
  ) =>
      value
          .toString()
          .padLeft(2, '0');

  if (days > 0) {
    return '${days}d ${two(hours)}:${two(minutes)}:${two(seconds)}';
  }

  return '${two(hours)}:${two(minutes)}:${two(seconds)}';
}

class _SelectedInterval {
  final int startUs;
  final int endUs;

  const _SelectedInterval({
    required this.startUs,
    required this.endUs,
  });
}

enum _ViewerAction {
  exportApex,
  exportCsv,
  sharePdf,
  printPdf,
}

enum _SignalChannel {
  ecg,
  respiration,
}

class _RecordingSignalPainter extends CustomPainter {
  final List<_DecodedSample> samples;
  final List<_RecordingGap> gaps;
  final int windowStartUs;
  final int windowEndUs;
  final _SignalChannel channel;
  final Color lineColor;
  final Color gridColor;
  final Color baselineColor;
  final Color gapColor;

  const _RecordingSignalPainter({
    required this.samples,
    required this.gaps,
    required this.windowStartUs,
    required this.windowEndUs,
    required this.channel,
    required this.lineColor,
    required this.gridColor,
    required this.baselineColor,
    required this.gapColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final durationUs = windowEndUs - windowStartUs;

    if (durationUs <= 0 ||
        size.width <= 0 ||
        size.height <= 0) {
      return;
    }

    _paintGrid(
      canvas,
      size,
      durationUs,
    );

    _paintGaps(
      canvas,
      size,
      durationUs,
    );

    if (samples.isEmpty) {
      return;
    }

    final values = <double>[];

    for (final sample in samples) {
      values.add(
        channel == _SignalChannel.ecg
            ? sample.ecg
            : sample.respiration,
      );
    }

    final center = _median(values);
    final scale = _robustScale(
      values,
      center,
    );

    final path = Path();
    bool started = false;

    final maxPoints =
        math.max(400, (size.width * 3).round());

    final stride = math.max(
      1,
      (samples.length / maxPoints).floor(),
    );

    for (int index = 0;
        index < samples.length;
        index += stride) {
      final sample = samples[index];

      final x = (
        (sample.elapsedUs - windowStartUs) /
        durationUs *
        size.width
      ).clamp(0.0, size.width);

      final value = channel == _SignalChannel.ecg
          ? sample.ecg
          : sample.respiration;

      final normalized = (
        (value - center) / scale
      ).clamp(-1.0, 1.0);

      final y =
          size.height / 2 -
          normalized * size.height * 0.42;

      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    canvas.drawPath(path, paint);
  }

  void _paintGrid(
    Canvas canvas,
    Size size,
    int durationUs,
  ) {
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.45)
      ..strokeWidth = 0.7;

    final baselinePaint = Paint()
      ..color = baselineColor
      ..strokeWidth = 1.0;

    for (int i = 1; i < 5; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    final seconds =
        durationUs / 1000000.0;

    final verticalCount = seconds <= 5
        ? 5
        : seconds <= 20
            ? 10
            : 12;

    for (int i = 1; i < verticalCount; i++) {
      final x = size.width * i / verticalCount;

      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        gridPaint,
      );
    }

    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      baselinePaint,
    );
  }

  void _paintGaps(
    Canvas canvas,
    Size size,
    int durationUs,
  ) {
    if (gaps.isEmpty) {
      return;
    }

    final paint = Paint()
      ..color = gapColor
      ..style = PaintingStyle.fill;

    for (final gap in gaps) {
      final gapStart = math.max(
        gap.startElapsedUs,
        windowStartUs,
      );

      final gapEnd = math.min(
        gap.endElapsedUs ?? windowEndUs,
        windowEndUs,
      );

      if (gapEnd <= gapStart) {
        continue;
      }

      final left = (
        (gapStart - windowStartUs) /
        durationUs *
        size.width
      ).clamp(0.0, size.width);

      final right = (
        (gapEnd - windowStartUs) /
        durationUs *
        size.width
      ).clamp(0.0, size.width);

      canvas.drawRect(
        Rect.fromLTRB(
          left,
          0,
          right,
          size.height,
        ),
        paint,
      );
    }
  }

  double _median(List<double> values) {
    if (values.isEmpty) {
      return 0;
    }

    final sorted = List<double>.from(values)
      ..sort();

    final middle = sorted.length ~/ 2;

    if (sorted.length.isOdd) {
      return sorted[middle];
    }

    return (
      sorted[middle - 1] +
      sorted[middle]
    ) / 2.0;
  }

  double _robustScale(
    List<double> values,
    double center,
  ) {
    if (values.isEmpty) {
      return 1;
    }

    final deviations = values
        .map((value) => (value - center).abs())
        .toList()
      ..sort();

    final index = (
      (deviations.length - 1) * 0.97
    ).round().clamp(
          0,
          deviations.length - 1,
        );

    final amplitude = deviations[index];

    if (!amplitude.isFinite ||
        amplitude < 1.0) {
      return 1.0;
    }

    return amplitude * 1.15;
  }

  @override
  bool shouldRepaint(
    covariant _RecordingSignalPainter oldDelegate,
  ) {
    return oldDelegate.samples != samples ||
        oldDelegate.gaps != gaps ||
        oldDelegate.windowStartUs != windowStartUs ||
        oldDelegate.windowEndUs != windowEndUs ||
        oldDelegate.channel != channel ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.baselineColor != baselineColor ||
        oldDelegate.gapColor != gapColor;
  }
}

class _ViewerMetrics {
  final double? estimatedHeartRateBpm;
  final double? estimatedMeanRrMs;
  final double? estimatedRespirationRateBpm;
  final double? estimatedMeanBreathMs;
  final int analyzedSamples;

  const _ViewerMetrics({
    required this.estimatedHeartRateBpm,
    required this.estimatedMeanRrMs,
    required this.estimatedRespirationRateBpm,
    required this.estimatedMeanBreathMs,
    required this.analyzedSamples,
  });
}

class _ViewerRateEstimate {
  final double? rateBpm;
  final double? intervalMs;

  const _ViewerRateEstimate({
    required this.rateBpm,
    required this.intervalMs,
  });
}

class _DecodedSample {
  final int elapsedUs;
  final double ecg;
  final double respiration;

  const _DecodedSample({
    required this.elapsedUs,
    required this.ecg,
    required this.respiration,
  });
}

class _RecordingGap {
  final int id;
  final int startElapsedUs;
  final int? endElapsedUs;
  final String reason;
  final String? details;

  const _RecordingGap({
    required this.id,
    required this.startElapsedUs,
    required this.endElapsedUs,
    required this.reason,
    required this.details,
  });

  factory _RecordingGap.fromRow(
    Map<String, Object?> row,
  ) {
    return _RecordingGap(
      id: row['id'] as int,
      startElapsedUs:
          row['start_elapsed_us'] as int? ?? 0,
      endElapsedUs:
          row['end_elapsed_us'] as int?,
      reason:
          row['reason'] as String? ?? 'unknown',
      details:
          row['details'] as String?,
    );
  }

  String get label {
    switch (reason) {
      case 'paused':
        return 'Paused';
      case 'bluetooth_disconnected':
        return 'Bluetooth disconnected';
      default:
        return reason;
    }
  }
}

class _GapTile extends StatelessWidget {
  final _RecordingGap gap;
  final String Function(int microseconds) formatDurationUs;
  final String gapLabel;

  const _GapTile({
    required this.gap,
    required this.formatDurationUs,
    required this.gapLabel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme =
        Theme.of(context).colorScheme;
    final language =
        context.watch<LanguageProvider>();
    final end =
        gap.endElapsedUs;

    final label =
        gap.reason == 'paused'
            ? language.translate(
                "paused",
              )
            : gap.reason ==
                    'bluetooth_disconnected'
                ? language.translate(
                    "signal_gap",
                  )
                : gapLabel;

    return Container(
      padding:
          const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            scheme.surfaceContainer,
        borderRadius:
            BorderRadius.circular(12),
        border: Border.all(
          color:
              scheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 34,
            decoration:
                BoxDecoration(
              borderRadius:
                  BorderRadius.circular(
                4,
              ),
              color:
                  gap.reason ==
                          'paused'
                      ? scheme.tertiary
                      : scheme.error,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
              children: [
                Text(
                  label,
                  style:
                      Theme.of(context)
                          .textTheme
                          .labelLarge,
                ),
                const SizedBox(
                  height: 3,
                ),
                Text(
                  end == null
                      ? '${formatDurationUs(gap.startElapsedUs)} → ${language.translate("open")}'
                      : '${formatDurationUs(gap.startElapsedUs)} → ${formatDurationUs(end)}',
                  style:
                      Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color: scheme
                                .onSurfaceVariant,
                            fontFeatures:
                                const [
                              FontFeature
                                  .tabularFigures(),
                            ],
                          ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VitalsCard extends StatelessWidget {
  final _ViewerMetrics? metrics;
  final bool loading;
  final String averageLabel;
  final String rrLabel;
  final String breathLabel;

  const _VitalsCard({
    required this.metrics,
    required this.loading,
    required this.averageLabel,
    required this.rrLabel,
    required this.breathLabel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme =
        Theme.of(context).colorScheme;

    final heart =
        metrics?.estimatedHeartRateBpm;
    final respiration =
        metrics
            ?.estimatedRespirationRateBpm;
    final rr =
        metrics?.estimatedMeanRrMs;
    final breath =
        metrics
            ?.estimatedMeanBreathMs;

    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.fromLTRB(
        8,
        12,
        8,
        10,
      ),
      decoration: BoxDecoration(
        color:
            scheme.surfaceContainer,
        borderRadius:
            BorderRadius.circular(14),
        border: Border.all(
          color:
              scheme.outlineVariant,
        ),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 74,
            child: Row(
              children: [
                Expanded(
                  child: _VitalValue(
                    value: loading
                        ? '...'
                        : heart == null
                            ? '--'
                            : heart
                                .round()
                                .toString(),
                    unit: 'BPM',
                    label:
                        averageLabel,
                    accent:
                        const Color(
                      0xFFE74C4C,
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 46,
                  color: scheme
                      .outlineVariant,
                ),
                Expanded(
                  child: _VitalValue(
                    value: loading
                        ? '...'
                        : respiration ==
                                null
                            ? '--'
                            : respiration
                                .round()
                                .toString(),
                    unit: 'BRPM',
                    label:
                        averageLabel,
                    accent:
                        scheme.primary,
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 12,
            color:
                scheme.outlineVariant,
          ),
          Row(
            children: [
              Expanded(
                child: _SmallMetric(
                  label: rrLabel,
                  value: rr == null
                      ? '--'
                      : '${rr.toStringAsFixed(0)} ms',
                ),
              ),
              Container(
                width: 1,
                height: 24,
                color: scheme
                    .outlineVariant,
              ),
              Expanded(
                child: _SmallMetric(
                  label:
                      breathLabel,
                  value: breath == null
                      ? '--'
                      : '${breath.toStringAsFixed(0)} ms',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SmallMetric extends StatelessWidget {
  final String label;
  final String value;

  const _SmallMetric({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final scheme =
        Theme.of(context).colorScheme;

    return Padding(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow:
                  TextOverflow.ellipsis,
              style:
                  Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(
                        color: scheme
                            .onSurfaceVariant,
                      ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style:
                Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(
                      fontWeight:
                          FontWeight.w600,
                    ),
          ),
        ],
      ),
    );
  }
}

class _RecordingContextCard
    extends StatelessWidget {
  final String statusLabel;
  final String notesLabel;
  final String status;
  final String? notes;

  const _RecordingContextCard({
    required this.statusLabel,
    required this.notesLabel,
    required this.status,
    required this.notes,
  });

  @override
  Widget build(BuildContext context) {
    final scheme =
        Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.fromLTRB(
        14,
        12,
        14,
        12,
      ),
      decoration: BoxDecoration(
        color:
            scheme.surfaceContainer,
        borderRadius:
            BorderRadius.circular(14),
        border: Border.all(
          color:
              scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                statusLabel,
                style:
                    Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(
                          color: scheme
                              .onSurfaceVariant,
                        ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration:
                    BoxDecoration(
                  borderRadius:
                      BorderRadius.circular(
                    999,
                  ),
                  color: scheme.primary
                      .withValues(
                    alpha: 0.10,
                  ),
                ),
                child: Text(
                  status,
                  style:
                      Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(
                            fontWeight:
                                FontWeight
                                    .w600,
                            color:
                                scheme.primary,
                          ),
                ),
              ),
            ],
          ),
          if (notes != null &&
              notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              notesLabel,
              style:
                  Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(
                        color: scheme
                            .onSurfaceVariant,
                      ),
            ),
            const SizedBox(height: 4),
            Text(
              notes!,
              style:
                  Theme.of(context)
                      .textTheme
                      .bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

class _VitalValue extends StatelessWidget {
  final String value;
  final String unit;
  final String label;
  final Color accent;

  const _VitalValue({
    required this.value,
    required this.unit,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final muted =
        Theme.of(context)
            .colorScheme
            .onSurfaceVariant;

    return Padding(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 10,
      ),
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment:
                CrossAxisAlignment.end,
            children: [
              Container(
                width: 7,
                height: 7,
                margin:
                    const EdgeInsets.only(
                  right: 7,
                  bottom: 5,
                ),
                decoration:
                    BoxDecoration(
                  shape:
                      BoxShape.circle,
                  color: accent,
                ),
              ),
              Flexible(
                child: FittedBox(
                  fit:
                      BoxFit.scaleDown,
                  alignment:
                      Alignment
                          .centerLeft,
                  child: Row(
                    crossAxisAlignment:
                        CrossAxisAlignment
                            .end,
                    children: [
                      Text(
                        value,
                        style:
                            Theme.of(
                          context,
                        )
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  fontWeight:
                                      FontWeight
                                          .w600,
                                  height:
                                      1,
                                ),
                      ),
                      const SizedBox(
                        width: 4,
                      ),
                      Padding(
                        padding:
                            const EdgeInsets
                                .only(
                          bottom: 3,
                        ),
                        child: Text(
                          unit,
                          style:
                              Theme.of(
                            context,
                          )
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color:
                                        muted,
                                  ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow:
                TextOverflow.ellipsis,
            style:
                Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(
                      color: muted,
                    ),
          ),
        ],
      ),
    );
  }
}

class _IntervalSelector
    extends StatelessWidget {
  final String title;
  final String start;
  final String end;
  final String changeLabel;
  final VoidCallback onChange;

  const _IntervalSelector({
    required this.title,
    required this.start,
    required this.end,
    required this.changeLabel,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final scheme =
        Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.fromLTRB(
        14,
        11,
        10,
        11,
      ),
      decoration: BoxDecoration(
        color:
            scheme.surfaceContainer,
        borderRadius:
            BorderRadius.circular(14),
        border: Border.all(
          color:
              scheme.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
              children: [
                Text(
                  title,
                  style:
                      Theme.of(
                    context,
                  )
                          .textTheme
                          .labelMedium
                          ?.copyWith(
                            color: scheme
                                .onSurfaceVariant,
                          ),
                ),
                const SizedBox(
                  height: 3,
                ),
                Text(
                  '$start  →  $end',
                  maxLines: 1,
                  overflow:
                      TextOverflow
                          .ellipsis,
                  style:
                      Theme.of(
                    context,
                  )
                          .textTheme
                          .titleSmall
                          ?.copyWith(
                            fontWeight:
                                FontWeight
                                    .w600,
                            fontFeatures:
                                const [
                              FontFeature
                                  .tabularFigures(),
                            ],
                          ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onChange,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child:
                  Text(changeLabel),
            ),
          ),
        ],
      ),
    );
  }
}

class _TechnicalDetailsCard
    extends StatelessWidget {
  final String title;
  final String sampleRateLabel;
  final String samplesLabel;
  final String coverageLabel;
  final String measuredLabel;
  final String timelineLabel;
  final String startedLabel;
  final String deviceLabel;
  final String disclaimer;
  final double sampleRate;
  final int sampleCount;
  final int timelineDurationUs;
  final String measuredDuration;
  final String timelineDuration;
  final String started;
  final String? device;

  const _TechnicalDetailsCard({
    required this.title,
    required this.sampleRateLabel,
    required this.samplesLabel,
    required this.coverageLabel,
    required this.measuredLabel,
    required this.timelineLabel,
    required this.startedLabel,
    required this.deviceLabel,
    required this.disclaimer,
    required this.sampleRate,
    required this.sampleCount,
    required this.timelineDurationUs,
    required this.measuredDuration,
    required this.timelineDuration,
    required this.started,
    required this.device,
  });

  @override
  Widget build(BuildContext context) {
    final scheme =
        Theme.of(context).colorScheme;

    final timelineSeconds =
        timelineDurationUs /
        Duration
            .microsecondsPerSecond;

    final measuredSeconds =
        sampleRate <= 0
            ? 0.0
            : sampleCount /
                sampleRate;

    final coverage =
        timelineSeconds <= 0
            ? 0.0
            : (measuredSeconds /
                    timelineSeconds *
                    100)
                .clamp(
                  0.0,
                  100.0,
                );

    final rows =
        <MapEntry<String, String>>[
      MapEntry(
        sampleRateLabel,
        '${sampleRate.toStringAsFixed(0)} Hz',
      ),
      MapEntry(
        samplesLabel,
        _formatCount(
          sampleCount,
        ),
      ),
      MapEntry(
        coverageLabel,
        '${coverage.toStringAsFixed(1)}%',
      ),
      MapEntry(
        measuredLabel,
        measuredDuration,
      ),
      MapEntry(
        timelineLabel,
        timelineDuration,
      ),
      MapEntry(
        startedLabel,
        started,
      ),
      MapEntry(
        deviceLabel,
        device == null ||
                device!.trim().isEmpty
            ? '--'
            : device!,
      ),
    ];

    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.fromLTRB(
        16,
        15,
        16,
        14,
      ),
      decoration: BoxDecoration(
        color:
            scheme.surfaceContainer,
        borderRadius:
            BorderRadius.circular(14),
        border: Border.all(
          color:
              scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style:
                Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(
                      fontWeight:
                          FontWeight.w600,
                    ),
          ),
          const SizedBox(height: 8),
          ...rows.map(
            (entry) =>
                _TechnicalRow(
              label: entry.key,
              value: entry.value,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            disclaimer,
            style:
                Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(
                      color: scheme
                          .onSurfaceVariant,
                    ),
          ),
        ],
      ),
    );
  }

  static String _formatCount(
    int count,
  ) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(2)}M';
    }

    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }

    return '$count';
  }
}

class _TechnicalRow
    extends StatelessWidget {
  final String label;
  final String value;

  const _TechnicalRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final scheme =
        Theme.of(context).colorScheme;

    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 6,
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style:
                  Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(
                        color: scheme
                            .onSurfaceVariant,
                      ),
            ),
          ),
          const SizedBox(width: 14),
          Flexible(
            child: Text(
              value,
              textAlign:
                  TextAlign.right,
              style:
                  Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(
                        fontWeight:
                            FontWeight
                                .w600,
                      ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewerActionRow
    extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ViewerActionRow({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme =
        Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(
          vertical: 14,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color:
                  scheme.outlineVariant,
            ),
          ),
        ),
        child: Text(
          label,
          maxLines: 2,
          overflow:
              TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorBody({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final scheme =
        Theme.of(context).colorScheme;
    final language =
        context.watch<LanguageProvider>();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 3,
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.circular(
                  4,
                ),
                color: scheme.error,
              ),
            ),
            const SizedBox(
              height: 14,
            ),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: Text(
                language.translate(
                  "retry",
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
