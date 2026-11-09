import 'dart:async';

import 'package:trackapp/models/care_class.dart';
import 'package:trackapp/services/class_service.dart';

//classes kept in memory, never firebase
class DemoClassService implements ClassService {
  DemoClassService(List<CareClass> classes) : _classes = List.of(classes);

  final List<CareClass> _classes;
  final StreamController<List<CareClass>> _changes =
      StreamController.broadcast();
  int _nextId = 1;

  List<CareClass> get classes => List.unmodifiable(_classes);

  @override
  Stream<List<CareClass>> watchClasses() async* {
    yield List.of(_classes);
    yield* _changes.stream;
  }

  void _emit() => _changes.add(List.of(_classes));

  int get _now => DateTime.now().millisecondsSinceEpoch;

  int _indexOf(String classId) {
    final i = _classes.indexWhere((c) => c.id == classId);
    if (i < 0) throw StateError('No class $classId.');
    return i;
  }

  CareClass _copy(
    CareClass c, {
    String? name,
    String? colorHex,
    List<ClassDevice>? devices,
  }) => CareClass(
    id: c.id,
    name: name ?? c.name,
    colorHex: colorHex ?? c.colorHex,
    devices:
        (devices ?? c.devices).toList()
          ..sort((a, b) => a.deviceId.compareTo(b.deviceId)),
    createdAt: c.createdAt,
    updatedAt: _now,
  );

  @override
  Future<void> createClass({
    required String name,
    required String colorHex,
    required List<String> deviceIds,
  }) async {
    final now = _now;
    _classes.add(
      CareClass(
        id: 'demo-new-${_nextId++}',
        name: name.trim(),
        colorHex: colorHex,
        devices: [for (final id in deviceIds) ClassDevice(deviceId: id)]
          ..sort((a, b) => a.deviceId.compareTo(b.deviceId)),
        createdAt: now,
        updatedAt: now,
      ),
    );
    _emit();
  }

  @override
  Future<void> updateClass({
    required String classId,
    required String name,
    required String colorHex,
    required List<String> deviceIds,
    Map<String, String> existingStudentNames = const {},
    Iterable<String> previousDeviceIds = const [],
  }) async {
    final i = _indexOf(classId);
    _classes[i] = _copy(
      _classes[i],
      name: name.trim(),
      colorHex: colorHex,
      devices: [
        for (final id in deviceIds)
          ClassDevice(deviceId: id, studentName: existingStudentNames[id]),
      ],
    );
    _emit();
  }

  @override
  Future<void> addDeviceToClass({
    required String classId,
    required String deviceId,
    String? studentName,
  }) async {
    final i = _indexOf(classId);
    final c = _classes[i];
    final old = c.devices.where((d) => d.deviceId == deviceId);
    final name = studentName ?? (old.isEmpty ? null : old.first.studentName);
    _classes[i] = _copy(
      c,
      devices: [
        for (final d in c.devices)
          if (d.deviceId != deviceId) d,
        ClassDevice(deviceId: deviceId, studentName: name),
      ],
    );
    _emit();
  }

  @override
  Future<void> deleteClass(String classId) async {
    _classes.removeAt(_indexOf(classId));
    _emit();
  }

  @override
  Future<void> updateStudentName({
    required String classId,
    required String deviceId,
    required String studentName,
  }) async {
    final i = _indexOf(classId);
    final c = _classes[i];
    final name = studentName.trim();
    _classes[i] = _copy(
      c,
      devices: [
        for (final d in c.devices)
          d.deviceId == deviceId
              ? ClassDevice(
                deviceId: deviceId,
                studentName: name.isEmpty ? null : name,
              )
              : d,
      ],
    );
    _emit();
  }
}
