import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trackapp/services/alert_engine.dart';
import 'package:trackapp/services/watch_ble_service.dart';

void main() {
  group('parsePredictionLine', () {
    test('parses the original two-field message', () {
      expect(parsePredictionLine('pred,low_fidgeting'), 'low_fidgeting');
    });

    test('ignores metadata appended by newer firmware', () {
      expect(parsePredictionLine('pred,not_fidgeting,5'), 'not_fidgeting');
    });

    test('rejects sensor samples and missing labels', () {
      expect(parsePredictionLine('12.3,1,2,3,4,5,6'), isNull);
      expect(parsePredictionLine('pred,'), isNull);
    });
  });
  group('parsePredictionVotes', () {
    test('reads the third field as the vote count', () {
      expect(parsePredictionVotes('pred,high_fidgeting,4'), 4);
    });

    test('rejects counts outside 0..K', () {
      expect(parsePredictionVotes('pred,high_fidgeting,6'), isNull);
      expect(parsePredictionVotes('pred,high_fidgeting,-1'), isNull);
      expect(parsePredictionVotes('pred,high_fidgeting,5'), knnK);
    });

    test('is null for old two-field lines and garbage', () {
      expect(parsePredictionVotes('pred,high_fidgeting'), isNull);
      expect(parsePredictionVotes('pred,high_fidgeting,x'), isNull);
      expect(parsePredictionVotes('12.3,1,2,3,4,5,6'), isNull);
    });
  });

  group('UART byte stream', () {
    TestWidgetsFlutterBinding.ensureInitialized();

    late WatchBleService service;
    late WovenWatch watch;
    late List<PredictionEvent> events;

    setUp(() {
      service = WatchBleService.instance;
      watch = WovenWatch(id: 'wwWatch-TEST');
      events = [];
    });

    /// Sends [chunks] as separate BLE packets; returns the events emitted.
    Future<List<PredictionEvent>> send(List<String> chunks) async {
      final sub = service.predictions.listen(events.add);
      for (final chunk in chunks) {
        service.debugReceiveBytes(watch, utf8.encode(chunk));
      }
      await Future<void>.delayed(Duration.zero); //broadcast delivery is async
      await sub.cancel();
      return events;
    }

    test('three-field line carries the vote count', () async {
      final got = await send(['pred,high_fidgeting,4\n']);
      expect(got, hasLength(1));
      expect(got.single.watchId, 'wwWatch-TEST');
      expect(got.single.label, FidgetLabel.highFidgeting);
      expect(got.single.votes, 4);
      expect(watch.prediction, 'high_fidgeting');
      expect(watch.lastVotes, 4);
    });

    test('two-field line from old firmware has null votes', () async {
      final got = await send(['pred,low_fidgeting\n']);
      expect(got.single.label, FidgetLabel.lowFidgeting);
      expect(got.single.votes, isNull);
      expect(watch.lastVotes, isNull);
    });

    test('a line split across two packets is parsed once, whole', () async {
      final got = await send(['pred,not_fidg', 'eting,5\n']);
      expect(got, hasLength(1));
      expect(got.single.label, FidgetLabel.notFidgeting);
      expect(got.single.votes, 5);
    });

    test('nothing is emitted until the line ends', () async {
      final got = await send(['pred,high_fidgeting,5']);
      expect(got, isEmpty);
      expect(watch.prediction, isNull);
    });

    test('malformed lines are dropped without crashing', () async {
      final got = await send([
        'pred,\n',
        'pred\n',
        'pred,banana,4\n',
        'pred,high_fidgeting,lots\n',
        ',,,\n',
        '\n',
      ]);
      // only the known label survives; its bad vote count becomes null
      expect(got, hasLength(1));
      expect(got.single.label, FidgetLabel.highFidgeting);
      expect(got.single.votes, isNull);
    });

    test('raw sample lines are a heartbeat only', () async {
      final before = watch.lastSeen;
      final got = await send(['12345,0.01,-0.02,9.81,0.1,0.2,0.3\n']);
      expect(got, isEmpty);
      expect(watch.prediction, isNull);
      expect(watch.lastSeen, isNot(before));
    });

    test('several lines in one packet each emit, in order', () async {
      final got = await send([
        '1,0,0,9.8,0,0,0\npred,low_fidgeting,3\npred,high_fidgeting,5\n',
      ]);
      expect(got.map((e) => e.label),
          [FidgetLabel.lowFidgeting, FidgetLabel.highFidgeting]);
      expect(got.map((e) => e.votes), [3, 5]);
    });
  });
}
