import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/ble.dart';
import '../providers/language.dart';
import '../providers/live_ecg.dart';

import '../widgets/ecg_painter.dart';
import '../widgets/respiration_painter.dart';

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
    final liveEcgProvider = Provider.of<LiveEcgProvider>(context);

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
            FilledButton(
              onPressed: widget.onGoToSettings,
              child: Text(
                languageProvider.translate(
                  "settings_tab",
                ),
              ),
            ),
            SizedBox(height: 50),
          ],
        ),
      );
    }

    return SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: true,
      minimum: EdgeInsets.only(bottom: 15),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          children: [
            SizedBox(
              height: 92,
              child: Consumer<BleProvider>(
                builder: (context, ble, child) {
                  return Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: _Heart(
                            bpm: ble.heartRate,
                            beatSerial: ble.heartBeatSerial,
                            label: languageProvider.translate("heart_rate"),
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 52,
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                      Expanded(
                        child: Center(
                          child: _Respiration(
                            respiratoryRate: ble.respiratoryRate,
                            respirationLevel: ble.respirationLevel,
                            label: languageProvider.translate("respiration"),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Divider(
              height: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
              thickness: 1,
            ),
            SizedBox(height: 14),
            Expanded(
              flex: 11,
              child: Consumer<BleProvider>(
                builder: (context, ble, child) {
                  return _Graph(
                    time: "2.4 s",
                    title: "ECG",
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: EcgPainter(
                          ble.ecgPoints,
                          liveEcgProvider.showGrid,
                          maxPoints: BleProvider.ecgVisiblePoints,
                          lineColor: Theme.of(context).colorScheme.primary,
                          gridColor: Theme.of(
                            context,
                          ).colorScheme.outlineVariant,
                          baselineColor: Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withValues(alpha: 0.55),
                        ),
                        size: Size.infinite,
                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: 14),
            Expanded(
              flex: 9,
              child: Consumer<BleProvider>(
                builder: (context, ble, child) {
                  return _Graph(
                    time: "12 s",
                    title: languageProvider.translate("respiration"),
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: RespirationPainter(
                          ble.respirationPoints,
                          ble.respirationDisplayRange,
                          liveEcgProvider.showGrid,
                          lineColor: Theme.of(context).colorScheme.tertiary,
                          gridColor: Theme.of(
                            context,
                          ).colorScheme.outlineVariant,
                          baselineColor: Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withValues(alpha: 0.55),
                          maxPoints: BleProvider.respirationVisiblePoints,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Graph extends StatelessWidget {
  final String title;
  final String time;
  final Widget child;

  const _Graph({required this.child, required this.time, required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              Spacer(),
              Text(
                time,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 7),
        Expanded(
          child: Container(
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              color: Theme.of(context).colorScheme.surfaceContainer,
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}

class _Heart extends StatefulWidget {
  final double bpm;
  final int beatSerial;
  final String label;

  const _Heart({
    required this.bpm,
    required this.beatSerial,
    required this.label,
  });

  @override
  State<_Heart> createState() => _HeartState();
}

class _HeartState extends State<_Heart> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 280),
    );

    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 1.12,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 35,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.12,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 65,
      ),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(covariant _Heart oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.beatSerial != oldWidget.beatSerial && widget.beatSerial > 0) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const heartColor = Color(0xFFE74C4C);

    final String bpmText = widget.bpm > 0
        ? widget.bpm.round().toString()
        : "--";

    return SizedBox(
      width: 141,
      height: 58,
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: Transform.translate(
                offset: const Offset(4, 0),
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final double scale = _scale.value;

                    final double animationAmount = ((scale - 1.0) / 0.12)
                        .clamp(0.0, 1.0)
                        .toDouble();

                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: heartColor.withValues(
                                alpha: 0.02 + animationAmount * 0.05,
                              ),
                              blurRadius: 4 + animationAmount * 6,
                              spreadRadius: animationAmount * 0.8,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.favorite_rounded,
                          color: heartColor,
                          size: 36,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      bpmText,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w600, height: 1),
                    ),
                    SizedBox(width: 4),
                    Padding(
                      padding: EdgeInsets.only(bottom: 3),
                      child: Text(
                        "BPM",
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 5),
                Text(
                  widget.label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Respiration extends StatelessWidget {
  final double respiratoryRate;
  final double respirationLevel;
  final String label;

  const _Respiration({
    required this.respirationLevel,
    required this.respiratoryRate,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final String rrText = respiratoryRate > 0
        ? respiratoryRate.round().toString()
        : "--";

    final double level = respirationLevel.clamp(0.0, 1.0).toDouble();

    return SizedBox(
      width: 141,
      height: 58,
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: level),
                duration: const Duration(milliseconds: 120),
                curve: Curves.easeOut,
                builder: (context, animatedLevel, child) {
                  return SizedBox(
                    width: 44,
                    height: 44,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: scheme.primary.withValues(alpha: 0.75),
                              width: 2,
                            ),
                          ),
                        ),
                        ClipOval(
                          child: SizedBox(
                            width: 38,
                            height: 38,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                widthFactor: 1,
                                heightFactor: animatedLevel,
                                child: ColoredBox(
                                  color: scheme.primary.withValues(alpha: 0.32),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      rrText,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w600, height: 1),
                    ),
                    SizedBox(width: 4),
                    Padding(
                      padding: EdgeInsets.only(bottom: 3),
                      child: Text(
                        "brpm",
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 5),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
