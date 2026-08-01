import 'package:flutter/material.dart';

class ThemeProvider extends ChangeNotifier {
  bool darkmode = false;

  void setDarkMode(bool value) {
    darkmode = value;
    notifyListeners();
  }
}
