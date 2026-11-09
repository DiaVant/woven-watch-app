import 'package:flutter/material.dart';
import 'package:trackapp/services/alert_engine.dart';
import 'package:trackapp/services/alert_manager.dart';
import 'package:trackapp/services/watch_ble_service.dart';
import 'package:trackapp/theme/app_theme.dart';

enum LiveKind {
  live,

  signalLost,

  waiting,

  offline,
}

class StudentLive {
  const StudentLive({
    required this.kind,
    required this.watch,
    this.label,
    this.lastLabel,
    this.lastReadingAt,
    this.stateFor,
    this.activeAlert,
    this.lastAlert,
    this.quiet = false,
  });

  final LiveKind kind;
  final WovenWatch? watch;

  final FidgetLabel? label;

  final FidgetLabel? lastLabel;

  final DateTime? lastReadingAt;

  final Duration? stateFor;

  final AlertLogEntry? activeAlert;
  final AlertLogEntry? lastAlert;
  final bool quiet;
}

FidgetLabel? _wireToLabel(String? wire) =>
    wire == null ? null : fidgetLabelFromWire(wire);

StudentLive studentLive(String classId, String deviceId, {DateTime? now}) {
  final at = now ?? DateTime.now();
  final manager = AlertManager.instance;
  final watch = WatchBleService.instance.watchById(deviceId);
  final reading = manager.lastReadingFor(classId, deviceId);
  final quiet = manager.isQuiet(classId, deviceId);
  final log = manager.logFor(classId, deviceId);

  // latest of the manager's reading and the watch's own prediction
  var lastAt = reading?.receivedAt;
  var lastLabel = reading?.label;
  final bleAt = watch?.predictionAt;
  final bleLabel = _wireToLabel(watch?.prediction);
  if (bleAt != null &&
      bleLabel != null &&
      (watch?.isConnected ?? false) &&
      (lastAt == null || bleAt.isAfter(lastAt))) {
    lastAt = bleAt;
    lastLabel = bleLabel;
  }

  final fresh = lastAt != null && at.difference(lastAt) <= silenceThreshold;
  final kind =
      fresh
          ? LiveKind.live
          : lastAt != null
          ? LiveKind.signalLost
          : (watch?.isConnected ?? false)
          ? LiveKind.waiting
          : LiveKind.offline;

  return StudentLive(
    kind: kind,
    watch: watch,
    label: fresh ? lastLabel : null,
    lastLabel: lastLabel,
    lastReadingAt: lastAt,
    stateFor: fresh ? manager.stateDuration(classId, deviceId) : null,
    activeAlert: quiet ? null : manager.activeAlertFor(classId, deviceId),
    lastAlert: log.isEmpty ? null : log.first,
    quiet: quiet,
  );
}

Color labelColor(FidgetLabel? label) => switch (label) {
  FidgetLabel.notFidgeting => appTeal,
  FidgetLabel.lowFidgeting => appGold,
  FidgetLabel.highFidgeting => appRed,
  null => appMuted,
};

Color labelTextColor(FidgetLabel? label) => switch (label) {
  FidgetLabel.notFidgeting => appTealText,
  FidgetLabel.lowFidgeting => appGoldText,
  FidgetLabel.highFidgeting => appRed,
  null => appMuted,
};

String labelName(FidgetLabel? label) => switch (label) {
  FidgetLabel.notFidgeting => 'Calm',
  FidgetLabel.lowFidgeting => 'Low fidgeting',
  FidgetLabel.highFidgeting => 'High fidgeting',
  null => '—',
};

({Color background, Color border}) stateTint(StudentLive live) {
  if (live.kind != LiveKind.live) {
    return (
      background: appMuted.withValues(alpha: 0.10),
      border: appMuted.withValues(alpha: 0.30),
    );
  }
  final color = labelColor(live.label);
  return (
    background: color.withValues(
      alpha: live.label == FidgetLabel.lowFidgeting ? 0.10 : 0.08,
    ),
    border: color.withValues(alpha: 0.40),
  );
}

//minutes only past 10m
String shortDuration(Duration d) {
  final s = d.inSeconds;
  if (s < 60) return '${s}s';
  final m = d.inMinutes;
  if (m < 10) return '${m}m ${s % 60}s';
  if (m < 60) return '${m}m';
  return '${d.inHours}h ${m % 60}m';
}

String agoShort(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inSeconds < 5) return 'just now';
  return '${shortDuration(d)} ago';
}

String clockMinutes(DateTime t) =>
    '${t.hour}:${t.minute.toString().padLeft(2, '0')}';

class AlertedPill extends StatelessWidget {
  const AlertedPill({super.key, required this.entry});

  final AlertLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final high = entry.event.tag == AlertTag.high;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: high ? appRed : appGoldText,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Colors.white,
            size: 15,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              'ALERTED ${agoShort(entry.receivedAt).toUpperCase()}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HistoryBars extends StatelessWidget {
  const HistoryBars({super.key, required this.readings, this.height = 16});

  final List<LastReading> readings;
  final double height;

  @override
  Widget build(BuildContext context) {
    const slots = AlertManager.historyLength;
    final recent =
        readings.length > slots
            ? readings.sublist(readings.length - slots)
            : readings;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < slots; i++)
          Container(
            width: 4.5,
            height: height,
            margin: const EdgeInsets.only(left: 1.5),
            color:
                i < recent.length
                    ? labelColor(recent[i].label)
                    : appBorder.withValues(alpha: 0.8),
          ),
      ],
    );
  }
}
