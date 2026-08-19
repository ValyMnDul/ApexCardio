import 'dart:async';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

typedef RecordingBackgroundCommand = Future<void> Function();

class RecordingBackgroundService {
  static final RecordingBackgroundService instance =
      RecordingBackgroundService._internal();

  RecordingBackgroundService._internal();

  static const int serviceId = 1292;

  static const String _channelId = 'apexcardio_recording';
  static const String _channelName = 'ApexCardio Recording';
  static const String _channelDescription =
      'Keeps an active ApexCardio recording running while the app is in the background.';

  static const String _commandType = 'recording_command';
  static const String _commandPause = 'pause';
  static const String _commandResume = 'resume';
  static const String _commandStop = 'stop';

  bool _initialized = false;
  bool _callbackRegistered = false;

  RecordingBackgroundCommand? _onPause;
  RecordingBackgroundCommand? _onResume;
  RecordingBackgroundCommand? _onStop;

  static void prepareCommunication() {
    FlutterForegroundTask.initCommunicationPort();
  }

  Future<void> initialize() async {
    if (_initialized || !Platform.isAndroid) {
      _initialized = true;
      return;
    }

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: _channelName,
        channelDescription: _channelDescription,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(5000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );

    if (!_callbackRegistered) {
      FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
      _callbackRegistered = true;
    }

    _initialized = true;
  }

  void bindCommands({
    required RecordingBackgroundCommand onPause,
    required RecordingBackgroundCommand onResume,
    required RecordingBackgroundCommand onStop,
  }) {
    _onPause = onPause;
    _onResume = onResume;
    _onStop = onStop;
  }

  void unbindCommands() {
    _onPause = null;
    _onResume = null;
    _onStop = null;
  }

  Future<bool> requestNotificationPermission() async {
    if (!Platform.isAndroid) {
      return true;
    }

    await initialize();

    final current = await FlutterForegroundTask.checkNotificationPermission();

    if (current == NotificationPermission.granted) {
      return true;
    }

    final result = await FlutterForegroundTask.requestNotificationPermission();

    return result == NotificationPermission.granted;
  }

  Future<void> start({
    required int recordingId,
    required String recordingName,
    required int startedAtMs,
    required bool paused,
    required bool connected,
  }) async {
    if (!Platform.isAndroid) {
      return;
    }

    await initialize();
    await requestNotificationPermission();

    await FlutterForegroundTask.saveData(
      key: 'recordingId',
      value: recordingId,
    );

    await FlutterForegroundTask.saveData(
      key: 'recordingName',
      value: recordingName,
    );

    await FlutterForegroundTask.saveData(
      key: 'startedAtMs',
      value: startedAtMs,
    );

    await FlutterForegroundTask.saveData(key: 'paused', value: paused);

    await FlutterForegroundTask.saveData(key: 'connected', value: connected);

    final isRunning = await FlutterForegroundTask.isRunningService;

    if (isRunning) {
      await FlutterForegroundTask.stopService();
    }

    await FlutterForegroundTask.startService(
      serviceId: serviceId,
      notificationTitle: recordingName,
      notificationText: _notificationText(
        elapsed: Duration(
          milliseconds: DateTime.now().millisecondsSinceEpoch - startedAtMs,
        ),
        paused: paused,
        connected: connected,
      ),
      notificationButtons: _notificationButtons(paused: paused),
      notificationInitialRoute: '/',
      callback: apexCardioRecordingTaskCallback,
    );
  }

  Future<void> update({
    required String recordingName,
    required int startedAtMs,
    required bool paused,
    required bool connected,
  }) async {
    if (!Platform.isAndroid) {
      return;
    }

    await initialize();

    if (!await FlutterForegroundTask.isRunningService) {
      return;
    }

    await FlutterForegroundTask.saveData(
      key: 'recordingName',
      value: recordingName,
    );

    await FlutterForegroundTask.saveData(
      key: 'startedAtMs',
      value: startedAtMs,
    );

    await FlutterForegroundTask.saveData(key: 'paused', value: paused);

    await FlutterForegroundTask.saveData(key: 'connected', value: connected);

    FlutterForegroundTask.sendDataToTask(<String, dynamic>{
      'type': 'recording_state',
      'recordingName': recordingName,
      'startedAtMs': startedAtMs,
      'paused': paused,
      'connected': connected,
    });

    await FlutterForegroundTask.updateService(
      notificationTitle: recordingName,
      notificationText: _notificationText(
        elapsed: Duration(
          milliseconds: DateTime.now().millisecondsSinceEpoch - startedAtMs,
        ),
        paused: paused,
        connected: connected,
      ),
      notificationButtons: _notificationButtons(paused: paused),
    );
  }

  Future<void> showStopping({required String recordingName}) async {
    if (!Platform.isAndroid) {
      return;
    }

    if (!await FlutterForegroundTask.isRunningService) {
      return;
    }

    await FlutterForegroundTask.updateService(
      notificationTitle: recordingName,
      notificationText: 'Finalizing and saving recording...',
      notificationButtons: const <NotificationButton>[],
    );
  }

  Future<void> stop() async {
    if (!Platform.isAndroid) {
      return;
    }

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }

    await FlutterForegroundTask.removeData(key: 'recordingId');

    await FlutterForegroundTask.removeData(key: 'recordingName');

    await FlutterForegroundTask.removeData(key: 'startedAtMs');

