import 'package:flutter/material.dart';
import 'package:trackapp/screens/alert_rule_screen.dart';
import 'package:trackapp/services/alert_engine.dart';
import 'package:trackapp/services/alert_manager.dart';
import 'package:trackapp/theme/app_theme.dart';

const _repeatStops = [
  Duration(seconds: 10),
  Duration(seconds: 30),
  Duration(seconds: 60),
  Duration(seconds: 120),
];

Color alertTagColor(AlertTag tag) =>
    tag == AlertTag.high ? appRed : appGoldText;

String alertTagText(AlertTag tag) => tag == AlertTag.high ? 'HIGH' : 'LOW';

//4 of 5 votes = 80%
String confidenceText(ConfidenceStop stop) {
  switch (stop) {
    case ConfidenceStop.off:
      return 'Off';
    case ConfidenceStop.fourOfFive:
      return '80%';
    case ConfidenceStop.fiveOfFive:
      return '100%';
  }
}

String fidgetLabelText(FidgetLabel label) {
  switch (label) {
    case FidgetLabel.notFidgeting:
      return 'Calm';
    case FidgetLabel.lowFidgeting:
      return 'Low fidgeting';
    case FidgetLabel.highFidgeting:
      return 'High fidgeting';
  }
}

String clockTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

class SkippedNote extends StatelessWidget {
  const SkippedNote(this.event, {super.key});

  final AlertEvent event;

