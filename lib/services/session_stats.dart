import 'package:trackapp/services/alert_engine.dart';
import 'package:trackapp/services/local_store.dart';

enum TimelineKind { calm, low, high, noSignal }

class TimelineSegment {
  const TimelineSegment(this.kind, this.start, this.end);

  final TimelineKind kind;
  final DateTime start;
  final DateTime end;
}

TimelineKind _kindOf(FidgetLabel label) => switch (label) {
      FidgetLabel.notFidgeting => TimelineKind.calm,
      FidgetLabel.lowFidgeting => TimelineKind.low,
      FidgetLabel.highFidgeting => TimelineKind.high,
    };

DateTime sessionEnd(StoredSession session, DateTime now) =>
    session.endedAt ?? now;

//gaps over 7.5 s count as no signal
List<TimelineSegment> buildTimeline(StoredSession session, DateTime now) {
  final start = session.startedAt;
  final end = sessionEnd(session, now);
  final readings = [...session.readings]..sort((a, b) => a.at.compareTo(b.at));
  final raw = <TimelineSegment>[];

  if (readings.isEmpty) {
    if (end.difference(start) > silenceThreshold) {
      raw.add(TimelineSegment(TimelineKind.noSignal, start, end));
    }
    return raw;
  }

  if (readings.first.at.difference(start) > silenceThreshold) {
    raw.add(TimelineSegment(TimelineKind.noSignal, start, readings.first.at));
  }
  for (var i = 0; i < readings.length; i++) {
    final r = readings[i];
    final next = i + 1 < readings.length ? readings[i + 1].at : end;
    final gap = next.difference(r.at);
    final last = i + 1 == readings.length;
    if (gap <= silenceThreshold) {
      raw.add(TimelineSegment(_kindOf(r.label), r.at, next));
    } else {
      final covered = r.at.add(predictionInterval);
      raw.add(TimelineSegment(_kindOf(r.label), r.at, covered));
      //a gap at the end of an open session only counts once it's past the threshold
      raw.add(TimelineSegment(TimelineKind.noSignal, covered, next));
    }
    if (last) break;
  }

  final merged = <TimelineSegment>[];
  for (final seg in raw) {
    if (!seg.end.isAfter(seg.start)) continue;
    if (merged.isNotEmpty && merged.last.kind == seg.kind) {
      merged[merged.length - 1] =
          TimelineSegment(seg.kind, merged.last.start, seg.end);
    } else {
      merged.add(seg);
    }
  }
  return merged;
}

class SessionStats {
  const SessionStats({
    required this.calm,
    required this.low,
    required this.high,
    required this.longestFidget,
    required this.highAlerts,
    required this.lowAlerts,
    required this.receivedFraction,
    required this.elapsed,
  });

  final Duration calm;
  final Duration low;
  final Duration high;

  final Duration longestFidget;
  final int highAlerts;
  final int lowAlerts;

  final double receivedFraction;
  final Duration elapsed;

  int get alerts => highAlerts + lowAlerts;
}

SessionStats computeSessionStats(StoredSession session, DateTime now) {
  final readings = [...session.readings]..sort((a, b) => a.at.compareTo(b.at));
  var calm = 0, low = 0, high = 0;
  var run = 0, longest = 0;
  DateTime? previous;
  for (final r in readings) {
    switch (r.label) {
      case FidgetLabel.notFidgeting:
        calm++;
      case FidgetLabel.lowFidgeting:
        low++;
      case FidgetLabel.highFidgeting:
        high++;
    }
    final silent =
        previous != null && r.at.difference(previous) > silenceThreshold;
    if (r.label == FidgetLabel.notFidgeting) {
      run = 0;
    } else {
      run = silent ? 1 : run + 1;
      if (run > longest) longest = run;
    }
    previous = r.at;
  }

  final elapsed = sessionEnd(session, now).difference(session.startedAt);
  final expected =
      elapsed.inMilliseconds / predictionInterval.inMilliseconds;
  final received = expected < 1
      ? (readings.isEmpty ? 0.0 : 1.0)
      : (readings.length / expected).clamp(0.0, 1.0);

  return SessionStats(
    calm: predictionInterval * calm,
    low: predictionInterval * low,
    high: predictionInterval * high,
    longestFidget: predictionInterval * longest,
    highAlerts: session.alerts.where((a) => a.tag == AlertTag.high).length,
    lowAlerts: session.alerts.where((a) => a.tag == AlertTag.low).length,
    receivedFraction: received.toDouble(),
    elapsed: elapsed,
  );
}
