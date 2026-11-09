import 'package:flutter/material.dart';
import 'package:trackapp/models/care_class.dart';
import 'package:trackapp/services/class_service.dart';
import 'package:trackapp/services/watch_ble_service.dart';
import 'package:trackapp/theme/app_theme.dart';

class AddDevicePage extends StatefulWidget {
  const AddDevicePage({super.key});

  @override
  State<AddDevicePage> createState() => AddDevicePageState();
}

class AddDevicePageState extends State<AddDevicePage> {
  final WatchBleService _bleService = WatchBleService.instance;
  final ClassService _classService = ClassService();
  late final Stream<List<CareClass>> _classesStream = _classService.watchClasses();

  @override
  void initState() {
    super.initState();
    searchAgain();
  }

  Future<void> searchAgain() async {
    try {
      await _bleService.startScan();
    } catch (e) {
      if (!mounted) return;
      showSnackBar('Bluetooth scan failed: $e');
    }
  }

  void showSnackBar(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> connectWatch(WovenWatch watch) async {
    try {
      await _bleService.connect(watch);
    } catch (e) {
      if (!mounted) return;
      showSnackBar('Could not connect to ${watch.id}: $e');
      return;
    }
    if (!mounted) return;
    showAssignSheet(watch);
  }

  void showAssignSheet(WovenWatch watch) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Connected to ${watch.id}",
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                        color: appInk,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                const Text(
                  "Add this watch to a class, or save it for later.",
                  style: TextStyle(color: appMuted),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    showClassPickerSheet(watch);
                  },
                  icon: const Icon(Icons.school_outlined),
                  label: const Text("Assign to a class"),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    Navigator.pop(context); //back to the Devices tab
                  },
                  icon: const Icon(Icons.bookmark_added_outlined),
                  label: const Text("Save Unassigned"),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void showClassPickerSheet(WovenWatch watch) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: StreamBuilder<List<CareClass>>(
              stream: _classesStream,
              builder: (sheetContext, snapshot) {
                final classes = snapshot.data ?? [];

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      "Assign ${watch.id}",
                      style: Theme.of(sheetContext)
                          .textTheme
                          .titleMedium
                          ?.copyWith(
                            color: appInk,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "Choose a class for this watch.",
                      style: TextStyle(color: appMuted),
                    ),
                    const SizedBox(height: 14),
                    if (!snapshot.hasData)
                      const Center(child: CircularProgressIndicator())
                    else if (classes.isEmpty)
                      const Text(
                        "No classes yet. Create one on the Home tab first.",
                        style: TextStyle(color: appMuted),
                      )
                    else
                      ...classes.map(
                        (careClass) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                assignToClass(sheetContext, watch, careClass),
                            icon: Icon(Icons.school_outlined,
                                color: careClass.color),
                            label: Text(careClass.name),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> assignToClass(
    BuildContext sheetContext,
    WovenWatch watch,
    CareClass careClass,
  ) async {
    try {
      await _classService.addDeviceToClass(
        classId: careClass.id,
        deviceId: watch.id,
      );
    } catch (e) {
      if (!mounted) return;
      showSnackBar('Could not assign ${watch.id}: $e');
      return;
    }
    if (!mounted) return;
    showSnackBar('${watch.id} added to "${careClass.name}".');
    if (sheetContext.mounted) Navigator.pop(sheetContext);
    Navigator.pop(context); //back to the Devices tab
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Add Watch")),
      body: ListenableBuilder(
        listenable: _bleService,
        builder: (context, _) {
          // candidates = watches seen in a scan that aren't connected yet
          final candidates = _bleService.watches
              .where((watch) => !watch.isConnected)
              .toList();

          return AppPage(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppCard(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _bleService.isScanning
                                  ? "Scanning for watches..."
                                  : "Ready to scan for watches",
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    color: appInk,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              "${candidates.length} wwWatch devices nearby",
                              style: const TextStyle(
                                color: appMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      IconButton.filled(
                        tooltip:
                            _bleService.isScanning ? "Searching" : "Search again",
                        onPressed: _bleService.isScanning ? null : searchAgain,
                        icon: _bleService.isScanning
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.4,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                if (candidates.isEmpty && !_bleService.isScanning)
                  const AppCard(
                    child: Text(
                      "No watches found. Make sure the watch is powered on and its light is blue (advertising), then search again.",
                      style: TextStyle(color: appMuted),
                    ),
                  ),
                ...candidates.map(
                  (watch) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _DetectedWatchTile(
                      watch: watch,
                      onConnect: () => connectWatch(watch),
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

class _DetectedWatchTile extends StatelessWidget {
  const _DetectedWatchTile({
    required this.watch,
    required this.onConnect,
  });

  final WovenWatch watch;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  watch.id,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: appInk,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  watch.rssi != null ? "${watch.rssi} dBm" : "",
                  style: const TextStyle(color: appMuted, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _SignalBars(level: watch.signalBars),
                    const SizedBox(width: 8),
                    Text(
                      watch.proximity,
                      style: const TextStyle(
                        color: appBlue,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.tonal(
            onPressed: watch.isConnecting ? null : onConnect,
            child: Text(watch.isConnecting ? "Connecting..." : "Connect"),
          ),
        ],
      ),
    );
  }
}

class _SignalBars extends StatelessWidget {
  const _SignalBars({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (index) {
        final isActive = index < level;
        return Container(
          width: 4,
          height: 8.0 + (index * 4),
          margin: const EdgeInsets.only(right: 3),
          decoration: BoxDecoration(
            color: isActive ? appTeal : appBorder,
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );
  }
}
