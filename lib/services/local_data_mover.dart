import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:trackapp/services/alert_engine.dart';
import 'package:trackapp/services/local_store.dart';
import 'package:trackapp/services/watch_settings_service.dart';

//moves settings saved on this device into the signed-in account, once.
//runs after every sign-in but does nothing when there is no old local data
class LocalDataMover {
  LocalDataMover({FirebaseDatabase? database, LocalStore? store})
      : _database = database ?? FirebaseDatabase.instance,
        _store = store ?? LocalStore.instance;

  final FirebaseDatabase _database;
  final LocalStore _store;
  bool _running = false;

  Future<void> run(String uid) async {
    if (_running) return;
    _running = true;
    try {
      await _store.load();
      if (!_store.hasLegacyData) return;
      final root = _database.ref('users/$uid');
      final classes = await root.child('classes').get();
      final defaultAlert = await root.child('prefs/defaultAlert').get();
      final paths = legacyMovePaths(
        classes: classes.value,
        hasDefault: defaultAlert.exists,
        localDefault: _store.legacyDefaultAlert,
        localSettings: _store.legacyAlertSettings,
        localQuiet: _store.legacyQuiet,
      );
      if (paths.isNotEmpty) await root.update(paths);
      await _store.dropLegacyData();
    } catch (e) {
      //local files stay, so it tries again next sign-in
      debugPrint('moving local settings to firebase failed: $e');
    } finally {
      _running = false;
    }
  }
}

//paths under users/{uid}. a watch's settings only go up if the watch is in
//one of this account's classes and the account has nothing there yet, so one
//teacher's settings never land in another teacher's account
Map<String, Object?> legacyMovePaths({
  required Object? classes,
  required bool hasDefault,
  required AlertSettings? localDefault,
  required Map<String, AlertSettings> localSettings,
  required Set<String> localQuiet,
}) {
  final byClass = classes is Map ? classes : const {};

  Map? child(String classId, String name) {
    final c = byClass[classId];
    final node = c is Map ? c[name] : null;
    return node is Map ? node : null;
  }

  //keys are classId/deviceId
  (String, String)? target(String key, String node) {
    final i = key.indexOf('/');
    if (i <= 0 || i == key.length - 1) return null;
    final classId = key.substring(0, i);
    final deviceId = key.substring(i + 1);
    final inClass = child(classId, 'devices')?.containsKey(deviceId) ?? false;
    final taken = child(classId, node)?.containsKey(deviceId) ?? false;
    return inClass && !taken ? (classId, deviceId) : null;
  }

  final out = <String, Object?>{};
  localSettings.forEach((key, settings) {
    if (target(key, 'alertSettings') case (final c, final d)) {
      out['classes/$c/alertSettings/$d'] = alertSettingsToDb(snapToStops(settings));
    }
  });
  for (final key in localQuiet) {
    if (target(key, 'quiet') case (final c, final d)) {
      out['classes/$c/quiet/$d'] = true;
    }
  }
  if (!hasDefault && localDefault != null) {
    out['prefs/defaultAlert'] = alertSettingsToDb(snapToStops(localDefault));
  }
  return out;
}
