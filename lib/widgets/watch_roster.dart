import 'package:flutter/material.dart';
import 'package:trackapp/models/care_class.dart';
import 'package:trackapp/services/watch_ble_service.dart';
import 'package:trackapp/theme/app_theme.dart';

typedef WatchAssignment = ({CareClass careClass, ClassDevice student});

class WatchEntry {
  WatchEntry({required this.id, this.watch, List<WatchAssignment>? assignments})
    : assignments = assignments ?? [];

  final String id;

  //null if not seen over BLE yet
  final WovenWatch? watch;
  final List<WatchAssignment> assignments;

  bool get isConnected => watch?.isConnected ?? false;
  bool get isAssigned => assignments.isNotEmpty;

  String get displayName => id;
}

List<WatchEntry> buildWatchRoster(
  List<CareClass> classes,
  WatchBleService ble,
) {
  final entries = <String, WatchEntry>{};
  for (final careClass in classes) {
    for (final student in careClass.devices) {
      entries
          .putIfAbsent(
            student.deviceId,
            () => WatchEntry(
              id: student.deviceId,
              watch: ble.watchById(student.deviceId),
            ),
          )
          .assignments
          .add((careClass: careClass, student: student));
    }
  }
  for (final watch in ble.watches) {
    entries.putIfAbsent(watch.id, () => WatchEntry(id: watch.id, watch: watch));
  }
  return entries.values.toList();
}

class SignalBars extends StatelessWidget {
  const SignalBars({super.key, required this.level, this.size = 16});

  final int level;
  final double size;

  @override
  Widget build(BuildContext context) {
    final barWidth = size / 4.5;
    return SizedBox(
      height: size,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < 4; i++)
            Container(
              width: barWidth,
              height: size * (0.4 + 0.2 * i),
              margin: EdgeInsets.only(right: i < 3 ? barWidth * 0.5 : 0),
              decoration: BoxDecoration(
                color: i < level ? appBlue : appBorder,
                borderRadius: BorderRadius.circular(barWidth),
              ),
            ),
        ],
      ),
    );
  }
}

class DashedBorder extends StatelessWidget {
  const DashedBorder({
    super.key,
    required this.child,
    this.color = appBorder,
    this.radius = 8,
  });

  final Widget child;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRRectPainter(color: color, radius: radius),
      child: child,
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
    final path =
        Path()..addRRect(
          RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
        );
    const dash = 5.0;
    const gap = 4.0;
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) =>
      old.color != color || old.radius != radius;
}
