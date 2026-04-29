import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';

void main() => runApp(MaterialApp(
      theme:
          ThemeData(brightness: Brightness.dark, primaryColor: Colors.blueGrey),
      home: const ScanScreen(),
      debugShowCheckedModeBanner: false,
    ));

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  List<ScanResult> scanResults = [];
  StreamSubscription? subscription;

  @override
  void initState() {
    super.initState();
    startScan();
  }

  void startScan() async {
    // Bluetooth merge doar pe mobil/mac/win, nu pe Linux desktop simplu
    if (Platform.isLinux) {
      debugPrint(
          "Bluetooth nu este suportat direct pe Linux Desktop de catre acest plugin.");
      return;
    }
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    subscription = FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() => scanResults = results);
      }
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scanare ApexCardio")),
      body: ListView.builder(
        itemCount: scanResults.length,
        itemBuilder: (c, i) => ListTile(
          title: Text(scanResults[i].device.platformName.isEmpty
              ? "Dispozitiv necunoscut"
              : scanResults[i].device.platformName),
          subtitle: Text(scanResults[i].device.remoteId.toString()),
          onTap: () {
            FlutterBluePlus.stopScan();
            Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (c) =>
                        MonitorScreen(device: scanResults[i].device)));
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: startScan,
        child: const Icon(Icons.refresh),
      ),
    );
  }
}

class MonitorScreen extends StatefulWidget {
  final BluetoothDevice device;
  const MonitorScreen({super.key, required this.device});

  @override
  State<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends State<MonitorScreen> {
  List<EkgData> dataPoints = [];
  List<String> csvBuffer = ["Time,Voltage"];
  ChartSeriesController? _chartSeriesController;
  BluetoothCharacteristic? targetChar;
  bool isRecording = false;

  @override
  void initState() {
    super.initState();
    connectToDevice();
  }

  void connectToDevice() async {
    try {
      await widget.device.connect();
      List<BluetoothService> services = await widget.device.discoverServices();
      for (var service in services) {
        for (var char in service.characteristics) {
          // Căutăm caracteristica care are NOTIFY activat
          if (char.properties.notify) {
            targetChar = char;
            await char.setNotifyValue(true);

            char.lastValueStream.listen((value) {
              if (value.isNotEmpty) {
                try {
                  // Decodăm și curățăm spațiile/liniile noi
                  String raw = utf8.decode(value).trim();

                  // Dacă ESP32 trimite mai multe valori lipite, luăm doar prima
                  if (raw.contains('\n')) {
                    raw = raw.split('\n').first.trim();
                  }

                  double? val = double.tryParse(raw);
                  if (val != null) {
                    _updateData(val);
                  }
                } catch (e) {
                  debugPrint("Eroare la parsare date brute: $e");
                }
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Eroare conectare: $e");
    }
  }

  void _updateData(double val) {
    final now = DateTime.now();
    final point = EkgData(now, val);

    if (mounted) {
      setState(() {
        dataPoints.add(point);
        if (isRecording) {
          csvBuffer.add("${DateFormat('HH:mm:ss.SSS').format(now)},$val");
        }
        // Păstrăm doar ultimele 50 de puncte pentru performanță (previne crash-ul)
        if (dataPoints.length > 50) {
          dataPoints.removeAt(0);
        }
      });

      // Actualizăm graficul doar dacă există controller-ul
      try {
        _chartSeriesController?.updateDataSource(
          addedDataIndex: dataPoints.length - 1,
          removedDataIndex: dataPoints.length > 50 ? 0 : -1,
        );
      } catch (e) {
        debugPrint("Eroare update grafic: $e");
      }
    }
  }

  Future<void> exportCsv() async {
    final directory = await getApplicationDocumentsDirectory();
    final path =
        "${directory.path}/ekg_${DateTime.now().millisecondsSinceEpoch}.csv";
    final file = File(path);
    await file.writeAsString(csvBuffer.join("\n"));
    Share.shareXFiles([XFile(path)], text: "Sesiune EKG ApexCardio");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Monitorizare Live")),
      body: Column(
        children: [
          Expanded(
            child: SfCartesianChart(
              primaryXAxis: const DateTimeAxis(isVisible: false),
              series: <LineSeries<EkgData, DateTime>>[
                LineSeries<EkgData, DateTime>(
                  onRendererCreated: (ChartSeriesController controller) {
                    _chartSeriesController = controller;
                  },
                  dataSource: dataPoints,
                  xValueMapper: (EkgData d, _) => d.time,
                  yValueMapper: (EkgData d, _) => d.value,
                  animationDuration: 0,
                  color: Colors.cyan,
                )
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isRecording ? Colors.red : Colors.green,
                  ),
                  onPressed: () => setState(() {
                    isRecording = !isRecording;
                    if (isRecording) csvBuffer = ["Time,Voltage"];
                  }),
                  child: Text(isRecording ? "Stop Salvare" : "Start Salvare"),
                ),
                ElevatedButton(
                  onPressed: exportCsv,
                  child: const Text("Export CSV"),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class EkgData {
  EkgData(this.time, this.value);
  final DateTime time;
  final double value;
}
