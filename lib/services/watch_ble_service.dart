import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:trackapp/services/alert_engine.dart'
    show FidgetLabel, fidgetLabelFromWire;
import 'package:trackapp/theme/app_theme.dart';

const watchNamePrefix = 'wwWatch-';

//nordic uart service from the firmware
final Guid uartServiceUuid = Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E');

//uart tx, the watch sends its lines on this
final Guid uartTxCharUuid = Guid('6E400003-B5A3-F393-E0A9-E50E24DCCA9E');

//one prediction every 2.5 s
const predictionInterval = Duration(milliseconds: 2500);

const _nearbyWindow = Duration(seconds: 30);

//lines look like pred,<label> or pred,<label>,<votes>
String? parsePredictionLine(String line) {
  final fields = line.trim().split(',');
  if (fields.length < 2 || fields.first != 'pred') return null;

  final label = fields[1].trim();
  return label.isEmpty ? null : label;
}

const knnK = 5;

int? parsePredictionVotes(String line) {
  final fields = line.trim().split(',');
  if (fields.length < 3 || fields.first != 'pred') return null;
  final votes = int.tryParse(fields[2].trim());
  if (votes == null || votes < 0 || votes > knnK) return null;
  return votes;
}

class PredictionEvent {
  const PredictionEvent({
    required this.watchId,
    required this.label,
    required this.votes,
    required this.at,
  });

  final String watchId;
  final FidgetLabel label;

  final int? votes;
  final DateTime at;
}

String predictionLabel(String? prediction) {
  switch (prediction) {
    case 'not_fidgeting':
      return 'Calm';
    case 'low_fidgeting':
      return 'Low fidgeting';
    case 'high_fidgeting':
      return 'High fidgeting';
    default:
      return 'Waiting for data';
  }
}

Color predictionColor(String? prediction) {
  switch (prediction) {
    case 'not_fidgeting':
      return appTeal;
    case 'low_fidgeting':
      return appGold;
    case 'high_fidgeting':
      return appRed;
    default:
      return appMuted;
  }
}

String formatAgo(DateTime? time) {
  if (time == null) return '—';
  final elapsed = DateTime.now().difference(time);
  if (elapsed.inSeconds < 10) return 'Just now';
  if (elapsed.inMinutes < 1) return '${elapsed.inSeconds}s ago';
  if (elapsed.inHours < 1) return '${elapsed.inMinutes}m ago';
  if (elapsed.inDays < 1) return '${elapsed.inHours}h ago';
  return '${elapsed.inDays}d ago';
}

String formatDuration(Duration duration) {
  if (duration.inSeconds < 60) return '${duration.inSeconds}s';
  if (duration.inHours < 1) return '${duration.inMinutes} min';
  return '${duration.inHours}h ${duration.inMinutes % 60}m';
}

class WovenWatch {
  WovenWatch({required this.id});

  //BLE name, also the deviceId in firebase
  final String id;

  BluetoothDevice? device;
  int? rssi;
  DateTime? lastSeen; //last advertisement or UART line
  bool isConnected = false;
  bool isConnecting = false;

  String? prediction;
  DateTime? predictionAt;

  int? lastVotes;

  Duration fidgetingTime = Duration.zero;

  String _lineBuffer = '';
  StreamSubscription<List<int>>? _dataSub;
  StreamSubscription<BluetoothConnectionState>? _stateSub;

  bool get isNearby =>
      !isConnected &&
      lastSeen != null &&
      DateTime.now().difference(lastSeen!) < _nearbyWindow;

  String get status =>
      isConnected ? 'Connected' : (isNearby ? 'Nearby' : 'Disconnected');

  Color get statusColor =>
      isConnected ? appTeal : (isNearby ? appGold : appMuted);

  int get signalBars {
    final value = rssi;
    if (value == null) return 0;
    if (value >= -55) return 4;
    if (value >= -67) return 3;
    if (value >= -80) return 2;
    return 1;
  }

  String get proximity {
    switch (signalBars) {
      case 4:
        return 'Very close';
      case 3:
        return 'Nearby';
      case 2:
        return 'Across room';
      case 1:
        return 'Far';
      default:
        return 'Unknown';
    }
  }
}