    await FlutterForegroundTask.removeData(key: 'paused');

    await FlutterForegroundTask.removeData(key: 'connected');
  }

  Future<void> _onReceiveTaskData(Object data) async {
    if (data is! Map) {
      return;
    }

    final type = data['type'];

    if (type != _commandType) {
      return;
    }

    final command = data['command'];

    switch (command) {
      case _commandPause:
        final callback = _onPause;

        if (callback != null) {
          await callback();
        }

        break;

      case _commandResume:
        final callback = _onResume;

        if (callback != null) {
          await callback();
        }

        break;

      case _commandStop:
        final callback = _onStop;

        if (callback != null) {
          await callback();
        }

        break;
    }
  }

  static List<NotificationButton> _notificationButtons({required bool paused}) {
    return <NotificationButton>[
      NotificationButton(
        id: paused ? _commandResume : _commandPause,
        text: paused ? 'Resume' : 'Pause',
      ),
      const NotificationButton(id: _commandStop, text: 'Stop'),
    ];
  }

  static String _notificationText({
    required Duration elapsed,
    required bool paused,
    required bool connected,
  }) {
    final status = paused
        ? 'Paused'
        : connected
        ? 'Recording'
        : 'Signal gap';

    final connection = connected
        ? 'ApexCardio connected'
        : 'Waiting for ApexCardio';

    return '${_formatDuration(elapsed)} • $status • $connection';
  }

  static String _formatDuration(Duration duration) {
    var totalSeconds = duration.inSeconds;

    if (totalSeconds < 0) {
      totalSeconds = 0;
    }

    final days = totalSeconds ~/ 86400;
    final hours = (totalSeconds % 86400) ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    String two(int value) => value.toString().padLeft(2, '0');

    if (days > 0) {
      return '${days}d ${two(hours)}:${two(minutes)}:${two(seconds)}';
    }

    return '${two(hours)}:${two(minutes)}:${two(seconds)}';
  }

  void dispose() {
    if (_callbackRegistered) {
      FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
      _callbackRegistered = false;
    }

    unbindCommands();
  }
}

@pragma('vm:entry-point')
void apexCardioRecordingTaskCallback() {
  FlutterForegroundTask.setTaskHandler(ApexCardioRecordingTaskHandler());
}

class ApexCardioRecordingTaskHandler extends TaskHandler {
  String _recordingName = 'ApexCardio Recording';
  int _startedAtMs = 0;
  bool _paused = false;
  bool _connected = true;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final recordingName = await FlutterForegroundTask.getData<String>(
      key: 'recordingName',
    );

    final startedAtMs = await FlutterForegroundTask.getData<int>(
      key: 'startedAtMs',
    );

    final paused = await FlutterForegroundTask.getData<bool>(key: 'paused');

    final connected = await FlutterForegroundTask.getData<bool>(
      key: 'connected',
    );

    if (recordingName != null && recordingName.trim().isNotEmpty) {
      _recordingName = recordingName;
    }

    _startedAtMs = startedAtMs ?? timestamp.millisecondsSinceEpoch;

    _paused = paused ?? false;
    _connected = connected ?? true;

    await _refreshNotification(timestamp);
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_refreshNotification(timestamp));
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) {
      return;
    }

    if (data['type'] != 'recording_state') {
      return;
    }

    final recordingName = data['recordingName'];

    final startedAtMs = data['startedAtMs'];

    final paused = data['paused'];

    final connected = data['connected'];

    if (recordingName is String && recordingName.trim().isNotEmpty) {
      _recordingName = recordingName;
    }

    if (startedAtMs is int) {
      _startedAtMs = startedAtMs;
    }

    if (paused is bool) {
      _paused = paused;
    }

    if (connected is bool) {
      _connected = connected;
    }

    unawaited(_refreshNotification(DateTime.now()));
  }

  @override
  void onNotificationButtonPressed(String id) {
    switch (id) {
      case 'pause':
        _paused = true;

        FlutterForegroundTask.sendDataToMain(const <String, dynamic>{
          'type': 'recording_command',
          'command': 'pause',
        });

        break;

      case 'resume':
        _paused = false;

        FlutterForegroundTask.sendDataToMain(const <String, dynamic>{
          'type': 'recording_command',
          'command': 'resume',
        });

        break;

      case 'stop':
        FlutterForegroundTask.sendDataToMain(const <String, dynamic>{
          'type': 'recording_command',
          'command': 'stop',
        });

        unawaited(
          FlutterForegroundTask.updateService(
            notificationTitle: _recordingName,
            notificationText: 'Finalizing and saving recording...',
            notificationButtons: const <NotificationButton>[],
          ),
        );

        return;
    }

    unawaited(_refreshNotification(DateTime.now()));
  }

  @override
  void onNotificationPressed() {}

  @override
  void onNotificationDismissed() {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  Future<void> _refreshNotification(DateTime timestamp) async {
    final elapsed = Duration(
      milliseconds: timestamp.millisecondsSinceEpoch - _startedAtMs,
    );

    await FlutterForegroundTask.updateService(
      notificationTitle: _recordingName,
      notificationText: RecordingBackgroundService._notificationText(
        elapsed: elapsed,
        paused: _paused,
        connected: _connected,
      ),
      notificationButtons: RecordingBackgroundService._notificationButtons(
        paused: _paused,
      ),
    );
  }
}
