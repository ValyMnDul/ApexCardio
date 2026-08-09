import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/ble.dart';
import '../providers/language.dart';
import '../providers/live_ecg.dart';

import '../widgets/ecg_painter.dart';

class Live extends StatefulWidget {
  const Live({super.key});

  @override
  State<Live> createState() => _LiveState();
}

class _LiveState extends State<Live> {
  @override
  Widget build(BuildContext context) {
    final bleProvider = Provider.of<BleProvider>(context);
    final liveEcgProvider = Provider.of<LiveEcgProvider>(context);

    if (bleProvider.isConnected == false) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bluetooth_disabled, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              "No Device Connected",
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            SizedBox(height: 60),
            ElevatedButton(onPressed: () {}, child: Text("Settings")),
            SizedBox(height: 50),
          ],
        ),
      );
    } else {
      return Column(
        children: [
          SizedBox(height: 20),
          Container(
            margin: EdgeInsets.symmetric(horizontal: 16),
            height: 250,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.teal.shade700, width: 1.5),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CustomPaint(
                painter: EcgPainter(
                  bleProvider.ecgPoints,
                  liveEcgProvider.showGrid,
                ),
              ),
            ),
          ),
        ],
      );
    }
  }
}
