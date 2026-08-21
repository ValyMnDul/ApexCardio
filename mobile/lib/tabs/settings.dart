import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme.dart';
import '../providers/language.dart';
import '../providers/font.dart';
import '../providers/ble.dart';
import '../providers/live_ecg.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  void _showBleScanDialog(BuildContext context) {
    final ble = context.read<BleProvider>();
    final language = context.read<LanguageProvider>();

    ble.startScan();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return Consumer<BleProvider>(
          builder: (context, provider, child) {
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.62,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              language.translate('available_devices'),
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          TextButton(
                            onPressed: provider.isScanning
                                ? provider.stopScan
                                : provider.startScan,
                            child: Text(
                              provider.isScanning ? 'Stop' : 'Scan again',
                            ),
                          ),
                        ],
                      ),
                      if (provider.isScanning) ...[
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(minHeight: 2),
                      ],
                      const SizedBox(height: 12),
                      Expanded(
                        child: provider.scanResults.isEmpty
                            ? Center(
                                child: Text(
                                  language.translate('no_device'),
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: provider.scanResults.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outlineVariant,
                                ),
                                itemBuilder: (context, index) {
                                  final result = provider.scanResults[index];
                                  final name =
                                      result.device.platformName.trim().isEmpty
                                      ? 'Unknown device'
                                      : result.device.platformName;
                                  final isApex = name == 'ApexCardio';

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall
                                                    ?.copyWith(
                                                      fontWeight: isApex
                                                          ? FontWeight.w600
                                                          : FontWeight.w500,
                                                    ),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                result.device.remoteId
                                                    .toString(),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        FilledButton.tonal(
                                          onPressed: () async {
                                            final success = await provider
                                                .connectToDevice(result.device);

                                            if (success) {
                                              provider.startListeningValues();
                                            }

                                            if (!context.mounted) {
                                              return;
                                            }

                                            Navigator.pop(context);

                                            ScaffoldMessenger.of(this.context)
                                              ..hideCurrentSnackBar()
                                              ..showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    language.translate(
                                                      success
                                                          ? 'succes_connect'
                                                          : 'error_connect',
                                                    ),
                                                  ),
                                                ),
                                              );
                                          },
                                          child: Text(
                                            language.translate(
                                              'ble_connect_to_device',
                                            ),
                                          ),
                                        ),
                                      ],
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
    ).whenComplete(() {
      if (ble.isScanning) {
        ble.stopScan();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final language = context.watch<LanguageProvider>();
    final font = context.watch<FontScaleProvider>();
    final ble = context.watch<BleProvider>();
    final live = context.watch<LiveEcgProvider>();
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
        children: [
          _SectionTitle('Device'),
          const SizedBox(height: 6),
          _SettingLine(
            title: ble.isConnected
                ? language.translate('ble_connected')
                : language.translate('ble_disconnected'),
            subtitle: ble.isConnected
                ? ble.deviceName == 'unknown_device'
                      ? language.translate('unknown_device')
                      : ble.deviceName
                : language.translate('press_to_scan'),
            trailing: ble.isConnected
                ? TextButton(
                    onPressed: ble.disconnect,
                    child: const Text('Disconnect'),
                  )
                : FilledButton.tonal(
                    onPressed: () => _showBleScanDialog(context),
                    child: Text(language.translate('ble_search')),
                  ),
          ),
          _Divider(),
          const SizedBox(height: 22),
          _SectionTitle('Display'),
          const SizedBox(height: 6),
          _SwitchLine(
            title: language.translate('dark_mode'),
            value: theme.darkmode,
            onChanged: theme.setDarkMode,
          ),
          _Divider(),
          _SwitchLine(
            title: language.translate('show_grid_title'),
            value: live.showGrid,
            onChanged: live.toggleGrid,
          ),
          const SizedBox(height: 24),
          _SectionTitle(language.translate('language_title')),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'EN', label: Text('EN')),
              ButtonSegment(value: 'RO', label: Text('RO')),
              ButtonSegment(value: 'DE', label: Text('DE')),
              ButtonSegment(value: 'RU', label: Text('RU')),
              ButtonSegment(value: 'ES', label: Text('ES')),
            ],
            selected: <String>{language.currentLang},
            onSelectionChanged: (selection) {
              language.setLanguage(selection.first);
            },
          ),
          const SizedBox(height: 28),
          _SectionTitle(language.translate('font_scale_title')),
          const SizedBox(height: 5),
          Text(
            'Controls the text size across ApexCardio.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          SegmentedButton<double>(
            segments: [
              ButtonSegment(
                value: 0.85,
                label: Text(language.translate('font_scale_title_small')),
              ),
              ButtonSegment(
                value: 1.0,
                label: Text(language.translate('font_scale_title_normal')),
              ),
              ButtonSegment(
                value: 1.15,
                label: Text(language.translate('font_scale_title_big')),
              ),
            ],
            selected: <double>{font.fontScale},
            onSelectionChanged: (selection) {
              font.setFontScale(selection.first);
            },
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

class _SettingLine extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget trailing;

  const _SettingLine({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          trailing,
        ],
      ),
    );
  }
}

class _SwitchLine extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchLine({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.bodyLarge),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}
