import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:trackapp/services/alert_engine.dart';
import 'package:trackapp/services/local_store.dart';
import 'package:trackapp/services/watch_settings_service.dart';
import 'package:trackapp/services/watch_ble_service.dart'
    show PredictionEvent, WatchBleService;

//same cart watch in two classes = two keys
typedef AlertKey = ({String classId, String deviceId});

class AlertLogEntry {
  const AlertLogEntry({
    required this.classId,
    required this.deviceId,
    required this.event,
    required this.receivedAt,
  });

  final String classId;
  final String deviceId;
  final AlertEvent event;

  final DateTime receivedAt;
}

class LastReading {
  const LastReading({
    required this.label,
    required this.votes,
    required this.at,
    required this.receivedAt,
  });

  final FidgetLabel label;
  final int? votes;

  final DateTime at;

  final DateTime receivedAt;
}

class AlertManager extends ChangeNotifier {
  AlertManager._internal() {
    WatchBleService.instance.predictions.listen(_onLivePrediction);
    _store.load();
  }

  LocalStore get _store => LocalStore.instance;

  //saved settings, then the default, then AlertSettings()
  AlertSettings _initialSettings(AlertKey key) =>
      _savedSettings[key] ?? _defaultAlert ?? defaultSettings;

  static final AlertManager instance = AlertManager._internal();

  static const AlertSettings defaultSettings = AlertSettings();

  final Map<AlertKey, AlertEngine> _engines = {};
  final Map<AlertKey, LastReading> _lastReadings = {};

  final Map<AlertKey, List<LastReading>> _history = {};

  final Map<AlertKey, DateTime> _stateSince = {};

  static const int historyLength = 12;
  final List<AlertLogEntry> _log = []; //oldest first

  String? _openClassId;
  Set<String> _openRoster = const {};

  //null in tests
  WatchSettingsService? _settingsService;

  final Map<AlertKey, AlertSettings> _savedSettings = {};
  final Set<AlertKey> _quiet = {};
  AlertSettings? _defaultAlert; //prefs/defaultAlert

  String? _syncedClassId;
  StreamSubscription<Map<String, AlertSettings>>? _settingsSub;
  StreamSubscription<Set<String>>? _quietSub;
  StreamSubscription<AlertSettings?>? _defaultSub;

  static AlertKey _key(String classId, String deviceId) =>
      (classId: classId, deviceId: deviceId);

  void viewClass(String classId, Iterable<String> deviceIds) {
    _openClassId = classId;
    _openRoster = deviceIds.toSet();
    _syncClass(classId);
  }

  void attachSettings(WatchSettingsService? service) {
    _settingsService = service;
    final classId = _syncedClassId;
    _syncedClassId = null;
    if (classId != null) _syncClass(classId);
  }

  void _syncClass(String classId) {
    if (_syncedClassId == classId) return;
    _settingsSub?.cancel();
    _quietSub?.cancel();
    _defaultSub?.cancel();
    _settingsSub = null;
    _quietSub = null;
    _defaultSub = null;
    _syncedClassId = classId;
    final service = _settingsService;
    if (service == null) return;
    _settingsSub = service.watchAlertSettings(classId).listen(
      (byDevice) => _onSavedSettings(classId, byDevice),
      onError: (Object e) => debugPrint('alertSettings/$classId: $e'),
    );
    _quietSub = service.watchQuiet(classId).listen(
      (devices) => _onQuiet(classId, devices),
      onError: (Object e) => debugPrint('quiet/$classId: $e'),
    );
    //resubscribed with each class so it follows whoever is signed in
    _defaultSub = service.watchDefaultAlert().listen(
      _onDefault,
      onError: (Object e) => debugPrint('prefs/defaultAlert: $e'),
    );
  }

  void _onDefault(AlertSettings? settings) {
    _defaultAlert = settings;
    //only watches without their own settings change
    for (final entry in _engines.entries) {
      if (!_savedSettings.containsKey(entry.key)) {
        entry.value.settings = _initialSettings(entry.key);
      }
    }
    notifyListeners();
  }

  void _onSavedSettings(String classId, Map<String, AlertSettings> byDevice) {
    _savedSettings.removeWhere((key, _) => key.classId == classId);
    byDevice.forEach((deviceId, s) => _savedSettings[_key(classId, deviceId)] = s);
    // a watch whose entry was removed goes back to the default
    for (final entry in _engines.entries) {
      if (entry.key.classId == classId) {
        entry.value.settings = _initialSettings(entry.key);
      }
    }
    notifyListeners();
  }

  void _onQuiet(String classId, Set<String> devices) {
    _quiet.removeWhere((key) => key.classId == classId);
    _quiet.addAll(devices.map((d) => _key(classId, d)));
    notifyListeners();
  }

  //sign out: forget the last teacher's alerts, readings and settings
  void reset() {
    _settingsSub?.cancel();
    _quietSub?.cancel();
    _defaultSub?.cancel();
    _settingsSub = null;
    _quietSub = null;
    _defaultSub = null;
    _syncedClassId = null;
    _openClassId = null;
    _openRoster = const {};
    _engines.clear();
    _lastReadings.clear();
    _history.clear();
    _stateSince.clear();
    _log.clear();
    _savedSettings.clear();
    _quiet.clear();
    _defaultAlert = null;
    notifyListeners();
  }

  String? get openClassId => _openClassId;
  List<String> get openRoster => _openRoster.toList();

  void leaveClass(String classId) {
    if (_openClassId != classId) return;
    _openClassId = null;
    _openRoster = const {};
  }

  AlertEngine engineFor(String classId, String deviceId) =>
      _engines.putIfAbsent(
        _key(classId, deviceId),
        () => AlertEngine(settings: _initialSettings(_key(classId, deviceId))),
      );

