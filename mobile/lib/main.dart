import 'package:apexcardio/providers/ble.dart';
import 'package:apexcardio/providers/live_ecg.dart';
import 'package:apexcardio/providers/recording.dart';
import 'package:apexcardio/services/recording_background_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import 'themes/light.dart';
import 'themes/dark.dart';

import 'providers/theme.dart';
import 'providers/language.dart';
import 'providers/font.dart';

import 'tabs/live.dart';
import 'tabs/recordings.dart';
import 'tabs/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await FlutterBluePlus.setOptions(restoreState: true);

  RecordingBackgroundService.prepareCommunication();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => FontScaleProvider()),
        ChangeNotifierProvider(create: (_) => BleProvider()),
        ChangeNotifierProvider(create: (_) => LiveEcgProvider()),
        ChangeNotifierProvider(
          lazy: false,
          create: (context) => RecordingProvider(context.read<BleProvider>()),
        ),
      ],
      child: const App(),
    ),
  );
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final fontScaleProvider = Provider.of<FontScaleProvider>(context);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: lightMode,
      darkTheme: darkMode,
      themeMode: themeProvider.darkmode ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(fontScaleProvider.fontScale),
          ),
          child: child!,
        );
      },
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with TickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 68,
        centerTitle: true,
        titleSpacing: 12,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text.rich(
              TextSpan(
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 21,
                  height: 1,
                ),
                children: [
                  TextSpan(
                    text: 'APEX',
                    style: TextStyle(
                      fontWeight: FontWeight.w400,
                      color: themeProvider.darkmode
                          ? Colors.teal[100]
                          : Colors.grey[850],
                    ),
                  ),
                  TextSpan(
                    text: ' CARDIO',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.teal[700],
                    ),
                  ),
                ],
              ),
            ),
            Consumer<RecordingProvider>(
              builder: (context, recording, child) {
                if (!recording.hasActiveRecording) {
                  return const SizedBox.shrink();
                }

                return Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: _AppRecordingDot(
                    active: recording.isRecording && recording.bleConnected,
                    paused: recording.isPaused || !recording.bleConnected,
                  ),
                );
              },
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: TabBar(
              controller: _tabController,
              dividerColor: Colors.transparent,
              labelPadding: const EdgeInsets.symmetric(horizontal: 12),
              tabs: [
                Tab(text: languageProvider.translate('live_tab')),
                Tab(text: languageProvider.translate('recordings_tab')),
                Tab(text: languageProvider.translate('settings_tab')),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          Live(() {
            _tabController.animateTo(2);
          }),
          const Recordings(),
          const Settings(),
        ],
      ),
    );
  }
}

class _AppRecordingDot extends StatefulWidget {
  final bool active;
  final bool paused;

  const _AppRecordingDot({required this.active, required this.paused});

  @override
  State<_AppRecordingDot> createState() => _AppRecordingDotState();
}

class _AppRecordingDotState extends State<_AppRecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );

    if (widget.active) {
      _controller.repeat(reverse: true);
    }

    _scale = Tween<double>(
      begin: 0.90,
      end: 1.16,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _opacity = Tween<double>(
      begin: 1,
      end: 0.48,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(covariant _AppRecordingDot oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.active != widget.active) {
      if (widget.active) {
        _controller.repeat(reverse: true);
      } else {
        _controller
          ..stop()
          ..value = 0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dotColor = widget.paused
        ? Theme.of(context).colorScheme.tertiary
        : const Color(0xFFE74C4C);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: widget.active ? _opacity.value : 1,
          child: Transform.scale(
            scale: widget.active ? _scale.value : 1,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
              ),
            ),
          ),
        );
      },
    );
  }
}
