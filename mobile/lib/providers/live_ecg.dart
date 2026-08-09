import 'package:flutter/material.dart';

class LiveEcgProvider extends ChangeNotifier {
  bool _showGrid = true;
  bool get showGrid => _showGrid;

  void toggleGrid(bool value) {
    _showGrid = value;
    notifyListeners();
  }
}
