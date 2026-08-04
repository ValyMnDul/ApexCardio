import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme.dart';
import '../providers/language.dart';
import '../providers/font.dart';
import '../providers/ble.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  void _showBleScanDialog(BuildContext context) {
    final bleProvider = Provider.of<BleProvider>(context);
    final languageProvider = Provider.of<LanguageProvider>(context);
    bleProvider.startScan();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Consumer<BleProvider>(
          builder: (context, ble, child) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.6,
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        languageProvider.translate("available_devices"),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        onPressed: bleProvider.isScanning
                            ? bleProvider.stopScan
                            : bleProvider.startScan,
                        icon: Icon(
                          bleProvider.isScanning ? Icons.stop : Icons.refresh,
                        ),
                      ),
                    ],
                  ),
                  if (bleProvider.isScanning) LinearProgressIndicator(),
                  SizedBox(height: 10),
                  Expanded(
                    child: bleProvider.scanResults.isEmpty
                        ? Center(
                            child: Text(
                              languageProvider.translate("no_device"),
                            ),
                          )
                        : ListView.builder(
                            itemBuilder: (context, index) {
                              final result = ble.scanResults[index];
                              final isApex =
                                  result.device.platformName == "ApexCardio";

                              return ListTile(
                                leading: Icon(
                                  Icons.bluetooth,
                                  color: isApex ? Colors.blue : Colors.grey,
                                ),
                                title: Text(
                                  result.device.platformName,
                                  style: TextStyle(
                                    fontWeight: isApex
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                                subtitle: Text(
                                  result.device.remoteId.toString(),
                                ),
                                trailing: ElevatedButton(
                                  onPressed: () async {},
                                  child: Text(
                                    languageProvider.translate(
                                      "ble_connect_to_device",
                                    ),
                                  ),
                                ),
                              );
                            },
                            itemCount: bleProvider.scanResults.length,
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final languageProvider = Provider.of<LanguageProvider>(context);
    final fontScaleProvider = Provider.of<FontScaleProvider>(context);
    final bleProvider = Provider.of<BleProvider>(context);

    final textColor = Theme.of(context).colorScheme.onSurface;

    return Column(
      children: [
        SizedBox(height: 10),
        ListTile(
          leading: Icon(
            bleProvider.isConnected
                ? Icons.bluetooth_connected
                : Icons.bluetooth_disabled,
            color: bleProvider.isConnected ? Colors.green : Colors.red,
          ),
          title: Text(
            bleProvider.isConnected
                ? languageProvider.translate("ble_connected")
                : languageProvider.translate("ble_disconnected"),
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            bleProvider.isConnected
                ? bleProvider.deviceName
                : languageProvider.translate("press_to_scan"),
          ),
          trailing: bleProvider.isConnected
              ? IconButton(
                  onPressed: () {
                    bleProvider.disconnect();
                  },
                  icon: Icon(Icons.close, color: Colors.red),
                )
              : ElevatedButton(
                  onPressed: () {
                    _showBleScanDialog(context);
                  },
                  child: Text(languageProvider.translate("ble_search")),
                ),
        ),
        Divider(thickness: 0.5, color: Colors.grey[600]),
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
