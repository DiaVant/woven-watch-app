import 'package:flutter/material.dart';
import 'package:trackapp/models/care_class.dart';
import 'package:trackapp/screens/home/class_dialogs.dart';
import 'package:trackapp/screens/home/class_page.dart';
import 'package:trackapp/screens/home/class_tile.dart';
import 'package:trackapp/screens/student_detail_screen.dart';
import 'package:trackapp/services/class_service.dart';
import 'package:trackapp/services/local_store.dart';
import 'package:trackapp/services/watch_ble_service.dart';
import 'package:trackapp/theme/app_theme.dart';
import 'package:trackapp/widgets/watch_detail_dialog.dart';
import 'package:trackapp/widgets/watch_roster.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.classService, this.openClass});

  final ClassService? classService;

  //opened on top right away (the demo starts in its class)
  final CareClass? openClass;

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  late final ClassService _classService = widget.classService ?? ClassService();
  final WatchBleService _bleService = WatchBleService.instance;

  //subscribe once here, not in build(), or it resubscribes every rebuild
  late final Stream<List<CareClass>> _classesStream = _classService.watchClasses();

  void showSnackBar(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> openClassDialog({CareClass? careClass}) {
    return showClassDialog(
      context: context,
      classService: _classService,
      showSnackBar: showSnackBar,
      careClass: careClass,
    );
  }

  Future<void> confirmDeleteClass(CareClass careClass) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete class?'),
          content: Text('Remove "${careClass.name}" from your classes?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;

    try {
      await _classService.deleteClass(careClass.id);
    } catch (e) {
      showSnackBar(e.toString());
    }
  }

  void openClassPage(CareClass careClass) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) {
          return ClassPage(
            initialCareClass: careClass,
            classService: _classService,
            onEditClass: (latestClass) =>
                openClassDialog(careClass: latestClass),
            onStudentTap: (latestClass, classDevice) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StudentDetailScreen(
                    careClass: latestClass,
                    student: classDevice,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    LocalStore.instance.load(); //list open/closed state
    if (widget.openClass case final careClass?) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) openClassPage(careClass);
      });
    }
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
            // assigned watches, plus any connected one that isn't (yet)
            final roster = buildWatchRoster(classes, _bleService)
                .where((entry) => entry.isAssigned || entry.isConnected)
                .toList()
              ..sort((a, b) => (b.isConnected ? 1 : 0) - (a.isConnected ? 1 : 0));

            return AppPage(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DeviceListCard(
                    roster: roster,
                    onOpenWatch: (entry) => showWatchDetailDialog(
                      context,
                      deviceId: entry.id,
                      assignments: entry.assignments,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Classes',
                          style: TextStyle(
                            color: appBlue,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton.filled(
                        tooltip: 'Create class',
                        iconSize: 28,
                        style: IconButton.styleFrom(
                          minimumSize: const Size(52, 52),
                        ),
                        icon: const Icon(Icons.add),
                        onPressed: () => openClassDialog(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _ClassList(
                    snapshot: snapshot,
                    ble: _bleService,
                    onOpenClass: openClassPage,
                    onEditClass: (careClass) =>
                        openClassDialog(careClass: careClass),
                    onDeleteClass: confirmDeleteClass,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

}

class _DeviceListCard extends StatelessWidget {
  const _DeviceListCard({required this.roster, required this.onOpenWatch});

  final List<WatchEntry> roster;
  final ValueChanged<WatchEntry> onOpenWatch;

  @override
  Widget build(BuildContext context) {
    final store = LocalStore.instance;
    final expanded = store.devicesListExpanded ?? false;
    final connected = roster.where((entry) => entry.isConnected).length;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => store.devicesListExpanded = !expanded,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Devices list',
                      style: TextStyle(
                        color: appBlue,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    '$connected/${roster.length} connected',
                    style: const TextStyle(
                      color: appMuted,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    color: appBlue,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 12),
            if (roster.isEmpty)
              const Text(
                'No watches yet. Add one on the Devices tab.',
                style: TextStyle(color: appMuted, fontWeight: FontWeight.w700),
              ),
            for (final entry in roster) ...[
              _HomeWatchRow(
                entry: entry,
                onTap: () => onOpenWatch(entry),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }
}

class _HomeWatchRow extends StatelessWidget {
  const _HomeWatchRow({required this.entry, required this.onTap});

  final WatchEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final watch = entry.watch;
    final prediction = entry.isConnected ? watch!.prediction : null;
    final (Color? tint, Color text) = switch (prediction) {
      'high_fidgeting' => (appRed, appRed),
      'low_fidgeting' => (appGold, appGoldText),
      'not_fidgeting' => (appTeal, appTealText),
      _ => (null, appMuted),
    };
    final stateText = !entry.isConnected
        ? (watch?.status ?? 'Disconnected')
        : predictionLabel(prediction);
    final first = entry.assignments.isEmpty ? null : entry.assignments.first;
    final more = entry.assignments.length - 1;

    return Material(
      color: tint?.withValues(alpha: tint == appGold ? 0.10 : 0.07) ??
          Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: tint?.withValues(alpha: 0.35) ?? appBorder,
          width: 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          child: Row(
            children: [
              Icon(
                entry.isConnected ? Icons.bluetooth : Icons.bluetooth_disabled,
                color: entry.isConnected ? text : appMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: entry.isConnected ? appInk : appMuted,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    DefaultTextStyle.merge(
                      style: const TextStyle(
                        color: appMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              first == null
                                  ? 'Not in any class'
                                  : first.student.studentName == null
                                      ? first.careClass.name
                                      : '${first.careClass.name} · '
                                          '${first.student.studentName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          //don't cut off the count
                          if (more > 0) Text('  +$more more'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    stateText,
                    style: TextStyle(
                      color: text,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (entry.isConnected && watch!.predictionAt != null)
                    Text(
                      formatAgo(watch.predictionAt),
                      style: const TextStyle(
                        color: appMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Icon(Icons.circle, size: 10, color: tint ?? appMuted),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClassList extends StatelessWidget {
  const _ClassList({
    required this.snapshot,
    required this.ble,
    required this.onOpenClass,
    required this.onEditClass,
    required this.onDeleteClass,
  });

  final AsyncSnapshot<List<CareClass>> snapshot;
  final WatchBleService ble;
  final ValueChanged<CareClass> onOpenClass;
  final ValueChanged<CareClass> onEditClass;
  final ValueChanged<CareClass> onDeleteClass;

  @override
  Widget build(BuildContext context) {
    if (snapshot.hasError) {
      return AppCard(child: Text('Error: ${snapshot.error}'));
    }
    if (!snapshot.hasData) {
      return const Center(child: CircularProgressIndicator());
    }
    final classes = snapshot.data!;
    if (classes.isEmpty) {
      return const AppCard(
        child: Text(
          'No classes yet. Tap + to create your first class.',
          style: TextStyle(color: appMuted, fontWeight: FontWeight.w700),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 600
                ? 2
                : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: classes.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            mainAxisExtent: 124,
          ),
          itemBuilder: (context, index) {
            final careClass = classes[index];
            return ClassTile(
              careClass: careClass,
              connectedCount: careClass.devices
                  .where((d) => ble.watchById(d.deviceId)?.isConnected ?? false)
                  .length,
              onOpen: () => onOpenClass(careClass),
              onEdit: () => onEditClass(careClass),
              onDelete: () => onDeleteClass(careClass),
            );
          },
        );
      },
    );
  }
}
