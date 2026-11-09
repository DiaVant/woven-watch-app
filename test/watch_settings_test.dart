import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:trackapp/services/alert_engine.dart';
import 'package:trackapp/services/alert_manager.dart';
import 'package:trackapp/services/class_service.dart';
import 'package:trackapp/models/care_class.dart';
import 'package:trackapp/services/watch_settings_service.dart';

//fake firebase: tests push snapshots and writes get recorded
class FakeWatchSettings implements WatchSettingsService {
  final settings = StreamController<Map<String, AlertSettings>>.broadcast();
  final quiet = StreamController<Set<String>>.broadcast();
  final defaults = StreamController<AlertSettings?>.broadcast();
  final writes = <String>[];

  @override
  Stream<Map<String, AlertSettings>> watchAlertSettings(String classId) =>
      settings.stream;

  @override
  Stream<Set<String>> watchQuiet(String classId) => quiet.stream;

  @override
  Stream<AlertSettings?> watchDefaultAlert() => defaults.stream;

  @override
  Future<void> setDefaultAlert(AlertSettings s) async =>
      writes.add('prefs/defaultAlert=${s.readingsInARow}');

  @override
  Future<void> setAlertSettings(
    String classId,
    String deviceId,
    AlertSettings s,
  ) async =>
      writes.add('$classId/alertSettings/$deviceId=${s.readingsInARow}');

  @override
  Future<void> setQuiet(String classId, String deviceId, bool q) async =>
      writes.add('$classId/quiet/$deviceId=$q');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final manager = AlertManager.instance;

  late FakeWatchSettings fake;
  setUp(() {
    fake = FakeWatchSettings();
    manager.attachSettings(fake);
  });
  tearDown(() {
    manager.leaveClass('sync');
    manager.attachSettings(null);
  });

  test('fallback chain: class + watch, then the default, then hardcoded',
      () async {
    manager.viewClass('sync', ['w-own', 'w-none']);
    expect(manager.settingsFor('sync', 'w-none').readingsInARow,
        AlertManager.defaultSettings.readingsInARow,
        reason: 'nothing loaded yet: alerting does not wait');

    fake.defaults.add(const AlertSettings(readingsInARow: 2));
    fake.settings.add({'w-own': const AlertSettings(readingsInARow: 4)});
    await pumpEventQueue();
    expect(manager.settingsFor('sync', 'w-own').readingsInARow, 4);
    expect(manager.settingsFor('sync', 'w-none').readingsInARow, 2);

    fake.defaults.add(null);
    fake.settings.add({}); //w-own's entry deleted, e.g. on another device
    await pumpEventQueue();
    expect(manager.settingsFor('sync', 'w-own').readingsInARow,
        AlertManager.defaultSettings.readingsInARow);
  });

  test('a new default only changes watches without their own settings',
      () async {
    manager.viewClass('sync', ['w-own', 'w-none']);
    fake.settings.add({'w-own': const AlertSettings(readingsInARow: 4)});
    fake.defaults.add(const AlertSettings(readingsInARow: 1));
    await pumpEventQueue();
    expect(manager.settingsFor('sync', 'w-own').readingsInARow, 4);
    expect(manager.settingsFor('sync', 'w-none').readingsInARow, 1);
    fake.defaults.add(null);
    await pumpEventQueue();
  });

  group('watch names', () {
    ClassDevice parse(Map<String, Object> device) =>
        CareClass.fromDatabase('c', {
          'name': 'Room 12',
          'devices': {'wwWatch-404F': device},
        }).devices.single;

    test('no student name shows the BLE id', () {
      expect(parse({'deviceId': 'wwWatch-404F'}).name, 'wwWatch-404F');
      expect(parse({'studentName': '  '}).studentName, isNull);
    });

    test('the old placeholder counts as no name', () {
      final d = parse({'studentName': 'Student WWWATCH-404F'});
      expect(d.studentName, isNull);
      expect(d.name, 'wwWatch-404F');
    });

    test('a student name is used inside the class', () {
      expect(parse({'studentName': 'Maya'}).name, 'Maya');
    });
  });