class WatchBleService extends ChangeNotifier {
  WatchBleService._internal() {
    FlutterBluePlus.scanResults.listen(_onScanResults);
    FlutterBluePlus.isScanning.listen((scanning) {
      _isScanning = scanning;
      notifyListeners();
    });
  }

  static final WatchBleService instance = WatchBleService._internal();

  final Map<String, WovenWatch> _watches = {};
  final Set<String> _simulated = {};
  bool _isScanning = false;
  final StreamController<PredictionEvent> _predictions =
      StreamController.broadcast();

  bool get isScanning => _isScanning;

  List<WovenWatch> get watches =>
      _watches.values.toList()..sort((a, b) => a.id.compareTo(b.id));

  WovenWatch? watchById(String id) => _watches[id];

  Stream<PredictionEvent> get predictions => _predictions.stream;

  int get connectedCount =>
      _watches.values.where((watch) => watch.isConnected).length;

  int get nearbyCount =>
      _watches.values
          .where((watch) => watch.isConnected || watch.isNearby)
          .length;

  Future<void> startScan({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    if (_isScanning || isSimulating) return;
    try {
      await FlutterBluePlus.startScan(
        withServices: [uartServiceUuid],
        timeout: timeout,
      );
    } catch (e) {
      debugPrint('BLE scan failed: $e');
      rethrow;
    }
  }

  Future<void> stopScan() => FlutterBluePlus.stopScan();

  void _onScanResults(List<ScanResult> results) {
    var changed = false;
    for (final result in results) {
      //web bluetooth only gives platformName, advName is empty
      final advertisedName = result.advertisementData.advName;
      final name =
          advertisedName.isNotEmpty
              ? advertisedName
              : result.device.platformName;
      if (!name.startsWith(watchNamePrefix)) continue;

      final watch = _watches.putIfAbsent(name, () => WovenWatch(id: name));
      watch.device = result.device;
      watch.rssi = result.rssi;
      watch.lastSeen = DateTime.now();
      changed = true;
    }
    if (changed) notifyListeners();
  }

  //connect by id. a watch not seen this session gets a scan first
  //(on web that opens the browser's bluetooth picker)
  Future<void> reconnect(
    String id, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    var watch = _seen(id);
    if (watch == null) {
      await startScan(timeout: timeout);
      watch = await _waitUntilSeen(id, timeout);
    }
    if (watch == null) {
      throw StateError('$id was not found nearby. Check it is on and charged.');
    }
    await connect(watch);
  }

  WovenWatch? _seen(String id) {
    final watch = _watches[id];
    if (_simulated.contains(id)) return watch;
    return watch?.device != null ? watch : null;
  }

  Future<WovenWatch?> _waitUntilSeen(String id, Duration timeout) async {
    if (_seen(id) case final watch?) return watch;
    final done = Completer<WovenWatch?>();
    void check() {
      if (_seen(id) case final watch? when !done.isCompleted) {
        done.complete(watch);
      }
    }

    addListener(check);
    final timer = Timer(timeout, () {
      if (!done.isCompleted) done.complete(_seen(id));
    });
    try {
      return await done.future;
    } finally {
      removeListener(check);
      timer.cancel();
    }
  }

  Future<void> connect(WovenWatch watch) async {
    if (_simulated.contains(watch.id)) {
      watch.isConnected = true;
      notifyListeners();
      return;
    }
    final device = watch.device;
    if (device == null) {
      throw StateError('${watch.id} has not been seen in a scan yet.');
    }
    if (watch.isConnected || watch.isConnecting) return;

    watch.isConnecting = true;
    notifyListeners();
    try {
      await FlutterBluePlus.stopScan(); //scanning while connecting is flaky
      await device.connect(license: License.nonprofit);

      await watch._stateSub?.cancel();
      watch._stateSub = device.connectionState.listen((state) {
        if (state == BluetoothConnectionState.disconnected) {
          watch.isConnected = false;
          watch._dataSub?.cancel();
          watch._dataSub = null;
          notifyListeners();
        }
      });

      final services = await device.discoverServices();
      BluetoothCharacteristic? txChar;
      for (final service in services) {
        for (final characteristic in service.characteristics) {
          if (characteristic.uuid == uartTxCharUuid) {
            txChar = characteristic;
          }
        }
      }
      if (txChar == null) {
        await device.disconnect();
        throw StateError(
          '${watch.id} does not expose the WovenWatch data stream.',
        );
      }

      await watch._dataSub?.cancel();
      watch._dataSub = txChar.onValueReceived.listen(
        (bytes) => _onData(watch, bytes),
      );
      await _enableNotifications(txChar);

      watch.isConnected = true;
      watch.fidgetingTime = Duration.zero; //fresh session
      watch.prediction = null;
      watch.predictionAt = null;
    } finally {
      watch.isConnecting = false;
      notifyListeners();
    }
  }

  Future<void> _enableNotifications(
    BluetoothCharacteristic characteristic,
  ) async {
    if (!kIsWeb) {
      await characteristic.setNotifyValue(true);
      return;
    }

    try {
      //flutter_blue_plus_web 7.0.2 waits for a CCCD event web bluetooth never
      //sends, so keep the timeout short and ignore just that one
      await characteristic.setNotifyValue(true, timeout: 1);
    } on FlutterBluePlusException catch (error) {
      final isWebCccdTimeout =
          error.function == 'setNotifyValue' &&
          error.code == FbpErrorCode.timeout.index;
      if (!isWebCccdTimeout) rethrow;

      debugPrint(
        'Web Bluetooth notifications started; ignored missing CCCD confirmation.',
      );
    }
  }

  Future<void> disconnect(WovenWatch watch) async {
    try {
      await watch.device?.disconnect();
    } finally {
      watch.isConnected = false;
      notifyListeners();
    }
  }

  //demo watches: no bluetooth, lines go through the same parser
  bool get isSimulating => _simulated.isNotEmpty;

  bool isSimulated(String id) => _simulated.contains(id);

  void addSimulatedWatches(Iterable<String> ids) {
    for (final id in ids) {
      _simulated.add(id);
      _watches[id] = WovenWatch(id: id)
        ..rssi = -58
        ..lastSeen = DateTime.now()
        ..isConnected = true;
    }
    notifyListeners();
  }

  void receiveSimulatedLine(String id, String line) {
    final watch = _watches[id];
    if (watch == null || !_simulated.contains(id) || !watch.isConnected) return;
    _onData(watch, utf8.encode('$line\n'));
  }

  void removeSimulatedWatches() {
    for (final id in _simulated) {
      _watches.remove(id);
    }
    _simulated.clear();
    notifyListeners();
  }

  //for tests
  @visibleForTesting
  void debugAddWatch(WovenWatch watch) {
    _watches[watch.id] = watch;
    notifyListeners();
  }

  //for tests
  @visibleForTesting
  void debugClearWatches() {
    _watches.clear();
    notifyListeners();
  }

  //for tests
  @visibleForTesting
  void debugReceiveBytes(WovenWatch watch, List<int> bytes) =>
      _onData(watch, bytes);

  void _onData(WovenWatch watch, List<int> bytes) {
    watch.lastSeen = DateTime.now();
    watch._lineBuffer += utf8.decode(bytes, allowMalformed: true);

    final lines = watch._lineBuffer.split('\n');
    watch._lineBuffer = lines.removeLast(); //keep trailing partial line

    for (final line in lines) {
      final trimmed = line.trim();
      final prediction = parsePredictionLine(trimmed);
      if (prediction != null) {
        watch.prediction = prediction;
        watch.predictionAt = DateTime.now();
        watch.lastVotes = parsePredictionVotes(trimmed);
        final label = fidgetLabelFromWire(prediction);
        if (label != null) {
          _predictions.add(
            PredictionEvent(
              watchId: watch.id,
              label: label,
              votes: watch.lastVotes,
              at: watch.predictionAt!,
            ),
          );
        }
        if (prediction != 'not_fidgeting') {
          watch.fidgetingTime += predictionInterval;
        }
      }
      //raw sensor lines just count as a heartbeat
    }
    notifyListeners();
  }
}
