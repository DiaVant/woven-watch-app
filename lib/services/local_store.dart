import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:trackapp/services/alert_engine.dart';
import 'package:trackapp/services/store_backend.dart';

//files with a different version are ignored
const storeSchemaVersion = 1;

//each is saved as <name>.json
const alertSettingsDoc = 'alert_settings';
const sessionsDoc = 'sessions';
const devicePrefsDoc = 'device_prefs';
const uiPrefsDoc = 'ui_prefs';

class StoredReading {
  const StoredReading({required this.at, required this.label, this.votes});

  final DateTime at;
  final FidgetLabel label;
  final int? votes;
}

class StoredAlert {
  const StoredAlert({required this.at, required this.tag});

  final DateTime at;
  final AlertTag tag;
}

class StoredSession {
  StoredSession({
    required this.classId,
    required this.deviceId,
    required this.startedAt,
    this.endedAt,
    List<StoredReading>? readings,
    List<StoredAlert>? alerts,
  })  : readings = readings ?? [],
        alerts = alerts ?? [];

  final String classId;
  final String deviceId;
  final DateTime startedAt;
  DateTime? endedAt;
  final List<StoredReading> readings;
  final List<StoredAlert> alerts;

  bool get isOpen => endedAt == null;
}

//saves to disk. writes are debounced, and a bad file falls back to defaults
class LocalStore extends ChangeNotifier {
  LocalStore({
    required StoreBackend backend,
    this.saveDelay = const Duration(seconds: 2),
    DateTime Function()? clock,
  })  : _backend = backend,
        _clock = clock ?? DateTime.now;

  static final LocalStore device =
      LocalStore(backend: StoreBackend.platformDefault());

  static LocalStore _current = device;

  //the demo swaps in a memory store so real sessions are never touched
  static LocalStore get instance => _current;

  static void use(LocalStore? store) => _current = store ?? device;

  static const int keptEndedSessions = 10;

  static const Duration readingRetention = Duration(hours: 2);

  final StoreBackend _backend;
  final DateTime Function() _clock;
  final Duration saveDelay;

  // alert_settings.json, old: only read so it can be moved to firebase
  AlertSettings? _defaultAlertSettings;
  final Map<String, AlertSettings> _alertSettings = {};

  // sessions.json
  final List<StoredSession> _sessions = [];

  // device_prefs.json, old: same
  final Set<String> _quiet = {};

  // ui_prefs.json
  bool? _devicesListExpanded;

  final Set<String> _dirty = {};
  Timer? _saveTimer;
  Future<void>? _loading;
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    _readAlertSettings(await _readDoc(alertSettingsDoc));
    _readSessions(await _readDoc(sessionsDoc));
    _readDevicePrefs(await _readDoc(devicePrefsDoc));
    _readUiPrefs(await _readDoc(uiPrefsDoc));
    _trimSessions();
    _loaded = true;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> _readDoc(String name) async {
    final String? text;
    try {
      text = await _backend.read(name);
    } catch (e) {
      debugPrint('LocalStore: $name unreadable, using defaults ($e)');
      return null;
    }
    if (text == null) return null;
    try {
      final json = jsonDecode(text);
      if (json is! Map<String, dynamic>) {
        throw const FormatException('not a JSON object');
      }
      final version = json['schemaVersion'];
      if (version != storeSchemaVersion) {
        debugPrint('LocalStore: $name has schemaVersion $version, '
            'expected $storeSchemaVersion; starting fresh');
        return null;
      }
      return json;
    } catch (e) {
      debugPrint('LocalStore: $name is corrupt, using defaults ($e)');
      return null;
    }
  }

  //read each entry separately so one bad entry doesn't drop the rest
  static void _eachEntry(Object? map, void Function(String, Object?) read) {
    if (map is! Map) return;
    for (final entry in map.entries) {
      try {
        read(entry.key.toString(), entry.value);
      } catch (e) {
        debugPrint('LocalStore: skipped bad entry ${entry.key} ($e)');
      }
    }
  }

  void _readAlertSettings(Map<String, dynamic>? json) {
    if (json == null) return;
    final fallback = json['default'];
    if (fallback != null) {
      try {
        _defaultAlertSettings = alertSettingsFromJson(fallback);
      } catch (e) {
        debugPrint('LocalStore: bad default alert settings ($e)');
      }
    }
    _eachEntry(json['settings'], (key, value) {
      _alertSettings[key] = alertSettingsFromJson(value);
    });
  }

