import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme.dart';
import '../providers/language.dart';
import '../providers/font.dart';
import '../providers/ble.dart';
import '../providers/live_ecg.dart';
import '../providers/recording.dart';
import '../providers/ui_preferences.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() =>
      _SettingsState();
}

class _SettingsState extends State<Settings> {
  void _showBleScanDialog(
    BuildContext context,
  ) {
    final recording =
        context.read<RecordingProvider>();

    if (recording.hasActiveRecording) {
      final language =
          context.read<LanguageProvider>();

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              language.translate(
                "stop_recording_to_connect",
              ),
            ),
          ),
        );

      return;
    }

    final bleProvider =
        context.read<BleProvider>();

    bleProvider.startScan();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return Consumer2<
            BleProvider,
            LanguageProvider>(
          builder: (
            context,
            ble,
            language,
            child,
          ) {
            return SafeArea(
              top: false,
              child: SizedBox(
                height:
                    MediaQuery.of(context)
                            .size
                            .height *
                        0.62,
                child: Padding(
                  padding:
                      const EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    16,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              language.translate(
                                "available_devices",
                              ),
                              maxLines: 1,
                              overflow:
                                  TextOverflow.ellipsis,
                              style:
                                  Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontWeight:
                                            FontWeight
                                                .w600,
                                      ),
                            ),
                          ),
                          const SizedBox(
                            width: 8,
                          ),
                          IconButton(
                            tooltip:
                                ble.isScanning
                                    ? language
                                        .translate(
                                          "stop_scan",
                                        )
                                    : language
                                        .translate(
                                          "scan_again",
                                        ),
                            onPressed:
                                ble.isScanning
                                    ? ble.stopScan
                                    : ble.startScan,
                            icon: Icon(
                              ble.isScanning
                                  ? Icons
                                      .stop_rounded
                                  : Icons
                                      .refresh_rounded,
                            ),
                          ),
                        ],
                      ),
                      if (ble.isScanning)
                        const Padding(
                          padding:
                              EdgeInsets.only(
                            top: 8,
                          ),
                          child:
                              LinearProgressIndicator(),
                        ),
                      const SizedBox(
                        height: 10,
                      ),
                      Expanded(
                        child:
                            ble.scanResults.isEmpty
                                ? Center(
                                    child:
                                        Text(
                                      language
                                          .translate(
                                        "no_device",
                                      ),
                                      textAlign:
                                          TextAlign
                                              .center,
                                    ),
                                  )
                                : ListView
                                    .separated(
                                    itemCount: ble
                                        .scanResults
                                        .length,
                                    separatorBuilder:
                                        (_, __) =>
                                            Divider(
                                      height: 1,
                                      color: Theme.of(
                                        context,
                                      )
                                          .colorScheme
                                          .outlineVariant,
                                    ),
                                    itemBuilder:
                                        (
                                      context,
                                      index,
                                    ) {
                                      final result =
                                          ble.scanResults[
                                              index];

                                      final name = result
                                              .device
                                              .platformName
                                              .trim()
                                              .isEmpty
                                          ? language
                                              .translate(
                                              "unknown_device",
                                            )
                                          : result
                                              .device
                                              .platformName;

                                      final isApex =
                                          result.device
                                                  .platformName ==
                                              "ApexCardio";

                                      return ListTile(
                                        contentPadding:
                                            const EdgeInsets
                                                .symmetric(
                                          horizontal: 2,
                                        ),
                                        leading:
                                            Icon(
                                          Icons
                                              .bluetooth_rounded,
                                          color: isApex
                                              ? Theme.of(
                                                  context,
                                                )
                                                  .colorScheme
                                                  .primary
                                              : Theme.of(
                                                  context,
                                                )
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                        ),
                                        title: Text(
                                          name,
                                          maxLines: 1,
                                          overflow:
                                              TextOverflow
                                                  .ellipsis,
                                          style: TextStyle(
                                            fontWeight:
                                                isApex
                                                    ? FontWeight
                                                        .w600
                                                    : FontWeight
                                                        .normal,
                                          ),
                                        ),
                                        subtitle:
                                            Text(
                                          result
                                              .device
                                              .remoteId
                                              .toString(),
                                          maxLines: 1,
                                          overflow:
                                              TextOverflow
                                                  .ellipsis,
                                        ),
                                        trailing:
                                            ConstrainedBox(
                                          constraints:
                                              const BoxConstraints(
                                            maxWidth:
                                                116,
                                          ),
                                          child:
                                              FittedBox(
                                            fit: BoxFit
                                                .scaleDown,
                                            child:
                                                FilledButton(
                                              onPressed:
                                                  () async {
                                                final success =
                                                    await ble.connectToDevice(
                                                  result
                                                      .device,
                                                );

                                                if (success) {
                                                  ble.startListeningValues();
                                                }

                                                if (!context
                                                    .mounted) {
                                                  return;
                                                }

                                                Navigator.pop(
                                                  context,
                                                );

                                                ScaffoldMessenger.of(
                                                  context,
                                                )
                                                  ..hideCurrentSnackBar()
                                                  ..showSnackBar(
                                                    SnackBar(
                                                      content:
                                                          Text(
                                                        language.translate(
                                                          success
                                                              ? "succes_connect"
                                                              : "error_connect",
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                              },
                                              child:
                                                  Text(
                                                language
                                                    .translate(
                                                  "ble_connect_to_device",
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider =
        context.watch<ThemeProvider>();
    final languageProvider =
        context.watch<LanguageProvider>();
    final fontScaleProvider =
        context.watch<FontScaleProvider>();
    final bleProvider =
        context.watch<BleProvider>();
    final liveEcgProvider =
        context.watch<LiveEcgProvider>();
    final recordingProvider =
        context.watch<RecordingProvider>();
    final uiPreferences =
        context.watch<UiPreferencesProvider>();
    final scheme =
        Theme.of(context).colorScheme;

    final deviceName = bleProvider.isConnected
        ? bleProvider.deviceName ==
                "unknown_device"
            ? languageProvider.translate(
                "unknown_device",
              )
            : bleProvider.deviceName
        : languageProvider.translate(
            "press_to_scan",
          );

    return SafeArea(
      top: false,
      left: false,
      right: false,
      child: ListView(
        padding:
            const EdgeInsets.fromLTRB(
          0,
          8,
          0,
          28,
        ),
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 8,
            ),
            child: ListTile(
              leading: Icon(
                bleProvider.isConnected
                    ? Icons
                        .bluetooth_connected_rounded
                    : Icons
                        .bluetooth_disabled_rounded,
                color: bleProvider.isConnected
                    ? scheme.primary
                    : scheme.error,
              ),
              title: Text(
                bleProvider.isConnected
                    ? languageProvider
                        .translate(
                          "ble_connected",
                        )
                    : languageProvider
                        .translate(
                          "ble_disconnected",
                        ),
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
              subtitle: Text(
                deviceName,
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
              ),
              trailing:
                  ConstrainedBox(
                constraints:
                    const BoxConstraints(
                  maxWidth: 126,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: bleProvider
                          .isConnected
                      ? TextButton(
                          onPressed:
                              recordingProvider
                                      .hasActiveRecording
                                  ? null
                                  : bleProvider
                                      .disconnect,
                          child: Text(
                            languageProvider
                                .translate(
                              "disconnect",
                            ),
                          ),
                        )
                      : FilledButton(
                          onPressed:
                              recordingProvider
                                      .hasActiveRecording
                                  ? null
                                  : () {
                                      _showBleScanDialog(
                                        context,
                                      );
                                    },
                          child: Text(
                            languageProvider
                                .translate(
                              "ble_search",
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
          _InsetDivider(
            color:
                scheme.outlineVariant,
          ),
          _SectionHeader(
            label: languageProvider.translate(
              "appearance_section",
            ),
          ),
          _SettingsSwitchRow(
            icon: themeProvider.darkmode
                ? Icons.dark_mode_rounded
                : Icons.light_mode_rounded,
            label: languageProvider.translate(
              "dark_mode",
            ),
            value:
                themeProvider.darkmode,
            onChanged:
                themeProvider.setDarkMode,
          ),
          _SettingsSwitchRow(
            icon: liveEcgProvider.showGrid
                ? Icons.grid_on_rounded
                : Icons.grid_off_rounded,
            label: languageProvider.translate(
              "show_grid_title",
            ),
            value:
                liveEcgProvider.showGrid,
            onChanged:
                liveEcgProvider.toggleGrid,
          ),
          _InsetDivider(
            color:
                scheme.outlineVariant,
          ),
          _SectionHeader(
            label: languageProvider.translate(
              "language_text_section",
            ),
          ),
          _ChoiceSetting<String>(
            title:
                languageProvider.translate(
              "language_title",
            ),
            values: const [
              "EN",
              "RO",
              "DE",
              "RU",
              "ES",
            ],
            selected:
                languageProvider.currentLang,
            labelBuilder:
                (value) => value,
            onSelected:
                languageProvider.setLanguage,
          ),
          const SizedBox(height: 18),
          _ChoiceSetting<double>(
            title:
                languageProvider.translate(
              "font_scale_title",
            ),
            values: const [
              0.85,
              1.0,
              1.15,
            ],
            selected:
                fontScaleProvider.fontScale,
            labelBuilder: (value) {
              if (value < 1) {
                return languageProvider
                    .translate(
                  "font_scale_title_small",
                );
              }

              if (value > 1) {
                return languageProvider
                    .translate(
                  "font_scale_title_big",
                );
              }

              return languageProvider
                  .translate(
                "font_scale_title_normal",
              );
            },
            onSelected:
                fontScaleProvider
                    .setFontScale,
          ),
          _InsetDivider(
            color:
                scheme.outlineVariant,
          ),
          _SectionHeader(
            label: languageProvider.translate(
              "ui_section",
            ),
          ),
          _SettingsSwitchRow(
            icon: Icons.circle_outlined,
            label: languageProvider.translate(
              "recording_indicator",
            ),
            subtitle:
                languageProvider.translate(
              "recording_indicator_desc",
            ),
            value:
                uiPreferences
                    .showRecordingIndicator,
            onChanged:
                uiPreferences
                    .setShowRecordingIndicator,
          ),
          _SettingsSwitchRow(
            icon: Icons.animation_rounded,
            label: languageProvider.translate(
              "recording_indicator_animation",
            ),
            subtitle:
                languageProvider.translate(
              "recording_indicator_animation_desc",
            ),
            value:
                uiPreferences
                    .animateRecordingIndicator,
            onChanged:
                uiPreferences
                        .showRecordingIndicator
                    ? uiPreferences
                        .setAnimateRecordingIndicator
                    : (_) {},
          ),
          _SettingsSwitchRow(
            icon:
                Icons.view_agenda_outlined,
            label: languageProvider.translate(
              "compact_recordings",
            ),
            subtitle:
                languageProvider.translate(
              "compact_recordings_desc",
            ),
            value:
                uiPreferences
                    .compactRecordingList,
            onChanged:
                uiPreferences
                    .setCompactRecordingList,
          ),
        ],
      ),
    );
  }
}

class _InsetDivider extends StatelessWidget {
  final Color color;

  const _InsetDivider({
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 8,
      ),
      child: Divider(
        height: 1,
        thickness: 1,
        color: color,
      ),
    );
  }
}

class _SectionHeader
    extends StatelessWidget {
  final String label;

  const _SectionHeader({
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(
        16,
        4,
        16,
        8,
      ),
      child: Text(
        label,
        style:
            Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(
                  color:
                      Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant,
                  fontWeight:
                      FontWeight.w600,
                ),
      ),
    );
  }
}

class _SettingsSwitchRow
    extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitchRow({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 8,
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color:
              Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant,
        ),
        title: Text(
          label,
          maxLines: 2,
          overflow:
              TextOverflow.ellipsis,
        ),
        subtitle:
            subtitle == null
                ? null
                : Text(
                    subtitle!,
                    maxLines: 2,
                    overflow:
                        TextOverflow.ellipsis,
                  ),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
        ),
        onTap: () {
          onChanged(!value);
        },
      ),
    );
  }
}

class _ChoiceSetting<T>
    extends StatelessWidget {
  final String title;
  final List<T> values;
  final T selected;
  final String Function(T value)
      labelBuilder;
  final void Function(T value)
      onSelected;

  const _ChoiceSetting({
    required this.title,
    required this.values,
    required this.selected,
    required this.labelBuilder,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 16,
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style:
                Theme.of(context)
                    .textTheme
                    .bodyLarge
                    ?.copyWith(
                      fontWeight:
                          FontWeight.w500,
                    ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (
              context,
              constraints,
            ) {
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    values.map((value) {
                  return ChoiceChip(
                    selected:
                        selected == value,
                    onSelected: (_) {
                      onSelected(value);
                    },
                    label: ConstrainedBox(
                      constraints:
                          BoxConstraints(
                        maxWidth: constraints
                                    .maxWidth <
                                340
                            ? 96
                            : 128,
                      ),
                      child: Text(
                        labelBuilder(
                          value,
                        ),
                        maxLines: 1,
                        overflow:
                            TextOverflow
                                .ellipsis,
                      ),
                    ),
                  );
                }).toList(
                  growable: false,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
