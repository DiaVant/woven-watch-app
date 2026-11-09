import 'package:flutter/material.dart';
import 'package:trackapp/services/local_store.dart';
import 'package:trackapp/services/watch_ble_service.dart';
import 'package:trackapp/theme/app_theme.dart';
import 'package:trackapp/widgets/watch_roster.dart';

Future<void> showWatchDetailDialog(
  BuildContext context, {
  required String deviceId,
  required List<WatchAssignment> assignments,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => ListenableBuilder(
      listenable: Listenable.merge([
        WatchBleService.instance,
        LocalStore.instance,
      ]),
      builder: (dialogContext, _) => _WatchDetail(
        deviceId: deviceId,
        assignments: assignments,
        onError: (message) =>
            messenger?.showSnackBar(SnackBar(content: Text(message))),
      ),
    ),
  );
}

class _WatchDetail extends StatelessWidget {
  const _WatchDetail({
    required this.deviceId,
    required this.assignments,
    required this.onError,
  });

  final String deviceId;
  final List<WatchAssignment> assignments;
  final ValueChanged<String> onError;

  Future<void> _toggle(WovenWatch watch) async {
    final ble = WatchBleService.instance;
    try {
      if (watch.isConnected) {
        await ble.disconnect(watch);
      } else {
        await ble.connect(watch);
      }
    } catch (e) {
      onError('${watch.id}: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final watch = WatchBleService.instance.watchById(deviceId);
    final connected = watch?.isConnected ?? false;
    final count = assignments.length;

    final (IconData activityIcon, Color activityColor) =
        switch (connected ? watch!.prediction : null) {
      'not_fidgeting' => (Icons.sentiment_satisfied_alt, appTeal),
      'low_fidgeting' => (Icons.vibration, appGold),
      'high_fidgeting' => (Icons.vibration, appRed),
      _ => (Icons.sensors_off_outlined, appMuted),
    };

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Icon(
                    connected ? Icons.bluetooth : Icons.bluetooth_disabled,
                    color: connected ? appTeal : appMuted,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        deviceId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: appInk,
                          fontSize: 23,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: SignalBars(
                    level: watch != null && (connected || watch.isNearby)
                        ? watch.signalBars
                        : 0,
                  ),
                ),
              ],
            ),
            const Divider(height: 24, thickness: 2, color: appBorder),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Last seen',
                    style: TextStyle(
                      color: appMuted,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  watch?.lastSeen == null
                      ? 'Not seen yet'
                      : formatAgo(watch!.lastSeen),
                  style: const TextStyle(
                    color: appInk,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: appIndigo.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: appIndigo.withValues(alpha: 0.30)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    count == 0
                        ? 'NOT IN ANY OF YOUR CLASSES'
                        : 'WORN BY $count ${count == 1 ? 'STUDENT' : 'STUDENTS'}',
                    style: const TextStyle(
                      color: appIndigo,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                  for (final pair in assignments)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.school_outlined,
                            size: 16,
                            color: appMuted,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              pair.student.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: appInk,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                pair.careClass.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: appMuted,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (count > 1) ...[
                    const SizedBox(height: 10),
                    const Text(
                      'A cart watch can be assigned in more than one class. '
                      'Readings are attributed to whichever class you have '
                      'open.',
                      style: TextStyle(
                        color: appMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            _InfoCard(
              icon: activityIcon,
              color: activityColor,
              label: 'Activity',
              value: connected ? predictionLabel(watch!.prediction) : 'Not connected',
            ),
            const SizedBox(height: 12),
            _InfoCard(
              icon: Icons.schedule,
              color: appGold,
              label: 'Fidgeting time',
              value: connected ? formatDuration(watch!.fidgetingTime) : '—',
            ),
            const SizedBox(height: 16),
            // wraps instead of overflowing with large text
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 12,
              overflowAlignment: OverflowBarAlignment.end,
              children: [
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: appMuted),
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    'Close',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                ),
                if (watch != null)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: connected ? appRed : appIndigo,
                      minimumSize: const Size(0, 48),
                    ),
                    onPressed: watch.isConnecting ? null : () => _toggle(watch),
                    icon: Icon(
                      connected ? Icons.bluetooth_disabled : Icons.bluetooth,
                    ),
                    label: Text(
                      watch.isConnecting
                          ? 'Connecting…'
                          : connected
                              ? 'Disconnect'
                              : 'Connect',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: appBorder, width: 1.5),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: appMuted,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: appInk,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
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
