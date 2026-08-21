import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/recording_analysis_service.dart';
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
  final RecordingAnalysisService _analysis = RecordingAnalysisService.instance;

  Map<String, Object?>? _recording;
  RecordingAnalysisSummary? _summary;
  List<_DecodedSample> _samples = const [];
  List<_Gap> _gaps = const [];

  bool _loading = true;
  bool _loadingSignal = false;
  bool _working = false;
  String? _error;

  double _sampleRate = 250.0;
  int _timelineUs = 0;
  int _intervalStartUs = 0;
  int _intervalEndUs = 10 * 1000000;

  static const int _defaultIntervalUs = 10 * 1000000;
  static const int _maximumDisplayPoints = 6000;
  static const int _maximumIntervalUs = 10 * 60 * 1000000;
  static const int _chunkPageSize = 180;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final recording = await _database.getRecordingById(widget.recordingId);

      if (recording == null) {
        throw StateError('Recording not found.');
      }

      final timelineUs = recording['timeline_duration_us'] as int? ?? 0;
      final sampleRate =
          (recording['sample_rate'] as num?)?.toDouble() ?? 250.0;
      final initialEnd = math.min(math.max(timelineUs, 0), _defaultIntervalUs);

      if (!mounted) {
        return;
      }

      setState(() {
        _recording = recording;
        _timelineUs = timelineUs;
        _sampleRate = sampleRate > 0 ? sampleRate : 250.0;
        _intervalStartUs = 0;
        _intervalEndUs = initialEnd > 0 ? initialEnd : _defaultIntervalUs;
        _loading = false;
      });

      await Future.wait<void>([_loadSignalInterval(), _loadAnalysis()]);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadAnalysis() async {
    final recording = _recording;

    if (recording == null) {
      return;
    }

    try {
      final summary = await _analysis.analyze(
        recordingId: widget.recordingId,
        recording: recording,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _summary = summary;
      });
    } catch (_) {}
  }

  Future<void> _loadSignalInterval() async {
    if (_timelineUs <= 0) {
      if (mounted) {
        setState(() {
          _samples = const [];
          _gaps = const [];
          _loadingSignal = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _loadingSignal = true;
      });
    }

    try {
      final startUs = _intervalStartUs.clamp(0, _timelineUs).toInt();
      final endUs = _intervalEndUs.clamp(startUs + 1, _timelineUs).toInt();
      final durationUs = endUs - startUs;
      final expectedSamples = durationUs / 1000000.0 * _sampleRate;
      final stride = math.max(
        1,
        (expectedSamples / _maximumDisplayPoints).ceil(),
      );
      final samplePeriodUs = 1000000.0 / _sampleRate;
      final db = await _database.database;
      final decoded = <_DecodedSample>[];
      var lastChunkIndex = -1;
      var globalVisibleIndex = 0;

      while (true) {
        final rows = await db.query(
          'signal_chunks',
          where: '''
            recording_id = ?
            AND chunk_index > ?
            AND start_elapsed_us < ?
            AND end_elapsed_us > ?
          ''',
          whereArgs: <Object?>[
            widget.recordingId,
            lastChunkIndex,
            endUs,
            startUs,
          ],
          orderBy: 'chunk_index ASC',
          limit: _chunkPageSize,
        );

        if (rows.isEmpty) {
          break;
        }

        for (final row in rows) {
          lastChunkIndex =
              (row['chunk_index'] as num?)?.toInt() ?? lastChunkIndex;
          final sampleCount = row['sample_count'] as int? ?? 0;
          final chunkStartUs = row['start_elapsed_us'] as int? ?? 0;
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
            final elapsedUs = chunkStartUs + (i * samplePeriodUs).round();

            if (elapsedUs < startUs) {
              continue;
            }

            if (elapsedUs >= endUs) {
              break;
            }

            if (globalVisibleIndex % stride == 0) {
              final offset = i * 8;
              decoded.add(
                _DecodedSample(
                  elapsedUs: elapsedUs,
                  ecg: data.getInt32(offset, Endian.little).toDouble(),
                  respiration: data
                      .getInt32(offset + 4, Endian.little)
                      .toDouble(),
                ),
              );
            }

            globalVisibleIndex++;
          }
        }
      }

      final gapRows = await _database.getGapsInRange(
        recordingId: widget.recordingId,
        startElapsedUs: startUs,
        endElapsedUs: endUs,
      );
      final gaps = gapRows.map(_Gap.fromRow).toList(growable: false);

      if (!mounted) {
        return;
      }

      setState(() {
        _samples = decoded;
        _gaps = gaps;
        _loadingSignal = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingSignal = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _chooseInterval() async {
    if (_timelineUs <= 0) {
      return;
    }

    final selected = await showDialog<_SelectedInterval>(
      context: context,
      builder: (dialogContext) {
        return _IntervalDialog(
          timelineUs: _timelineUs,
          startUs: _intervalStartUs,
          endUs: math.min(_intervalEndUs, _timelineUs),
          maximumIntervalUs: _maximumIntervalUs,
        );
      },
    );

    if (selected == null || !mounted) {
      return;
    }

    setState(() {
      _intervalStartUs = selected.startUs;
      _intervalEndUs = selected.endUs;
    });

    await _loadSignalInterval();
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
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  maxLines: 1,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: notesController,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (save == true) {
      final name = nameController.text.trim();
      final notes = notesController.text.trim();

      if (name.isNotEmpty) {
        await _database.updateRecordingDetails(
          recordingId: widget.recordingId,
          name: name,
          notes: notes.isEmpty ? null : notes,
          replaceNotes: true,
        );
        await _reloadMetadata();
      }
    }

    nameController.dispose();
    notesController.dispose();
  }

  Future<void> _reloadMetadata() async {
    final recording = await _database.getRecordingById(widget.recordingId);

    if (!mounted || recording == null) {
      return;
    }

    setState(() {
      _recording = recording;
    });
  }

  Rect? _shareOrigin() {
    final box = context.findRenderObject() as RenderBox?;

    if (box == null) {
      return null;
    }

    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _runAction(
    Future<void> Function() action,
    String success,
  ) async {
    if (_working) {
      return;
    }

    setState(() {
      _working = true;
    });

    try {
      await action();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(success)));
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
          _working = false;
        });
      }
    }
  }

  Future<void> _showActions() async {
    final action = await showModalBottomSheet<_ViewerAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Recording actions',
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                _ActionRow(
                  label: 'Generate / Share PDF',
                  onTap: () => Navigator.pop(sheetContext, _ViewerAction.pdf),
                ),
                _ActionRow(
                  label: 'Print PDF',
                  onTap: () =>
                      Navigator.pop(sheetContext, _ViewerAction.printPdf),
                ),
                _ActionRow(
                  label: 'Export ApexCardio file (.apex)',
                  onTap: () => Navigator.pop(sheetContext, _ViewerAction.apex),
                ),
                _ActionRow(
                  label: 'Export CSV',
                  onTap: () => Navigator.pop(sheetContext, _ViewerAction.csv),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (action == null || !mounted) {
      return;
    }

    switch (action) {
      case _ViewerAction.pdf:
        await _runAction(
          () => RecordingReportService.instance.shareReport(
            recordingId: widget.recordingId,
            sharePositionOrigin: _shareOrigin(),
          ),
          'PDF report ready',
        );
        break;
      case _ViewerAction.printPdf:
        await _runAction(
          () => RecordingReportService.instance.printReport(
            recordingId: widget.recordingId,
          ),
          'Print dialog opened',
        );
        break;
      case _ViewerAction.apex:
        await _runAction(
          () => RecordingExportService.instance.export(
            recordingId: widget.recordingId,
            format: RecordingExportFormat.apex,
            sharePositionOrigin: _shareOrigin(),
          ),
          'ApexCardio export ready',
        );
        break;
      case _ViewerAction.csv:
        await _runAction(
          () => RecordingExportService.instance.export(
            recordingId: widget.recordingId,
            format: RecordingExportFormat.csv,
            sharePositionOrigin: _shareOrigin(),
          ),
          'CSV export ready',
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final recording = _recording;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Text(
          recording?['name'] as String? ?? 'Recording',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (_working)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          TextButton(
            onPressed: recording == null || _working ? null : _editDetails,
            child: const Text('Edit'),
          ),
          TextButton(
            onPressed: recording == null || _working ? null : _showActions,
            child: const Text('More'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : recording == null
          ? Center(child: Text(_error ?? 'Recording not found'))
          : _buildBody(context, recording),
    );
  }

  Widget _buildBody(BuildContext context, Map<String, Object?> recording) {
    final scheme = Theme.of(context).colorScheme;
    final summary = _summary;
    final sampleCount = recording['recorded_sample_count'] as int? ?? 0;
    final measuredUs = _sampleRate <= 0
        ? 0
        : (sampleCount / _sampleRate * 1000000).round();
    final notes = recording['notes'] as String?;
    final startedAt = recording['started_at_ms'] as int? ?? 0;
    final endedAt = recording['ended_at_ms'] as int?;
    final status = recording['status'] as String? ?? 'completed';
    final device = recording['device_name'] as String?;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _VitalsHeader(
            heartRate: summary?.averageHeartRateBpm,
            respirationRate: summary?.averageRespirationRateBrpm,
          ),
          const SizedBox(height: 18),
          Divider(height: 1, color: scheme.outlineVariant),
          const SizedBox(height: 14),
          _IntervalBar(
            start: _formatClock(_intervalStartUs),
            end: _formatClock(math.min(_intervalEndUs, _timelineUs)),
            onChange: _chooseInterval,
          ),
          const SizedBox(height: 18),
          _SignalSection(
            title: 'ECG',
            range: _formatIntervalLength(),
            height: 230,
            loading: _loadingSignal,
            painter: _SignalPainter(
              samples: _samples,
              gaps: _gaps,
              startUs: _intervalStartUs,
              endUs: math.min(_intervalEndUs, _timelineUs),
              channel: _SignalChannel.ecg,
              lineColor: scheme.primary,
              gridColor: scheme.outlineVariant,
              gapColor: scheme.error.withValues(alpha: 0.09),
            ),
          ),
          const SizedBox(height: 24),
          _SignalSection(
            title: 'Respiration',
            range: _formatIntervalLength(),
            height: 180,
            loading: _loadingSignal,
            painter: _SignalPainter(
              samples: _samples,
              gaps: _gaps,
              startUs: _intervalStartUs,
              endUs: math.min(_intervalEndUs, _timelineUs),
              channel: _SignalChannel.respiration,
              lineColor: scheme.tertiary,
              gridColor: scheme.outlineVariant,
              gapColor: scheme.error.withValues(alpha: 0.09),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Details',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          _DetailRow(
            label: 'Average R-R interval',
            value: summary?.averageRrMs == null
                ? '--'
                : '${summary!.averageRrMs!.toStringAsFixed(0)} ms',
          ),
          _DetailRow(
            label: 'Average breath interval',
            value: summary?.averageBreathIntervalMs == null
                ? '--'
                : '${summary!.averageBreathIntervalMs!.toStringAsFixed(0)} ms',
          ),
          _DetailRow(
            label: 'Sample rate',
            value: '${_sampleRate.toStringAsFixed(0)} Hz',
          ),
          _DetailRow(label: 'Samples', value: _formatNumber(sampleCount)),
          _DetailRow(
            label: 'Measured signal',
            value: _formatDuration(measuredUs),
          ),
          _DetailRow(label: 'Timeline', value: _formatDuration(_timelineUs)),
          _DetailRow(
            label: 'Gaps',
            value: summary == null
                ? '--'
                : '${summary.gapCount} · ${_formatDuration(summary.gapDurationUs)}',
          ),
          _DetailRow(label: 'Started', value: _formatDateTime(startedAt)),
          _DetailRow(
            label: 'Ended',
            value: endedAt == null ? '--' : _formatDateTime(endedAt),
          ),
          _DetailRow(label: 'Status', value: _titleCase(status)),
          _DetailRow(
            label: 'Device',
            value: device?.trim().isEmpty == false ? device! : '--',
          ),
          if (notes != null && notes.trim().isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              'Notes',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 7),
            Text(
              notes,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 18),
            Text(
              _error!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Average rates are derived from representative signal windows across the recording and are not a clinical diagnosis.',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  String _formatIntervalLength() {
    final end = math.min(_intervalEndUs, _timelineUs);
    final duration = math.max(0, end - _intervalStartUs);
    return _formatDuration(duration);
  }

  String _formatClock(int microseconds) {
    final totalSeconds = microseconds ~/ 1000000;
    final days = totalSeconds ~/ 86400;
    final hours = (totalSeconds % 86400) ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final prefix = days > 0 ? '${days}d ' : '';
    return '$prefix${_two(hours)}:${_two(minutes)}:${_two(seconds)}';
  }

  String _formatDuration(int microseconds) {
    return _formatClock(microseconds);
  }

  String _formatDateTime(int milliseconds) {
    final date = DateTime.fromMillisecondsSinceEpoch(milliseconds);
    return '${date.year}-${_two(date.month)}-${_two(date.day)} '
        '${_two(date.hour)}:${_two(date.minute)}';
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

  String _titleCase(String value) {
    if (value.isEmpty) {
      return value;
    }
    return '${value[0].toUpperCase()}${value.substring(1).toLowerCase()}';
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}

class _VitalsHeader extends StatelessWidget {
  final double? heartRate;
  final double? respirationRate;

  const _VitalsHeader({required this.heartRate, required this.respirationRate});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: 82,
      child: Row(
        children: [
          Expanded(
            child: _Vital(
              value: heartRate == null ? '--' : heartRate!.round().toString(),
              unit: 'BPM',
              label: 'Average',
              accent: const Color(0xFFE74C4C),
            ),
          ),
          Container(width: 1, height: 52, color: scheme.outlineVariant),
          Expanded(
            child: _Vital(
              value: respirationRate == null
                  ? '--'
                  : respirationRate!.round().toString(),
              unit: 'BRPM',
              label: 'Average',
              accent: scheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _Vital extends StatelessWidget {
  final String value;
  final String unit;
  final String label;
  final Color accent;

  const _Vital({
    required this.value,
    required this.unit,
    required this.label,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Center(
      child: SizedBox(
        width: 145,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 7, bottom: 6),
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
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntervalBar extends StatelessWidget {
  final String start;
  final String end;
  final VoidCallback onChange;

  const _IntervalBar({
    required this.start,
    required this.end,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Interval',
                style: Theme.of(
                  context,
                ).textTheme.labelMedium?.copyWith(color: muted),
              ),
              const SizedBox(height: 3),
              Text(
                '$start  →  $end',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
        TextButton(onPressed: onChange, child: const Text('Change')),
      ],
    );
  }
}

class _SignalSection extends StatelessWidget {
  final String title;
  final String range;
  final double height;
  final bool loading;
  final CustomPainter painter;

  const _SignalSection({
    required this.title,
    required this.range,
    required this.height,
    required this.loading,
    required this.painter,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Text(
              range,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          height: height,
          width: double.infinity,
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            border: Border.symmetric(
              horizontal: BorderSide(color: scheme.outlineVariant),
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(painter: painter),
              if (loading)
                ColoredBox(
                  color: scheme.surface.withValues(alpha: 0.58),
                  child: const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.75),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 20),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ActionRow({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
        ),
        child: Text(label),
      ),
    );
  }
}

class _IntervalDialog extends StatefulWidget {
  final int timelineUs;
  final int startUs;
  final int endUs;
  final int maximumIntervalUs;

  const _IntervalDialog({
    required this.timelineUs,
    required this.startUs,
    required this.endUs,
    required this.maximumIntervalUs,
  });

  @override
  State<_IntervalDialog> createState() => _IntervalDialogState();
}

class _IntervalDialogState extends State<_IntervalDialog> {
  late final _ClockControllers _start;
  late final _ClockControllers _end;
  String? _error;

  @override
  void initState() {
    super.initState();
    _start = _ClockControllers.fromUs(widget.startUs);
    _end = _ClockControllers.fromUs(widget.endUs);
  }

  @override
  void dispose() {
    _start.dispose();
    _end.dispose();
    super.dispose();
  }

  void _apply() {
    final startUs = _start.toUs();
    final endUs = _end.toUs();

    if (startUs < 0 || endUs <= startUs) {
      setState(() {
        _error = 'End must be after start.';
      });
      return;
    }

    if (endUs > widget.timelineUs) {
      setState(() {
        _error = 'End is outside the recording.';
      });
      return;
    }

    if (endUs - startUs > widget.maximumIntervalUs) {
      setState(() {
        _error = 'A graph interval can be at most 10 minutes.';
      });
      return;
    }

    Navigator.pop(context, _SelectedInterval(startUs: startUs, endUs: endUs));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SizedBox(
        width: 390,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Choose interval',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                'Recording length: ${_formatStatic(widget.timelineUs)} · max graph interval 10 min',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              _ClockEditor(label: 'Start', controllers: _start),
              const SizedBox(height: 18),
              _ClockEditor(label: 'End', controllers: _end),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _apply,
                      child: const Text('Show interval'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatStatic(int microseconds) {
    final seconds = microseconds ~/ 1000000;
    final days = seconds ~/ 86400;
    final hours = (seconds % 86400) ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    String two(int value) => value.toString().padLeft(2, '0');
    return days > 0
        ? '${days}d ${two(hours)}:${two(minutes)}:${two(secs)}'
        : '${two(hours)}:${two(minutes)}:${two(secs)}';
  }
}

class _ClockEditor extends StatelessWidget {
  final String label;
  final _ClockControllers controllers;

  const _ClockEditor({required this.label, required this.controllers});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _ClockField(controller: controllers.days, label: 'Days'),
            const SizedBox(width: 8),
            _ClockField(controller: controllers.hours, label: 'Hours'),
            const SizedBox(width: 8),
            _ClockField(controller: controllers.minutes, label: 'Min'),
            const SizedBox(width: 8),
            _ClockField(controller: controllers.seconds, label: 'Sec'),
          ],
        ),
      ],
    );
  }
}

class _ClockField extends StatelessWidget {
  final TextEditingController controller;
  final String label;

  const _ClockField({required this.controller, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        decoration: InputDecoration(labelText: label, isDense: true),
      ),
    );
  }
}

class _ClockControllers {
  final TextEditingController days;
  final TextEditingController hours;
  final TextEditingController minutes;
  final TextEditingController seconds;

  _ClockControllers({
    required this.days,
    required this.hours,
    required this.minutes,
    required this.seconds,
  });

  factory _ClockControllers.fromUs(int microseconds) {
    final total = microseconds ~/ 1000000;
    return _ClockControllers(
      days: TextEditingController(text: '${total ~/ 86400}'),
      hours: TextEditingController(text: '${(total % 86400) ~/ 3600}'),
      minutes: TextEditingController(text: '${(total % 3600) ~/ 60}'),
      seconds: TextEditingController(text: '${total % 60}'),
    );
  }

  int toUs() {
    final d = int.tryParse(days.text.trim()) ?? 0;
    final h = int.tryParse(hours.text.trim()) ?? 0;
    final m = int.tryParse(minutes.text.trim()) ?? 0;
    final s = int.tryParse(seconds.text.trim()) ?? 0;

    if (d < 0 || h < 0 || m < 0 || s < 0) {
      return -1;
    }

    return (((d * 24 + h) * 60 + m) * 60 + s) * 1000000;
  }

  void dispose() {
    days.dispose();
    hours.dispose();
    minutes.dispose();
    seconds.dispose();
  }
}

class _SelectedInterval {
  final int startUs;
  final int endUs;

  const _SelectedInterval({required this.startUs, required this.endUs});
}

enum _ViewerAction { pdf, printPdf, apex, csv }

enum _SignalChannel { ecg, respiration }

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

class _Gap {
  final int startUs;
  final int? endUs;

  const _Gap({required this.startUs, required this.endUs});

  factory _Gap.fromRow(Map<String, Object?> row) {
    return _Gap(
      startUs: row['start_elapsed_us'] as int? ?? 0,
      endUs: row['end_elapsed_us'] as int?,
    );
  }
}

class _SignalPainter extends CustomPainter {
  final List<_DecodedSample> samples;
  final List<_Gap> gaps;
  final int startUs;
  final int endUs;
  final _SignalChannel channel;
  final Color lineColor;
  final Color gridColor;
  final Color gapColor;

  const _SignalPainter({
    required this.samples,
    required this.gaps,
    required this.startUs,
    required this.endUs,
    required this.channel,
    required this.lineColor,
    required this.gridColor,
    required this.gapColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final durationUs = endUs - startUs;

    if (durationUs <= 0 || size.width <= 0 || size.height <= 0) {
      return;
    }

    final grid = Paint()
      ..color = gridColor.withValues(alpha: 0.42)
      ..strokeWidth = 0.7;

    for (int i = 1; i < 5; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    for (int i = 1; i < 10; i++) {
      final x = size.width * i / 10;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }

    final gapPaint = Paint()
      ..color = gapColor
      ..style = PaintingStyle.fill;

    for (final gap in gaps) {
      final gapStart = math.max(startUs, gap.startUs);
      final gapEnd = math.min(endUs, gap.endUs ?? endUs);

      if (gapEnd <= gapStart) {
        continue;
      }

      final left = (gapStart - startUs) / durationUs * size.width;
      final right = (gapEnd - startUs) / durationUs * size.width;
      canvas.drawRect(Rect.fromLTRB(left, 0, right, size.height), gapPaint);
    }

    if (samples.length < 2) {
      return;
    }

    final values = samples
        .map(
          (sample) =>
              channel == _SignalChannel.ecg ? sample.ecg : sample.respiration,
        )
        .toList(growable: false);
    final center = _median(values);
    final scale = _robustScale(values, center);
    final path = Path();
    var started = false;

    for (final sample in samples) {
      final x = ((sample.elapsedUs - startUs) / durationUs * size.width).clamp(
        0.0,
        size.width,
      );
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

    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 1.55
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  double _median(List<double> values) {
    final sorted = List<double>.from(values)..sort();
    final middle = sorted.length ~/ 2;

    if (sorted.length.isOdd) {
      return sorted[middle];
    }

    return (sorted[middle - 1] + sorted[middle]) / 2;
  }

  double _robustScale(List<double> values, double center) {
    final deviations = values.map((value) => (value - center).abs()).toList()
      ..sort();
    final index = ((deviations.length - 1) * 0.97).round().clamp(
      0,
      deviations.length - 1,
    );
    final scale = deviations[index];

    if (!scale.isFinite || scale < 1) {
      return 1;
    }

    return scale * 1.15;
  }

  @override
  bool shouldRepaint(covariant _SignalPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.gaps != gaps ||
        oldDelegate.startUs != startUs ||
        oldDelegate.endUs != endUs ||
        oldDelegate.channel != channel ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.gapColor != gapColor;
  }
}
