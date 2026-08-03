import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  bool darkmode = false;

  ThemeProvider() {
    loadFromLocal();
  }

  Future<void> loadFromLocal() async {
    final prefs = await SharedPreferences.getInstance();
    darkmode = prefs.getBool('darkmode') ?? false;

    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    darkmode = value;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("darkmode", value);
  }
}
