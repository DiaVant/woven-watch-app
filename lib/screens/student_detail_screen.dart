import 'dart:async';

import 'package:flutter/material.dart';
import 'package:trackapp/models/care_class.dart';
import 'package:trackapp/screens/alert_sensitivity_screen.dart';
import 'package:trackapp/services/alert_engine.dart';
import 'package:trackapp/services/alert_manager.dart';
import 'package:trackapp/services/local_store.dart';
import 'package:trackapp/services/session_stats.dart';
import 'package:trackapp/services/watch_ble_service.dart';
import 'package:trackapp/theme/app_theme.dart';
import 'package:trackapp/widgets/student_live.dart';
import 'package:trackapp/widgets/watch_roster.dart';

class StudentDetailScreen extends StatefulWidget {
  const StudentDetailScreen({
    super.key,
    required this.careClass,
    required this.student,
  });

  final CareClass careClass;
  final ClassDevice student;

  @override
  State<StudentDetailScreen> createState() => _StudentDetailScreenState();
}

class _StudentDetailScreenState extends State<StudentDetailScreen> {
  late final Timer _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
    if (mounted) setState(() {});
  });

  @override
  void initState() {
    super.initState();
    _ticker; //start it
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  void _openSensitivity() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AlertSensitivityScreen(
          classId: widget.careClass.id,
          deviceId: widget.student.deviceId,
          studentName: widget.student.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final classId = widget.careClass.id;
    final deviceId = widget.student.deviceId;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.student.name,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w400),
        ),
        actions: [
          IconButton(
            tooltip: 'Alert sensitivity',
            icon: const Icon(Icons.tune),
            onPressed: _openSensitivity,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          AlertManager.instance,
          WatchBleService.instance,
          LocalStore.instance,
        ]),
        builder: (context, _) {
          final now = DateTime.now();
          final live = studentLive(classId, deviceId, now: now);
          final session = LocalStore.instance.latestSession(classId, deviceId);
          final settings = AlertManager.instance.settingsFor(classId, deviceId);

          return AppPage(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _RightNowCard(deviceId: deviceId, live: live),
                const SizedBox(height: 12),
                _QuietBar(classId: classId, deviceId: deviceId),
                const SizedBox(height: 16),
                _TimelineCard(session: session, now: now),
                const SizedBox(height: 16),
                _StatsCard(session: session, now: now),
                const SizedBox(height: 16),
                AppCard(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: _openSensitivity,
                    child: Row(
                      children: [
                        const Icon(Icons.tune, color: appIndigo, size: 30),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Alert sensitivity',
                                style: TextStyle(
                                  color: appInk,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Text(
                                sensitivitySummary(settings),
                                style: const TextStyle(
                                  color: appMuted,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: appMuted),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

String sensitivitySummary(AlertSettings s) {
  final stop = switch (s.minConfidence) {
    ConfidenceStop.off => 'all readings count',
    ConfidenceStop.fourOfFive => 'skip below 80%',
    ConfidenceStop.fiveOfFive => 'skip below 100%',
  };
  return '${s.readingsInARow} in a row · '
      'repeat ${s.repeatEvery.inSeconds} s · $stop';
}

class _RightNowCard extends StatelessWidget {
  const _RightNowCard({required this.deviceId, required this.live});

  final String deviceId;
  final StudentLive live;

  @override
  Widget build(BuildContext context) {
    final tint = stateTint(live);
    final isLive = live.kind == LiveKind.live;
    final watch = live.watch;
    final title = switch (live.kind) {
      LiveKind.live => labelName(live.label),
      LiveKind.signalLost => 'Signal lost',
      LiveKind.waiting => 'Waiting for data',
      LiveKind.offline => 'Not connected',
    };
    final active = live.activeAlert;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: tint.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tint.border, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Right now',
                  style: TextStyle(
                    color: appMuted,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                deviceId,
                style: const TextStyle(
                  color: appMuted,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 8),
              SignalBars(
                level: (watch?.isConnected ?? false) ? watch!.signalBars : 0,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isLive ? labelColor(live.label) : appMuted,
              fontSize: 38,
              fontWeight: FontWeight.w900,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (active != null)
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AlertedPill(entry: active),
                  ),
                )
              else
                Expanded(
                  child: Text(
                    switch (live.kind) {
                      LiveKind.signalLost =>
                        'Last seen ${labelName(live.lastLabel)} at '
                            '${clockMinutes(live.lastReadingAt!)} · '
                            'alerts paused',
                      LiveKind.waiting => 'Connected, waiting for a reading',
                      LiveKind.offline => 'Connect the watch to see live data',
                      LiveKind.live => live.quiet
                          ? 'Quiet mode on · alerts not shown'
                          : 'No alert running',
                    },
                    style: const TextStyle(
                      color: appMuted,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              const SizedBox(width: 12),
              if (isLive && live.stateFor != null)
                Text(
                  live.label == FidgetLabel.notFidgeting
                      ? 'Calm ${shortDuration(live.stateFor!)}'
                      : 'Active ${shortDuration(live.stateFor!)}',
                  style: const TextStyle(
                    color: appInk,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

Color _kindColor(TimelineKind kind) => switch (kind) {
      TimelineKind.calm => appTeal,
      TimelineKind.low => appGold,
      TimelineKind.high => appRed,
      TimelineKind.noSignal => appBorder,
    };

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.session, required this.now});

  final StoredSession? session;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final s = session;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Session timeline',
                  style: TextStyle(
                    color: appInk,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (s != null)
                Text(
                  '${sessionEnd(s, now).difference(s.startedAt).inMinutes} min',
                  style: const TextStyle(
                    color: appMuted,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (s == null)
            const Text(
              'No session recorded yet. Start a session on the class page to '
              'record a timeline.',
              style: TextStyle(color: appMuted, fontWeight: FontWeight.w700),
            )
          else
            _Timeline(session: s, now: now),
          const Divider(height: 28, color: appBorder),
          const _Legend(),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.session, required this.now});

  final StoredSession session;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final start = session.startedAt;
    final end = sessionEnd(session, now);
    final segments = buildTimeline(session, now);
    const ticks = 5;
    final span = end.difference(start);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 14,
          child: CustomPaint(
            painter: _MarkerPainter(
              alerts: session.alerts,
              start: start,
              end: end,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 66,
          child: CustomPaint(
            painter: _BarPainter(segments: segments, start: start, end: end),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < ticks; i++)
              Expanded(
                child: Text(
                  clockMinutes(start.add(span * (i / (ticks - 1)))),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  textAlign: i == 0
                      ? TextAlign.left
                      : i == ticks - 1
                          ? TextAlign.right
                          : TextAlign.center,
                  style: const TextStyle(
                    color: appMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

double _fraction(DateTime t, DateTime start, DateTime end) {
  final total = end.difference(start).inMilliseconds;
  if (total <= 0) return 0;
  return (t.difference(start).inMilliseconds / total).clamp(0.0, 1.0);
}

void _hatch(Canvas canvas, Rect rect) {
  canvas.drawRect(rect, Paint()..color = Colors.white);
  canvas.save();
  canvas.clipRect(rect);
  final line = Paint()
    ..color = appBorder
    ..strokeWidth = 2;
  for (var x = rect.left - rect.height; x < rect.right; x += 6) {
    canvas.drawLine(
      Offset(x, rect.bottom),
      Offset(x + rect.height, rect.top),
      line,
    );
  }
  canvas.restore();
}

class _BarPainter extends CustomPainter {
  _BarPainter({required this.segments, required this.start, required this.end});

  final List<TimelineSegment> segments;
  final DateTime start;
  final DateTime end;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(8),
    );
    canvas.save();
    canvas.clipRRect(outer);
    canvas.drawRect(Offset.zero & size, Paint()..color = appSoftGray);
    for (final seg in segments) {
      final left = _fraction(seg.start, start, end) * size.width;
      final right = _fraction(seg.end, start, end) * size.width;
      // keep very short stretches visible
      final rect = Rect.fromLTRB(left, 0, right < left + 1 ? left + 1 : right,
          size.height);
      if (seg.kind == TimelineKind.noSignal) {
        _hatch(canvas, rect);
      } else {
        canvas.drawRect(rect, Paint()..color = _kindColor(seg.kind));
      }
    }
    canvas.restore();
    canvas.drawRRect(
      outer,
      Paint()
        ..color = appBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) => true;
}

void _triangle(Canvas canvas, Offset bottomCentre, double size, Color color) {
  final path = Path()
    ..moveTo(bottomCentre.dx - size / 2, bottomCentre.dy)
    ..lineTo(bottomCentre.dx + size / 2, bottomCentre.dy)
    ..lineTo(bottomCentre.dx, bottomCentre.dy - size * 0.85)
    ..close();
  canvas.drawPath(path, Paint()..color = color);
}

class _MarkerPainter extends CustomPainter {
  _MarkerPainter({required this.alerts, required this.start, required this.end});

  final List<StoredAlert> alerts;
  final DateTime start;
  final DateTime end;

  @override
  void paint(Canvas canvas, Size size) {
    for (final alert in alerts) {
      final x = _fraction(alert.at, start, end) * size.width;
      _triangle(
        canvas,
        Offset(x.clamp(7.0, size.width - 7), size.height),
        14,
        alert.tag == AlertTag.high ? appRed : appGoldText,
      );
    }
  }

  @override
  bool shouldRepaint(_MarkerPainter old) => true;
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget item(String label, void Function(Canvas, Size) draw) => Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CustomPaint(painter: _SwatchPainter(draw)),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: appMuted,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        );
    void square(Canvas c, Size s, Color color) => c.drawRRect(
          RRect.fromRectAndRadius(Offset.zero & s, const Radius.circular(2)),
          Paint()..color = color,
        );

    final items = [
      item('Calm', (c, s) => square(c, s, appTeal)),
      item('Low', (c, s) => square(c, s, appGold)),
      item('High', (c, s) => square(c, s, appRed)),
      item('No signal', (c, s) => _hatch(c, Offset.zero & s)),
      item('High alert',
          (c, s) => _triangle(c, Offset(s.width / 2, s.height), s.width, appRed)),
      item('Low alert', (c, s) =>
          _triangle(c, Offset(s.width / 2, s.height), s.width, appGoldText)),
    ];
    return Column(
      children: [
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: 12),
          Row(
            children: [
              for (var col = 0; col < 3; col++)
                Expanded(child: items[row * 3 + col]),
            ],
          ),
        ],
      ],
    );
  }
}

class _SwatchPainter extends CustomPainter {
  _SwatchPainter(this.draw);

  final void Function(Canvas, Size) draw;

  @override
  void paint(Canvas canvas, Size size) => draw(canvas, size);

  @override
  bool shouldRepaint(_SwatchPainter old) => false;
}

class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.session, required this.now});

  final StoredSession? session;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final stats = s == null ? null : computeSessionStats(s, now);
    String d(Duration? v) => v == null ? '—' : shortDurationSeconds(v);

    return AppCard(
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Stat('Calm', d(stats?.calm), tint: appTeal, text: appTealText),
              const SizedBox(width: 12),
              _Stat('Low fidgeting', d(stats?.low),
                  tint: appGold, text: appGoldText),
              const SizedBox(width: 12),
              _Stat('High fidgeting', d(stats?.high),
                  tint: appRed, text: appRed),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Stat('Longest fidget', d(stats?.longestFidget)),
              const SizedBox(width: 12),
              _Stat(
                'Alerts',
                stats == null ? '—' : '${stats.alerts}',
                suffix: stats == null
                    ? null
                    : '${stats.highAlerts}H · ${stats.lowAlerts}L',
              ),
              const SizedBox(width: 12),
              _Stat(
                'Received readings',
                stats == null
                    ? '—'
                    : '${(stats.receivedFraction * 100).round()}%',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String shortDurationSeconds(Duration d) {
  final s = d.inSeconds;
  if (s < 60) return '${s}s';
  if (d.inHours < 1) {
    return '${d.inMinutes}m ${(s % 60).toString().padLeft(2, '0')}s';
  }
  return '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}m';
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.tint, this.text, this.suffix});

  final String label;
  final String value;
  final Color? tint;
  final Color? text;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 6, 12),
        decoration: BoxDecoration(
          color: tint?.withValues(alpha: tint == appGold ? 0.14 : 0.10) ??
              Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // labels shrink a little rather than truncate in a narrow column
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  color: text ?? appMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  text: value,
                  children: [
                    if (suffix != null)
                      TextSpan(
                        text: '  $suffix',
                        style: const TextStyle(
                          color: appMuted,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
                style: TextStyle(
                  color: text ?? appInk,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

//mute or unmute this student's alerts in this class
class _QuietBar extends StatelessWidget {
  const _QuietBar({required this.classId, required this.deviceId});

  final String classId;
  final String deviceId;

  @override
  Widget build(BuildContext context) {
    final manager = AlertManager.instance;
    final quiet = manager.isQuiet(classId, deviceId);
    final recorded = manager.logFor(classId, deviceId).length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: quiet ? appIndigo.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: quiet ? appIndigo.withValues(alpha: 0.35) : appBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(
            quiet
                ? Icons.notifications_off_outlined
                : Icons.notifications_active_outlined,
            color: appIndigo,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quiet ? 'Alerts muted' : 'Alerts on',
                  style: const TextStyle(
                    color: appInk,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  quiet
                      ? '$recorded ${recorded == 1 ? 'alert' : 'alerts'} '
                          'recorded, none shown'
                      : 'Mute to keep recording without showing alerts',
                  style: const TextStyle(
                    color: appMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          quiet
              ? FilledButton.icon(
                  onPressed: () => manager.setQuiet(classId, deviceId, false),
                  icon: const Icon(Icons.notifications_active_outlined, size: 18),
                  label: const Text(
                    'Unmute',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                )
              : OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: appIndigo,
                    side: BorderSide(color: appIndigo.withValues(alpha: 0.35)),
                  ),
                  onPressed: () => manager.setQuiet(classId, deviceId, true),
                  icon: const Icon(Icons.notifications_off_outlined, size: 18),
                  label: const Text(
                    'Mute',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
        ],
      ),
    );
  }
}
