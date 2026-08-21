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

  await FlutterBluePlus.setOptions(
    restoreState: true,
  );

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
          create: (context) => RecordingProvider(
            context.read<BleProvider>(),
          ),
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
    final themeProvider = context.watch<ThemeProvider>();
    final fontScaleProvider = context.watch<FontScaleProvider>();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: lightMode,
      darkTheme: darkMode,
      themeMode:
          themeProvider.darkmode ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
              fontScaleProvider.fontScale,
            ),
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

class _HomeState extends State<Home>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider =
        context.watch<LanguageProvider>();
    final themeProvider =
        context.watch<ThemeProvider>();
    final recording =
        context.watch<RecordingProvider>();

    final scheme =
        Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 12,
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.graphic_eq_rounded,
                color: Colors.teal[800],
                size: 29,
              ),
              const SizedBox(width: 9),
              Text.rich(
                TextSpan(
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 22,
                  ),
                  children: [
                    TextSpan(
                      text: 'APEX',
                      style: TextStyle(
                        fontWeight: FontWeight.w400,
                        color: themeProvider.darkmode
                            ? Colors.teal[100]
                            : Colors.grey[800],
                      ),
                    ),
                    TextSpan(
                      text: ' CARDIO',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        color: Colors.teal[800],
                      ),
                    ),
                  ],
                ),
              ),
              if (recording.hasActiveRecording) ...[
                const SizedBox(width: 10),
                _RecordingHeaderPulse(
                  active:
                      recording.isRecording &&
                      recording.bleConnected &&
                      recording.activeGapReason == null,
                  paused:
                      recording.isPaused ||
                      !recording.bleConnected,
                ),
              ],
            ],
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(65),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TabBar(
                controller: _tabController,
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                tabs: [
                  _ResponsiveTab(
                    icon: Icons.favorite_rounded,
                    label: languageProvider.translate(
                      "live_tab",
                    ),
                  ),
                  _ResponsiveTab(
                    icon: Icons.folder_rounded,
                    label: languageProvider.translate(
                      "recordings_tab",
                    ),
                  ),
                  _ResponsiveTab(
                    icon: Icons.settings_rounded,
                    label: languageProvider.translate(
                      "settings_tab",
                    ),
                  ),
                ],
              ),
              Divider(
                height: 1,
                thickness: 1,
                color: scheme.outlineVariant,
              ),
            ],
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

class _ResponsiveTab extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ResponsiveTab({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Tab(
      height: 63,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 2,
        ),
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 22,
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 100,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordingHeaderPulse extends StatefulWidget {
  final bool active;
  final bool paused;

  const _RecordingHeaderPulse({
    required this.active,
    required this.paused,
  });

  @override
  State<_RecordingHeaderPulse> createState() =>
      _RecordingHeaderPulseState();
}

class _RecordingHeaderPulseState
    extends State<_RecordingHeaderPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration:
          const Duration(milliseconds: 900),
    );

    _opacity = Tween<double>(
      begin: 1,
      end: 0.35,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    _scale = Tween<double>(
      begin: 1,
      end: 1.22,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    _syncAnimation();
  }

  @override
  void didUpdateWidget(
    covariant _RecordingHeaderPulse oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.active != widget.active ||
        oldWidget.paused != widget.paused) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (widget.active) {
      _controller.repeat(reverse: true);
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme =
        Theme.of(context).colorScheme;
    final color = widget.paused
        ? scheme.tertiary
        : scheme.error;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity:
              widget.active ? _opacity.value : 1,
          child: Transform.scale(
            scale:
                widget.active ? _scale.value : 1,
            child: child,
          ),
        );
      },
      child: Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color:
                  color.withValues(alpha: 0.28),
              blurRadius: 5,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }
}
