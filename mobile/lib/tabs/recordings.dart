import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/recording.dart';
import '../providers/language.dart';
import '../providers/ui_preferences.dart';
import '../screens/recording_viewer.dart';
import '../services/recording_database.dart';
import '../services/recording_import_service.dart';
import '../services/recording_report_service.dart';

class Recordings extends StatefulWidget {
  const Recordings({super.key});

  @override
  State<Recordings> createState() => _RecordingsState();
}

class _RecordingsState extends State<Recordings> {
  final RecordingDatabase _database = RecordingDatabase.instance;

  List<Map<String, Object?>> _recordings = <Map<String, Object?>>[];
  bool _loading = true;
  bool _importing = false;
  String? _loadError;
  Timer? _timer;

  @override
  void initState() {
    super.initState();

    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted) {
          setState(() {});
        }
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reloadRecordings();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _reloadRecordings() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final recordingProvider = context.read<RecordingProvider>();
      await recordingProvider.ensureInitialized();

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
        _loadError = error.toString();
      });
    }
  }

  Future<void> _showCreateRecordingDialog() async {
    final recording = context.read<RecordingProvider>();

    if (!recording.initialized) {
      try {
        await recording.ensureInitialized();
      } catch (error) {
        if (!mounted) {
          return;
        }

        _showMessage(
          context.read<LanguageProvider>().translate(
            "action_failed",
            <String, Object?>{
              "error": error,
            },
          ),
        );
        return;
      }
    }

    if (!mounted || !recording.isIdle) {
      return;
    }

    if (!recording.bleConnected) {
      _showMessage(
        context
            .read<LanguageProvider>()
            .translate(
              "device_required_recording",
            ),
      );
      return;
    }

    final nameController = TextEditingController(
      text: _defaultRecordingName(),
    );

    final notesController = TextEditingController();

    final language =
        context.read<LanguageProvider>();

    final result = await showDialog<_CreateRecordingData>(
      context: context,
      builder: (dialogContext) {
        final media =
            MediaQuery.of(dialogContext);
        final width =
            (media.size.width - 32)
                .clamp(0.0, 420.0)
                .toDouble();
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          child: SizedBox(
            width: width,
            child: Padding(
              padding:
                  const EdgeInsets.fromLTRB(
                22,
                18,
                22,
                14,
              ),
              child: Column(
                mainAxisSize:
                    MainAxisSize.min,
                crossAxisAlignment:
                    CrossAxisAlignment.stretch,
                children: [
                  Text(
                    language.translate(
                      "create_recording",
                    ),
                    textAlign:
                        TextAlign.center,
                    maxLines: 2,
                    overflow:
                        TextOverflow.ellipsis,
                    style: Theme.of(
                      dialogContext,
                    )
                        .textTheme
                        .titleLarge
                        ?.copyWith(
                          fontWeight:
                              FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 16),
                  SingleChildScrollView(
                    child: Column(
                      mainAxisSize:
                          MainAxisSize.min,
                      children: [
                        TextField(
                          controller:
                              nameController,
                          autofocus: true,
                          maxLines: 1,
                          textInputAction:
                              TextInputAction
                                  .next,
                          decoration:
                              InputDecoration(
                            labelText:
                                language
                                    .translate(
                              "recording_name",
                            ),
                          ),
                        ),
                        const SizedBox(
                          height: 12,
                        ),
                        TextField(
                          controller:
                              notesController,
                          minLines: 1,
                          maxLines: 5,
                          maxLength: 500,
                          textInputAction:
                              TextInputAction
                                  .newline,
                          decoration:
                              InputDecoration(
                            labelText:
                                language
                                    .translate(
                              "notes",
                            ),
                            hintText:
                                language
                                    .translate(
                              "optional",
                            ),
                            alignLabelWithHint:
                                true,
                            counterText: '',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton(
                          onPressed: () {
                            Navigator.pop(
                              dialogContext,
                            );
                          },
                          child: FittedBox(
                            fit:
                                BoxFit.scaleDown,
                            child: Text(
                              language
                                  .translate(
                                "cancel",
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            Navigator.pop(
                              dialogContext,
                              _CreateRecordingData(
                                name:
                                    nameController
                                        .text,
                                notes:
                                    notesController
                                        .text,
                              ),
                            );
                          },
                          child: FittedBox(
                            fit:
                                BoxFit.scaleDown,
                            child: Text(
                              language
                                  .translate(
                                "start_recording",
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
          ),
        );
      },
    );

    nameController.dispose();
    notesController.dispose();

    if (result == null || !mounted) {
      return;
    }

    try {
      await recording.startRecording(
        name: result.name,
        notes: result.notes,
      );

      if (!mounted) {
        return;
      }

      setState(() {});
      _showMessage(
        context.read<LanguageProvider>().translate(
          "recording_started",
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        context.read<LanguageProvider>().translate(
          "could_not_start_recording",
          <String, Object?>{"error": error},
        ),
      );
    }
  }

  Future<void> _pauseRecording() async {
    final recording = context.read<RecordingProvider>();

    try {
      await recording.pauseRecording();

      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          context.read<LanguageProvider>().translate(
            "could_not_pause_recording",
            <String, Object?>{"error": error},
          ),
        );
      }
    }
  }

  Future<void> _resumeRecording() async {
    final recording = context.read<RecordingProvider>();

    try {
      await recording.resumeRecording();

      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          context.read<LanguageProvider>().translate(
            "could_not_resume_recording",
            <String, Object?>{"error": error},
          ),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    final recording = context.read<RecordingProvider>();

    final language =
        context.read<LanguageProvider>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            language.translate(
              "stop_recording_question",
            ),
          ),
          content: Text(
            language.translate(
              "stop_recording_description",
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: Text(
                language.translate(
                  "cancel",
                ),
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child: Text(
                language.translate(
                  "stop",
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await recording.stopRecording();
      await _reloadRecordings();

      if (mounted) {
        _showMessage(
          context.read<LanguageProvider>().translate(
            "recording_saved",
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          context.read<LanguageProvider>().translate(
            "could_not_stop_recording",
            <String, Object?>{"error": error},
          ),
        );
      }
    }
  }

  Future<void> _retryWrites() async {
    final recording = context.read<RecordingProvider>();

    try {
      await recording.retryPendingWrites();

      if (mounted) {
        _showMessage(
          context.read<LanguageProvider>().translate(
            "pending_data_saved",
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          context.read<LanguageProvider>().translate(
            "write_retry_failed",
            <String, Object?>{"error": error},
          ),
        );
      }
    }
  }

  Future<void> _importRecording() async {
    if (_importing) {
      return;
    }

    setState(() {
      _importing = true;
    });

    try {
      final importedId =
          await RecordingImportService.instance.pickAndImport();

      if (!mounted) {
        return;
      }

      if (importedId == null) {
        setState(() {
          _importing = false;
        });
        return;
      }

      await _reloadRecordings();

      if (!mounted) {
        return;
      }

      setState(() {
        _importing = false;
      });

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RecordingViewer(
            recordingId: importedId,
          ),
        ),
      );

      await _reloadRecordings();
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _importing = false;
      });

      _showMessage(
        context.read<LanguageProvider>().translate(
          "could_not_import_recording",
          <String, Object?>{"error": error},
        ),
      );
    }
  }

  Future<void> _openRecording(int recordingId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RecordingViewer(
          recordingId: recordingId,
        ),
      ),
    );

    await _reloadRecordings();
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

  Future<void> _shareRecordingPdf(
    int recordingId,
  ) async {
    final language =
        context.read<LanguageProvider>();

    try {
      await RecordingReportService.instance.shareReport(
        recordingId: recordingId,
        languageCode:
            language.currentLang,
        sharePositionOrigin:
            _shareOrigin(),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage(
        language.translate(
          "action_failed",
          <String, Object?>{
            "error": error,
          },
        ),
      );
    }
  }

  Future<void> _editRecording(
    Map<String, Object?> row,
  ) async {
    final recordingId =
        row['id'] as int;

    final recordingProvider =
        context.read<RecordingProvider>();

    if (recordingProvider.recordingId ==
        recordingId) {
      _showMessage(
        context
            .read<LanguageProvider>()
            .translate(
              "stop_before_delete",
            ),
      );
      return;
    }

    final language =
        context.read<LanguageProvider>();

    final nameController =
        TextEditingController(
      text:
          row['name'] as String? ??
          language.translate(
            "recording",
          ),
    );

    final notesController =
        TextEditingController(
      text:
          row['notes'] as String? ??
          '',
    );

    final save =
        await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final media =
            MediaQuery.of(
          dialogContext,
        );

        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          child: SizedBox(
            width:
                (media.size.width - 32)
                    .clamp(
                      0.0,
                      420.0,
                    )
                    .toDouble(),
            child: Padding(
              padding:
                  const EdgeInsets.fromLTRB(
                20,
                18,
                20,
                14,
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
                      "edit_recording",
                    ),
                    textAlign:
                        TextAlign.center,
                    style:
                        Theme.of(
                      dialogContext,
                    )
                            .textTheme
                            .titleLarge
                            ?.copyWith(
                              fontWeight:
                                  FontWeight
                                      .w600,
                            ),
                  ),
                  const SizedBox(
                    height: 16,
                  ),
                  TextField(
                    controller:
                        nameController,
                    maxLines: 1,
                    decoration:
                        InputDecoration(
                      labelText:
                          language.translate(
                        "recording_name",
                      ),
                    ),
                  ),
                  const SizedBox(
                    height: 14,
                  ),
                  TextField(
                    controller:
                        notesController,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: 500,
                    textInputAction:
                        TextInputAction
                            .newline,
                    decoration:
                        InputDecoration(
                      labelText:
                          language.translate(
                        "notes",
                      ),
                      hintText:
                          language.translate(
                        "optional",
                      ),
                      alignLabelWithHint:
                          true,
                      counterText: '',
                    ),
                  ),
                  const SizedBox(
                    height: 12,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child:
                            TextButton(
                          onPressed: () {
                            Navigator.pop(
                              dialogContext,
                              false,
                            );
                          },
                          child:
                              FittedBox(
                            fit:
                                BoxFit
                                    .scaleDown,
                            child: Text(
                              language
                                  .translate(
                                "cancel",
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(
                        width: 8,
                      ),
                      Expanded(
                        child:
                            FilledButton(
                          onPressed: () {
                            Navigator.pop(
                              dialogContext,
                              true,
                            );
                          },
                          child:
                              FittedBox(
                            fit:
                                BoxFit
                                    .scaleDown,
                            child: Text(
                              language
                                  .translate(
                                "save",
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
          ),
        );
      },
    );

    if (save != true) {
      nameController.dispose();
      notesController.dispose();
      return;
    }

    final name =
        nameController.text
            .trim();

    final notes =
        notesController.text
            .trim();

    nameController.dispose();
    notesController.dispose();

    await _database.updateRecordingDetails(
      recordingId:
          recordingId,
      name: name.isEmpty
          ? language.translate(
              "recording",
            )
          : name,
      notes:
          notes.isEmpty
              ? null
              : notes,
      replaceNotes: true,
      replaceMetadata: true,
      metadataJson: null,
    );

    await _reloadRecordings();
  }

  Future<void> _deleteRecording(
    int recordingId,
    String name,
  ) async {
    final recording = context.read<RecordingProvider>();

    if (recording.recordingId == recordingId) {
      _showMessage(
        context.read<LanguageProvider>().translate(
          "stop_before_delete",
        ),
      );
      return;
    }

    final language =
        context.read<LanguageProvider>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            language.translate(
              "delete_recording_question",
            ),
          ),
          content: Text(
            language.translate(
              "delete_recording_description",
              <String, Object?>{
                "name": name,
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: Text(
                language.translate(
                  "cancel",
                ),
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              child: Text(
                language.translate(
                  "delete",
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _database.deleteRecording(recordingId);
      await _reloadRecordings();

      if (mounted) {
        _showMessage(
          context.read<LanguageProvider>().translate(
            "recording_deleted",
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        _showMessage(
          context.read<LanguageProvider>().translate(
            "could_not_delete_recording",
            <String, Object?>{"error": error},
          ),
        );
      }
    }
  }

  void _showMessage(String message) {
    // Intentionally no snackbar. Recording state/errors are reflected
    // by the page/provider instead of transient bottom popups.
  }

  String _defaultRecordingName() {
    final now = DateTime.now();

    final base = context
        .read<LanguageProvider>()
        .translate("recording");

    return '$base ${_formatDate(now)} ${_two(now.hour)}:${_two(now.minute)}';
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${_two(date.month)}-${_two(date.day)}';
  }

  String _formatDateTime(int milliseconds) {
    final date = DateTime.fromMillisecondsSinceEpoch(milliseconds);

    return '${_formatDate(date)}  ${_two(date.hour)}:${_two(date.minute)}';
  }

  String _formatDurationFromUs(int microseconds) {
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

  String _two(int value) {
    return value.toString().padLeft(2, '0');
  }

  @override
  Widget build(BuildContext context) {
    final recording =
        context.watch<RecordingProvider>();
    final language =
        context.watch<LanguageProvider>();

    return SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: true,
      minimum: const EdgeInsets.only(bottom: 12),
      child: RefreshIndicator(
        onRefresh: _reloadRecordings,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              sliver: SliverToBoxAdapter(
                child: _buildHeader(context, recording),
              ),
            ),
            if (recording.hasActiveRecording ||
                !recording.initialized ||
                recording.hasError)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                sliver: SliverToBoxAdapter(
                  child: _buildActiveRecording(context, recording),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Text(
                      language.translate(
                        "saved_recordings",
                      ),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const Spacer(),
                    if (!_loading)
                      Text(
                        '${_visibleRecordings(recording).length}',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                  ],
                ),
              ),
            ),
            ..._buildRecordingSlivers(context, recording),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    RecordingProvider recording,
  ) {
    final scheme =
        Theme.of(context).colorScheme;
    final language =
        context.watch<LanguageProvider>();
    final busy = recording.isStarting ||
        recording.isStopping ||
        !recording.initialized;

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed:
                recording.isIdle &&
                        !busy &&
                        recording.bleConnected
                    ? _showCreateRecordingDialog
                    : null,
            icon: recording.isStarting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.add_rounded),
            label: Text(
              recording.isStarting
                  ? language.translate(
                      "starting",
                    )
                  : recording.hasActiveRecording
                      ? language.translate(
                          "recording_active",
                        )
                      : language.translate(
                          "create_recording",
                        ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton.icon(
          onPressed: _importing || recording.hasActiveRecording
              ? null
              : _importRecording,
          icon: _importing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                )
              : const Icon(Icons.file_open_rounded),
          label: Text(
            language.translate(
              "open",
            ),
          ),
        ),
        if (recording.hasError && recording.lastError != null) ...[
          const SizedBox(width: 8),
          Icon(
            Icons.error_outline_rounded,
            color: scheme.error,
          ),
        ],
      ],
    );
  }

  Widget _buildActiveRecording(
    BuildContext context,
    RecordingProvider recording,
  ) {
    final scheme =
        Theme.of(context).colorScheme;
    final language =
        context.watch<LanguageProvider>();

    if (!recording.initialized && !recording.hasError) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: scheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
              ),
            ),
            const SizedBox(
              width: 14,
            ),
            Expanded(
              child: Text(
                language.translate(
                  "preparing_storage",
                ),
                maxLines: 2,
                overflow:
                    TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    if (recording.hasError && recording.recordingId == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: scheme.error.withValues(alpha: 0.35),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              language.translate(
                "recording_storage_error",
              ),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onErrorContainer,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              recording.lastError ??
                  language.translate(
                    "unknown_error",
                  ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: recording.clearError,
              child: Text(
                language.translate(
                  "dismiss",
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (!recording.hasActiveRecording) {
      return const SizedBox.shrink();
    }

    final paused = recording.isPaused;
    final disconnected = !recording.bleConnected;
    final writingError = recording.lastError != null;
    final elapsed = recording.timelineDuration;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: writingError
              ? scheme.error.withValues(alpha: 0.65)
              : paused || disconnected
                  ? scheme.tertiary.withValues(alpha: 0.55)
                  : scheme.primary.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RecordingPulse(
                active: recording.isRecording &&
                    recording.bleConnected &&
                    recording.activeGapReason == null,
                paused: paused || disconnected,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  recording.recordingName ??
                      language.translate(
                        "recording",
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _formatDuration(elapsed),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontFeatures: const [
                        FontFeature.tabularFigures(),
                      ],
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StatusChip(
                icon: recording.bleConnected
                    ? Icons.bluetooth_connected_rounded
                    : Icons.bluetooth_disabled_rounded,
                label: recording.bleConnected
                    ? language.translate(
                        "device_connected",
                      )
                    : language.translate(
                        "signal_gap",
                      ),
              ),
              _StatusChip(
                icon: paused
                    ? Icons.pause_rounded
                    : Icons.fiber_manual_record_rounded,
                label: paused
                    ? language.translate(
                        "paused",
                      )
                    : disconnected
                        ? language.translate(
                            "waiting_for_device",
                          )
                        : language.translate(
                            "recording",
                          ),
              ),
              _StatusChip(
                icon: Icons.save_outlined,
                label: recording.hasPendingWrites
                    ? language.translate(
                        "pending",
                        <String, Object?>{
                          "count":
                              recording.pendingChunkWrites,
                        },
                      )
                    : language.translate(
                        "saved",
                      ),
              ),
            ],
          ),
          if (recording.notes != null &&
              recording.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              recording.notes!,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
          if (writingError) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recording.lastError!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onErrorContainer,
                        ),
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _retryWrites,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(
                      language.translate(
                        "retry_save",
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: recording.isStopping ||
                          recording.isStarting ||
                          writingError
                      ? null
                      : paused
                          ? _resumeRecording
                          : _pauseRecording,
                  icon: Icon(
                    paused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                  ),
                  label: Text(
                    paused
                        ? language.translate(
                            "resume",
                          )
                        : language.translate(
                            "pause",
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: recording.isStopping
                      ? null
                      : _stopRecording,
                  icon: recording.isStopping
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.stop_rounded),
                  label: Text(
                    recording.isStopping
                        ? language.translate(
                            "saving",
                          )
                        : language.translate(
                            "stop",
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Map<String, Object?>> _visibleRecordings(
    RecordingProvider recording,
  ) {
    final activeId = recording.recordingId;

    if (activeId == null) {
      return _recordings;
    }

    return _recordings
        .where((row) => row['id'] != activeId)
        .toList(growable: false);
  }

  List<Widget> _buildRecordingSlivers(
    BuildContext context,
    RecordingProvider recording,
  ) {
    if (_loading) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      ];
    }

    if (_loadError != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _ErrorView(
            message: _loadError!,
            onRetry: _reloadRecordings,
          ),
        ),
      ];
    }

    final visible = _visibleRecordings(recording);

    if (visible.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _EmptyRecordingsView(
            onCreate:
                recording.isIdle &&
                        recording.bleConnected
                    ? _showCreateRecordingDialog
                    : null,
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        sliver: SliverList.separated(
          itemCount: visible.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final row = visible[index];

            return _RecordingTile(
              row: row,
              formatDateTime: _formatDateTime,
              formatDuration: _formatDurationFromUs,
              onTap: () {
                _openRecording(row['id'] as int);
              },
              onEdit: () {
                _editRecording(
                  row,
                );
              },
              onPdf: () {
                _shareRecordingPdf(
                  row['id'] as int,
                );
              },
              onDelete: () {
                _deleteRecording(
                  row['id'] as int,
                  row['name'] as String? ??
                      context
                          .read<LanguageProvider>()
                          .translate(
                            "recording",
                          ),
                );
              },
            );
          },
        ),
      ),
    ];
  }
}

class _CreateRecordingData {
  final String name;
  final String notes;

  const _CreateRecordingData({
    required this.name,
    required this.notes,
  });
}

class _RecordingTile
    extends StatefulWidget {
  final Map<String, Object?> row;
  final String Function(int milliseconds)
      formatDateTime;
  final String Function(int microseconds)
      formatDuration;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onPdf;
  final VoidCallback onDelete;

  const _RecordingTile({
    required this.row,
    required this.formatDateTime,
    required this.formatDuration,
    required this.onTap,
    required this.onEdit,
    required this.onPdf,
    required this.onDelete,
  });

  @override
  State<_RecordingTile> createState() =>
      _RecordingTileState();
}

class _RecordingTileState
    extends State<_RecordingTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme =
        Theme.of(context).colorScheme;
    final language =
        context.watch<LanguageProvider>();
    final uiPreferences =
        context.watch<UiPreferencesProvider>();

    final row = widget.row;

    final name =
        row['name'] as String? ??
        language.translate(
          "recording",
        );

    final startedAtMs =
        row['started_at_ms'] as int? ??
        0;

    final timelineUs =
        row['timeline_duration_us']
            as int? ??
        0;

    final recordedSamples =
        row['recorded_sample_count']
            as int? ??
        0;

    final sampleRate =
        (row['sample_rate'] as num?)
                ?.toDouble() ??
            250.0;

    final status =
        row['status'] as String? ??
        'completed';

    final measuredSeconds =
        sampleRate <= 0
            ? 0.0
            : recordedSamples /
                sampleRate;

    return Material(
      color:
          scheme.surfaceContainer,
      borderRadius:
          BorderRadius.circular(14),
      clipBehavior:
          Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius:
              BorderRadius.circular(14),
          border: Border.all(
            color:
                scheme.outlineVariant,
          ),
        ),
        child: Column(
          children: [
            InkWell(
              onTap: widget.onTap,
              child: Padding(
                padding:
                    EdgeInsets.fromLTRB(
                  14,
                  uiPreferences.compactRecordingList
                      ? 9
                      : 13,
                  4,
                  uiPreferences.compactRecordingList
                      ? 9
                      : 13,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration:
                                    BoxDecoration(
                                  shape:
                                      BoxShape.circle,
                                  color:
                                      _statusColor(
                                    context,
                                    status,
                                  ),
                                ),
                              ),
                              const SizedBox(
                                width: 9,
                              ),
                              Expanded(
                                child: Text(
                                  name,
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
                                          ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(
                            height:
                                uiPreferences.compactRecordingList
                                    ? 2
                                    : 4,
                          ),
                          Text(
                            widget
                                .formatDateTime(
                              startedAtMs,
                            ),
                            maxLines: 1,
                            overflow:
                                TextOverflow
                                    .ellipsis,
                            style:
                                Theme.of(
                              context,
                            )
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color:
                                          scheme
                                              .onSurfaceVariant,
                                    ),
                          ),
                          SizedBox(
                            height:
                                uiPreferences.compactRecordingList
                                    ? 3
                                    : 5,
                          ),
                          Text(
                            '${language.translate(
                              "measured",
                              <String, Object?>{
                                "duration":
                                    _formatMeasured(
                                  measuredSeconds,
                                ),
                              },
                            )}'
                            '${status == "completed" ? "" : "  ·  ${_statusLabel(language, status)}"}',
                            maxLines: 1,
                            overflow:
                                TextOverflow
                                    .ellipsis,
                            style:
                                Theme.of(
                              context,
                            )
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      color:
                                          scheme
                                              .onSurfaceVariant,
                                      fontWeight:
                                          FontWeight
                                              .w500,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip:
                          language.translate(
                        "more",
                      ),
                      onPressed: () {
                        setState(() {
                          _expanded =
                              !_expanded;
                        });
                      },
                      icon:
                          AnimatedRotation(
                        turns:
                            _expanded
                                ? 0.5
                                : 0,
                        duration:
                            const Duration(
                          milliseconds:
                              180,
                        ),
                        child: const Icon(
                          Icons
                              .keyboard_arrow_down_rounded,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration:
                  const Duration(
                milliseconds: 180,
              ),
              curve:
                  Curves.easeOutCubic,
              child: _expanded
                  ? Column(
                      children: [
                        Divider(
                          height: 1,
                          color: scheme
                              .outlineVariant,
                        ),
                        Padding(
                          padding:
                              const EdgeInsets
                                  .fromLTRB(
                            8,
                            5,
                            8,
                            6,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child:
                                    TextButton.icon(
                                  onPressed:
                                      widget.onEdit,
                                  icon: const Icon(
                                    Icons
                                        .edit_outlined,
                                    size: 18,
                                  ),
                                  label:
                                      FittedBox(
                                    fit: BoxFit
                                        .scaleDown,
                                    child:
                                        Text(
                                      language
                                          .translate(
                                        "edit",
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child:
                                    TextButton.icon(
                                  onPressed:
                                      widget.onPdf,
                                  icon: const Icon(
                                    Icons
                                        .picture_as_pdf_outlined,
                                    size: 18,
                                  ),
                                  label:
                                      const FittedBox(
                                    fit: BoxFit
                                        .scaleDown,
                                    child:
                                        Text(
                                      'PDF',
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child:
                                    TextButton.icon(
                                  onPressed:
                                      widget
                                          .onDelete,
                                  icon: Icon(
                                    Icons
                                        .delete_outline_rounded,
                                    size: 18,
                                    color: scheme
                                        .error,
                                  ),
                                  label:
                                      FittedBox(
                                    fit: BoxFit
                                        .scaleDown,
                                    child:
                                        Text(
                                      language
                                          .translate(
                                        "delete",
                                      ),
                                      style:
                                          TextStyle(
                                        color:
                                            scheme
                                                .error,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatMeasured(
    double seconds,
  ) {
    final duration = Duration(
      milliseconds:
          (seconds * 1000).round(),
    );

    final totalSeconds =
        duration.inSeconds;
    final days =
        totalSeconds ~/ 86400;
    final hours =
        (totalSeconds % 86400) ~/
        3600;
    final minutes =
        (totalSeconds % 3600) ~/ 60;
    final secs =
        totalSeconds % 60;

    String two(
      int value,
    ) =>
        value
            .toString()
            .padLeft(2, '0');

    if (days > 0) {
      return '${days}d ${two(hours)}:${two(minutes)}:${two(secs)}';
    }

    if (hours > 0) {
      return '${two(hours)}:${two(minutes)}:${two(secs)}';
    }

    return '${two(minutes)}:${two(secs)}';
  }

  static String _statusLabel(
    LanguageProvider language,
    String status,
  ) {
    switch (status) {
      case 'interrupted':
        return language.translate(
          "interrupted",
        );
      case 'paused':
        return language.translate(
          "paused",
        );
      case 'recording':
        return language.translate(
          "recording",
        );
      default:
        return language.translate(
          "completed",
        );
    }
  }

  static Color _statusColor(
    BuildContext context,
    String status,
  ) {
    final scheme =
        Theme.of(context).colorScheme;

    switch (status) {
      case 'interrupted':
        return scheme.error;
      case 'paused':
        return scheme.tertiary;
      case 'recording':
        return scheme.error;
      default:
        return scheme.primary;
    }
  }
}

class _SmallInfo extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SmallInfo({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
              ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _StatusChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: scheme.surfaceContainerHighest,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _RecordingPulse extends StatefulWidget {
  final bool active;
  final bool paused;

  const _RecordingPulse({
    required this.active,
    required this.paused,
  });

  @override
  State<_RecordingPulse> createState() => _RecordingPulseState();
}

class _RecordingPulseState extends State<_RecordingPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _opacity = Tween<double>(
      begin: 1.0,
      end: 0.30,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    _updateAnimation();
  }

  @override
  void didUpdateWidget(covariant _RecordingPulse oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.active != widget.active ||
        oldWidget.paused != widget.paused) {
      _updateAnimation();
    }
  }

  void _updateAnimation() {
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
    final scheme = Theme.of(context).colorScheme;

    final color = widget.paused ? scheme.tertiary : scheme.error;

    return FadeTransition(
      opacity: widget.active
          ? _opacity
          : const AlwaysStoppedAnimation<double>(1),
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }
}

class _EmptyRecordingsView extends StatelessWidget {
  final VoidCallback? onCreate;

  const _EmptyRecordingsView({
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    final scheme =
        Theme.of(context).colorScheme;
    final language =
        context.watch<LanguageProvider>();

    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 16, 28, 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open_rounded,
              size: 58,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              language.translate("no_recordings_yet"),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              language.translate("no_recordings_description"),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            if (onCreate != null) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded),
                label: Text(
                  language.translate(
                    "create_recording",
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorView({
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
        padding: const EdgeInsets.fromLTRB(28, 16, 28, 80),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 54,
              color: scheme.error,
            ),
            const SizedBox(height: 14),
            Text(
              language.translate("could_not_load_recordings"),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(
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
