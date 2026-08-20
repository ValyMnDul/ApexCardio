import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/recording_database.dart';
import '../services/recording_export_service.dart';
import '../services/recording_report_service.dart';

class RecordingViewer extends StatefulWidget {
  final int recordingId;

  const RecordingViewer({super.key, required this.recordingId});

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

  double _sampleRate = 250.0;

  Timer? _windowLoadDebounce;
  int _windowRequestSerial = 0;

  double _gestureWidth = 1.0;
  int _gestureStartWindowUs = 0;
  int _gestureStartDurationUs = 10 * 1000000;
  double _gestureStartFocalX = 0.0;
  int _gestureAnchorTimeUs = 0;

  static const int _minimumWindowUs = 2 * 1000000;
  static const int _maximumDetailedWindowUs = 5 * 60 * 1000000;

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
    return math.min(_timelineDurationUs, _windowStartUs + _windowDurationUs);
  }

  Future<void> _loadRecording() async {
    setState(() {
      _loadingRecording = true;
      _error = null;
    });

    try {
      final recording = await _database.getRecordingById(widget.recordingId);

      if (recording == null) {
        throw StateError('Recording not found.');
      }

      final timelineDurationUs = recording['timeline_duration_us'] as int? ?? 0;

      final sampleRate =
          (recording['sample_rate'] as num?)?.toDouble() ?? 250.0;

      final initialWindow = timelineDurationUs <= 0
          ? 10 * 1000000
          : math.min(timelineDurationUs, 10 * 1000000);

      if (!mounted) {
        return;
      }

      setState(() {
        _recording = recording;
        _timelineDurationUs = timelineDurationUs;
        _sampleRate = sampleRate > 0 ? sampleRate : 250.0;
        _windowStartUs = 0;
        _windowDurationUs = math.max(_minimumWindowUs, initialWindow);
        _loadingRecording = false;
      });

      await Future.wait<void>([_loadVisibleWindow(), _loadOverviewMetrics()]);
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
      final db = await _database.database;
      final ecgValues = <double>[];
      final respirationValues = <double>[];

      const analysisMaxSamples = 75000;
      const chunkPageSize = 300;

      var lastChunkIndex = -1;

      while (ecgValues.length < analysisMaxSamples) {
        final rows = await db.query(
          'signal_chunks',
          where: 'recording_id = ? AND chunk_index > ?',
          whereArgs: <Object?>[widget.recordingId, lastChunkIndex],
          orderBy: 'chunk_index ASC',
          limit: chunkPageSize,
        );

        if (rows.isEmpty) {
          break;
        }

        for (final row in rows) {
          lastChunkIndex = row['chunk_index'] as int? ?? lastChunkIndex;

          final sampleCount = row['sample_count'] as int? ?? 0;
          final raw = row['signal_data'];

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

          for (int i = 0; i < sampleCount; i++) {
            if (ecgValues.length >= analysisMaxSamples) {
              break;
            }

            final offset = i * 8;

            ecgValues.add(data.getInt32(offset, Endian.little).toDouble());

            respirationValues.add(
              data.getInt32(offset + 4, Endian.little).toDouble(),
            );
          }
        }
      }

      final heart = _estimateRate(
        values: ecgValues,
        sampleRate: _sampleRate,
        minimumDistanceSeconds: 0.28,
        thresholdMultiplier: 0.95,
        smoothingRadius: 2,
      );

      final respiration = _estimateRate(
        values: respirationValues,
        sampleRate: _sampleRate,
        minimumDistanceSeconds: 1.20,
        thresholdMultiplier: 0.30,
        smoothingRadius: 8,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _metrics = _ViewerMetrics(
          estimatedHeartRateBpm: heart.rateBpm,
          estimatedMeanRrMs: heart.intervalMs,
          estimatedRespirationRateBpm: respiration.rateBpm,
          estimatedMeanBreathMs: respiration.intervalMs,
          analyzedSamples: ecgValues.length,
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
      return const _ViewerRateEstimate(rateBpm: null, intervalMs: null);
    }

    final smoothed = _smoothValues(values, radius: smoothingRadius);

    final mean = smoothed.reduce((a, b) => a + b) / smoothed.length;

    var variance = 0.0;

    for (final value in smoothed) {
      final difference = value - mean;
      variance += difference * difference;
    }

    variance /= smoothed.length;
    final standardDeviation = math.sqrt(variance);

    if (!standardDeviation.isFinite || standardDeviation <= 0) {
      return const _ViewerRateEstimate(rateBpm: null, intervalMs: null);
    }

    final threshold = mean + standardDeviation * thresholdMultiplier;

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
        if (peaks.isNotEmpty && current > smoothed[peaks.last]) {
          peaks[peaks.length - 1] = i;
          lastPeak = i;
        }

        continue;
      }

      peaks.add(i);
      lastPeak = i;
    }

    if (peaks.length < 2) {
      return const _ViewerRateEstimate(rateBpm: null, intervalMs: null);
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
      return const _ViewerRateEstimate(rateBpm: null, intervalMs: null);
    }

    final averageIntervalSeconds = intervalSumSeconds / intervalCount;

    if (!averageIntervalSeconds.isFinite || averageIntervalSeconds <= 0) {
      return const _ViewerRateEstimate(rateBpm: null, intervalMs: null);
    }

    return _ViewerRateEstimate(
      rateBpm: 60.0 / averageIntervalSeconds,
      intervalMs: averageIntervalSeconds * 1000,
    );
  }

  List<double> _smoothValues(List<double> values, {required int radius}) {
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

      output[i] = (prefix[end + 1] - prefix[start]) / (end - start + 1);
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

      final chunks = results[0] as List<Map<String, Object?>>;
      final gapRows = results[1] as List<Map<String, Object?>>;

      final decoded = _decodeChunks(chunks, startUs, endUs);

      final gaps = gapRows.map(_RecordingGap.fromRow).toList(growable: false);

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
      final encodingVersion = chunk['encoding_version'] as int? ?? 1;

      if (encodingVersion != 1) {
        continue;
      }

      final sampleCount = chunk['sample_count'] as int? ?? 0;

      final chunkStartUs = chunk['start_elapsed_us'] as int? ?? 0;

      final raw = chunk['signal_data'];

      final bytes = switch (raw) {
        Uint8List value => value,
        List<int> value => Uint8List.fromList(value),
        _ => null,
      };

      if (bytes == null || sampleCount <= 0 || bytes.length < sampleCount * 8) {
        continue;
      }

      final data = ByteData.sublistView(bytes);

      for (int index = 0; index < sampleCount; index++) {
        final elapsedUs = chunkStartUs + (index * samplePeriodUs).round();

        if (elapsedUs < visibleStartUs) {
          continue;
        }

        if (elapsedUs >= visibleEndUs) {
          break;
        }

        final offset = index * 8;

        final ecg = data.getInt32(offset, Endian.little);

        final respiration = data.getInt32(offset + 4, Endian.little);

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

  void _onScaleStart(ScaleStartDetails details, double width) {
    _gestureWidth = math.max(width, 1.0);
    _gestureStartWindowUs = _windowStartUs;
    _gestureStartDurationUs = _windowDurationUs;
    _gestureStartFocalX = details.localFocalPoint.dx.clamp(0.0, _gestureWidth);

    final fraction = _gestureStartFocalX / _gestureWidth;

    _gestureAnchorTimeUs =
        (_gestureStartWindowUs + fraction * _gestureStartDurationUs).round();
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_timelineDurationUs <= 0) {
      return;
    }

    final maxWindow = math.max(
      _minimumWindowUs,
      math.min(_timelineDurationUs, _maximumDetailedWindowUs),
    );

    final newDuration =
        (_gestureStartDurationUs / math.max(details.scale, 0.01)).round().clamp(
          _minimumWindowUs,
          maxWindow,
        );

    final currentFocalX = details.localFocalPoint.dx.clamp(0.0, _gestureWidth);

    final focalFraction = currentFocalX / _gestureWidth;

    var newStart = (_gestureAnchorTimeUs - focalFraction * newDuration).round();

    newStart = _clampWindowStart(newStart, newDuration);

    if (newStart == _windowStartUs && newDuration == _windowDurationUs) {
      return;
    }

    setState(() {
      _windowStartUs = newStart;
      _windowDurationUs = newDuration;
    });

    _scheduleWindowLoad();
  }

  int _clampWindowStart(int startUs, int durationUs) {
    final maximumStart = math.max(0, _timelineDurationUs - durationUs);

    return startUs.clamp(0, maximumStart);
  }

  void _zoomBy(double factor) {
    if (_timelineDurationUs <= 0) {
      return;
    }

    final maxWindow = math.max(
      _minimumWindowUs,
      math.min(_timelineDurationUs, _maximumDetailedWindowUs),
    );

    final center = _windowStartUs + _windowDurationUs / 2;

    final newDuration = (_windowDurationUs * factor).round().clamp(
      _minimumWindowUs,
      maxWindow,
    );

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

    final duration = math.min(_timelineDurationUs, 10 * 1000000);

    setState(() {
      _windowDurationUs = math.max(_minimumWindowUs, duration);
      _windowStartUs = 0;
    });

    _scheduleWindowLoad();
  }

  void _jumpToTimelineFraction(double fraction) {
    if (_timelineDurationUs <= 0) {
      return;
    }

    final targetUs = (_timelineDurationUs * fraction).round();

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
        ..showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Action failed: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _workingAction = false;
        });
      }
    }
  }

  Future<void> _exportApex() async {
    await _runViewerAction(() async {
      await RecordingExportService.instance.export(
        recordingId: widget.recordingId,
        format: RecordingExportFormat.apex,
      );
    }, successMessage: 'Apex recording export opened');
  }

  Future<void> _exportCsv() async {
    await _runViewerAction(() async {
      await RecordingExportService.instance.export(
        recordingId: widget.recordingId,
        format: RecordingExportFormat.csv,
      );
    }, successMessage: 'CSV export opened');
  }

  Future<void> _sharePdfReport() async {
    final box = context.findRenderObject() as RenderBox?;

    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;

    await _runViewerAction(() async {
      await RecordingReportService.instance.shareReport(
        recordingId: widget.recordingId,
        sharePositionOrigin: origin,
      );
    }, successMessage: 'PDF report ready');
  }

  Future<void> _printPdfReport() async {
    await _runViewerAction(() async {
      await RecordingReportService.instance.printReport(
        recordingId: widget.recordingId,
      );
    }, successMessage: 'Print dialog opened');
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

    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit recording'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: notesController,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    hintText: 'Optional',
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
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Save'),
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
    return _formatDuration(Duration(microseconds: microseconds));
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
    final date = DateTime.fromMillisecondsSinceEpoch(milliseconds);

    return '${date.year}-${_two(date.month)}-${_two(date.day)} '
        '${_two(date.hour)}:${_two(date.minute)}:${_two(date.second)}';
  }

  String _two(int value) {
    return value.toString().padLeft(2, '0');
  }

  @override
  Widget build(BuildContext context) {
    final recording = _recording;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          recording?['name'] as String? ?? 'Recording',
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
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          TextButton(
            onPressed: recording == null || _workingAction
                ? null
                : _editDetails,
            child: const Text('Edit'),
          ),
          PopupMenuButton<_ViewerAction>(
            enabled: recording != null && !_workingAction,
            tooltip: 'Recording actions',
            onSelected: (action) {
              switch (action) {
                case _ViewerAction.exportApex:
                  _exportApex();
                  break;
                case _ViewerAction.exportCsv:
                  _exportCsv();
                  break;
                case _ViewerAction.sharePdf:
                  _sharePdfReport();
                  break;
                case _ViewerAction.printPdf:
                  _printPdfReport();
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _ViewerAction.sharePdf,
                child: Text('Generate / Share PDF'),
              ),
              PopupMenuItem(
                value: _ViewerAction.printPdf,
                child: Text('Print PDF report'),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: _ViewerAction.exportApex,
                child: Text('Export .apex'),
              ),
              PopupMenuItem(
                value: _ViewerAction.exportCsv,
                child: Text('Export CSV'),
              ),
            ],
          ),
        ],
      ),
      body: _loadingRecording
          ? const Center(child: CircularProgressIndicator())
          : _error != null && recording == null
          ? _ErrorBody(message: _error!, onRetry: _loadRecording)
          : recording == null
          ? const Center(child: Text('Recording not found'))
          : _buildContent(context, recording),
    );
  }

  Widget _buildContent(BuildContext context, Map<String, Object?> recording) {
    final scheme = Theme.of(context).colorScheme;
    final startedAtMs = recording['started_at_ms'] as int? ?? 0;
    final timelineUs = recording['timeline_duration_us'] as int? ?? 0;
    final sampleCount = recording['recorded_sample_count'] as int? ?? 0;
    final status = recording['status'] as String? ?? 'completed';
    final notes = recording['notes'] as String?;

    final measuredDuration = Duration(
      microseconds: (sampleCount / _sampleRate * 1000000).round(),
    );

    return RefreshIndicator(
      onRefresh: _loadRecording,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _RecordingOverview(
            startedAt: _formatDateTime(startedAtMs),
            timelineDuration: _formatDurationUs(timelineUs),
            measuredDuration: _formatDuration(measuredDuration),
            timelineDurationUs: timelineUs,
            sampleRate: _sampleRate,
            sampleCount: sampleCount,
            status: status,
            notes: notes,
            metrics: _metrics,
            loadingMetrics: _loadingMetrics,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'Signal viewer',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (_loadingWindow)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_formatDurationUs(_windowStartUs)} → '
            '${_formatDurationUs(_windowEndUs)}'
            '   •   ${(_windowDurationUs / 1000000).toStringAsFixed(1)} s visible',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          _SignalViewer(
            samples: _samples,
            gaps: _gaps,
            windowStartUs: _windowStartUs,
            windowEndUs: _windowEndUs,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 44,
                child: OutlinedButton(
                  onPressed: () {
                    _zoomBy(0.5);
                  },
                  child: const Text('+'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 44,
                child: OutlinedButton(
                  onPressed: () {
                    _zoomBy(2.0);
                  },
                  child: const Text('−'),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(onPressed: _resetWindow, child: const Text('Reset')),
              const Spacer(),
              Text(
                '${_samples.length} samples',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (_timelineDurationUs > 0) ...[
            const SizedBox(height: 4),
            Slider(
              min: 0,
              max: 1,
              value:
                  ((_windowStartUs + _windowDurationUs / 2) /
                          _timelineDurationUs)
                      .clamp(0.0, 1.0),
              onChanged: _jumpToTimelineFraction,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Text(
                    '00:00',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _formatDurationUs(_timelineDurationUs),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_gaps.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'Gaps in visible range',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ..._gaps.map(
              (gap) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _GapTile(gap: gap, formatDurationUs: _formatDurationUs),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _error!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SignalViewer extends StatelessWidget {
  final List<_DecodedSample> samples;
  final List<_RecordingGap> gaps;
  final int windowStartUs;
  final int windowEndUs;
  final void Function(ScaleStartDetails details, double width) onScaleStart;
  final void Function(ScaleUpdateDetails details) onScaleUpdate;

  const _SignalViewer({
    required this.samples,
    required this.gaps,
    required this.windowStartUs,
    required this.windowEndUs,
    required this.onScaleStart,
    required this.onScaleUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (details) {
            onScaleStart(details, constraints.maxWidth);
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
                    gapColor: scheme.error.withValues(alpha: 0.10),
                  ),
                  size: const Size(double.infinity, 230),
                ),
              ),
              const SizedBox(height: 14),
              _GraphCard(
                title: 'Respiration',
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
                    gapColor: scheme.error.withValues(alpha: 0.10),
                  ),
                  size: const Size(double.infinity, 180),
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

  const _GraphCard({required this.title, required this.child});

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
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 7),
        Container(
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
            color: scheme.surfaceContainer,
          ),
          child: child,
        ),
      ],
    );
  }
}

enum _ViewerAction { exportApex, exportCsv, sharePdf, printPdf }

enum _SignalChannel { ecg, respiration }

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

    if (durationUs <= 0 || size.width <= 0 || size.height <= 0) {
      return;
    }

    _paintGrid(canvas, size, durationUs);

    _paintGaps(canvas, size, durationUs);

    if (samples.isEmpty) {
      return;
    }

    final values = <double>[];

    for (final sample in samples) {
      values.add(
        channel == _SignalChannel.ecg ? sample.ecg : sample.respiration,
      );
    }

    final center = _median(values);
    final scale = _robustScale(values, center);

    final path = Path();
    bool started = false;

    final maxPoints = math.max(400, (size.width * 3).round());

    final stride = math.max(1, (samples.length / maxPoints).floor());

    for (int index = 0; index < samples.length; index += stride) {
      final sample = samples[index];

      final x = ((sample.elapsedUs - windowStartUs) / durationUs * size.width)
          .clamp(0.0, size.width);

      final value = channel == _SignalChannel.ecg
          ? sample.ecg
          : sample.respiration;

      final normalized = ((value - center) / scale).clamp(-1.0, 1.0);

      final y = size.height / 2 - normalized * size.height * 0.42;

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

  void _paintGrid(Canvas canvas, Size size, int durationUs) {
    final gridPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.45)
      ..strokeWidth = 0.7;

    final baselinePaint = Paint()
      ..color = baselineColor
      ..strokeWidth = 1.0;

    for (int i = 1; i < 5; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final seconds = durationUs / 1000000.0;

    final verticalCount = seconds <= 5
        ? 5
        : seconds <= 20
        ? 10
        : 12;

    for (int i = 1; i < verticalCount; i++) {
      final x = size.width * i / verticalCount;

      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      baselinePaint,
    );
  }

  void _paintGaps(Canvas canvas, Size size, int durationUs) {
    if (gaps.isEmpty) {
      return;
    }

    final paint = Paint()
      ..color = gapColor
      ..style = PaintingStyle.fill;

    for (final gap in gaps) {
      final gapStart = math.max(gap.startElapsedUs, windowStartUs);

      final gapEnd = math.min(gap.endElapsedUs ?? windowEndUs, windowEndUs);

      if (gapEnd <= gapStart) {
        continue;
      }

      final left = ((gapStart - windowStartUs) / durationUs * size.width).clamp(
        0.0,
        size.width,
      );

      final right = ((gapEnd - windowStartUs) / durationUs * size.width).clamp(
        0.0,
        size.width,
      );

      canvas.drawRect(Rect.fromLTRB(left, 0, right, size.height), paint);
    }
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

    if (!amplitude.isFinite || amplitude < 1.0) {
      return 1.0;
    }

    return amplitude * 1.15;
  }

  @override
  bool shouldRepaint(covariant _RecordingSignalPainter oldDelegate) {
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

  const _ViewerRateEstimate({required this.rateBpm, required this.intervalMs});
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

  factory _RecordingGap.fromRow(Map<String, Object?> row) {
    return _RecordingGap(
      id: row['id'] as int,
      startElapsedUs: row['start_elapsed_us'] as int? ?? 0,
      endElapsedUs: row['end_elapsed_us'] as int?,
      reason: row['reason'] as String? ?? 'unknown',
      details: row['details'] as String?,
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

  const _GapTile({required this.gap, required this.formatDurationUs});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final end = gap.endElapsedUs;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: gap.reason == 'paused' ? scheme.tertiary : scheme.error,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(gap.label, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 3),
                Text(
                  end == null
                      ? '${formatDurationUs(gap.startElapsedUs)} → open'
                      : '${formatDurationUs(gap.startElapsedUs)} → '
                            '${formatDurationUs(end)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
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

class _RecordingOverview extends StatelessWidget {
  final String startedAt;
  final String timelineDuration;
  final String measuredDuration;
  final int timelineDurationUs;
  final double sampleRate;
  final int sampleCount;
  final String status;
  final String? notes;
  final _ViewerMetrics? metrics;
  final bool loadingMetrics;

  const _RecordingOverview({
    required this.startedAt,
    required this.timelineDuration,
    required this.measuredDuration,
    required this.timelineDurationUs,
    required this.sampleRate,
    required this.sampleCount,
    required this.status,
    required this.notes,
    required this.metrics,
    required this.loadingMetrics,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final heartRate = metrics?.estimatedHeartRateBpm;
    final respirationRate = metrics?.estimatedRespirationRateBpm;
    final rrMs = metrics?.estimatedMeanRrMs;
    final breathMs = metrics?.estimatedMeanBreathMs;

    final timelineSeconds = timelineDurationUs / Duration.microsecondsPerSecond;
    final measuredSeconds = sampleRate <= 0 ? 0.0 : sampleCount / sampleRate;
    final coverage = timelineSeconds <= 0
        ? 0.0
        : (measuredSeconds / timelineSeconds * 100).clamp(0.0, 100.0);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 76,
            child: Row(
              children: [
                Expanded(
                  child: _VitalReading(
                    value: loadingMetrics
                        ? '...'
                        : heartRate == null
                        ? '--'
                        : heartRate.round().toString(),
                    unit: 'BPM',
                    label: 'Estimated avg heart rate',
                    accent: const Color(0xFFE74C4C),
                  ),
                ),
                Container(width: 1, height: 46, color: scheme.outlineVariant),
                Expanded(
                  child: _VitalReading(
                    value: loadingMetrics
                        ? '...'
                        : respirationRate == null
                        ? '--'
                        : respirationRate.round().toString(),
                    unit: 'brpm',
                    label: 'Estimated respiration',
                    accent: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 18, color: scheme.outlineVariant),
          Wrap(
            spacing: 18,
            runSpacing: 10,
            children: [
              _TechnicalFact(
                label: 'R-R',
                value: rrMs == null ? '--' : '${rrMs.toStringAsFixed(0)} ms',
              ),
              _TechnicalFact(
                label: 'Breath interval',
                value: breathMs == null
                    ? '--'
                    : '${breathMs.toStringAsFixed(0)} ms',
              ),
              _TechnicalFact(
                label: 'Sample rate',
                value: '${sampleRate.toStringAsFixed(0)} Hz',
              ),
              _TechnicalFact(
                label: 'Samples',
                value: _formatSampleCount(sampleCount),
              ),
              _TechnicalFact(
                label: 'Signal coverage',
                value: '${coverage.toStringAsFixed(1)}%',
              ),
              _TechnicalFact(label: 'Measured', value: measuredDuration),
              _TechnicalFact(label: 'Timeline', value: timelineDuration),
              _TechnicalFact(label: 'Started', value: startedAt, width: 190),
              _TechnicalFact(label: 'Status', value: _statusLabel(status)),
            ],
          ),
          if (notes != null && notes!.trim().isNotEmpty) ...[
            Divider(height: 20, color: scheme.outlineVariant),
            Text(notes!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 8),
          Text(
            'Rate values are signal-derived estimates and are not a medical diagnosis.',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'recording':
        return 'Recording';
      case 'paused':
        return 'Paused';
      case 'interrupted':
        return 'Interrupted';
      default:
        return 'Completed';
    }
  }

  static String _formatSampleCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(2)}M';
    }

    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }

    return '$count';
  }
}

class _VitalReading extends StatelessWidget {
  final String value;
  final String unit;
  final String label;
  final Color accent;

  const _VitalReading({
    required this.value,
    required this.unit,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.only(right: 7, bottom: 5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent,
                ),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1,
                ),
              ),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  unit,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
    );
  }
}

class _TechnicalFact extends StatelessWidget {
  final String label;
  final String value;
  final double width;

  const _TechnicalFact({
    required this.label,
    required this.value,
    this.width = 132,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: muted),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorBody({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 56, color: scheme.error),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