  test('changes apply at once and are written to Firebase', () async {
    manager.viewClass('sync', ['w1']);
    manager.setSettings('sync', 'w1', const AlertSettings(readingsInARow: 1));
    expect(manager.settingsFor('sync', 'w1').readingsInARow, 1);

    manager.setQuiet('sync', 'w1', true);
    expect(manager.isQuiet('sync', 'w1'), isTrue);
    manager.setQuiet('sync', 'w1', true); //no change, no write
    await pumpEventQueue();
    expect(fake.writes, [
      'sync/alertSettings/w1=1',
      'sync/quiet/w1=true',
    ]);
  });

  test('quiet follows Firebase, per class', () async {
    manager.viewClass('sync', ['w1', 'w2']);
    fake.quiet.add({'w2'});
    await pumpEventQueue();
    expect(manager.isQuiet('sync', 'w2'), isTrue);
    expect(manager.isQuiet('sync', 'w1'), isFalse);
    expect(manager.isQuiet('elsewhere', 'w2'), isFalse);
    fake.quiet.add({});
    await pumpEventQueue();
    expect(manager.isQuiet('sync', 'w2'), isFalse);
  });

  test('sign out forgets the last teacher', () async {
    manager.viewClass('sync', ['w1']);
    fake.quiet.add({'w1'});
    await pumpEventQueue();
    for (var i = 0; i < 3; i++) {
      manager.inject('sync', 'w1', FidgetLabel.highFidgeting);
    }
    expect(manager.classLog('sync'), isNotEmpty);
    manager.reset();
    expect(manager.isQuiet('sync', 'w1'), isFalse);
    expect(manager.classLog('sync'), isEmpty);
    expect(manager.openClassId, isNull);
  });

  group('editing a class', () {
    Map<String, Map<String, Object>> devices(List<String> ids) => {
          for (final id in ids) id: {'deviceId': id, 'updatedAt': 1},
        };

    test('removing a watch clears its settings and quiet flag', () {
      final paths = classUpdatePaths(
        name: ' Room 12 ',
        colorHex: '#6662D9',
        devices: devices(['w1']),
        previousDeviceIds: ['w1', 'w2'],
        now: 5,
      );
      expect(paths['name'], 'Room 12');
      expect(paths.containsKey('alertSettings/w2'), isTrue);
      expect(paths['alertSettings/w2'], isNull);
      expect(paths.containsKey('quiet/w2'), isTrue);
    });

    test('a watch that stays keeps its settings', () {
      final paths = classUpdatePaths(
        name: 'Room 12',
        colorHex: '#6662D9',
        devices: devices(['w1', 'w2']),
        previousDeviceIds: ['w1', 'w2'],
        now: 5,
      );
      expect(paths.keys.where((k) => k.startsWith('alertSettings')), isEmpty);
      expect(paths.keys.where((k) => k.startsWith('quiet')), isEmpty);
      expect(paths.containsKey('alertSettings'), isFalse,
          reason: 'never replace the whole node');
    });

    test('a watch with no student gets no placeholder name', () {
      final map = classDeviceMap(
        deviceIds: ['w1', 'w2'],
        existingStudentNames: {'w2': 'Maya'},
      );
      expect(map['w1']!.containsKey('studentName'), isFalse);
      expect(map['w2']!['studentName'], 'Maya');
    });

    test('an empty class writes devices as null', () {
      final paths = classUpdatePaths(
        name: 'Room 12',
        colorHex: '#6662D9',
        devices: const {},
        previousDeviceIds: ['w1'],
        now: 5,
      );
      expect(paths.containsKey('devices'), isTrue);
      expect(paths['devices'], isNull);
    });
  });

  test('database records parse only within the rules', () {
    final good = alertSettingsFromDb(
      alertSettingsToDb(const AlertSettings(
        readingsInARow: 2,
        repeatEvery: Duration(seconds: 30),
        minConfidence: ConfidenceStop.fiveOfFive,
      )),
    )!;
    expect(good.readingsInARow, 2);
    expect(good.repeatEvery, const Duration(seconds: 30));
    expect(good.minConfidence, ConfidenceStop.fiveOfFive);

    Map<String, Object> rec(int n, int repeat, String stop) =>
        {'readingsInARow': n, 'repeatEverySeconds': repeat, 'minConfidence': stop};
    expect(alertSettingsFromDb(rec(5, 30, 'off')), isNull);
    expect(alertSettingsFromDb(rec(3, 45, 'off')), isNull);
    expect(alertSettingsFromDb(rec(3, 30, 'sometimes')), isNull);
    expect(alertSettingsFromDb('junk'), isNull);
  });
}