  void _readSessions(Map<String, dynamic>? json) {
    final list = json?['sessions'];
    if (list is! List) return;
    for (final item in list) {
      try {
        _sessions.add(_sessionFromJson(item));
      } catch (e) {
        debugPrint('LocalStore: skipped bad session ($e)');
      }
    }
  }

  void _readDevicePrefs(Map<String, dynamic>? json) {
    if (json == null) return;
    final quiet = json['quiet'];
    if (quiet is List) _quiet.addAll(quiet.whereType<String>());
  }

  void _readUiPrefs(Map<String, dynamic>? json) {
    final expanded = json?['devicesListExpanded'];
    if (expanded is bool) _devicesListExpanded = expanded;
  }

  //settings saved on this device before they moved to firebase.
  //keys are classId/deviceId
  AlertSettings? get legacyDefaultAlert => _defaultAlertSettings;
  Map<String, AlertSettings> get legacyAlertSettings =>
      Map.unmodifiable(_alertSettings);
  Set<String> get legacyQuiet => Set.unmodifiable(_quiet);

  bool get hasLegacyData =>
      _defaultAlertSettings != null ||
      _alertSettings.isNotEmpty ||
      _quiet.isNotEmpty;

  //after the move to firebase worked
  Future<void> dropLegacyData() async {
    _defaultAlertSettings = null;
    _alertSettings.clear();
    _quiet.clear();
    for (final doc in [alertSettingsDoc, devicePrefsDoc]) {
      try {
        await _backend.delete(doc);
      } catch (e) {
        debugPrint('LocalStore: could not delete $doc ($e)');
      }
    }
  }

  //sign out and account deletion: session history is about students
  Future<void> clearSessions() async {
    _sessions.clear();
    _changed(sessionsDoc);
    await flush();
  }

  //null until the list is opened or closed once
  bool? get devicesListExpanded => _devicesListExpanded;

  set devicesListExpanded(bool? value) {
    if (_devicesListExpanded == value) return;
    _devicesListExpanded = value;
    _changed(uiPrefsDoc);
  }

  List<StoredSession> get sessions => List.unmodifiable(_sessions);

  StoredSession? openSession(String classId, String deviceId) {
    for (final session in _sessions) {
      if (session.isOpen &&
          session.classId == classId &&
          session.deviceId == deviceId) {
        return session;
      }
    }
    return null;
  }

  StoredSession startSession(String classId, String deviceId, {DateTime? at}) {
    final now = at ?? _clock();
    openSession(classId, deviceId)?.endedAt = now;
    final session =
        StoredSession(classId: classId, deviceId: deviceId, startedAt: now);
    _sessions.add(session);
    _trimSessions();
    _changed(sessionsDoc);
    return session;
  }

  void endSession(String classId, String deviceId, {DateTime? at}) {
    final session = openSession(classId, deviceId);
    if (session == null) return;
    session.endedAt = at ?? _clock();
    _trimSessions();
    _changed(sessionsDoc);
  }

  void recordReading(
    String classId,
    String deviceId,
    FidgetLabel label, {
    int? votes,
    DateTime? at,
  }) {
    final session = openSession(classId, deviceId);
    if (session == null) return;
    session.readings.add(
      StoredReading(at: at ?? _clock(), label: label, votes: votes),
    );
    _changed(sessionsDoc);
  }

  void recordAlert(
    String classId,
    String deviceId,
    AlertTag tag, {
    DateTime? at,
  }) {
    final session = openSession(classId, deviceId);
    if (session == null) return;
    session.alerts.add(StoredAlert(at: at ?? _clock(), tag: tag));
    _changed(sessionsDoc);
  }

  List<StoredSession> openSessionsIn(String classId) =>
      _sessions.where((s) => s.isOpen && s.classId == classId).toList();

  bool isClassSessionRunning(String classId) =>
      _sessions.any((s) => s.isOpen && s.classId == classId);

  DateTime? classSessionStartedAt(String classId) {
    DateTime? earliest;
    for (final s in openSessionsIn(classId)) {
      if (earliest == null || s.startedAt.isBefore(earliest)) {
        earliest = s.startedAt;
      }
    }
    return earliest;
  }

  void startClassSession(
    String classId,
    Iterable<String> deviceIds, {
    DateTime? at,
  }) {
    final now = at ?? _clock();
    for (final deviceId in deviceIds) {
      startSession(classId, deviceId, at: now);
    }
  }

  void endClassSession(String classId, {DateTime? at}) {
    final now = at ?? _clock();
    for (final s in openSessionsIn(classId)) {
      s.endedAt = now;
    }
    _trimSessions();
    _changed(sessionsDoc);
  }

