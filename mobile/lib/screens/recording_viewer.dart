import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/recording_database.dart';

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
  String? _error;

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

      await _loadVisibleWindow();
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
          IconButton(
            onPressed: recording == null ? null : _editDetails,
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
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
          _RecordingSummaryCard(
            startedAt: _formatDateTime(startedAtMs),
            timelineDuration: _formatDurationUs(timelineUs),
            measuredDuration: _formatDuration(measuredDuration),
            sampleRate: _sampleRate,
            status: status,
            notes: notes,
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
              IconButton.filledTonal(
                onPressed: () {
                  _zoomBy(0.5);
                },
                icon: const Icon(Icons.zoom_in_rounded),
                tooltip: 'Zoom in',
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                onPressed: () {
                  _zoomBy(2.0);
                },
                icon: const Icon(Icons.zoom_out_rounded),
                tooltip: 'Zoom out',
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _resetWindow,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Reset'),
              ),
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
          Icon(
            gap.reason == 'paused'
                ? Icons.pause_circle_outline_rounded
                : Icons.bluetooth_disabled_rounded,
            color: scheme.onSurfaceVariant,
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

class _RecordingSummaryCard extends StatelessWidget {
  final String startedAt;
  final String timelineDuration;
  final String measuredDuration;
  final double sampleRate;
  final String status;
  final String? notes;

  const _RecordingSummaryCard({
    required this.startedAt,
    required this.timelineDuration,
    required this.measuredDuration,
    required this.sampleRate,
    required this.status,
    required this.notes,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 18,
            runSpacing: 12,
            children: [
              _SummaryValue(
                label: 'Started',
                value: startedAt,
                icon: Icons.calendar_today_outlined,
              ),
              _SummaryValue(
                label: 'Timeline',
                value: timelineDuration,
                icon: Icons.schedule_rounded,
              ),
              _SummaryValue(
                label: 'Measured',
                value: measuredDuration,
                icon: Icons.monitor_heart_outlined,
              ),
              _SummaryValue(
                label: 'Sample rate',
                value: '${sampleRate.toStringAsFixed(0)} Hz',
                icon: Icons.speed_rounded,
              ),
              _SummaryValue(
                label: 'Status',
                value: _statusLabel(status),
                icon: _statusIcon(status),
              ),
            ],
          ),
          if (notes != null && notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(color: scheme.outlineVariant),
            const SizedBox(height: 8),
            Text(notes!, style: Theme.of(context).textTheme.bodyMedium),
          ],
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

  static IconData _statusIcon(String status) {
    switch (status) {
      case 'recording':
        return Icons.fiber_manual_record_rounded;
      case 'paused':
        return Icons.pause_rounded;
      case 'interrupted':
        return Icons.warning_amber_rounded;
      default:
        return Icons.check_circle_outline_rounded;
    }
  }
}

class _SummaryValue extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SummaryValue({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: 145,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
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
