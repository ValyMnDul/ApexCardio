import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

enum RecordingLiveActivityCommand { pause, resume, stop }

typedef RecordingLiveActivityCommandCallback = Future<void> Function();

class RecordingLiveActivityService {
  static final RecordingLiveActivityService instance =
      RecordingLiveActivityService._internal();

  RecordingLiveActivityService._internal() {
    _channel.setMethodCallHandler(_handleNativeMethodCall);
  }

  static const MethodChannel _channel = MethodChannel(
    'apexcardio/live_activity',
  );

  RecordingLiveActivityCommandCallback? _onPause;
  RecordingLiveActivityCommandCallback? _onResume;
  RecordingLiveActivityCommandCallback? _onStop;

  RecordingLiveActivityCommand? _pendingCommand;

  bool _disposed = false;

  void bindCommands({
    required RecordingLiveActivityCommandCallback onPause,
    required RecordingLiveActivityCommandCallback onResume,
    required RecordingLiveActivityCommandCallback onStop,
  }) {
    _onPause = onPause;
    _onResume = onResume;
    _onStop = onStop;

    final pending = _pendingCommand;

    if (pending != null) {
      _pendingCommand = null;

      unawaited(_dispatchCommand(pending));
    }
  }

  void unbindCommands() {
    _onPause = null;
    _onResume = null;
    _onStop = null;
  }

  Future<bool> isSupported() async {
    if (!Platform.isIOS || _disposed) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<String?> start({
    required int recordingId,
    required String recordingName,
    required DateTime startedAt,
    required bool isPaused,
    required bool isConnected,
    required String statusText,
  }) async {
    if (!Platform.isIOS || _disposed) {
      return null;
    }

    try {
      return await _channel.invokeMethod<String>('start', <String, Object?>{
        'recordingId': recordingId,
        'recordingName': recordingName,
        'startedAtMs': startedAt.millisecondsSinceEpoch,
        'isPaused': isPaused,
        'isConnected': isConnected,
        'statusText': statusText,
      });
    } on MissingPluginException {
      return null;
    }
  }

  Future<bool> update({
    required int recordingId,
    required bool isPaused,
    required bool isConnected,
    required String statusText,
  }) async {
    if (!Platform.isIOS || _disposed) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>('update', <String, Object?>{
            'recordingId': recordingId,
            'isPaused': isPaused,
            'isConnected': isConnected,
            'statusText': statusText,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<bool> end({
    required int recordingId,
    String finalStatus = 'Saved',
  }) async {
    if (!Platform.isIOS || _disposed) {
      return false;
    }

    try {
      return await _channel.invokeMethod<bool>('end', <String, Object?>{
            'recordingId': recordingId,
            'finalStatus': finalStatus,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<int> endAll() async {
    if (!Platform.isIOS || _disposed) {
      return 0;
    }

    try {
      return await _channel.invokeMethod<int>('endAll') ?? 0;
    } on MissingPluginException {
      return 0;
    }
  }

  Future<dynamic> _handleNativeMethodCall(MethodCall call) async {
    if (_disposed) {
      return null;
    }

    if (call.method != 'recordingCommand') {
      throw MissingPluginException(
        'Unknown ApexCardio Live Activity method: ${call.method}',
      );
    }

    final rawCommand = call.arguments;

    if (rawCommand is! String) {
      throw PlatformException(
        code: 'INVALID_COMMAND',
        message: 'Live Activity command must be a string.',
      );
    }

    final command = _commandFromString(rawCommand);

    if (command == null) {
      throw PlatformException(
        code: 'INVALID_COMMAND',
        message: 'Unknown Live Activity command: $rawCommand',
      );
    }

    final hasHandler = _handlerFor(command) != null;

    if (!hasHandler) {
      _pendingCommand = command;
      return true;
    }

    await _dispatchCommand(command);

    return true;
  }

  RecordingLiveActivityCommand? _commandFromString(String value) {
    switch (value) {
      case 'pause':
        return RecordingLiveActivityCommand.pause;
      case 'resume':
        return RecordingLiveActivityCommand.resume;
      case 'stop':
        return RecordingLiveActivityCommand.stop;
      default:
        return null;
    }
  }

  RecordingLiveActivityCommandCallback? _handlerFor(
    RecordingLiveActivityCommand command,
  ) {
    switch (command) {
      case RecordingLiveActivityCommand.pause:
        return _onPause;
      case RecordingLiveActivityCommand.resume:
        return _onResume;
      case RecordingLiveActivityCommand.stop:
        return _onStop;
    }
  }

  Future<void> _dispatchCommand(RecordingLiveActivityCommand command) async {
    final handler = _handlerFor(command);

    if (handler == null) {
      _pendingCommand = command;
      return;
    }

    await handler();
  }

  void dispose() {
    if (_disposed) {
      return;
    }

    _disposed = true;

    unbindCommands();
    _pendingCommand = null;

    _channel.setMethodCallHandler(null);
  }
}
