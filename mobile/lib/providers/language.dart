import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LanguageProvider extends ChangeNotifier {
  String currentLang = "EN";

  LanguageProvider() {
    loadFromLocal();
  }

  Future<void> loadFromLocal() async {
    final prefs = await SharedPreferences.getInstance();
    currentLang = prefs.getString("language") ?? "EN";

    notifyListeners();
  }

  final Map<String, Map<String, String>> dictionary = {
    "EN": {
      "live_tab": 'Live',
      "recordings_tab": "Recordings",

      "settings_tab": "Settings",
      "dark_mode": "Dark Mode",
      "show_grid_title": "Show Grid",
      "language_title": "App Language",
      "font_scale_title": "Font Scale",
      "font_scale_title_small": "Small",
      "font_scale_title_normal": "Normal",
      "font_scale_title_big": "Big",
      "ble_connected": "Device Connected",
      "ble_disconnected": "Device Disconnected",
      "press_to_scan": "Press to scan",
      "ble_search": "Search",
      "available_devices": "Available Devices",
      "ble_connect_to_device": "Connect",
      "succes_connect": "Successfully connected!",
      "error_connect": "Connection error!",
      "no_device": "No devices :(",
      "unknown_device": "Unknown Device",
    },
    "RO": {
      "live_tab": "Live",
      "recordings_tab": "Înregistrări",

      "settings_tab": "Setări",
      "dark_mode": "Mod întunecat",
      "show_grid_title": "Arată grila",
      "language_title": "Limbă aplicație",
      "font_scale_title": "Mărime Font",
      "font_scale_title_small": "Mic",
      "font_scale_title_normal": "Normal",
      "font_scale_title_big": "Mare",
      "ble_connected": "Dispozitiv Conectat",
      "ble_disconnected": "Dispozitiv Deconectat",
      "press_to_scan": "Apasa pentru a scana",
      "ble_search": "Caută",
      "available_devices": "Dispozitive Disponibile",
      "ble_connect_to_device": "Conectează",
      "succes_connect": "Conectat cu succes!",
      "error_connect": "Eroare la conectare!",
      "no_device": "Niciun dispozitiv :(",
      "unknown_device": "Dispozitiv necunoscut",
    },
    "DE": {},
    "RU": {},
    "ES": {},
  };

  String translate(String key) {
    return dictionary[currentLang]?[key] ?? key;
  }

  Future<void> setLanguage(String langCode) async {
    currentLang = langCode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("language", langCode);
  }
}
