import 'dart:async';

import 'package:flutter/material.dart';
import 'package:trackapp/models/care_class.dart';
import 'package:trackapp/screens/alert_sensitivity_screen.dart';
import 'package:trackapp/screens/student_detail_screen.dart';
import 'package:trackapp/services/alert_engine.dart';
import 'package:trackapp/services/alert_manager.dart';
import 'package:trackapp/services/local_store.dart';
import 'package:trackapp/services/watch_ble_service.dart';
import 'package:trackapp/theme/app_theme.dart';

bool isQuiet(String classId, String deviceId) =>
    AlertManager.instance.isQuiet(classId, deviceId);

void toggleQuiet(String classId, String deviceId) => AlertManager.instance
    .setQuiet(classId, deviceId, !isQuiet(classId, deviceId));

String _agoWords(DateTime t) {
  final s = DateTime.now().difference(t).inSeconds;
  if (s < 10) return 'just now';
  if (s < 60) return '$s seconds ago';
  final m = s ~/ 60;
  if (m < 60) return m == 1 ? '1 minute ago' : '$m minutes ago';
  final h = m ~/ 60;
  return h == 1 ? '1 hour ago' : '$h hours ago';
}

String _shortDuration(Duration d) {
  final s = d.inSeconds;
  if (s < 60) return '${s}s';
  return '${s ~/ 60}m ${s % 60}s';
}

