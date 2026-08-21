import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UiPreferencesProvider extends ChangeNotifier {
  bool showRecordingIndicator = true;
  bool animateRecordingIndicator = true;
  bool compactRecordingList = false;

  UiPreferencesProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    showRecordingIndicator =
        prefs.getBool('ui_show_recording_indicator') ?? true;

    animateRecordingIndicator =
        prefs.getBool('ui_animate_recording_indicator') ?? true;

    compactRecordingList =
        prefs.getBool('ui_compact_recording_list') ?? false;

    notifyListeners();
  }

  Future<void> setShowRecordingIndicator(bool value) async {
    showRecordingIndicator = value;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      'ui_show_recording_indicator',
      value,
    );
  }

  Future<void> setAnimateRecordingIndicator(bool value) async {
    animateRecordingIndicator = value;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      'ui_animate_recording_indicator',
      value,
    );
  }

  Future<void> setCompactRecordingList(bool value) async {
    compactRecordingList = value;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      'ui_compact_recording_list',
      value,
    );
  }
}
