import 'package:apexcardio/providers/theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Column(
      children: [
        SizedBox(height: 10),
        SwitchListTile(
          title: themeProvider.darkmode
              ? Text("Light Mode")
              : Text("Dark Mode"),
          value: themeProvider.darkmode,
          secondary: themeProvider.darkmode
              ? Icon(Icons.light_mode)
              : Icon(Icons.dark_mode),
          onChanged: (value) {
            themeProvider.setDarkMode(value);
          },
        ),
      ],
    );
  }
}
