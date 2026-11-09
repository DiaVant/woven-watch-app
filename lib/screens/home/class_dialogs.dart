import 'package:flutter/material.dart';
import 'package:trackapp/models/care_class.dart';
import 'package:trackapp/services/class_service.dart';
import 'package:trackapp/services/watch_ble_service.dart';
import 'package:trackapp/theme/app_theme.dart';
import 'package:trackapp/widgets/text_prompt_dialog.dart';

const classColorOptions = [
  '#705FD9',
  '#245CA6',
  '#21BFAF',
  '#F2B33D',
];

Color colorFromHex(String colorHex) {
  final hex = colorHex.replaceFirst('#', '');
  return Color(int.parse('FF$hex', radix: 16));
}

Future<void> showClassDialog({
  required BuildContext context,
  required ClassService classService,
  required void Function(String message) showSnackBar,
  CareClass? careClass,
}) async {
  final nameController = TextEditingController(text: careClass?.name ?? '');
  String selectedColor = careClass?.colorHex ?? classColorOptions.first;
  final selectedDeviceIds =
      careClass?.devices.map((device) => device.deviceId).toSet() ?? <String>{};
  final existingNames = {
    for (final device in careClass?.devices ?? <ClassDevice>[])
      if (device.studentName case final name?) device.deviceId: name,
  };

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> openDevicePicker() async {
            final pickedDeviceIds = await showDevicePicker(
              context: dialogContext,
              initialSelection: selectedDeviceIds,
            );
            if (pickedDeviceIds == null) return;
            setDialogState(() {
              selectedDeviceIds
                ..clear()
                ..addAll(pickedDeviceIds);
            });
          }

          return AlertDialog(
            title: Text(careClass == null ? 'Create class' : 'Edit your class'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Name input',
                      hintText: 'Class name',
                      prefixIcon: Icon(Icons.school),
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Color choose',
                    style: TextStyle(
                      color: appInk,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    children: classColorOptions.map((colorHex) {
                      final isSelected = selectedColor == colorHex;
                      return InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () {
                          setDialogState(() {
                            selectedColor = colorHex;
                          });
                        },
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: colorFromHex(colorHex),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? appInk : Colors.white,
                              width: isSelected ? 3 : 2,
                            ),
                          ),
                          child: isSelected
                              ? const Icon(Icons.check, color: Colors.white)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Devices in class',
                          style: TextStyle(
                            color: appInk,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton.outlined(
                        tooltip: 'Select devices',
                        icon: const Icon(Icons.add),
                        onPressed: openDevicePicker,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (selectedDeviceIds.isEmpty)
                    const Text(
                      'No devices selected',
                      style: TextStyle(color: appMuted),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: selectedDeviceIds.map((deviceId) {
                        return InputChip(
                          label: Text(deviceId),
                          avatar: const Icon(Icons.watch, size: 18),
                          onDeleted: () {
                            setDialogState(() {
                              selectedDeviceIds.remove(deviceId);
                            });
                          },
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  final name = nameController.text.trim();
                  if (name.isEmpty) {
                    showSnackBar('Please enter a class name.');
                    return;
                  }

                  try {
                    final deviceIds = selectedDeviceIds.toList()..sort();
                    if (careClass == null) {
                      await classService.createClass(
                        name: name,
                        colorHex: selectedColor,
                        deviceIds: deviceIds,
                      );
                    } else {
                      await classService.updateClass(
                        classId: careClass.id,
                        name: name,
                        colorHex: selectedColor,
                        deviceIds: deviceIds,
                        existingStudentNames: existingNames,
                        previousDeviceIds: existingNames.keys,
                      );
                    }

                    if (!dialogContext.mounted) return;
                    Navigator.pop(dialogContext);
                  } catch (e) {
                    showSnackBar(e.toString());
                  }
                },
                child: Text(careClass == null ? 'Create' : 'Save'),
              ),
            ],
          );
        },
      );
    },
  );

  nameController.dispose();
}

//also lists offline watches already in the class so they can be removed
Future<Set<String>?> showDevicePicker({
  required BuildContext context,
  required Set<String> initialSelection,
}) async {
  final bleService = WatchBleService.instance;
  final selected = {...initialSelection};

  // fill the list in live if a scan is still running
  bleService.startScan().catchError((_) {});

  return showDialog<Set<String>>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return ListenableBuilder(
            listenable: bleService,
            builder: (context, _) {
              final deviceIds = <String>{
                ...bleService.watches.map((watch) => watch.id),
                ...initialSelection,
              }.toList()
                ..sort();
              final allSelected = selected.length == deviceIds.length;

              return AlertDialog(
                title: Row(
                  children: [
                    const Expanded(child: Text('Select devices')),
                    TextButton(
                      onPressed: deviceIds.isEmpty
                          ? null
                          : () {
                              setDialogState(() {
                                if (allSelected) {
                                  selected.clear();
                                } else {
                                  selected
                                    ..clear()
                                    ..addAll(deviceIds);
                                }
                              });
                            },
                      child: Text(allSelected ? 'Clear all' : 'Select all'),
                    ),
                  ],
                ),
                content: deviceIds.isEmpty
                    ? Text(
                        bleService.isScanning
                            ? 'Scanning for watches...'
                            : 'No watches found. Power on a watch and scan from the Devices tab.',
                        style: const TextStyle(color: appMuted),
                      )
                    : Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: deviceIds.map((deviceId) {
                          final isSelected = selected.contains(deviceId);
                          final watch = bleService.watchById(deviceId);
                          return FilterChip(
                            label: Text(deviceId),
                            selected: isSelected,
                            avatar: Icon(
                              watch != null && watch.isConnected
                                  ? Icons.bluetooth_connected
                                  : Icons.watch,
                              color: isSelected ? appTeal : appMuted,
                            ),
                            onSelected: (value) {
                              setDialogState(() {
                                if (value) {
                                  selected.add(deviceId);
                                } else {
                                  selected.remove(deviceId);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context, selected),
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
                  ),
                ],
              );
            },
          );
        },
      );
    },
  );
}

Future<void> showEditStudentNameDialog({
  required BuildContext context,
  required ClassService classService,
  required CareClass careClass,
  required ClassDevice classDevice,
  required void Function(String message) showSnackBar,
}) async {
  //empty clears the name and the BLE id shows again
  final studentName = await showTextPrompt(
    context,
    title: 'Name for ${classDevice.deviceId}',
    initial: classDevice.studentName ?? '',
    hint: 'Student name',
    helper: 'Leave empty to show the watch id',
    capitalization: TextCapitalization.words,
  );
  if (studentName == null) return;
  try {
    await classService.updateStudentName(
      classId: careClass.id,
      deviceId: classDevice.deviceId,
      studentName: studentName,
    );
  } catch (e) {
    showSnackBar(e.toString());
  }
}

Future<void> showStudentDetails({
  required BuildContext context,
  required ClassService classService,
  required CareClass careClass,
  required ClassDevice classDevice,
  required void Function(String message) showSnackBar,
}) async {
  final parentContext = context;
  final bleService = WatchBleService.instance;
  bool showTechnicalStats = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          // live BLE state for this student's watch (null if never seen)
          return ListenableBuilder(
            listenable: bleService,
            builder: (dialogContext, _) {
              final watch = bleService.watchById(classDevice.deviceId);
              final isConnected = watch?.isConnected ?? false;

              return AlertDialog(
                title: Row(
                  children: [
                    Expanded(child: Text(classDevice.name)),
                    IconButton(
                      tooltip: 'Edit student name',
                      icon: const Icon(Icons.edit),
                      onPressed: () {
                        Navigator.pop(dialogContext);
                        showEditStudentNameDialog(
                          context: parentContext,
                          classService: classService,
                          careClass: careClass,
                          classDevice: classDevice,
                          showSnackBar: showSnackBar,
                        );
                      },
                    ),
                  ],
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (isConnected) ...[
                        _StudentMetricCard(
                          title: 'Status',
                          value: predictionLabel(watch!.prediction),
                          icon: Icons.psychology_alt_outlined,
                          color: predictionColor(watch.prediction),
                        ),
                        const SizedBox(height: 12),
                        _StudentMetricCard(
                          title: 'Fidgeting time',
                          value: formatDuration(watch.fidgetingTime),
                          icon: Icons.directions_walk,
                          color: appIndigo,
                        ),
                        const SizedBox(height: 12),
                        _StudentMetricCard(
                          title: 'Last update',
                          value: formatAgo(watch.predictionAt),
                          icon: Icons.update,
                          color: appBlue,
                        ),
                      ] else
                        const _StudentMetricCard(
                          title: 'Watch offline',
                          value:
                              'Connect this student\'s watch on the Devices tab to see live activity.',
                          icon: Icons.bluetooth_disabled,
                          color: appGold,
                        ),
                      const SizedBox(height: 12),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          setDialogState(() {
                            showTechnicalStats = !showTechnicalStats;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Technical Stats',
                                  style: TextStyle(
                                    color: appInk,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              Icon(
                                showTechnicalStats
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                color: appMuted,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (showTechnicalStats) ...[
                        const SizedBox(height: 4),
                        _StudentStatRow(
                          label: 'Device ID',
                          value: classDevice.deviceId,
                        ),
                        _StudentStatRow(label: 'Class', value: careClass.name),
                        _StudentStatRow(
                          label: 'Connection',
                          value: watch?.status ?? 'Never seen',
                        ),
                        _StudentStatRow(
                          label: 'Signal',
                          value: watch?.rssi != null
                              ? '${watch!.rssi} dBm'
                              : '—',
                        ),
                        _StudentStatRow(
                          label: 'Last seen',
                          value: formatAgo(watch?.lastSeen),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    },
  );
}

class _StudentStatRow extends StatelessWidget {
  const _StudentStatRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: appMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: appInk,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentMetricCard extends StatelessWidget {
  const _StudentMetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: appMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    color: appInk,
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
