import 'dart:async';

import 'package:flutter/material.dart';
import 'package:trackapp/models/care_class.dart';
import 'package:trackapp/screens/alerts_screen.dart';
import 'package:trackapp/screens/home/class_dialogs.dart';
import 'package:trackapp/services/alert_engine.dart';
import 'package:trackapp/services/alert_manager.dart';
import 'package:trackapp/services/class_service.dart';
import 'package:trackapp/services/local_store.dart';
import 'package:trackapp/services/watch_ble_service.dart'
    show WatchBleService, WovenWatch;
import 'package:trackapp/theme/app_theme.dart';
import 'package:trackapp/widgets/student_live.dart';

class ClassPage extends StatefulWidget {
  const ClassPage({
    super.key,
    required this.initialCareClass,
    required this.classService,
    required this.onEditClass,
    required this.onStudentTap,
  });

  final CareClass initialCareClass;
  final ClassService classService;
  final ValueChanged<CareClass> onEditClass;
  final void Function(CareClass careClass, ClassDevice classDevice)
      onStudentTap;

  @override
  State<ClassPage> createState() => ClassPageState();
}

class ClassPageState extends State<ClassPage> {
  // subscribe once for the page lifetime instead of on every rebuild
  late final Stream<List<CareClass>> _classesStream =
      widget.classService.watchClasses();

  //keeps the "x ago" text fresh between readings
  late final Timer _ticker =
      Timer.periodic(const Duration(seconds: 1), (_) {
    if (mounted) setState(() {});
  });

  @override
  void initState() {
    super.initState();
    _ticker; //start it
    LocalStore.instance.load();
  }

  @override
  void dispose() {
    _ticker.cancel();
    AlertManager.instance.leaveClass(widget.initialCareClass.id);
    super.dispose();
  }

  AlertLogEntry? _dismissed;

  AlertLogEntry? _bannerAlert(CareClass careClass) {
    final manager = AlertManager.instance;
    final roster = {for (final d in careClass.devices) d.deviceId};
    for (final entry in manager.classLog(careClass.id)) {
      if (!roster.contains(entry.deviceId)) continue;
      if (AlertManager.instance.isQuiet(careClass.id, entry.deviceId)) continue;
      if (!identical(
        manager.activeAlertFor(careClass.id, entry.deviceId),
        entry,
      )) {
        continue;
      }
      return identical(entry, _dismissed) ? null : entry;
    }
    return null;
  }

