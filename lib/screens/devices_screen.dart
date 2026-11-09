import 'package:flutter/material.dart';
import 'package:trackapp/demo/demo_mode.dart';
import 'package:trackapp/models/care_class.dart';
import 'package:trackapp/pages/add_device.dart';
import 'package:trackapp/services/class_service.dart';
import 'package:trackapp/services/local_store.dart';
import 'package:trackapp/services/watch_ble_service.dart';
import 'package:trackapp/theme/app_theme.dart';
import 'package:trackapp/widgets/watch_detail_dialog.dart';
import 'package:trackapp/widgets/watch_roster.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key, this.classService});

  final ClassService? classService;

  @override
  State<DevicesScreen> createState() => DevicesScreenState();
}

class DevicesScreenState extends State<DevicesScreen> {
  final WatchBleService _bleService = WatchBleService.instance;
  late final ClassService _classService = widget.classService ?? ClassService();
  late final Stream<List<CareClass>> _classesStream =
      _classService.watchClasses();

  static DateTime? _lastScanAt;
  final Set<String> _reconnecting = {};

  @override
  void initState() {
    super.initState();
    //only scan when Search again is tapped
    LocalStore.instance.load();
  }

  void navigateToAddDevicesPage() {
    //adding a real watch saves it to an account
    if (DemoMode.isActive) {
      _showSnackBar('Adding a watch needs an account and a real watch.');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const AddDevicePage()),
    );
  }

  void _showSnackBar(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _startScan() async {
    if (DemoMode.isActive) {
      _showSnackBar('Demo watches are always nearby, no scan needed.');
      return;
    }
    setState(() => _lastScanAt = DateTime.now());
    try {
      await _bleService.startScan();
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Bluetooth scan failed: $e');
    }
  }

  Future<void> _reconnect(String id) async {
    if (!_reconnecting.add(id)) return;
    setState(() {});
    try {
      await _bleService.reconnect(id);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(e is StateError ? e.message : 'Could not connect $id: $e');
    } finally {
      _reconnecting.remove(id);
      if (mounted) setState(() {});
    }
  }

  //connected first, then most classes, then name. unassigned last
  static int _order(WatchEntry a, WatchEntry b) {
    int rank(WatchEntry e) => !e.isAssigned ? 2 : (e.isConnected ? 0 : 1);
    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    final byClasses = b.assignments.length.compareTo(a.assignments.length);
    if (byClasses != 0) return byClasses;
    return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CareClass>>(
      stream: _classesStream,
      builder: (context, snapshot) {
        final classes = snapshot.data ?? const <CareClass>[];
        return ListenableBuilder(
          listenable: Listenable.merge([_bleService, LocalStore.instance]),
          builder: (context, _) {
            final roster = buildWatchRoster(classes, _bleService)..sort(_order);
            final assigned = roster.where((e) => e.isAssigned).toList();
            final connected = assigned.where((e) => e.isConnected).length;

            return AppPage(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HeaderCard(
                    connected: connected,
                    total: assigned.length,
                    nearby: _bleService.nearbyCount,
                    lastScanAt: _lastScanAt,
                    isScanning: _bleService.isScanning,
                    onScan: _startScan,
                    onAddWatch: navigateToAddDevicesPage,
                  ),
                  const SizedBox(height: 16),
                  if (roster.isEmpty)
                    AppCard(
                      child: Text(
                        _bleService.isScanning
                            ? 'Scanning for Woven Watches...'
                            : 'No watches yet. Make sure a watch is powered on, '
                                'then tap the refresh button to scan.',
                        style: const TextStyle(
                          color: appMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  for (final entry in roster) ...[
                    if (entry.isAssigned)
                      _WatchCard(
                        entry: entry,
                        reconnecting: _reconnecting.contains(entry.id),
                        onReconnect: () => _reconnect(entry.id),
                        onTap: () => showWatchDetailDialog(
                          context,
                          deviceId: entry.id,
                          assignments: entry.assignments,
                        ),
                      )
                    else
                      _UnassignedCard(
                        entry: entry,
                        onTap: () => showWatchDetailDialog(
                          context,
                          deviceId: entry.id,
                          assignments: entry.assignments,
                        ),
                        onAssign: () => _showAssignSheet(entry.id, classes),
                      ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showAssignSheet(String deviceId, List<CareClass> classes) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (sheetContext) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Assign $deviceId',
                    style: const TextStyle(
                      color: appInk,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Choose a class for this watch.',
                    style: TextStyle(color: appMuted),
                  ),
                  const SizedBox(height: 14),
                  if (classes.isEmpty)
                    const Text(
                      'No classes yet. Create one on the Home tab first.',
                      style: TextStyle(color: appMuted),
                    ),
                  for (final careClass in classes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(sheetContext);
                          try {
                            await _classService.addDeviceToClass(
                              classId: careClass.id,
                              deviceId: deviceId,
                            );
                            if (!mounted) return;
                            _showSnackBar(
                              '$deviceId added to "${careClass.name}".',
                            );
                          } catch (e) {
                            if (!mounted) return;
                            _showSnackBar('Could not assign $deviceId: $e');
                          }
                        },
                        icon: Icon(
                          Icons.school_outlined,
                          color: careClass.color,
                        ),
                        label: Text(careClass.name),
                      ),
                    ),
                ],
              ),
            ),
          ),
    );
  }

}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.connected,
    required this.total,
    required this.nearby,
    required this.lastScanAt,
    required this.isScanning,
    required this.onScan,
    required this.onAddWatch,
  });

  final int connected;
  final int total;
  final int nearby;
  final DateTime? lastScanAt;
  final bool isScanning;
  final VoidCallback onScan;
  final VoidCallback onAddWatch;

  @override
  Widget build(BuildContext context) {
    final scanned =
        isScanning
            ? 'Scanning now'
            : lastScanAt == null
            ? 'Not scanned yet'
            : 'Last scan ${formatAgo(lastScanAt).toLowerCase()}';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const AppLogo(size: 46, showName: false),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Woven Watch',
                      style: TextStyle(
                        color: appInk,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      '$connected of $total connected',
                      style: const TextStyle(
                        color: appMuted,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  side: const BorderSide(color: appBorder),
                  foregroundColor: appBlue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: isScanning ? null : onScan,
                child:
                    isScanning
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                        : const Tooltip(
                          message: 'Search again',
                          child: Icon(Icons.refresh),
                        ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$scanned · $nearby nearby · scans only on demand',
            style: const TextStyle(
              color: appMuted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: onAddWatch,
            icon: const Icon(Icons.add),
            label: const Text(
              'Add Watch',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalLine extends StatelessWidget {
  const _SignalLine({required this.entry});

  final WatchEntry entry;

  @override
  Widget build(BuildContext context) {
    final watch = entry.watch;
    final inRange = watch != null && (watch.isConnected || watch.isNearby);
    // in range the bars say enough; out of range, say when it was seen
    final words =
        inRange
            ? null
            : watch?.lastSeen == null
            ? 'not seen yet'
            : 'seen ${formatAgo(watch!.lastSeen).toLowerCase()}';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SignalBars(level: inRange ? watch.signalBars : 0),
        if (words != null) ...[
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              words,
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
      ],
    );
  }
}

//tap to reconnect when not connected
class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.watch,
    this.reconnecting = false,
    this.onReconnect,
  });

  final WovenWatch? watch;
  final bool reconnecting;
  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context) {
    final connected = watch?.isConnected ?? false;
    final connecting = reconnecting || (watch?.isConnecting ?? false);
    final nearby = !connected && (watch?.isNearby ?? false);
    final (String label, Color bg, Color fg) =
        connected
            ? ('Connected', appTeal.withValues(alpha: 0.14), appTealText)
            : connecting
            ? ('Connecting…', appIndigo.withValues(alpha: 0.10), appIndigo)
            : nearby
            ? ('Nearby', appGold.withValues(alpha: 0.16), appGoldText)
            : ('Disconnected', appBorder, appMuted);
    final tappable = !connected && !connecting && onReconnect != null;

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (tappable) ...[
            Icon(Icons.refresh, size: 15, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
    if (!tappable) return chip;
    return Tooltip(
      message: 'Reconnect',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onReconnect,
        child: chip,
      ),
    );
  }
}

class _WatchCard extends StatelessWidget {
  const _WatchCard({
    required this.entry,
    required this.onTap,
    required this.reconnecting,
    required this.onReconnect,
  });

  final WatchEntry entry;
  final VoidCallback onTap;
  final bool reconnecting;
  final VoidCallback onReconnect;

  @override
  Widget build(BuildContext context) {
    final connected = entry.isConnected;
    final count = entry.assignments.length;

    return AppCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Icon(
                    connected ? Icons.bluetooth : Icons.bluetooth_disabled,
                    color: connected ? appTeal : appMuted,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            entry.id,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: connected ? appInk : appMuted,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(child: _SignalLine(entry: entry)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _StatusChip(
                  watch: entry.watch,
                  reconnecting: reconnecting,
                  onReconnect: onReconnect,
                ),
              ],
            ),
            const Divider(height: 24, color: appBorder),
            if (count > 1) ...[
              Text(
                'ASSIGNED IN $count CLASSES',
                style: const TextStyle(
                  color: appMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 6),
            ],
            for (final pair in entry.assignments)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    const Icon(
                      Icons.school_outlined,
                      size: 16,
                      color: appMuted,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text.rich(
                        TextSpan(
                          text: pair.careClass.name,
                          style: const TextStyle(color: appInk),
                          children: [
                            if (pair.student.studentName case final name?)
                              TextSpan(
                                text: '  —  $name',
                                style: const TextStyle(color: appMuted),
                              ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UnassignedCard extends StatelessWidget {
  const _UnassignedCard({
    required this.entry,
    required this.onTap,
    required this.onAssign,
  });

  final WatchEntry entry;
  final VoidCallback onTap;
  final VoidCallback onAssign;

  @override
  Widget build(BuildContext context) {
    final watch = entry.watch;
    return DashedBorder(
      color: appMuted.withValues(alpha: 0.5),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.bluetooth, color: appMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: appInk,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        SignalBars(level: watch?.signalBars ?? 0),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Not in any of your classes',
                            style: const TextStyle(
                              color: appMuted,
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: appBlue,
                  side: const BorderSide(color: appBorder, width: 1.5),
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: onAssign,
                child: const Text(
                  'Assign',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
