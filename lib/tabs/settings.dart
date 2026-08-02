import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme.dart';
import '../providers/language.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final languageProvider = Provider.of<LanguageProvider>(context);

    return Column(
      children: [
        SizedBox(height: 10),
        SwitchListTile(
          title: themeProvider.darkmode
              ? Text(languageProvider.translate("light_mode"))
              : Text(languageProvider.translate("dark_mode")),
          value: themeProvider.darkmode,
          secondary: themeProvider.darkmode
              ? Icon(Icons.light_mode)
              : Icon(Icons.dark_mode),
          onChanged: (value) {
            themeProvider.setDarkMode(value);
          },
        ),
        ListTile(
          leading: Icon(Icons.translate),
          title: Text(languageProvider.translate("language_title")),
          trailing: SegmentedButton(
            segments: [
              ButtonSegment(value: "EN", label: Text("EN")),
              ButtonSegment(value: "RO", label: Text("RO")),
            ],
            selected: {languageProvider.currentLang},
            onSelectionChanged: (Set<String> newSelection) {
              languageProvider.setLanguage(newSelection.first);
            },
          ),
        ),
      ],
    );
  }
}
