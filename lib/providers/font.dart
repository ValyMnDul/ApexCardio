import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FontScaleProvider extends ChangeNotifier {
  double fontScale = 1.0;

  FontScaleProvider() {
    loadFromLocal();
  }

  Future<void> loadFromLocal() async {
    final prefs = await SharedPreferences.getInstance();
    fontScale = prefs.getDouble("font_scale") ?? 1.0;

    notifyListeners();
  }

  Future<void> setFontScale(double scale) async {
    fontScale = scale;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble("font_scale", scale);
  }
}
