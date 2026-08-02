import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme.dart';
import '../providers/language.dart';
import '../providers/font.dart';

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
    final fontScaleProvider = Provider.of<FontScaleProvider>(context);

    final textColor = Theme.of(context).colorScheme.onSurface;

    return Column(
      children: [
        SizedBox(height: 10),
        SwitchListTile(
          title: themeProvider.darkmode
              ? Text(languageProvider.translate("light_mode"))
              : Text(languageProvider.translate("dark_mode")),
          value: themeProvider.darkmode,
          secondary: themeProvider.darkmode
              ? Icon(Icons.light_mode, color: textColor)
              : Icon(Icons.dark_mode, color: textColor),
          onChanged: (value) {
            themeProvider.setDarkMode(value);
          },
        ),
        ListTile(
          leading: Icon(Icons.translate, color: textColor),
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 15.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Row(
                children: [
                  Icon(Icons.text_fields, color: textColor),
                  SizedBox(width: 16),
                  Text(
                    languageProvider.translate("font_scale_title"),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: SegmentedButton<double>(
                  segments: [
                    ButtonSegment(
                      value: 0.85,
                      label: Text(
                        languageProvider.translate("font_scale_title_small"),
                      ),
                    ),
                    ButtonSegment(
                      value: 1.0,
                      label: Text(
                        languageProvider.translate("font_scale_title_normal"),
                      ),
                    ),
                    ButtonSegment(
                      value: 1.15,
                      label: Text(
                        languageProvider.translate("font_scale_title_big"),
                      ),
                    ),
                  ],
                  selected: {fontScaleProvider.fontScale},
                  onSelectionChanged: (Set<double> newSelection) {
                    fontScaleProvider.setFontScale(newSelection.first);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
