import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/ble.dart';
import '../providers/language.dart';
import '../providers/live_ecg.dart';

import '../widgets/ecg_painter.dart';

class Live extends StatefulWidget {
  final VoidCallback? onGoToSettings;

  const Live(this.onGoToSettings, {super.key});

  @override
  State<Live> createState() => _LiveState();
}

class _LiveState extends State<Live> {
  @override
  Widget build(BuildContext context) {
    final bleProvider = Provider.of<BleProvider>(context);
    final languageProvider = Provider.of<LanguageProvider>(context);

    if (bleProvider.isConnected == false) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bluetooth_disabled_rounded,
              size: 58,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            SizedBox(height: 16),
            Text(
              languageProvider.translate("no_device_connected"),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: 28),
            ElevatedButton(
              onPressed: widget.onGoToSettings,
              child: Text(languageProvider.translate("settings_tab")),
            ),
            SizedBox(height: 50),
          ],
        ),
      );
    }

    final liveEcgProvider = Provider.of<LiveEcgProvider>(context);

    return Padding(padding: EdgeInsetsGeometry.fromLTRB(16, 10, 16, 12));
  }
}