  void _showSnackBar(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleSession(CareClass careClass) async {
    final store = LocalStore.instance;
    if (!store.isClassSessionRunning(careClass.id)) {
      store.startClassSession(
        careClass.id,
        careClass.devices.map((device) => device.deviceId),
      );
      return;
    }
    final end = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('End session?'),
        content: const Text(
          'The timeline and stats stop recording. Live alerts keep working.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('End session'),
          ),
        ],
      ),
    );
    if (end == true) store.endClassSession(careClass.id);
  }

  Future<void> _connect(WovenWatch watch) async {
    try {
      await WatchBleService.instance.connect(watch);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('${watch.id}: $e');
    }
  }

  Future<void> _assign(CareClass careClass, String deviceId) async {
    try {
      await widget.classService.addDeviceToClass(
        classId: careClass.id,
        deviceId: deviceId,
      );
      if (!mounted) return;
      _showSnackBar('$deviceId added to "${careClass.name}".');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Could not assign $deviceId: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CareClass>>(
      stream: _classesStream,
      builder: (context, snapshot) {
        final classes = snapshot.data ?? const <CareClass>[];
        final matches = classes
            .where((item) => item.id == widget.initialCareClass.id)
            .toList();
        final careClass = matches.isEmpty ? null : matches.first;
        final shownClass = careClass ?? widget.initialCareClass;
        // live readings from this roster are attributed to this class
        AlertManager.instance.viewClass(
          shownClass.id,
          shownClass.devices.map((device) => device.deviceId),
        );

        return Scaffold(
          appBar: AppBar(
            title: Text(
              shownClass.name,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w400),
            ),
            actions: [
              IconButton(
                tooltip: 'Edit class',
                icon: const Icon(Icons.edit_outlined),
                onPressed: careClass == null
                    ? null
                    : () => widget.onEditClass(careClass),
              ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (careClass != null)
                ListenableBuilder(
                  listenable: Listenable.merge([
                    AlertManager.instance,
                    LocalStore.instance,
                  ]),
                  builder: (context, _) {
                    final entry = _bannerAlert(careClass);
                    if (entry == null) return const SizedBox.shrink();
                    final device = careClass.devices
                        .firstWhere((d) => d.deviceId == entry.deviceId);
                    return AlertBanner(
                      entry: entry,
                      studentName: device.name,
                      onOpen: () {
                        setState(() => _dismissed = entry);
                        widget.onStudentTap(careClass, device);
                      },
                      onDismiss: () => setState(() => _dismissed = entry),
                    );
                  },
                ),
              Expanded(
                child: Builder(
                  builder: (context) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (careClass == null) {
                      return const AppPage(
                        child: AppCard(
                          child: Text(
                            'This class was deleted.',
                            style: TextStyle(color: appMuted),
                          ),
                        ),
                      );
                    }
                    return ListenableBuilder(
                      listenable: Listenable.merge([
                        AlertManager.instance,
                        WatchBleService.instance,
                        LocalStore.instance,
                      ]),
                      builder: (context, _) => _body(careClass, classes),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _body(CareClass careClass, List<CareClass> classes) {
    final ble = WatchBleService.instance;
    final lives = {
      for (final d in careClass.devices)
        d.deviceId: studentLive(careClass.id, d.deviceId),
    };
    int count(FidgetLabel label) => lives.values
        .where((l) => l.kind == LiveKind.live && l.label == label)
        .length;
    final connected = lives.values
        .where((l) =>
            (l.watch?.isConnected ?? false) || l.kind == LiveKind.live)
        .length;

    // watches nearby that are in none of the teacher's classes
    final assigned = {
      for (final c in classes)
        for (final d in c.devices) d.deviceId,
    };
    final unassigned = ble.watches
        .where((w) =>
            !assigned.contains(w.id) && (w.isConnected || w.isNearby))
        .toList();

    final quiet = careClass.devices
        .where((d) => AlertManager.instance.isQuiet(careClass.id, d.deviceId))
        .toList();

    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ClassHeaderCard(
            careClass: careClass,
            connected: connected,
            onOpenAlerts: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AlertsScreen(careClass: careClass),
              ),
            ),
            onToggleSession: () => _toggleSession(careClass),
          ),
          const SizedBox(height: 22),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 14,
            runSpacing: 4,
            children: [
              const Text(
                'Watches',
                style: TextStyle(
                  color: appInk,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              _CountDot(
                color: appTeal,
                text: '${count(FidgetLabel.notFidgeting)} calm',
              ),
              _CountDot(
                color: appGold,
                text: '${count(FidgetLabel.lowFidgeting)} low',
              ),
              _CountDot(
                color: appRed,
                text: '${count(FidgetLabel.highFidgeting)} high',
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final device in quiet) ...[
            _QuietBanner(
              careClass: careClass,
              device: device,
              onView: () => widget.onStudentTap(careClass, device),
            ),
            const SizedBox(height: 12),
          ],
          if (careClass.devices.isEmpty)
            const AppCard(
              child: Text(
                'No students in this class yet. Tap the edit button to add '
                'watches.',
                style: TextStyle(color: appMuted, fontWeight: FontWeight.w700),
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 760 ? 2 : 1;
              const gap = 12.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final device in careClass.devices)
                    SizedBox(
                      width: width,
                      child: _StudentTile(
                        classId: careClass.id,
                        device: device,
                        live: lives[device.deviceId]!,
                        onTap: () => widget.onStudentTap(careClass, device),
                        onConnect: _connect,
                        onRename: () => showEditStudentNameDialog(
                          context: context,
                          classService: widget.classService,
                          careClass: careClass,
                          classDevice: device,
                          showSnackBar: _showSnackBar,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          for (final watch in unassigned) ...[
            const SizedBox(height: 12),
            _UnassignedWatchCard(
              watch: watch,
              className: careClass.name,
              onAssign: () => _assign(careClass, watch.id),
            ),
          ],
        ],
      ),
    );
  }
}

class _ClassHeaderCard extends StatelessWidget {
  const _ClassHeaderCard({
    required this.careClass,
    required this.connected,
    required this.onOpenAlerts,
    required this.onToggleSession,
  });

  final CareClass careClass;
  final int connected;
  final VoidCallback onOpenAlerts;
  final VoidCallback onToggleSession;

  @override
  Widget build(BuildContext context) {
    final store = LocalStore.instance;
    final running = store.isClassSessionRunning(careClass.id);
    final startedAt = store.classSessionStartedAt(careClass.id);
    final alerts = AlertManager.instance.alertCountFor(careClass.id);
    final total = careClass.devices.length;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.school_outlined, color: careClass.color, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      careClass.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: appInk,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '$connected of $total '
                      '${total == 1 ? 'watch' : 'watches'} connected',
                      style: const TextStyle(color: appMuted, fontSize: 15),
                    ),
                  ],
                ),
              ),
              _AlertBell(count: alerts, onTap: onOpenAlerts),
            ],
          ),
          const SizedBox(height: 14),
          Material(
            color: appSoftGray,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: appBorder),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onToggleSession,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      running ? Icons.stop_outlined : Icons.play_arrow_rounded,
                      color: running ? appRed : appIndigo,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        running ? 'End session' : 'Start session',
                        style: const TextStyle(
                          color: appInk,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      running && startedAt != null
                          ? 'Running ${_running(startedAt)}'
                          : 'Not recording',
                      style: const TextStyle(
                        color: appMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _running(DateTime since) {
    final d = DateTime.now().difference(since);
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    if (d.inHours < 1) return '${d.inMinutes} min';
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }
}

class _AlertBell extends StatelessWidget {
  const _AlertBell({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Alerts',
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Badge(
          isLabelVisible: count > 0,
          backgroundColor: appRed,
          offset: const Offset(2, -2),
          label: Text('$count'),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: appRed.withValues(alpha: 0.10),
            ),
            child: const Icon(Icons.notifications_none, color: appRed),
          ),
        ),
      ),
    );
  }
}

class _CountDot extends StatelessWidget {
  const _CountDot({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(color: appInk, fontSize: 16)),
      ],
    );
  }
}

class _StudentTile extends StatelessWidget {
  const _StudentTile({
    required this.classId,
    required this.device,
    required this.live,
    required this.onTap,
    required this.onConnect,
    required this.onRename,
  });

  final String classId;
  final ClassDevice device;
  final StudentLive live;
  final VoidCallback onTap;
  final ValueChanged<WovenWatch> onConnect;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final tint = stateTint(live);
    final isLive = live.kind == LiveKind.live;
    final color = isLive ? labelColor(live.label) : appMuted;
    final watch = live.watch;

    final String stateText = switch (live.kind) {
      LiveKind.live => labelName(live.label),
      LiveKind.signalLost => 'Signal lost',
      LiveKind.waiting => 'Waiting for data',
      LiveKind.offline => 'Not connected',
    };

    Widget? action;
    if ((live.kind == LiveKind.signalLost || live.kind == LiveKind.offline) &&
        watch != null &&
        !watch.isConnected) {
      action = OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: appBlue,
          side: const BorderSide(color: appBorder),
          visualDensity: VisualDensity.compact,
        ),
        onPressed: watch.isConnecting ? null : () => onConnect(watch),
        child: Text(
          watch.isConnecting
              ? 'Connecting…'
              : live.kind == LiveKind.signalLost
                  ? 'Reconnect'
                  : 'Connect',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      );
    }

    return Material(
      color: tint.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: tint.border, width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.person_outline, color: color, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            device.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isLive ? appInk : appMuted,
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Edit name',
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          color: appMuted,
                          visualDensity: VisualDensity.compact,
                          onPressed: onRename,
                        ),
                      ],
                    ),
                  ),
                  Text(
                    device.deviceId,
                    style: const TextStyle(
                      color: appMuted,
                      fontSize: 13,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      stateText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: isLive ? 26 : 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  action ??
                      HistoryBars(
                        readings: AlertManager.instance
                            .recentReadings(classId, device.deviceId),
                      ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(child: _footnote()),
                  if (isLive && live.stateFor != null)
                    Text(
                      live.label == FidgetLabel.notFidgeting
                          ? 'calm ${shortDuration(live.stateFor!)}'
                          : 'active ${shortDuration(live.stateFor!)}',
                      style: const TextStyle(
                        color: appMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footnote() {
    const muted = TextStyle(
      color: appMuted,
      fontSize: 13,
      fontWeight: FontWeight.w900,
    );
    final String text;
    switch (live.kind) {
      case LiveKind.signalLost:
        final last = live.lastReadingAt!;
        text = 'No readings for '
            '${shortDuration(DateTime.now().difference(last))} · last seen '
            '${labelName(live.lastLabel)} at ${clockMinutes(last)} · '
            'alerts paused';
      case LiveKind.waiting:
        text = 'Connected · first reading within '
            '${predictionInterval.inMilliseconds / 1000} s';
      case LiveKind.offline:
        text = live.watch == null
            ? 'Not seen yet · scan on the Devices tab'
            : 'Watch nearby · not connected';
      case LiveKind.live:
        final active = live.activeAlert;
        if (active != null) {
          return Align(
            alignment: Alignment.centerLeft,
            child: AlertedPill(entry: active),
          );
        }
        final last = live.lastAlert;
        text = live.quiet && last != null
            ? 'Quiet · alerts recorded, not shown'
            : last == null
                ? 'No alerts this period'
                : 'Last alert ${agoShort(last.receivedAt)} · '
                    '${last.event.tag.name}';
    }
    return Text(
      text,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: muted,
    );
  }
}

class _QuietBanner extends StatelessWidget {
  const _QuietBanner({
    required this.careClass,
    required this.device,
    required this.onView,
  });

  final CareClass careClass;
  final ClassDevice device;
  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    final recorded =
        AlertManager.instance.logFor(careClass.id, device.deviceId).length;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: appIndigo.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: appIndigo.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.notifications_off_outlined, color: appIndigo),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quiet mode on for ${device.name}',
                  style: const TextStyle(
                    color: appInk,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '$recorded ${recorded == 1 ? 'alert' : 'alerts'} recorded '
                  'this session, none shown',
                  style: const TextStyle(
                    color: appMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: appIndigo,
              side: BorderSide(color: appIndigo.withValues(alpha: 0.35)),
            ),
            onPressed: onView,
            child: const Text(
              'View',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnassignedWatchCard extends StatelessWidget {
  const _UnassignedWatchCard({
    required this.watch,
    required this.className,
    required this.onAssign,
  });

  final WovenWatch watch;
  final String className;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: appBorder, width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.bluetooth, color: appMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  watch.id,
                  style: const TextStyle(
                    color: appInk,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'Nearby · no student in $className',
                  style: const TextStyle(
                    color: appMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: appBlue),
            onPressed: onAssign,
            child: const Text(
              'Assign',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class AlertBanner extends StatelessWidget {
  const AlertBanner({
    super.key,
    required this.entry,
    required this.studentName,
    required this.onOpen,
    required this.onDismiss,
  });

  final AlertLogEntry entry;
  final String studentName;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final high = entry.event.tag == AlertTag.high;
    final color = high ? appRed : appGoldText;
    final what = high ? 'High fidgeting' : 'Low fidgeting';
    final n = entry.event.highs + entry.event.lows;

    return Material(
      color: color,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$studentName · $what',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '${entry.event.isRepeat ? 'Still going' : 'Alert'} · '
                      '$n fidget readings in a row · '
                      '${agoShort(entry.receivedAt)} · tap to view',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
              IconButton(
                tooltip: 'Dismiss',
                onPressed: onDismiss,
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

