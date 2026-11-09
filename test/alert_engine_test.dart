import 'package:flutter_test/flutter_test.dart';
import 'package:trackapp/services/alert_engine.dart';

const calm = FidgetLabel.notFidgeting;
const low = FidgetLabel.lowFidgeting;
const high = FidgetLabel.highFidgeting;

final t0 = DateTime(2026, 10, 4, 9);

/// Feeds readings 2.5 s apart; returns the events that fired.
class Feeder {
  Feeder(this.engine);

  final AlertEngine engine;
  DateTime at = t0;
  bool _first = true;

  AlertEvent? feed(FidgetLabel label, {int? votes, Duration? gap}) {
    if (!_first) at = at.add(gap ?? predictionInterval);
    _first = false;
    return engine.ingest(Reading(label: label, votes: votes, at: at));
  }

  List<AlertEvent> feedAll(List<FidgetLabel> labels, {int? votes}) => [
        for (final l in labels) feed(l, votes: votes),
      ].whereType<AlertEvent>().toList();
}

void main() {
  test('N in a row fires exactly one alert; N-1 fires none', () {
    final f = Feeder(AlertEngine());
    expect(f.feedAll([high, high]), isEmpty);
    expect(f.engine.runLength, 2);

    final events = f.feedAll([high]);
    expect(events, hasLength(1));
    expect(events.single.isRepeat, isFalse);
    expect(f.engine.lastDecision, 'ALERT fired');

    // continuing inside the default 60 s repeat window fires nothing more
    expect(f.feedAll([high, high, high]), isEmpty);
  });

  test('tag is the majority of the last N', () {
    final f = Feeder(AlertEngine());
    final events = f.feedAll([high, low, low]);
    expect(events.single.tag, AlertTag.low);
    expect(events.single.highs, 1);
    expect(events.single.lows, 2);

    final g = Feeder(AlertEngine());
    expect(g.feedAll([low, high, high]).single.tag, AlertTag.high);
  });

  test('a 2-2 tie tags high', () {
    final f = Feeder(
      AlertEngine(settings: const AlertSettings(readingsInARow: 4)),
    );
    final event = f.feedAll([low, high, low, high]).single;
    expect(event.highs, 2);
    expect(event.lows, 2);
    expect(event.tag, AlertTag.high);
  });

  test('a calm reading resets the run', () {
    final f = Feeder(AlertEngine());
    expect(f.feedAll([high, high, calm, high, high]), isEmpty);
    expect(f.engine.runLength, 2);
    f.feed(calm);
    expect(f.engine.lastDecision, 'run broken by calm');
    expect(f.engine.runLength, 0);
    expect(f.engine.recent, isEmpty);
  });

  test('a sub-threshold reading is skipped: neither advances nor breaks', () {
    final f = Feeder(
      AlertEngine(
        settings: const AlertSettings(minConfidence: ConfidenceStop.fourOfFive),
      ),
    );
    f.feed(high, votes: 5);
    f.feed(high, votes: 4);
    expect(f.engine.runLength, 2);

    expect(f.feed(high, votes: 3), isNull);
    expect(f.engine.runLength, 2);
    expect(f.engine.recent, [high, high]);
    expect(f.engine.skippedInRun, 1);
    expect(f.engine.lastDecision, 'skipped — below 4 of 5');

    // a sub-threshold calm does not break the run either
    expect(f.feed(calm, votes: 3), isNull);
    expect(f.engine.runLength, 2);
    expect(f.engine.skippedInRun, 2);

    expect(f.feed(high, votes: 5), isNotNull);
  });

  test('five-of-five stop skips a 4-vote reading', () {
    final f = Feeder(
      AlertEngine(
        settings: const AlertSettings(minConfidence: ConfidenceStop.fiveOfFive),
      ),
    );
    f.feed(high, votes: 4);
    expect(f.engine.runLength, 0);
    expect(f.engine.skippedInRun, 1);
  });

  test('votes == null always passes the confidence stop', () {
    final f = Feeder(
      AlertEngine(
        settings: const AlertSettings(minConfidence: ConfidenceStop.fiveOfFive),
      ),
    );
    expect(f.feedAll([high, high, high]), hasLength(1));
    expect(f.engine.skippedInRun, 0);
  });

  test('silence > 7.5 s resets the run; 7.4 s does not', () {
    final f = Feeder(AlertEngine());
    f.feed(high);
    f.feed(high);
    expect(
      f.feed(high, gap: const Duration(milliseconds: 7400)),
      isNotNull,
    );

    final g = Feeder(AlertEngine());
    g.feed(high);
    g.feed(high);
    expect(g.feed(high, gap: const Duration(milliseconds: 7600)), isNull);
    expect(g.engine.runLength, 1);
    expect(g.engine.lastDecision, startsWith('run reset — no reading for 8 s'));
  });

  test('skipped readings are arrivals, so a skipped stretch is not silence',
      () {
    final f = Feeder(
      AlertEngine(
        settings: const AlertSettings(minConfidence: ConfidenceStop.fourOfFive),
      ),
    );
    f.feed(high, votes: 5);
    f.feed(high, votes: 5);
    for (var i = 0; i < 5; i++) {
      f.feed(high, votes: 3); //12.5 s of skipped readings
    }
    expect(f.engine.runLength, 2);
    expect(f.feed(high, votes: 5), isNotNull);
  });

  test('inside repeatEvery nothing fires; one reading past it, a repeat fires',
      () {
    final f = Feeder(
      AlertEngine(
        settings: const AlertSettings(repeatEvery: Duration(seconds: 10)),
      ),
    );
    final first = f.feedAll([high, high, high]).single; //fires at +5 s
    expect(first.at, t0.add(const Duration(seconds: 5)));

    // +7.5, +10, +12.5: within 10 s of the alert
    expect(f.feedAll([high, high, high]), isEmpty);
    expect(f.engine.lastAlertAt, first.at);

    // +15: exactly 10 s later, the repeat fires
    final repeat = f.feed(high);
    expect(repeat, isNotNull);
    expect(repeat!.isRepeat, isTrue);
    expect(repeat.at.difference(first.at), const Duration(seconds: 10));
  });

  test('resetRun does not clear lastAlertAt', () {
    final f = Feeder(AlertEngine());
    f.feedAll([high, high, high]);
    final alertAt = f.engine.lastAlertAt;
    f.feed(calm);
    expect(f.engine.lastAlertAt, alertAt);
    // a fresh run inside the window waits for it
    expect(f.feedAll([high, high, high]), isEmpty);
  });

  test('a repeat re-decides the tag: a run that started high can repeat LOW',
      () {
    final f = Feeder(
      AlertEngine(
        settings: const AlertSettings(repeatEvery: Duration(seconds: 10)),
      ),
    );
    final first = f.feedAll([high, high, high]).single;
    expect(first.tag, AlertTag.high);

    final events = f.feedAll([high, low, low, low]);
    expect(events, hasLength(1));
    expect(events.single.isRepeat, isTrue);
    expect(events.single.tag, AlertTag.low);
    expect(events.single.lows, 3);
  });

  test('shrinking N applies to the running engine', () {
    final engine = AlertEngine();
    final f = Feeder(engine);
    f.feedAll([high, high]);
    engine.settings = engine.settings.copyWith(readingsInARow: 1);
    expect(engine.recent, [high]);
    expect(f.feed(low)!.tag, AlertTag.low);
  });

  test('nominalRunDuration is 2.5 s x N', () {
    expect(const AlertSettings().nominalRunDuration,
        const Duration(milliseconds: 7500));
  });

  test('suppression is counted once per run, not once per reading', () {
    final f = Feeder(AlertEngine()); //repeat 60 s
    f.feedAll([high, high, high]); //fires
    expect(f.engine.suppressions, 0);

    f.feedAll([high, high, high, high, high]); //5 gated readings, one run
    expect(f.engine.suppressions, 1);

    f.feed(calm);
    f.feedAll([low, low, low, low]); //new run, still inside the window
    expect(f.engine.suppressions, 2);
  });

  //traced at N=3, repeat 60 s, stop 4 of 5
  test('reproduces the AlertRule.png trace', () {
    final engine = AlertEngine(
      settings: const AlertSettings(
        readingsInARow: 3,
        repeatEvery: Duration(seconds: 60),
        minConfidence: ConfidenceStop.fourOfFive,
      ),
    );

    // (seconds after t0, label, votes, expected run, expected tag or null)
    final rows = <(double, FidgetLabel, int, int, AlertTag?)>[
      (0.0, calm, 5, 0, null),
      (2.5, high, 5, 1, null), //run starts
      (5.0, high, 4, 2, null),
      (7.5, low, 3, 2, null), //skipped, run unchanged
      (10.0, high, 5, 3, AlertTag.high), //HIGH ALERT, 3 of 3
      (12.5, low, 4, 4, null), //repeat opens at +70.0 s
      (15.0, calm, 5, 0, null), //run broken
      (17.5, low, 5, 1, null), //run restarts
      (20.0, low, 4, 2, null),
      (22.5, high, 4, 3, null), //rule met, wait 47 s
      // ⋮ fidgeting continues: +25.0 .. +62.5, all above the stop
      for (var i = 0; i < 16; i++)
        (25.0 + 2.5 * i, i.isEven ? low : high, 4 + i % 2, 4 + i, null),
      (65.0, low, 5, 20, null),
      (67.5, high, 4, 21, null),
      (70.0, low, 5, 22, AlertTag.low), //LOW ALERT, 2 low 1 high
    ];

    final fired = <AlertEvent>[];
    for (final (seconds, label, votes, run, tag) in rows) {
      final at = t0.add(Duration(milliseconds: (seconds * 1000).round()));
      final event =
          engine.ingest(Reading(label: label, votes: votes, at: at));
      expect(engine.runLength, run, reason: 'run at +${seconds}s');
      expect(event?.tag, tag, reason: 'alert at +${seconds}s');
      if (event != null) fired.add(event);

      if (seconds == 7.5) {
        expect(engine.skippedInRun, 1);
        expect(engine.lastDecision, 'skipped — below 4 of 5');
      }
      if (seconds == 12.5) {
        // repeat window opens 60 s after the +10.0 s alert
        expect(engine.lastAlertAt!.add(engine.settings.repeatEvery),
            t0.add(const Duration(seconds: 70)));
      }
      if (seconds == 15.0) expect(engine.lastDecision, 'run broken by calm');
    }

    expect(fired, hasLength(2));
    // three-in-a-row spanned +2.5 .. +10.0 s = 10 s, past 7.5 s, via the skip
    expect(fired[0].highs, 3);
    expect(fired[0].lows, 0);
    expect(fired[1].lows, 2);
    expect(fired[1].highs, 1);
    expect(fired[1].at.difference(fired[0].at), const Duration(seconds: 60));
    // gated once in the first run (+12.5) and once in the second (+22.5)
    expect(engine.suppressions, 2);
  });

  test('an alert reports the skips inside it and how long it spanned', () {
    final f = Feeder(
      AlertEngine(
        settings: const AlertSettings(minConfidence: ConfidenceStop.fourOfFive),
      ),
    );
    //3 counted readings around 4 skipped ones
    f.feed(low, votes: 5);
    f.feed(low, votes: 3);
    f.feed(high, votes: 3);
    f.feed(low, votes: 5);
    f.feed(low, votes: 3);
    f.feed(high, votes: 3);
    final event = f.feed(high, votes: 4)!;
    expect(event.skipped, 4);
    expect(event.span, const Duration(milliseconds: 17500));
    expect(event.lows, 2);
    expect(event.highs, 1);

    // no skips: N readings span N × 2.5 s
    final g = Feeder(AlertEngine());
    final plain = g.feedAll([high, high, high]).single;
    expect(plain.skipped, 0);
    expect(plain.span, const Duration(milliseconds: 7500));
  });

  test('skips before the counted readings are not in the span', () {
    final f = Feeder(
      AlertEngine(
        settings: const AlertSettings(
          readingsInARow: 2,
          repeatEvery: Duration(seconds: 10),
          minConfidence: ConfidenceStop.fourOfFive,
        ),
      ),
    );
    f.feed(high, votes: 5); //+0.0
    f.feed(high, votes: 3); //+2.5 skipped
    final first = f.feed(high, votes: 5)!; //+5.0 fires, window +0.0..+5.0
    expect(first.skipped, 1);
    expect(first.span, const Duration(milliseconds: 7500));

    f.feed(high, votes: 3); //+7.5 skipped, before the next window
    f.feed(high, votes: 5); //+10.0 gated
    f.feed(high, votes: 5); //+12.5 gated
    final repeat = f.feed(high, votes: 5)!; //+15.0 repeats, window +12.5..
    expect(repeat.isRepeat, isTrue);
    expect(repeat.skipped, 0);
    expect(repeat.span, const Duration(seconds: 5));
  });
}
