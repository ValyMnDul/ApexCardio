import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LiveEcgProvider extends ChangeNotifier {
  bool _showGrid = true;
  bool get showGrid => _showGrid;

  LiveEcgProvider() {
    _loadFromLocal();
  }

  Future<void> _loadFromLocal() async {
    final prefs = await SharedPreferences.getInstance();
    _showGrid = prefs.getBool("show_grid") ?? true;
  }

  Future<void> toggleGrid(bool value) async {
    _showGrid = value;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool("show_grid", value);
  }
}