  @override
  Widget build(BuildContext context) {
    if (event.skipped == 0) return const SizedBox.shrink();
    final seconds = event.span.inMilliseconds / 1000;
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 14, color: appGoldText),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              '${event.skipped} '
              '${event.skipped == 1 ? 'reading' : 'readings'} skipped · '
              'alert spanned ${seconds.toStringAsFixed(1)} s',
              style: const TextStyle(
                color: appGoldText,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AlertTagChip extends StatelessWidget {
  const AlertTagChip(this.tag, {super.key});

  final AlertTag tag;

  @override
  Widget build(BuildContext context) {
    final high = tag == AlertTag.high;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color:
            high
                ? appRed.withValues(alpha: 0.12)
                : appGold.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        alertTagText(tag),
        style: TextStyle(
          color: alertTagColor(tag),
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class AlertSensitivityScreen extends StatelessWidget {
  const AlertSensitivityScreen({
    super.key,
    required this.classId,
    required this.deviceId,
    required this.studentName,
  });

  //cart watches can have different settings in each class
  final String classId;
  final String deviceId;
  final String studentName;

  @override
  Widget build(BuildContext context) {
    final manager = AlertManager.instance;

    return Scaffold(
      backgroundColor: appSoftGray,
      appBar: AppBar(
        title: Text(
          studentName,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w400),
        ),
        actions: [
          IconButton(
            tooltip: 'How an alert is decided',
            icon: const Icon(Icons.info_outline, color: Colors.white),
            onPressed:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder:
                        (_) => AlertRuleScreen(
                          classId: classId,
                          deviceId: deviceId,
                        ),
                  ),
                ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: manager,
        builder: (context, _) {
          final settings = manager.settingsFor(classId, deviceId);
          final n = settings.readingsInARow;
          final runSeconds = settings.nominalRunDuration.inMilliseconds / 1000;
          final repeatIndex = _repeatStops.indexOf(settings.repeatEvery);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Sensitivity Settings',
                  style: TextStyle(
                    color: appInk,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 14),
                _SettingCard(
                  label: 'Fidget readings in a row',
                  value: '$n',
                  stops: const ['1', '2', '3', '4'],
                  selected: n - 1,
                  caption:
                      'About ${_trimZero(runSeconds)} seconds of unbroken fidgeting',
                  onChanged:
                      (i) => manager.setSettings(
                        classId,
                        deviceId,
                        settings.copyWith(readingsInARow: i + 1),
                      ),
                ),
                const SizedBox(height: 14),
                _SettingCard(
                  label: 'Repeat alerts every',
                  value: '${settings.repeatEvery.inSeconds} s',
                  stops: [
                    for (final stop in _repeatStops) '${stop.inSeconds} s',
                  ],
                  selected: repeatIndex < 0 ? 0 : repeatIndex,
                  caption: 'Only while the fidgeting is still going',
                  onChanged:
                      (i) => manager.setSettings(
                        classId,
                        deviceId,
                        settings.copyWith(repeatEvery: _repeatStops[i]),
                      ),
                ),
                const SizedBox(height: 14),
                _SettingCard(
                  label: 'Minimum confidence',
                  value: confidenceText(settings.minConfidence),
                  valueIsOff: settings.minConfidence == ConfidenceStop.off,
                  stops: [
                    for (final stop in ConfidenceStop.values)
                      confidenceText(stop),
                  ],
                  selected: settings.minConfidence.index,
                  caption:
                      'A skipped reading does not continue nor break fidget '
                      'times. At 80% minimum confidence, the watch drops about '
                      'a quarter of all readings.',
                  onChanged:
                      (i) => manager.setSettings(
                        classId,
                        deviceId,
                        settings.copyWith(
                          minConfidence: ConfidenceStop.values[i],
                        ),
                      ),
                ),
                const SizedBox(height: 14),
                _AlertLogCard(classId: classId, deviceId: deviceId),
              ],
            ),
          );
        },
      ),
    );
  }
}

String _trimZero(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

//inset so the end thumbs fit and labels sit under the ticks
const double _trackInset = 16;

class _SettingCard extends StatelessWidget {
  const _SettingCard({
    required this.label,
    required this.value,
    this.valueIsOff = false,
    required this.stops,
    required this.selected,
    required this.caption,
    required this.onChanged,
  });

  final String label;
  final String value;

  final bool valueIsOff;
  final List<String> stops;
  final int selected;
  final String caption;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: appInk,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: valueIsOff ? appMuted : appIndigo,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 5,
              trackShape: const RoundedRectSliderTrackShape(),
              activeTrackColor: appIndigo,
              inactiveTrackColor: appBorder,
              activeTickMarkColor: appIndigo,
              //one dot per stop
              inactiveTickMarkColor: appMuted.withValues(alpha: 0.22),
              tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 5),
              thumbColor: appIndigo,
              thumbShape: const _RingThumbShape(),
              overlayColor: appIndigo.withValues(alpha: 0.12),
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: Slider(
              padding: const EdgeInsets.symmetric(horizontal: _trackInset),
              value: selected.toDouble(),
              min: 0,
              max: (stops.length - 1).toDouble(),
              divisions: stops.length - 1,
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
          const SizedBox(height: 8),
          _StopLabels(stops: stops, selected: selected),
          const SizedBox(height: 10),
          Text(
            caption,
            style: const TextStyle(
              color: appMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _StopLabels extends StatelessWidget {
  const _StopLabels({required this.stops, required this.selected});

  final List<String> stops;
  final int selected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final track = constraints.maxWidth - 2 * _trackInset;
        const labelWidth = 2 * _trackInset + 16;
        return SizedBox(
          height: 18,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < stops.length; i++)
                Positioned(
                  left:
                      _trackInset +
                      track * i / (stops.length - 1) -
                      labelWidth / 2,
                  width: labelWidth,
                  child: Text(
                    stops[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: i == selected ? appIndigo : appMuted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RingThumbShape extends SliderComponentShape {
  const _RingThumbShape();

  static const double _radius = 11;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.fromRadius(_radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final color = sliderTheme.thumbColor ?? appIndigo;
    canvas.drawCircle(center, _radius, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      _radius - 1.25,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.drawCircle(center, 5, Paint()..color = color);
  }
}

class _AlertLogCard extends StatelessWidget {
  const _AlertLogCard({required this.classId, required this.deviceId});

  final String classId;
  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final log = AlertManager.instance.logFor(classId, deviceId);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'ALERT LOG (${log.length})',
            style: const TextStyle(
              color: appMuted,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          if (log.isEmpty)
            const Text(
              'No alerts yet.',
              style: TextStyle(color: appMuted, fontWeight: FontWeight.w700),
            ),
          for (final entry in log)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        clockTime(entry.receivedAt),
                        style: const TextStyle(
                          color: appInk,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 10),
                      AlertTagChip(entry.event.tag),
                      if (entry.event.isRepeat) ...[
                        const SizedBox(width: 8),
                        const Text(
                          'repeat',
                          style: TextStyle(
                            color: appMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${entry.event.highs} high · ${entry.event.lows} low',
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: appMuted, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  SkippedNote(entry.event),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
