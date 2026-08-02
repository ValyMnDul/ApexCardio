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
      "light_mode": "Light Mode",
      "language_title": "App Language",
    },
    "RO": {
      "live_tab": "Live",
      "recordings_tab": "Înregistrări",
      "settings_tab": "Setări",

      "dark_mode": "Mod întunecat",
      "light_mode": "Mod luminos",
      "language_title": "Limbă aplicație",
    },
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
