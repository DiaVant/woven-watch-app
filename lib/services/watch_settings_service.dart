import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:trackapp/services/alert_engine.dart';

//alert settings and quiet flags under users/{uid}/classes/{classId},
//plus the account default under users/{uid}/prefs/defaultAlert
class WatchSettingsService {
  WatchSettingsService({FirebaseAuth? auth, FirebaseDatabase? database})
      : _auth = auth ?? FirebaseAuth.instance,
        _database = database ?? FirebaseDatabase.instance;

  final FirebaseAuth _auth;
  final FirebaseDatabase _database;

  DatabaseReference? _classRef(String classId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    return _database.ref('users/$uid/classes/$classId');
  }

  DatabaseReference? get _defaultRef {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    return _database.ref('users/$uid/prefs/defaultAlert');
  }

  //null when the account has no default yet
  Stream<AlertSettings?> watchDefaultAlert() {
    final ref = _defaultRef;
    if (ref == null) return const Stream.empty();
    return ref.onValue.map((event) => alertSettingsFromDb(event.snapshot.value));
  }

  Future<void> setDefaultAlert(AlertSettings settings) async {
    final ref = _defaultRef;
    if (ref == null) throw StateError('No signed-in user.');
    await ref.set(alertSettingsToDb(settings));
  }

  Stream<Map<String, AlertSettings>> watchAlertSettings(String classId) {
    final ref = _classRef(classId);
    if (ref == null) return const Stream.empty();
    return ref.child('alertSettings').onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return const <String, AlertSettings>{};
      final out = <String, AlertSettings>{};
      value.forEach((key, raw) {
        final settings = alertSettingsFromDb(raw);
        if (settings != null) out[key.toString()] = settings;
      });
      return out;
    });
  }

  Stream<Set<String>> watchQuiet(String classId) {
    final ref = _classRef(classId);
    if (ref == null) return const Stream.empty();
    return ref.child('quiet').onValue.map((event) {
      final value = event.snapshot.value;
      if (value is! Map) return const <String>{};
      return {
        for (final e in value.entries)
          if (e.value == true) e.key.toString(),
      };
    });
  }

  Future<void> setAlertSettings(
    String classId,
    String deviceId,
    AlertSettings settings,
  ) async {
    final ref = _classRef(classId);
    if (ref == null) throw StateError('No signed-in user.');
    await ref.child('alertSettings/$deviceId').set(alertSettingsToDb(settings));
  }

  //quiet is stored as true and removed when off
  Future<void> setQuiet(String classId, String deviceId, bool quiet) async {
    final ref = _classRef(classId);
    if (ref == null) throw StateError('No signed-in user.');
    await ref.child('quiet/$deviceId').set(quiet ? true : null);
  }
}

//same stops the database rules allow
const List<int> repeatStopsSeconds = [10, 30, 60, 120];

Map<String, Object> alertSettingsToDb(AlertSettings s) => {
      'readingsInARow': s.readingsInARow,
      'repeatEverySeconds': s.repeatEvery.inSeconds,
      'minConfidence': s.minConfidence.name,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };

//null for bad data so it falls back to the default
@visibleForTesting
AlertSettings? alertSettingsFromDb(Object? raw) {
  if (raw is! Map) return null;
  final n = raw['readingsInARow'];
  final repeat = raw['repeatEverySeconds'];
  final stopName = raw['minConfidence'];
  if (n is! int || n < 1 || n > 4) return null;
  if (repeat is! int || !repeatStopsSeconds.contains(repeat)) return null;
  final stop = ConfidenceStop.values.where((c) => c.name == stopName);
  if (stop.isEmpty) return null;
  return AlertSettings(
    readingsInARow: n,
    repeatEvery: Duration(seconds: repeat),
    minConfidence: stop.first,
  );
}

//old local settings could use any repeat time, firebase only takes the stops
AlertSettings snapToStops(AlertSettings s) {
  final secs = s.repeatEvery.inSeconds;
  var best = repeatStopsSeconds.first;
  for (final stop in repeatStopsSeconds) {
    if ((stop - secs).abs() < (best - secs).abs()) best = stop;
  }
  return AlertSettings(
    readingsInARow: s.readingsInARow.clamp(1, 4),
    repeatEvery: Duration(seconds: best),
    minConfidence: s.minConfidence,
  );
}
