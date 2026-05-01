import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:syncfusion_flutter_core/core.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: Colors.blueGrey,
        useMaterial3: true,
      ),
      home: const ScanScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class EkgData {
  EkgData(this.time, this.value);
  final DateTime time;
  final double value;
}

class RecordingSession {
  final String id;
  final DateTime startTime;
  DateTime endTime;
  String filePath;
  double minValue = 0.0;
  double maxValue = 0.0;
  double avgValue = 0.0;
  int beatCount = 0;
  final List<EkgData> data = [];

  RecordingSession({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.filePath,
  });

  Duration get duration => endTime.difference(startTime);

  void calculateStats() {
    if (data.isEmpty) {
      minValue = 0.0;
      maxValue = 0.0;
      avgValue = 0.0;
      beatCount = 0;
      return;
    }

    minValue = data.map((e) => e.value).reduce((a, b) => a < b ? a : b);
    maxValue = data.map((e) => e.value).reduce((a, b) => a > b ? a : b);
    avgValue = data.map((e) => e.value).reduce((a, b) => a + b) / data.length;
    beatCount = _estimateBeatCount();
  }

  int _estimateBeatCount() {
    if (data.length < 3) return 0;

    final values = data.map((e) => e.value).toList();
    final mean = values.reduce((a, b) => a + b) / values.length;
    final maxv = values.reduce((a, b) => a > b ? a : b);
    final threshold = mean + (maxv - mean) * 0.5;

    int count = 0;
    DateTime? lastPeak;
    for (int i = 1; i < data.length - 1; i++) {
      if (data[i].value > data[i - 1].value &&
          data[i].value > data[i + 1].value &&
          data[i].value > threshold) {
        final t = data[i].time;
        if (lastPeak == null || t.difference(lastPeak).inMilliseconds > 400) {
          count++;
          lastPeak = t;
        }
      }
    }
    return count;
  }
}

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  List<ScanResult> scanResults = [];
  StreamSubscription? subscription;
  bool isScanning = false;

  @override
  void initState() {
    super.initState();
    startScan();
  }

  void startScan() async {
    if (Platform.isLinux) {
      return;
    }

    setState(() => isScanning = true);
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    subscription = FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() {
          scanResults = results;
          isScanning = false;
        });
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
      appBar: AppBar(
        title: const Text('ApexCardio - Selectare Dispozitiv'),
        elevation: 0,
      ),
      body: scanResults.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isScanning)
                    const CircularProgressIndicator()
                  else
                    const Icon(Icons.search_off, size: 80, color: Colors.grey),
                  const SizedBox(height: 20),
                  Text(
                    isScanning ? 'Searching devices...' : 'No devices found',
                    style: const TextStyle(fontSize: 18),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: scanResults.length,
              itemBuilder: (c, i) => Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  leading: const Icon(Icons.bluetooth, color: Colors.cyan),
                  title: Text(scanResults[i].device.platformName.isEmpty
                      ? 'Dispozitiv necunoscut'
                      : scanResults[i].device.platformName),
                  subtitle: Text(scanResults[i].device.remoteId.toString()),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    FlutterBluePlus.stopScan();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (c) => MonitorScreen(
                          device: scanResults[i].device,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: startScan,
        label: const Text('Rescan'),
        icon: const Icon(Icons.refresh),
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

class _MonitorScreenState extends State<MonitorScreen>
    with TickerProviderStateMixin {
  static const String _prefLanguageKey = 'settings_language';
  static const String _prefFontScaleKey = 'settings_font_scale';
  static const String _prefDarkModeKey = 'settings_dark_mode';
  static const String _prefLiveWindowPointsKey = 'settings_live_window_points';
  static const String _prefYAxisMaxKey = 'settings_y_axis_max';

  late TabController _tabController;
  List<EkgData> dataPoints = [];
  List<RecordingSession> sessions = [];
  ChartSeriesController? _chartSeriesController;
  BluetoothCharacteristic? targetChar;

  bool isRecording = false;
  RecordingSession? currentSession;
  DateTime? recordingStart;
  String language = 'en';
  double fontScale = 1.0;
  bool isDarkMode = true;
  int liveWindowPoints = 50;
  double yAxisMax = 4300;

  String t(String en, String ro) => language == 'ro' ? ro : en;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSettings();
    connectToDevice();
    loadSessions();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      language = prefs.getString(_prefLanguageKey) ?? language;
      fontScale = prefs.getDouble(_prefFontScaleKey) ?? fontScale;
      isDarkMode = prefs.getBool(_prefDarkModeKey) ?? isDarkMode;
      liveWindowPoints =
          prefs.getInt(_prefLiveWindowPointsKey) ?? liveWindowPoints;
      yAxisMax = prefs.getDouble(_prefYAxisMaxKey) ?? yAxisMax;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefLanguageKey, language);
    await prefs.setDouble(_prefFontScaleKey, fontScale);
    await prefs.setBool(_prefDarkModeKey, isDarkMode);
    await prefs.setInt(_prefLiveWindowPointsKey, liveWindowPoints);
    await prefs.setDouble(_prefYAxisMaxKey, yAxisMax);
  }

  Future<void> loadSessions() async {
    final directory = await getApplicationDocumentsDirectory();
    final sessionDir = Directory('${directory.path}/apex_sessions');

    if (!await sessionDir.exists()) {
      await sessionDir.create(recursive: true);
    }

    final files = sessionDir.listSync();
    final loadedSessions = <RecordingSession>[];

    for (var file in files) {
      if (file is File && file.path.endsWith('.csv')) {
        final sessionData = await _loadSessionFromFile(file);
        if (sessionData != null) {
          loadedSessions.add(sessionData);
        }
      }
    }

    if (mounted) {
      setState(() {
        sessions = loadedSessions
          ..sort((a, b) => b.startTime.compareTo(a.startTime));
      });
    }
  }

  Future<RecordingSession?> _loadSessionFromFile(File file) async {
    try {
      final lines = await file.readAsLines();
      if (lines.isEmpty) return null;

      final filename = file.path.split('/').last;
      final parts =
          filename.replaceAll('ekg_', '').replaceAll('.csv', '').split('_');
      if (parts.length < 2) return null;

      final startTime =
          DateTime.fromMillisecondsSinceEpoch(int.parse(parts[0]));
      final endTime = DateTime.fromMillisecondsSinceEpoch(int.parse(parts[1]));

      final session = RecordingSession(
        id: filename,
        startTime: startTime,
        endTime: endTime,
        filePath: file.path,
      );

      DateTime? previousPointTime;
      for (var i = 1; i < lines.length; i++) {
        final row = lines[i].split(',');
        if (row.length >= 2) {
          try {
            DateTime pointTime;
            double value;

            if (row.length >= 3 && int.tryParse(row[0]) != null) {
              final elapsedMs = int.parse(row[0]);
              pointTime = startTime.add(Duration(milliseconds: elapsedMs));
              value = double.parse(row[2]);
            } else {
              value = double.parse(row[1]);
              final parsedTime = DateFormat('HH:mm:ss.SSS').parse(row[0]);
              pointTime = DateTime(
                startTime.year,
                startTime.month,
                startTime.day,
                parsedTime.hour,
                parsedTime.minute,
                parsedTime.second,
                parsedTime.millisecond,
              );
              if (previousPointTime != null &&
                  pointTime.isBefore(previousPointTime)) {
                pointTime = pointTime.add(const Duration(days: 1));
              }
            }

            previousPointTime = pointTime;
            session.data.add(EkgData(pointTime, value));
          } catch (_) {
            continue;
          }
        }
      }

      session.calculateStats();
      return session;
    } catch (e) {
      debugPrint('Error loading session: $e');
      return null;
    }
  }

  void connectToDevice() async {
    try {
      await widget.device.connect();
      final services = await widget.device.discoverServices();
      for (var service in services) {
        for (var char in service.characteristics) {
          if (char.properties.notify) {
            targetChar = char;
            await char.setNotifyValue(true);

            char.lastValueStream.listen((value) {
              if (value.isNotEmpty) {
                try {
                  String raw = utf8.decode(value).trim();
                  if (raw.contains('\n')) {
                    raw = raw.split('\n').first.trim();
                  }
                  final val = double.tryParse(raw);
                  if (val != null) {
                    _updateData(val);
                  }
                } catch (e) {
                  debugPrint('Error parsing: $e');
                }
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error connecting: $e');
    }
  }

  void _updateData(double val) {
    final now = DateTime.now();
    final point = EkgData(now, val);
    bool removedOldest = false;

    if (mounted) {
      setState(() {
        dataPoints.add(point);
        if (isRecording && currentSession != null) {
          currentSession!.data.add(point);
        }
        if (dataPoints.length > liveWindowPoints) {
          dataPoints.removeAt(0);
          removedOldest = true;
        }
      });

      try {
        _chartSeriesController?.updateDataSource(
          addedDataIndex: dataPoints.length - 1,
          removedDataIndex: removedOldest ? 0 : -1,
        );
      } catch (e) {
        debugPrint('Error updating chart: $e');
      }
    }
  }

  void _setLiveWindowPoints(int value) {
    final clamped = value.clamp(1, 1000000);
    int removedCount = 0;

    setState(() {
      liveWindowPoints = clamped;
      if (dataPoints.length > liveWindowPoints) {
        removedCount = dataPoints.length - liveWindowPoints;
        dataPoints = dataPoints.sublist(removedCount);
      }
    });

    if (removedCount > 0) {
      try {
        _chartSeriesController?.updateDataSource(
          removedDataIndexes: List<int>.generate(removedCount, (i) => i),
        );
      } catch (e) {
        debugPrint('Error shrinking chart window: $e');
      }
    }
  }

  void startRecording() async {
    recordingStart = DateTime.now();
    currentSession = RecordingSession(
      id: 'ekg_${recordingStart!.millisecondsSinceEpoch}',
      startTime: recordingStart!,
      endTime: DateTime.now(),
      filePath: '',
    );

    if (mounted) {
      setState(() => isRecording = true);
    }
  }

  void stopRecording() async {
    if (currentSession == null) return;

    currentSession!.endTime = DateTime.now();
    currentSession!.calculateStats();

    final directory = await getApplicationDocumentsDirectory();
    final sessionDir = Directory('${directory.path}/apex_sessions');
    if (!await sessionDir.exists()) {
      await sessionDir.create(recursive: true);
    }

    final filePath =
        '${sessionDir.path}/ekg_${recordingStart!.millisecondsSinceEpoch}_${currentSession!.endTime.millisecondsSinceEpoch}.csv';
    currentSession!.filePath = filePath;

    final file = File(filePath);
    final csvLines = ['ElapsedMs,Time,Voltage'];
    for (var data in currentSession!.data) {
      final elapsedMs = data.time.difference(recordingStart!).inMilliseconds;
      csvLines.add(
          '$elapsedMs,${DateFormat('HH:mm:ss.SSS').format(data.time)},${data.value}');
    }
    await file.writeAsString(csvLines.join('\n'));

    if (mounted) {
      setState(() {
        isRecording = false;
        sessions.insert(0, currentSession!);
        currentSession = null;
      });
    }
  }

  Future<void> deleteSession(RecordingSession session) async {
    final file = File(session.filePath);
    if (await file.exists()) {
      await file.delete();
    }

    if (mounted) {
      setState(() {
        sessions.removeWhere((s) => s.id == session.id);
      });
    }
  }

  Future<void> shareSession(RecordingSession session) async {
    await Share.shareXFiles(
      [XFile(session.filePath)],
      text:
          'ApexCardio EKG Session - ${DateFormat('dd.MM.yyyy HH:mm').format(session.startTime)}',
    );
  }

  @override
  void dispose() {
    try {
      targetChar?.setNotifyValue(false);
      widget.device.disconnect();
    } catch (e) {
      debugPrint('Error during disconnect: $e');
    }
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackNavigation();
      },
      child: Theme(
        data: ThemeData(
          brightness: isDarkMode ? Brightness.dark : Brightness.light,
          useMaterial3: true,
          colorSchemeSeed: Colors.teal,
        ),
        child: MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(fontScale)),
          child: Scaffold(
            appBar: AppBar(
              title: Text(widget.device.platformName.isEmpty
                  ? 'ApexCardio'
                  : widget.device.platformName),
              actions: [
                if (isRecording && currentSession != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: Row(
                      children: [
                        const Icon(Icons.circle, color: Colors.red, size: 12),
                        const SizedBox(width: 6),
                        StreamBuilder(
                          stream: Stream.periodic(
                              const Duration(milliseconds: 200)),
                          builder: (c, s) => Text(
                            '${t('Recording', 'Înregistrare')} ${currentSession == null ? '' : '${DateTime.now().difference(currentSession!.startTime).inSeconds}s'}',
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
              bottom: TabBar(
                controller: _tabController,
                tabs: [
                  Tab(
                      icon: const Icon(Icons.show_chart),
                      text: t('Live', 'Live')),
                  Tab(
                      icon: const Icon(Icons.history),
                      text: t('Recordings', 'Înregistrări')),
                  Tab(
                      icon: const Icon(Icons.settings),
                      text: t('Settings', 'Setări')),
                ],
              ),
            ),
            body: TabBarView(
              controller: _tabController,
              children: [
                _buildLiveTab(),
                _buildRecordingsTab(),
                _buildSettingsTab(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleBackNavigation() async {
    if (isRecording) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Active recording'),
          content: const Text('Do you want to stop recording before leaving?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Yes, stop'),
            ),
          ],
        ),
      );

      if (confirm == true) {
        stopRecording();
        await widget.device.disconnect();
        if (mounted) Navigator.pop(context);
      }
      return;
    }

    await widget.device.disconnect();
    if (mounted) Navigator.pop(context);
  }

  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          t('Settings', 'Setări'),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 1,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('Display', 'Afișare'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(t('Language', 'Limbă')),
                const SizedBox(height: 6),
                DropdownButton<String>(
                  isExpanded: true,
                  value: language,
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text('English')),
                    DropdownMenuItem(value: 'ro', child: Text('Română')),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      setState(() => language = v);
                      _saveSettings();
                    }
                  },
                ),
                const SizedBox(height: 12),
                Text(t('Font scale', 'Mărime font')),
                Slider(
                  value: fontScale,
                  min: 0.8,
                  max: 1.4,
                  divisions: 6,
                  label: fontScale.toStringAsFixed(2),
                  onChanged: (v) => setState(() => fontScale = v),
                  onChangeEnd: (_) => _saveSettings(),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('Dark mode', 'Mod întunecat')),
                  value: isDarkMode,
                  onChanged: (v) {
                    setState(() => isDarkMode = v);
                    _saveSettings();
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Card(
          elevation: 1,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('Chart', 'Grafic'),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _buildInfoSettingLabel(
                  title: t('Live points window', 'Fereastră puncte live'),
                  infoMessage: t(
                    'Shows how many recent points stay visible in Live chart.',
                    'Arată câte puncte recente rămân vizibile în graficul Live.',
                  ),
                ),
                Slider(
                  value: liveWindowPoints.toDouble(),
                  min: 30,
                  max: 200,
                  divisions: 17,
                  label: liveWindowPoints.toString(),
                  onChanged: (v) => _setLiveWindowPoints(v.round()),
                  onChangeEnd: (_) => _saveSettings(),
                ),
                const SizedBox(height: 8),
                _buildInfoSettingLabel(
                  title: t('Chart max value', 'Valoare maximă grafic'),
                  infoMessage: t(
                    'Sets the fixed maximum value on chart Y axis.',
                    'Setează valoarea maximă fixă pe axa Y a graficului.',
                  ),
                ),
                Slider(
                  value: yAxisMax,
                  min: 3000,
                  max: 6000,
                  divisions: 30,
                  label: yAxisMax.toStringAsFixed(0),
                  onChanged: (v) => setState(() => yAxisMax = v),
                  onChangeEnd: (_) => _saveSettings(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoSettingLabel({
    required String title,
    required String infoMessage,
  }) {
    return Row(
      children: [
        Expanded(child: Text(title)),
        Tooltip(
          message: infoMessage,
          waitDuration: const Duration(milliseconds: 300),
          child: IconButton(
            iconSize: 18,
            splashRadius: 18,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            padding: EdgeInsets.zero,
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text(title),
                  content: Text(infoMessage),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(t('OK', 'OK')),
                    ),
                  ],
                ),
              );
            },
            icon: const Icon(Icons.info_outline),
          ),
        ),
      ],
    );
  }

  Widget _buildLiveTab() {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDarkMode
                        ? [const Color(0xFF0B1723), const Color(0xFF0E2432)]
                        : [const Color(0xFFDFF4FF), const Color(0xFFF2FAFF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: SfCartesianChart(
                  margin: const EdgeInsets.all(12),
                  primaryXAxis: const DateTimeAxis(isVisible: false),
                  primaryYAxis: NumericAxis(
                    minimum: 0,
                    maximum: yAxisMax,
                    interval: 500,
                  ),
                  series: <LineSeries<EkgData, DateTime>>[
                    LineSeries<EkgData, DateTime>(
                      onRendererCreated: (ChartSeriesController controller) {
                        _chartSeriesController = controller;
                      },
                      dataSource: dataPoints,
                      xValueMapper: (EkgData d, _) => d.time,
                      yValueMapper: (EkgData d, _) => d.value,
                      animationDuration: 0,
                      color: Colors.cyanAccent,
                      width: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF141A1F) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 18,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isRecording ? Colors.red : Colors.green,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    onPressed: isRecording ? stopRecording : startRecording,
                    icon: Icon(
                        isRecording ? Icons.stop : Icons.fiber_manual_record),
                    label: Text(isRecording
                        ? t('Stop Recording', 'Stop Înregistrare')
                        : t('Start Recording', 'Start Înregistrare')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecordingsTab() {
    return sessions.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history, size: 80, color: Colors.grey[600]),
                const SizedBox(height: 16),
                Text(
                  t('No recordings yet', 'Nicio înregistrare încă'),
                  style: const TextStyle(fontSize: 18, color: Colors.grey),
                ),
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: sessions.length,
            itemBuilder: (c, i) => _buildSessionCard(sessions[i]),
          );
  }

  Widget _buildSessionCard(RecordingSession session) {
    return Card(
      margin: const EdgeInsets.all(8),
      child: ExpansionTile(
        leading: const Icon(Icons.favorite, color: Colors.red),
        title: Text(
          DateFormat('dd.MM.yyyy HH:mm:ss').format(session.startTime),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${t('Duration', 'Durată')}: ${session.duration.inSeconds}s | ${t('Samples', 'Puncte')}: ${session.data.length}',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatRow(t('Min', 'Min'),
                    '${session.minValue.toStringAsFixed(0)} mV'),
                _buildStatRow(t('Max', 'Max'),
                    '${session.maxValue.toStringAsFixed(0)} mV'),
                _buildStatRow(t('Avg', 'Medie'),
                    '${session.avgValue.toStringAsFixed(0)} mV'),
                _buildStatRow(
                  t('Estimated beats', 'Bătăi estimate'),
                  session.duration.inSeconds < 60
                      ? '-'
                      : '${session.beatCount}',
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.preview),
                      label: Text(t('View', 'Vizualizare')),
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (c) => DetailScreen(
                            session: session,
                            language: language,
                            fontScale: fontScale,
                            isDarkMode: isDarkMode,
                          ),
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.share),
                      label: Text(t('Export', 'Export')),
                      onPressed: () => shareSession(session),
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.delete),
                      label: Text(t('Delete', 'Șterge')),
                      style:
                          ElevatedButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () => deleteSession(session),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }
}

class DetailScreen extends StatefulWidget {
  final RecordingSession session;
  final String language;
  final double fontScale;
  final bool isDarkMode;

  const DetailScreen({
    super.key,
    required this.session,
    required this.language,
    required this.fontScale,
    required this.isDarkMode,
  });

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late DateTime rangeStartTime;
  late DateTime rangeEndTime;
  late final RangeController _rangeController;
  late final ZoomPanBehavior _zoomPanBehavior;
  bool _isSyncingFromCode = false;

  bool get _hasData => widget.session.data.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_hasData) {
      rangeStartTime = widget.session.data.first.time;
      rangeEndTime = widget.session.data.last.time;
    } else {
      rangeStartTime = DateTime.now();
      rangeEndTime = DateTime.now();
    }
    _rangeController = RangeController(
      start: rangeStartTime,
      end: rangeEndTime,
    );
    _zoomPanBehavior = ZoomPanBehavior(
      enablePinching: true,
      enablePanning: true,
      zoomMode: ZoomMode.x,
    );
  }

  String t(String en, String ro) => widget.language == 'ro' ? ro : en;

  int get _lastIndex => widget.session.data.length - 1;

  int _clampIndex(int index) => index.clamp(0, _lastIndex);

  int _findFirstIndexAtOrAfter(DateTime time) {
    int low = 0;
    int high = _lastIndex;
    while (low <= high) {
      final int mid = (low + high) >> 1;
      final current = widget.session.data[mid].time;
      if (current.isBefore(time)) {
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return _clampIndex(low);
  }

  int _findLastIndexAtOrBefore(DateTime time) {
    int low = 0;
    int high = _lastIndex;
    while (low <= high) {
      final int mid = (low + high) >> 1;
      final current = widget.session.data[mid].time;
      if (current.isAfter(time)) {
        high = mid - 1;
      } else {
        low = mid + 1;
      }
    }
    return _clampIndex(high);
  }

  List<EkgData> _getVisibleData() {
    if (!_hasData) return <EkgData>[];
    final startIndex = _findFirstIndexAtOrAfter(rangeStartTime);
    final endIndex = _findLastIndexAtOrBefore(rangeEndTime);
    if (endIndex < startIndex) return <EkgData>[];
    return widget.session.data.sublist(startIndex, endIndex + 1);
  }

  Map<String, double> _calculateRangeStats() {
    final visibleData = _getVisibleData();
    if (visibleData.isEmpty) {
      return {'min': 0.0, 'max': 0.0, 'avg': 0.0};
    }
    final values = visibleData.map((e) => e.value).toList();
    final min = values.reduce((a, b) => a < b ? a : b);
    final max = values.reduce((a, b) => a > b ? a : b);
    final avg = values.reduce((a, b) => a + b) / values.length;
    return {'min': min, 'max': max, 'avg': avg};
  }

  Duration get _rangeDuration => rangeEndTime.difference(rangeStartTime);

  double get _totalDurationSeconds {
    if (!_hasData) return 1;
    final totalSeconds = widget.session.data.last.time
        .difference(widget.session.data.first.time)
        .inSeconds;
    return totalSeconds <= 0 ? 1 : totalSeconds.toDouble();
  }

  Duration _offsetFromStart(DateTime time) =>
      time.difference(widget.session.startTime);

  DateTime _timeFromOffset(Duration offset) {
    final candidate = widget.session.startTime.add(offset);
    final first = widget.session.data.first.time;
    final last = widget.session.data.last.time;
    if (candidate.isBefore(first)) return first;
    if (candidate.isAfter(last)) return last;
    return candidate;
  }

  String _formatOffset(Duration offset) {
    final clamped = offset.isNegative ? Duration.zero : offset;
    final hours = clamped.inHours;
    final minutes = clamped.inMinutes.remainder(60);
    final seconds = clamped.inSeconds.remainder(60);
    return '+${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration duration) {
    final days = duration.inDays;
    final hours = duration.inHours.remainder(24);
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    final parts = <String>[];
    if (days > 0) parts.add('${days}d');
    if (hours > 0 || days > 0) parts.add('${hours}h');
    if (minutes > 0 || hours > 0 || days > 0) parts.add('${minutes}m');
    parts.add('${seconds}s');
    return parts.join(' ');
  }

  void _syncRange(DateTime start, DateTime end) {
    if (start.isAfter(end)) {
      final temp = start;
      start = end;
      end = temp;
    }

    if (_hasData) {
      final first = widget.session.data.first.time;
      final last = widget.session.data.last.time;
      if (start.isBefore(first)) start = first;
      if (end.isAfter(last)) end = last;
    }

    if (start == rangeStartTime && end == rangeEndTime) return;

    _isSyncingFromCode = true;
    setState(() {
      rangeStartTime = start;
      rangeEndTime = end;
    });
    _rangeController.start = start;
    _rangeController.end = end;
    _isSyncingFromCode = false;
  }

  void _syncFromChart(ActualRangeChangedArgs args) {
    if (args.orientation != AxisOrientation.horizontal) return;
    if (_isSyncingFromCode) return;
    final visibleMin = args.visibleMin;
    final visibleMax = args.visibleMax;
    if (visibleMin == null || visibleMax == null) return;

    final start = DateTime.fromMillisecondsSinceEpoch(visibleMin.round());
    final end = DateTime.fromMillisecondsSinceEpoch(visibleMax.round());
    if (start == rangeStartTime && end == rangeEndTime) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (start == rangeStartTime && end == rangeEndTime) return;
      _syncRange(start, end);
    });
  }

  Widget _buildBoundaryButton({
    required String label,
    required DateTime value,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: widget.isDarkMode ? const Color(0xFF1B232A) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.isDarkMode ? Colors.white10 : Colors.black12,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            Text(
              _formatOffset(_offsetFromStart(value)),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisStats() {
    final stats = _calculateRangeStats();
    final visibleCount = _getVisibleData().length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: widget.isDarkMode
            ? const Color(0xFF1A2127)
            : const Color(0xFFF4F6F8),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildStatTile(
                    'Min', '${stats['min']!.toStringAsFixed(0)} mV'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatTile(
                    'Max', '${stats['max']!.toStringAsFixed(0)} mV'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatTile(
                  t('Avg', 'Medie'),
                  '${stats['avg']!.toStringAsFixed(0)} mV',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatTile(t('Samples', 'Puncte'), '$visibleCount'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasData) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
              DateFormat('dd.MM.yyyy HH:mm').format(widget.session.startTime)),
        ),
        body: const Center(child: Text('No data')),
      );
    }

    return Theme(
      data: ThemeData(
        brightness: widget.isDarkMode ? Brightness.dark : Brightness.light,
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
      ),
      child: MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(widget.fontScale)),
        child: Scaffold(
          appBar: AppBar(
            title: Text(DateFormat('dd.MM.yyyy HH:mm')
                .format(widget.session.startTime)),
          ),
          body: Column(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: widget.isDarkMode
                                    ? [
                                        const Color(0xFF07131B),
                                        const Color(0xFF0F2430),
                                      ]
                                    : [
                                        const Color(0xFFE6F9FF),
                                        const Color(0xFFF8FCFF),
                                      ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: SfCartesianChart(
                              margin: const EdgeInsets.all(10),
                              zoomPanBehavior: _zoomPanBehavior,
                              onActualRangeChanged: _syncFromChart,
                              primaryXAxis: DateTimeAxis(
                                minimum: widget.session.data.first.time,
                                maximum: widget.session.data.last.time,
                                rangeController: _rangeController,
                                dateFormat: DateFormat('dd.MM HH:mm'),
                                intervalType: DateTimeIntervalType.auto,
                              ),
                              primaryYAxis: const NumericAxis(
                                minimum: 0,
                                maximum: 4300,
                                interval: 500,
                              ),
                              series: <LineSeries<EkgData, DateTime>>[
                                LineSeries<EkgData, DateTime>(
                                  dataSource: widget.session.data,
                                  xValueMapper: (EkgData d, _) => d.time,
                                  yValueMapper: (EkgData d, _) => d.value,
                                  color: Colors.cyanAccent,
                                  width: 2,
                                  animationDuration: 800,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Container(
                      color: widget.isDarkMode
                          ? const Color(0xFF0E1418)
                          : Colors.grey[100],
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t('Analysis window', 'Fereastră analiză'),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _buildBoundaryButton(
                                label: t('Start time', 'Început'),
                                value: rangeStartTime,
                              ),
                              const SizedBox(width: 10),
                              _buildBoundaryButton(
                                label: t('End time', 'Sfârșit'),
                                value: rangeEndTime,
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          RangeSlider(
                            values: RangeValues(
                              _offsetFromStart(rangeStartTime)
                                  .inSeconds
                                  .toDouble(),
                              _offsetFromStart(rangeEndTime)
                                  .inSeconds
                                  .toDouble(),
                            ),
                            min: 0,
                            max: _totalDurationSeconds,
                            onChanged: (RangeValues values) {
                              final start = _timeFromOffset(
                                  Duration(seconds: values.start.round()));
                              final end = _timeFromOffset(
                                  Duration(seconds: values.end.round()));
                              _syncRange(start, end);
                            },
                            labels: RangeLabels(
                              _formatOffset(_offsetFromStart(rangeStartTime)),
                              _formatOffset(_offsetFromStart(rangeEndTime)),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              t(
                                'Samples: ${_getVisibleData().length} • Duration: ${_formatDuration(_rangeDuration)}',
                                'Puncte: ${_getVisibleData().length} • Durată: ${_formatDuration(_rangeDuration)}',
                              ),
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                color:
                    widget.isDarkMode ? const Color(0xFF141A1F) : Colors.white,
                child: Column(
                  children: [
                    _buildAnalysisStats(),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              _syncRange(
                                widget.session.data.first.time,
                                widget.session.data.last.time,
                              );
                            },
                            child: Text(t('Reset view', 'Resetează vederea')),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(t('Back', 'Înapoi')),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatTile(String label, String value) {
    return Card(
      color: widget.isDarkMode ? Colors.grey[800] : Colors.grey[200],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label,
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