  AlertSettings settingsFor(String classId, String deviceId) =>
      engineFor(classId, deviceId).settings;

  //update right away, save to firebase in the background
  void setSettings(String classId, String deviceId, AlertSettings settings) {
    final key = _key(classId, deviceId);
    _savedSettings[key] = settings;
    engineFor(classId, deviceId).settings = settings;
    notifyListeners();
    _settingsService
        ?.setAlertSettings(classId, deviceId, settings)
        .catchError((Object e) => debugPrint('save alertSettings: $e'));
  }

  //quiet students still get alerts recorded, just not shown
  bool isQuiet(String classId, String deviceId) =>
      _quiet.contains(_key(classId, deviceId));

  void setQuiet(String classId, String deviceId, bool quiet) {
    final key = _key(classId, deviceId);
    final changed = quiet ? _quiet.add(key) : _quiet.remove(key);
    if (!changed) return;
    notifyListeners();
    _settingsService
        ?.setQuiet(classId, deviceId, quiet)
        .catchError((Object e) => debugPrint('save quiet: $e'));
  }

  LastReading? lastReadingFor(String classId, String deviceId) =>
      _lastReadings[_key(classId, deviceId)];

  List<LastReading> recentReadings(String classId, String deviceId) =>
      List.unmodifiable(_history[_key(classId, deviceId)] ?? const []);

  Duration? stateDuration(String classId, String deviceId) {
    final key = _key(classId, deviceId);
    final since = _stateSince[key];
    final last = _lastReadings[key];
    if (since == null || last == null) return null;
    return last.at.difference(since) + predictionInterval;
  }

  List<AlertLogEntry> classLog(String classId) =>
      _log.reversed.where((entry) => entry.classId == classId).toList();

  List<AlertLogEntry> logFor(String classId, String deviceId) => _log.reversed
      .where((e) => e.classId == classId && e.deviceId == deviceId)
      .toList();

  int alertCountFor(String classId) =>
      _log.where((entry) => entry.classId == classId).length;

  AlertLogEntry? activeAlertFor(String classId, String deviceId) {
    final key = _key(classId, deviceId);
    final engine = _engines[key];
    final last = _lastReadings[key];
    if (engine == null || last == null || !engine.alertedInRun) return null;
    if (DateTime.now().difference(last.receivedAt) > silenceThreshold) {
      return null;
    }
    for (final entry in _log.reversed) {
      if (entry.classId == classId && entry.deviceId == deviceId) return entry;
    }
    return null;
  }

  Duration? nextRepeatIn(String classId, String deviceId) {
    final engine = _engines[_key(classId, deviceId)];
    final lastAlert = engine?.lastAlertAt;
    final lastArrival = engine?.lastArrivalAt;
    if (engine == null || lastAlert == null || lastArrival == null) return null;
    final remaining =
        lastAlert.add(engine.settings.repeatEvery).difference(lastArrival);
    return remaining > Duration.zero ? remaining : null;
  }

  void _onLivePrediction(PredictionEvent p) {
    final classId = _openClassId;
    if (classId == null || !_openRoster.contains(p.watchId)) return;
    final key = _key(classId, p.watchId);
    final engine = engineFor(classId, p.watchId);
    final lastArrival = engine.lastArrivalAt;
    if (lastArrival != null && p.at.isBefore(lastArrival)) {
      //injected readings can push the clock ahead, so start fresh
      _engines[key] = AlertEngine(settings: engine.settings);
    }
    _ingest(key, Reading(label: p.label, votes: p.votes, at: p.at));
  }

  //for tests: adds a reading 2.5 s after the last one
  void inject(
    String classId,
    String deviceId,
    FidgetLabel label, {
    int? votes,
  }) {
    final lastArrival = engineFor(classId, deviceId).lastArrivalAt;
    final at =
        lastArrival == null ? DateTime.now() : lastArrival.add(predictionInterval);
    _ingest(
      _key(classId, deviceId),
      Reading(label: label, votes: votes, at: at),
    );
  }

  void _ingest(AlertKey key, Reading reading) {
    final now = DateTime.now();
    final previous = _lastReadings[key];
    final current = LastReading(
      label: reading.label,
      votes: reading.votes,
      at: reading.at,
      receivedAt: now,
    );
    _lastReadings[key] = current;

    final history = _history.putIfAbsent(key, () => []);
    history.add(current);
    if (history.length > historyLength) history.removeAt(0);

    bool fidgeting(FidgetLabel l) => l != FidgetLabel.notFidgeting;
    if (previous == null ||
        fidgeting(previous.label) != fidgeting(reading.label) ||
        reading.at.difference(previous.at) > silenceThreshold) {
      _stateSince[key] = reading.at;
    }

    final event = engineFor(key.classId, key.deviceId).ingest(reading);
    if (event != null) {
      _log.add(AlertLogEntry(
        classId: key.classId,
        deviceId: key.deviceId,
        event: event,
        receivedAt: now,
      ));
    }
    _record(key, reading, event, now);
    notifyListeners();
  }

  //only saved while a session is running
  void _record(AlertKey key, Reading reading, AlertEvent? event, DateTime now) {
    final store = _store;
    if (!store.isClassSessionRunning(key.classId)) return;
    // a watch added to the class mid-session joins the running session
    if (store.openSession(key.classId, key.deviceId) == null) {
      store.startSession(key.classId, key.deviceId, at: now);
    }
    store.recordReading(
      key.classId,
      key.deviceId,
      reading.label,
      votes: reading.votes,
      at: now,
    );
    if (event != null) {
      store.recordAlert(key.classId, key.deviceId, event.tag, at: now);
    }
  }
}