  StoredSession? latestSession(String classId, String deviceId) {
    StoredSession? latest;
    for (final s in _sessions) {
      if (s.classId != classId || s.deviceId != deviceId) continue;
      if (s.isOpen) return s;
      if (latest == null || s.endedAt!.isAfter(latest.endedAt!)) latest = s;
    }
    return latest;
  }

  void _trimSessions() {
    final open = _sessions.where((s) => s.isOpen).toList();
    final ended = _sessions.where((s) => !s.isOpen).toList()
      ..sort((a, b) => b.endedAt!.compareTo(a.endedAt!));
    _sessions
      ..clear()
      ..addAll(open)
      ..addAll(ended.take(keptEndedSessions));

    final cutoff = _clock().subtract(readingRetention);
    for (final session in _sessions) {
      session.readings.removeWhere((r) => r.at.isBefore(cutoff));
    }
  }

  void _changed(String doc) {
    _dirty.add(doc);
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, () => unawaited(flush()));
    notifyListeners();
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final docs = Set.of(_dirty);
    _dirty.clear();
    if (docs.contains(sessionsDoc)) _trimSessions();
    for (final doc in docs) {
      try {
        await _backend.write(doc, jsonEncode(_documentJson(doc)));
      } catch (e) {
        debugPrint('LocalStore: could not save $doc ($e)');
        _dirty.add(doc); //try again on the next change
      }
    }
  }

  Map<String, dynamic> _documentJson(String doc) {
    final body = switch (doc) {
      sessionsDoc => {
          'sessions': [for (final s in _sessions) _sessionToJson(s)],
        },
      uiPrefsDoc => {
          if (_devicesListExpanded != null)
            'devicesListExpanded': _devicesListExpanded,
        },
      _ => throw ArgumentError.value(doc, 'doc'),
    };
    return {'schemaVersion': storeSchemaVersion, ...body};
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}

const _labelWire = {
  FidgetLabel.notFidgeting: 'not_fidgeting',
  FidgetLabel.lowFidgeting: 'low_fidgeting',
  FidgetLabel.highFidgeting: 'high_fidgeting',
};

AlertSettings alertSettingsFromJson(Object? json) {
  if (json is! Map) throw const FormatException('settings is not an object');
  final n = json['readingsInARow'];
  final repeat = json['repeatEverySeconds'];
  final stop = json['minConfidence'];
  if (n is! int || n < 1 || n > 4) {
    throw FormatException('readingsInARow $n');
  }
  if (repeat is! int || repeat <= 0) {
    throw FormatException('repeatEverySeconds $repeat');
  }
  return AlertSettings(
    readingsInARow: n,
    repeatEvery: Duration(seconds: repeat),
    minConfidence: ConfidenceStop.values.byName(stop as String),
  );
}

Map<String, dynamic> _sessionToJson(StoredSession s) => {
      'deviceId': s.deviceId,
      'classId': s.classId,
      'startedAt': s.startedAt.millisecondsSinceEpoch,
      'endedAt': s.endedAt?.millisecondsSinceEpoch,
      'readings': [
        for (final r in s.readings)
          {
            't': r.at.millisecondsSinceEpoch,
            'label': _labelWire[r.label],
            if (r.votes != null) 'votes': r.votes,
          },
      ],
      'alerts': [
        for (final a in s.alerts)
          {'t': a.at.millisecondsSinceEpoch, 'tag': a.tag.name},
      ],
    };

StoredSession _sessionFromJson(Object? json) {
  if (json is! Map) throw const FormatException('session is not an object');
  DateTime time(Object? ms) =>
      DateTime.fromMillisecondsSinceEpoch(ms as int);
  final endedAt = json['endedAt'];
  return StoredSession(
    classId: json['classId'] as String,
    deviceId: json['deviceId'] as String,
    startedAt: time(json['startedAt']),
    endedAt: endedAt == null ? null : time(endedAt),
    readings: [
      for (final r in (json['readings'] as List? ?? const []))
        if (r is Map && fidgetLabelFromWire('${r['label']}') != null)
          StoredReading(
            at: time(r['t']),
            label: fidgetLabelFromWire('${r['label']}')!,
            votes: r['votes'] is int ? r['votes'] as int : null,
          ),
    ],
    alerts: [
      for (final a in (json['alerts'] as List? ?? const []))
        if (a is Map)
          StoredAlert(
            at: time(a['t']),
            tag: AlertTag.values.byName(a['tag'] as String),
          ),
    ],
  );
}
