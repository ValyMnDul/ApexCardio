import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/recording.dart';
import '../screens/recording_viewer.dart';
import '../services/recording_database.dart';
import '../services/recording_import_service.dart';

class Recordings extends StatefulWidget {
  const Recordings({super.key});

  @override
  State<Recordings> createState() => _RecordingsState();
}

class _RecordingsState extends State<Recordings> {
  final RecordingDatabase _database = RecordingDatabase.instance;

  List<Map<String, Object?>> _recordings = const [];
  bool _loading = true;
  bool _importing = false;
  String? _error;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();

    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reload();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final recording = context.read<RecordingProvider>();
      await recording.ensureInitialized();
      final rows = await _database.getRecordings();

      if (!mounted) {
        return;
      }

      setState(() {
        _recordings = rows;
        _loading = false;
      });
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

  Future<void> _createRecording() async {
    final provider = context.read<RecordingProvider>();

    if (!provider.initialized) {
      try {
        await provider.ensureInitialized();
      } catch (error) {
        _message('Recording storage error: $error');
        return;
      }
    }

    if (!mounted || !provider.isIdle) {
      return;
    }

    final name = TextEditingController(text: _defaultName());
    final notes = TextEditingController();
    final additional = TextEditingController();

    final result = await showDialog<_CreateRecordingData>(
      context: context,
      builder: (dialogContext) {
        final width = (MediaQuery.of(dialogContext).size.width - 32)
            .clamp(0.0, 420.0)
            .toDouble();

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          child: SizedBox(
            width: width,
            height: 430,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Create recording',
                    textAlign: TextAlign.center,
                    style: Theme.of(dialogContext).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: name,
                    autofocus: true,
                    maxLines: 1,
                    decoration: const InputDecoration(
                      labelText: 'Recording name',
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 88,
                    child: TextField(
                      controller: notes,
                      expands: true,
                      minLines: null,
                      maxLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        labelText: 'Notes',
                        hintText: 'Optional',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 88,
                    child: TextField(
                      controller: additional,
                      expands: true,
                      minLines: null,
                      maxLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        labelText: 'Additional information',
                        hintText: 'Optional',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.pop(
                              dialogContext,
                              _CreateRecordingData(
                                name: name.text,
                                notes: notes.text,
                                additional: additional.text,
                              ),
                            );
                          },
                          child: const Text('Start recording'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    name.dispose();
    notes.dispose();
    additional.dispose();

    if (result == null || !mounted) {
      return;
    }

    try {
      await provider.startRecording(
        name: result.name,
        notes: result.notes,
        additionalData: result.additional.trim().isEmpty
            ? null
            : <String, Object?>{
                'additional_information': result.additional.trim(),
              },
      );

      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      _message('Could not start recording: $error');
    }
  }

  Future<void> _pauseOrResume() async {
    final provider = context.read<RecordingProvider>();

    try {
      if (provider.isPaused) {
        await provider.resumeRecording();
      } else {
        await provider.pauseRecording();
      }
    } catch (error) {
      _message('Could not change recording state: $error');
    }
  }

  Future<void> _stop() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Stop recording?'),
          content: const Text(
            'The recording will be finalized and saved on this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Stop'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await context.read<RecordingProvider>().stopRecording();
      await _reload();
    } catch (error) {
      _message('Could not stop recording: $error');
    }
  }

  Future<void> _import() async {
    if (_importing) {
      return;
    }

    setState(() {
      _importing = true;
    });

    try {
      final id = await RecordingImportService.instance.pickAndImport();

      if (!mounted) {
        return;
      }

      setState(() {
        _importing = false;
      });

      if (id == null) {
        return;
      }

      await _reload();

      if (!mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RecordingViewer(recordingId: id)),
      );

      await _reload();
    } catch (error) {
      if (mounted) {
        setState(() {
          _importing = false;
        });
      }
      _message('Could not import recording: $error');
    }
  }

  Future<void> _open(int id) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => RecordingViewer(recordingId: id)));

    await _reload();
  }

  Future<void> _delete(int id, String name) async {
    final provider = context.read<RecordingProvider>();

    if (provider.recordingId == id) {
      _message('Stop the active recording before deleting it.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete recording?'),
          content: Text('"$name" will be permanently deleted.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _database.deleteRecording(id);
      await _reload();
    } catch (error) {
      _message('Could not delete recording: $error');
    }
  }

  void _message(String text) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  List<Map<String, Object?>> _visible(RecordingProvider provider) {
    final activeId = provider.recordingId;

    if (activeId == null) {
      return _recordings;
    }

    return _recordings
        .where((row) => row['id'] != activeId)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RecordingProvider>();
    final rows = _visible(provider);

    return SafeArea(
      top: false,
      child: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
          children: [
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed:
                        provider.isIdle &&
                            provider.initialized &&
                            !provider.isStarting
                        ? _createRecording
                        : null,
                    child: Text(
                      provider.isStarting ? 'Starting...' : 'Create recording',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: _importing || provider.hasActiveRecording
                      ? null
                      : _import,
                  child: Text(_importing ? 'Opening...' : 'Open'),
                ),
              ],
            ),
            if (provider.hasActiveRecording) ...[
              const SizedBox(height: 18),
              _ActiveRecordingStrip(
                provider: provider,
                onPauseResume: _pauseOrResume,
                onStop: _stop,
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Text(
                  'Saved recordings',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (!_loading)
                  Text(
                    '${rows.length}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 50),
                child: Column(
                  children: [
                    Text(
                      'Could not load recordings',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 7),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(onPressed: _reload, child: const Text('Retry')),
                  ],
                ),
              )
            else if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 68),
                child: Center(
                  child: Text(
                    'No saved recordings yet',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              ...List<Widget>.generate(rows.length, (index) {
                final row = rows[index];
                final id = row['id'] as int;
                final name = row['name'] as String? ?? 'Recording';

                return Column(
                  children: [
                    _RecordingRow(
                      row: row,
                      onOpen: () => _open(id),
                      onDelete: () => _delete(id, name),
                    ),
                    if (index != rows.length - 1)
                      Divider(
                        height: 1,
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                  ],
                );
              }),
          ],
        ),
      ),
    );
  }

  String _defaultName() {
    final now = DateTime.now();
    return 'Recording ${now.year}-${_two(now.month)}-${_two(now.day)} '
        '${_two(now.hour)}:${_two(now.minute)}';
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}

class _ActiveRecordingStrip extends StatelessWidget {
  final RecordingProvider provider;
  final VoidCallback onPauseResume;
  final VoidCallback onStop;

  const _ActiveRecordingStrip({
    required this.provider,
    required this.onPauseResume,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _PulseDot(
                active: provider.isRecording && provider.bleConnected,
                paused: provider.isPaused || !provider.bleConnected,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  provider.recordingName ?? 'Recording',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _formatDuration(provider.timelineDuration),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: Text(
                  provider.isPaused
                      ? 'Paused'
                      : provider.bleConnected
                      ? 'Recording · device connected'
                      : 'Recording · signal gap',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: provider.isStopping ? null : onPauseResume,
                child: Text(provider.isPaused ? 'Resume' : 'Pause'),
              ),
              TextButton(
                onPressed: provider.isStopping ? null : onStop,
                child: Text(provider.isStopping ? 'Saving...' : 'Stop'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatDuration(Duration duration) {
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
}

class _RecordingRow extends StatelessWidget {
  final Map<String, Object?> row;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  const _RecordingRow({
    required this.row,
    required this.onOpen,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = row['name'] as String? ?? 'Recording';
    final startedAt = row['started_at_ms'] as int? ?? 0;
    final timelineUs = row['timeline_duration_us'] as int? ?? 0;
    final sampleRate = (row['sample_rate'] as num?)?.toDouble() ?? 250.0;
    final samples = row['recorded_sample_count'] as int? ?? 0;
    final status = row['status'] as String? ?? 'completed';
    final measuredUs = sampleRate <= 0
        ? 0
        : (samples / sampleRate * 1000000).round();

    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatDate(startedAt),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${_formatDuration(timelineUs)} timeline · '
                    '${_formatDuration(measuredUs)} measured · '
                    '${sampleRate.toStringAsFixed(0)} Hz'
                    '${status == 'completed' ? '' : ' · ${_status(status)}'}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            PopupMenuButton<String>(
              tooltip: 'Recording options',
              onSelected: (value) {
                if (value == 'delete') {
                  onDelete();
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Text('More'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(int ms) {
    final date = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)}  '
        '${two(date.hour)}:${two(date.minute)}';
  }

  static String _formatDuration(int us) {
    final seconds = us ~/ 1000000;
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

  static String _status(String status) {
    switch (status) {
      case 'interrupted':
        return 'Interrupted';
      case 'paused':
        return 'Paused';
      case 'recording':
        return 'Recording';
      default:
        return 'Completed';
    }
  }
}

class _PulseDot extends StatefulWidget {
  final bool active;
  final bool paused;

  const _PulseDot({required this.active, required this.paused});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    _opacity = Tween<double>(
      begin: 1,
      end: 0.28,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    _sync();
  }

  @override
  void didUpdateWidget(covariant _PulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active ||
        oldWidget.paused != widget.paused) {
      _sync();
    }
  }

  void _sync() {
    if (widget.active) {
      _controller.repeat(reverse: true);
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.paused
        ? Theme.of(context).colorScheme.tertiary
        : const Color(0xFFE74C4C);

    return FadeTransition(
      opacity: widget.active
          ? _opacity
          : const AlwaysStoppedAnimation<double>(1),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}

class _CreateRecordingData {
  final String name;
  final String notes;
  final String additional;

  const _CreateRecordingData({
    required this.name,
    required this.notes,
    required this.additional,
  });
}
