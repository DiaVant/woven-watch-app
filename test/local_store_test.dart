import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trackapp/services/alert_engine.dart';
import 'package:trackapp/services/local_store.dart';
import 'package:trackapp/services/store_backend.dart';
import 'package:trackapp/services/store_backend_io.dart';

/// Counts writes, for the debounce test.
class CountingBackend implements StoreBackend {
  final Map<String, String> docs = {};
  final Map<String, int> writes = {};

  @override
  Future<String?> read(String name) async => docs[name];

  @override
  Future<void> write(String name, String contents) async {
    docs[name] = contents;
    writes[name] = (writes[name] ?? 0) + 1;
  }

  @override
  Future<void> delete(String name) async => docs.remove(name);
}

void main() {
  late Directory dir;
  final now = DateTime(2026, 10, 11, 9, 30);

  setUp(() => dir = Directory.systemTemp.createTempSync('wovenwatch_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  LocalStore storeIn(Directory d, {DateTime? at}) => LocalStore(
        backend: FileStoreBackend(d),
        clock: () => at ?? now,
      );

  File file(String doc) => File('${dir.path}/$doc.json');

  void writeLegacy() {
    file(alertSettingsDoc).writeAsStringSync(jsonEncode({
      'schemaVersion': 1,
      'default': {
        'readingsInARow': 4,
        'repeatEverySeconds': 60,
        'minConfidence': 'off',
      },
      'settings': {
        'room12/wwWatch-7B12': {
          'readingsInARow': 2,
          'repeatEverySeconds': 30,
          'minConfidence': 'fourOfFive',
        },
      },
    }));
    file(devicePrefsDoc).writeAsStringSync(jsonEncode({
      'schemaVersion': 1,
      'nicknames': {'wwWatch-7B12': 'Cart watch 2'},
      'quiet': ['room12/wwWatch-404F'],
    }));
  }

  test('old settings files are read, then dropped', () async {
    writeLegacy();
    final store = storeIn(dir);
    await store.load();
    expect(store.hasLegacyData, isTrue);
    final s = store.legacyAlertSettings['room12/wwWatch-7B12']!;
    expect(s.readingsInARow, 2);
    expect(s.repeatEvery, const Duration(seconds: 30));
    expect(s.minConfidence, ConfidenceStop.fourOfFive);
    expect(store.legacyDefaultAlert!.readingsInARow, 4);
    expect(store.legacyQuiet, {'room12/wwWatch-404F'});

    await store.dropLegacyData();
    expect(store.hasLegacyData, isFalse);
    expect(file(alertSettingsDoc).existsSync(), isFalse);
    expect(file(devicePrefsDoc).existsSync(), isFalse);
  });

  test('sessions and ui prefs round-trip', () async {
    final a = storeIn(dir);
    await a.load();
    a.devicesListExpanded = true;
    a.startSession('room12', 'wwWatch-404F',
        at: now.subtract(const Duration(minutes: 5)));
    a.recordReading('room12', 'wwWatch-404F', FidgetLabel.highFidgeting,
        votes: 4, at: now.subtract(const Duration(minutes: 1)));
    a.recordReading('room12', 'wwWatch-404F', FidgetLabel.notFidgeting,
        at: now); //old firmware, no votes
    a.recordAlert('room12', 'wwWatch-404F', AlertTag.high, at: now);
    await a.flush();

    for (final doc in [sessionsDoc, uiPrefsDoc]) {
      expect(file(doc).existsSync(), isTrue, reason: doc);
      expect(jsonDecode(file(doc).readAsStringSync())['schemaVersion'], 1);
    }
    expect(dir.listSync().where((f) => f.path.endsWith('.tmp')), isEmpty);

    expect(file(alertSettingsDoc).existsSync(), isFalse,
        reason: 'old settings files are never written again');

    final b = storeIn(dir);
    await b.load();
    expect(b.hasLegacyData, isFalse);
    expect(b.devicesListExpanded, isTrue);

    final session = b.openSession('room12', 'wwWatch-404F')!;
    expect(session.startedAt, now.subtract(const Duration(minutes: 5)));
    expect(session.readings.map((r) => r.label),
        [FidgetLabel.highFidgeting, FidgetLabel.notFidgeting]);
    expect(session.readings.map((r) => r.votes), [4, null]);
    expect(session.alerts.single.tag, AlertTag.high);
  });

  test('no files yet gives defaults', () async {
    final store = storeIn(dir);
    await store.load();
    expect(store.isLoaded, isTrue);
    expect(store.hasLegacyData, isFalse);
    expect(store.devicesListExpanded, isNull); //first run
    expect(store.sessions, isEmpty);
  });

  test('a corrupt file returns defaults and does not throw', () async {
    file(alertSettingsDoc).writeAsStringSync('{{{ not json');
    file(devicePrefsDoc).writeAsStringSync('[1, 2, 3]'); //valid JSON, wrong shape
    final store = storeIn(dir);
    await store.load();
    expect(store.hasLegacyData, isFalse);
  });

  test('a half-written file returns defaults', () async {
    final good = jsonEncode({
      'schemaVersion': 1,
      'quiet': ['room12/wwWatch-404F'],
    });
    file(devicePrefsDoc).writeAsStringSync(good.substring(0, good.length ~/ 2));
    final store = storeIn(dir);
    await store.load();
    expect(store.legacyQuiet, isEmpty);
  });

  test('an unknown or missing schema version returns defaults', () async {
    file(uiPrefsDoc).writeAsStringSync(
        jsonEncode({'schemaVersion': 2, 'devicesListExpanded': true}));
    file(devicePrefsDoc).writeAsStringSync(
        jsonEncode({'quiet': ['room12/wwWatch-404F']}));
    final store = storeIn(dir);
    await store.load();
    expect(store.devicesListExpanded, isNull);
    expect(store.legacyQuiet, isEmpty);
  });

  test('one bad settings entry is skipped, the rest load', () async {
    file(alertSettingsDoc).writeAsStringSync(jsonEncode({
      'schemaVersion': 1,
      'settings': {
        'room12/good': {
          'readingsInARow': 3,
          'repeatEverySeconds': 60,
          'minConfidence': 'off',
        },
        'room12/badN': {
          'readingsInARow': 9,
          'repeatEverySeconds': 60,
          'minConfidence': 'off',
        },
        'room12/badStop': {
          'readingsInARow': 3,
          'repeatEverySeconds': 60,
          'minConfidence': 'maybe',
        },
      },
    }));
    final store = storeIn(dir);
    await store.load();
    expect(store.legacyAlertSettings.keys, ['room12/good']);
  });

  test('sessions keep the open ones plus the last 10 ended', () async {
    final store = storeIn(dir);
    await store.load();
    for (var i = 0; i < 15; i++) {
      final start = now.subtract(Duration(minutes: 60 - i));
      store.startSession('room12', 'wwWatch-$i', at: start);
      store.endSession('room12', 'wwWatch-$i',
          at: start.add(const Duration(minutes: 1)));
    }
    store.startSession('room12', 'wwWatch-OPEN', at: now);
    await store.flush();

    final reloaded = storeIn(dir);
    await reloaded.load();
    expect(reloaded.sessions, hasLength(11));
    expect(reloaded.openSession('room12', 'wwWatch-OPEN'), isNotNull);
    // the five oldest ended sessions are gone, the ten newest remain
    final ids = reloaded.sessions.map((s) => s.deviceId).toSet();
    for (var i = 0; i < 5; i++) {
      expect(ids, isNot(contains('wwWatch-$i')));
    }
    for (var i = 5; i < 15; i++) {
      expect(ids, contains('wwWatch-$i'));
    }
  });

  test('readings older than 2 hours are trimmed', () async {
    final store = storeIn(dir);
    await store.load();
    store.startSession('room12', 'wwWatch-404F',
        at: now.subtract(const Duration(hours: 3)));
    for (var m = 180; m >= 0; m -= 10) {
      store.recordReading('room12', 'wwWatch-404F', FidgetLabel.lowFidgeting,
          votes: 5, at: now.subtract(Duration(minutes: m)));
    }
    await store.flush();

    final reloaded = storeIn(dir);
    await reloaded.load();
    final readings = reloaded.openSession('room12', 'wwWatch-404F')!.readings;
    expect(readings, hasLength(13)); //120, 110 ... 0 minutes ago
    expect(
      readings.every((r) =>
          !r.at.isBefore(now.subtract(LocalStore.readingRetention))),
      isTrue,
    );
  });

  test('a session growing all day stays bounded', () async {
    var clock = now;
    final store = LocalStore(
      backend: FileStoreBackend(dir),
      clock: () => clock,
    );
    await store.load();
    store.startSession('room12', 'wwWatch-404F', at: clock);
    // 6 hours of readings every 2.5 s
    for (var i = 0; i < 6 * 60 * 60 * 2 / 5; i++) {
      clock = clock.add(predictionInterval);
      store.recordReading('room12', 'wwWatch-404F', FidgetLabel.notFidgeting,
          votes: 5, at: clock);
    }
    await store.flush();
    final kept = store.openSession('room12', 'wwWatch-404F')!.readings.length;
    // 2 h / 2.5 s = 2880, +1 for the reading exactly at the cutoff
    expect(kept, lessThanOrEqualTo(2881));
  });

  test('saves are debounced: a burst of changes is one write', () async {
    final backend = CountingBackend();
    final store = LocalStore(
      backend: backend,
      saveDelay: const Duration(milliseconds: 50),
      clock: () => now,
    );
    await store.load();
    for (var i = 0; i < 20; i++) {
      store.devicesListExpanded = i.isEven;
    }
    expect(backend.writes, isEmpty); //nothing written yet
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(backend.writes, {uiPrefsDoc: 1});
    expect(jsonDecode(backend.docs[uiPrefsDoc]!)['devicesListExpanded'], false);
  });

  test('sign out clears session history', () async {
    final store = storeIn(dir);
    await store.load();
    store.startSession('room12', 'wwWatch-404F', at: now);
    await store.flush();
    await store.clearSessions();
    expect(store.sessions, isEmpty);
    expect(jsonDecode(file(sessionsDoc).readAsStringSync())['sessions'], isEmpty);
  });
}