String _hourMinute(DateTime t) =>
    '${t.hour}:${t.minute.toString().padLeft(2, '0')}';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key, required this.careClass});

  final CareClass careClass;

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  bool _highOnly = false;

  // keeps the "x ago" text fresh when no readings are arriving
  late final Timer _ticker =
      Timer.periodic(const Duration(seconds: 5), (_) => setState(() {}));

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

  void _openDetail(ClassDevice device) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentDetailScreen(
          careClass: widget.careClass,
          student: device,
        ),
      ),
    );
  }

  void _openStudent(ClassDevice device) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AlertSensitivityScreen(
          classId: widget.careClass.id,
          deviceId: device.deviceId,
          studentName: device.name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final manager = AlertManager.instance;
    final ble = WatchBleService.instance;

    return Scaffold(
      backgroundColor: appSoftGray,
      appBar: AppBar(title: const Text('Alerts')),
      body: ListenableBuilder(
        listenable: Listenable.merge([manager, ble, LocalStore.instance]),
        builder: (context, _) {
          final devices = widget.careClass.devices;
          final classId = widget.careClass.id;
          bool keep(AlertLogEntry e) =>
              !_highOnly || e.event.tag == AlertTag.high;

          // class-wide alerts, newest first
          final classLog = manager.classLog(classId);
          final shown = classLog.where(keep).toList();
          final periodMinutes = classLog.isEmpty
              ? 0
              : DateTime.now().difference(classLog.last.receivedAt).inMinutes;

          final now = <ClassDevice>[];
          final past = <ClassDevice>[];
          final footer = <String>[];
          for (final device in devices) {
            final active = manager.activeAlertFor(classId, device.deviceId);
            if (active != null &&
                !isQuiet(classId, device.deviceId) &&
                keep(active)) {
              now.add(device);
            }
            if (shown.any((e) => e.deviceId == device.deviceId)) {
              past.add(device);
            }

            final watch = ble.watchById(device.deviceId);
            final online = watch?.isConnected ?? false;
            if (!online) {
              final seen = watch?.lastSeen;
              footer.add(seen == null
                  ? '${device.name} offline'
                  : '${device.name} offline since ${_hourMinute(seen)}');
            } else if (!classLog.any((e) => e.deviceId == device.deviceId)) {
              footer.add('${device.name} had no alerts');
            }
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _Pill(
                      label: 'This period',
                      selected: true,
                      onTap: () => setState(() => _highOnly = false),
                    ),
                    const SizedBox(width: 8),
                    _Pill(
                      label: 'High only',
                      selected: _highOnly,
                      onTap: () => setState(() => _highOnly = !_highOnly),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${shown.length} alerts · $periodMinutes min',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: appMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (now.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _SectionHeader(
                    dot: appRed,
                    title: 'NOW',
                    count: now.length,
                  ),
                  const SizedBox(height: 10),
                  for (final device in now) ...[
                    _NowCard(
                      classId: classId,
                      device: device,
                      onOpen: () => _openDetail(device),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
                if (past.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _SectionHeader(
                    dot: appMuted,
                    title: 'PAST',
                    count: past.length,
                  ),
                  const SizedBox(height: 10),
                  AppCard(
                    child: Column(
                      children: [
                        for (var i = 0; i < past.length; i++) ...[
                          if (i > 0)
                            const Divider(height: 1, color: appBorder),
                          _PastRow(
                            classId: classId,
                            device: past[i],
                            entries: shown
                                .where((e) => e.deviceId == past[i].deviceId)
                                .toList(),
                            quiet: isQuiet(classId, past[i].deviceId),
                            onTap: () => _openStudent(past[i]),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                if (footer.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  AppCard(
                    child: Row(
                      children: [
                        const Icon(Icons.check, color: appTeal),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            footer.join('\n'),
                            style: const TextStyle(
                              color: appMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? appIndigo : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? appIndigo : appBorder),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : appInk,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.dot,
    required this.title,
    required this.count,
  });

  final Color dot;
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.circle, size: 8, color: dot),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: appInk,
            fontSize: 13,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          count == 1 ? '1 student' : '$count students',
          style: const TextStyle(
            color: appMuted,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _NowCard extends StatelessWidget {
  const _NowCard({
    required this.classId,
    required this.device,
    required this.onOpen,
  });

  final String classId;
  final ClassDevice device;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final manager = AlertManager.instance;
    final id = device.deviceId;
    final active = manager.activeAlertFor(classId, id)!;
    final engine = manager.engineFor(classId, id);

    // alerts in the current run: newest back to its initial alert
    var runAlerts = 0;
    AlertLogEntry? initial;
    for (final entry in manager.logFor(classId, id)) {
      runAlerts++;
      if (!entry.event.isRepeat) {
        initial = entry;
        break;
      }
    }
    // reading time: from the run's first reading to the latest one
    final lastArrival = engine.lastArrivalAt;
    final going = initial == null || lastArrival == null
        ? Duration.zero
        : lastArrival.difference(initial.event.at) +
            engine.settings.nominalRunDuration;
    final high = active.event.tag == AlertTag.high;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: appRed.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: appRed.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline, color: appRed),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: appInk,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                id,
                style: const TextStyle(
                  color: appMuted,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            high ? 'High fidgeting' : 'Low fidgeting',
            style: const TextStyle(
              color: appRed,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            'going ${_shortDuration(going)} · '
            '$runAlerts ${runAlerts == 1 ? 'alert' : 'alerts'} · '
            'last ${_agoWords(active.receivedAt)}',
            style: const TextStyle(
              color: appInk,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: appIndigo,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: onOpen,
                  child: Text(
                    'Open ${device.name.split(' ').first}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: appMuted,
                    side: const BorderSide(color: appBorder),
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: () => toggleQuiet(classId, id),
                  icon: const Icon(Icons.notifications_off_outlined, size: 18),
                  label: const Text(
                    'Quiet',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PastRow extends StatelessWidget {
  const _PastRow({
    required this.classId,
    required this.device,
    required this.entries,
    required this.quiet,
    required this.onTap,
  });

  final String classId;
  final ClassDevice device;

  final List<AlertLogEntry> entries;
  final bool quiet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final latest = entries.first.event.tag;
    final high = latest == AlertTag.high;
    final times = entries.take(3).map((e) => _agoWords(e.receivedAt)).join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: high
                    ? appRed.withValues(alpha: 0.12)
                    : appGold.withValues(alpha: 0.16),
              ),
              child: Text(
                '${entries.length}',
                style: TextStyle(
                  color: alertTagColor(latest),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          device.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: appInk,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AlertTagChip(latest),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    entries.length > 3 ? '$times …' : times,
                    style: const TextStyle(
                      color: appMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SkippedNote(entries.first.event),
                ],
              ),
            ),
            if (quiet)
              IconButton(
                tooltip: 'Unmute',
                icon: const Icon(Icons.notifications_off_outlined,
                    color: appMuted, size: 20),
                onPressed: () => toggleQuiet(classId, device.deviceId),
              ),
            const Icon(Icons.chevron_right, color: appMuted),
          ],
        ),
      ),
    );
  }
}
