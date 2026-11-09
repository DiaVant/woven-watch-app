import 'package:flutter_test/flutter_test.dart';
import 'package:trackapp/services/alert_engine.dart';
import 'package:trackapp/services/local_store.dart';
import 'package:trackapp/services/session_stats.dart';

final t0 = DateTime(2026, 10, 11, 9, 5);

const calm = FidgetLabel.notFidgeting;
const low = FidgetLabel.lowFidgeting;
const high = FidgetLabel.highFidgeting;

/// Readings every 2.5 s from [from] seconds after t0.
List<StoredReading> run(double from, List<FidgetLabel> labels) => [
      for (var i = 0; i < labels.length; i++)
        StoredReading(
          at: t0.add(Duration(milliseconds: ((from + 2.5 * i) * 1000).round())),
          label: labels[i],
          votes: 5,
        ),
    ];

StoredSession session(List<StoredReading> readings,
        {List<StoredAlert>? alerts, double? endedAfter}) =>
    StoredSession(
      classId: 'c',
      deviceId: 'w',
      startedAt: t0,
      endedAt: endedAfter == null
          ? null
          : t0.add(Duration(milliseconds: (endedAfter * 1000).round())),
      readings: readings,
      alerts: alerts,
    );

DateTime at(double seconds) =>
    t0.add(Duration(milliseconds: (seconds * 1000).round()));

void main() {
  group('timeline', () {
    test('same-label readings merge into one stretch', () {
      final s = session(run(0, [calm, calm, high, high, high, calm]),
          endedAfter: 15);
      final kinds = buildTimeline(s, at(15)).map((g) => g.kind).toList();
      expect(kinds,
          [TimelineKind.calm, TimelineKind.high, TimelineKind.calm]);
    });

    test('a gap over 7.5 s is no signal; 7.5 s or less is not', () {
      final readings = [
        ...run(0, [calm, calm]), //0, 2.5
        ...run(10, [calm]), //7.5 s gap: still continuous
        ...run(30, [low]), //20 s gap: no signal
      ];
      final segs = buildTimeline(session(readings, endedAfter: 32.5), at(32.5));
      expect(segs.map((g) => g.kind), [
        TimelineKind.calm,
        TimelineKind.noSignal,
        TimelineKind.low,
      ]);
      // the calm stretch covers its last reading's 2.5 s, then signal drops
      expect(segs[0].end, at(12.5));
      expect(segs[1].start, at(12.5));
      expect(segs[1].end, at(30));
    });

    test('a long wait before the first reading is no signal', () {
      final segs = buildTimeline(
          session(run(20, [calm]), endedAfter: 22.5), at(22.5));
      expect(segs.first.kind, TimelineKind.noSignal);
      expect(segs.first.end, at(20));
    });

    test('silence after the last reading of an open session', () {
      final segs = buildTimeline(session(run(0, [high])), at(60));
      expect(segs.map((g) => g.kind),
          [TimelineKind.high, TimelineKind.noSignal]);
      expect(segs.last.end, at(60));
    });

    test('an empty open session is all no signal once past the threshold',
        () {
      expect(buildTimeline(session([]), at(5)), isEmpty);
      expect(buildTimeline(session([]), at(60)).single.kind,
          TimelineKind.noSignal);
    });
  });

  group('stats', () {
    test('time per state is readings × 2.5 s', () {
      final stats = computeSessionStats(
        session(run(0, [calm, calm, calm, low, high, high]), endedAfter: 15),
        at(15),
      );
      expect(stats.calm, const Duration(milliseconds: 7500));
      expect(stats.low, const Duration(milliseconds: 2500));
      expect(stats.high, const Duration(seconds: 5));
    });

    test('longest fidget counts low and high together', () {
      final stats = computeSessionStats(
        session(run(0, [low, high, low, calm, high, high]), endedAfter: 15),
        at(15),
      );
      expect(stats.longestFidget, const Duration(milliseconds: 7500));
    });

    test('silence over 7.5 s also ends a fidget run', () {
      final readings = [
        ...run(0, [high, high]),
        ...run(20, [high, high]), //12.5 s after the last: a new run
      ];
      final stats =
          computeSessionStats(session(readings, endedAfter: 25), at(25));
      expect(stats.longestFidget, const Duration(seconds: 5));
    });

    test('alerts split high and low', () {
      final stats = computeSessionStats(
        session(run(0, [high]), alerts: [
          StoredAlert(at: at(1), tag: AlertTag.high),
          StoredAlert(at: at(2), tag: AlertTag.low),
          StoredAlert(at: at(3), tag: AlertTag.high),
        ], endedAfter: 5),
        at(5),
      );
      expect(stats.alerts, 3);
      expect(stats.highAlerts, 2);
      expect(stats.lowAlerts, 1);
    });

    test('received readings is received ÷ expected, capped at 100%', () {
      // 100 s expects 40 readings; 30 arrived
      final readings = run(0, List.filled(30, calm));
      final stats =
          computeSessionStats(session(readings, endedAfter: 100), at(100));
      expect(stats.receivedFraction, closeTo(0.75, 0.001));

      final crowded = computeSessionStats(
          session(run(0, List.filled(50, calm)), endedAfter: 100), at(100));
      expect(crowded.receivedFraction, 1.0);
    });
  });
}
