import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:trackapp/models/care_class.dart';

class ClassService {
  final FirebaseAuth _auth;
  final FirebaseDatabase _database;

  ClassService({
    FirebaseAuth? auth,
    FirebaseDatabase? database,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _database = database ?? FirebaseDatabase.instance;

  DatabaseReference? get _classesRef {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    return _database.ref('users/$uid/classes');
  }

  Stream<List<CareClass>> watchClasses() {
    final ref = _classesRef;
    if (ref == null) return Stream.value([]);

    return ref.onValue.map((event) {
      final value = event.snapshot.value;
      if (value == null) return <CareClass>[];

      final data = Map<Object?, Object?>.from(value as Map);
      final classes = data.entries
          .map((entry) => CareClass.fromDatabase(
                entry.key.toString(),
                entry.value,
              ))
          .toList();

      classes.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return classes;
    });
  }

  Future<void> createClass({
    required String name,
    required String colorHex,
    required List<String> deviceIds,
  }) async {
    final ref = _classesRef;
    if (ref == null) throw StateError('No signed-in user.');

    final now = DateTime.now().millisecondsSinceEpoch;
    await ref.push().set({
      'name': name.trim(),
      'colorHex': colorHex,
      'devices': classDeviceMap(deviceIds: deviceIds),
      'createdAt': now,
      'updatedAt': now,
    });
  }

  //one write so it can't half fail. removed watches lose their settings + quiet
  Future<void> updateClass({
    required String classId,
    required String name,
    required String colorHex,
    required List<String> deviceIds,
    Map<String, String> existingStudentNames = const {},
    Iterable<String> previousDeviceIds = const [],
  }) async {
    final ref = _classesRef;
    if (ref == null) throw StateError('No signed-in user.');

    await ref.child(classId).update(classUpdatePaths(
      name: name,
      colorHex: colorHex,
      devices: classDeviceMap(
        deviceIds: deviceIds,
        existingStudentNames: existingStudentNames,
      ),
      previousDeviceIds: previousDeviceIds,
      now: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  //used by Add Watch. keeps the student name if it's already in the class
  Future<void> addDeviceToClass({
    required String classId,
    required String deviceId,
    String? studentName,
  }) async {
    final ref = _classesRef;
    if (ref == null) throw StateError('No signed-in user.');

    final now = DateTime.now().millisecondsSinceEpoch;
    await ref.child('$classId/devices/$deviceId').update({
      'deviceId': deviceId,
      if (studentName != null) 'studentName': studentName,
      'updatedAt': now,
    });
    await ref.child(classId).update({'updatedAt': now});
  }

  Future<void> deleteClass(String classId) async {
    final ref = _classesRef;
    if (ref == null) throw StateError('No signed-in user.');

    await ref.child(classId).remove();
  }

  Future<void> updateStudentName({
    required String classId,
    required String deviceId,
    required String studentName,
  }) async {
    final ref = _classesRef;
    if (ref == null) throw StateError('No signed-in user.');

    final name = studentName.trim();
    await ref.child('$classId/devices/$deviceId').update({
      'deviceId': deviceId,
      'studentName': name.isEmpty ? null : name, //empty removes it
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
    await ref.child(classId).update({
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }
}

//devices gets replaced whole, alertSettings/quiet only lose removed watches
Map<String, Object?> classUpdatePaths({
  required String name,
  required String colorHex,
  required Map<String, Map<String, Object>> devices,
  required Iterable<String> previousDeviceIds,
  required int now,
}) {
  final removed = previousDeviceIds.where((id) => !devices.containsKey(id));
  return {
    'name': name.trim(),
    'colorHex': colorHex,
    'updatedAt': now,
    'devices': devices.isEmpty ? null : devices,
    for (final id in removed) ...{
      'alertSettings/$id': null,
      'quiet/$id': null,
    },
  };
}

//no studentName key when there is no name
Map<String, Map<String, Object>> classDeviceMap({
  required List<String> deviceIds,
  Map<String, String> existingStudentNames = const {},
}) {
  final now = DateTime.now().millisecondsSinceEpoch;
  return {
    for (final deviceId in deviceIds)
      deviceId: {
        'deviceId': deviceId,
        if (existingStudentNames[deviceId] case final name?) 'studentName': name,
        'updatedAt': now,
      },
  };
}
