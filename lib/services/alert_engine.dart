//N fidget readings in a row fires an alert. low confidence readings are skipped,
//and 7.5 s with no reading resets the run.
library;

const Duration predictionInterval = Duration(milliseconds: 2500);
const Duration silenceThreshold = Duration(milliseconds: 7500);

enum FidgetLabel { notFidgeting, lowFidgeting, highFidgeting }

enum AlertTag { low, high }

//min votes out of 5
enum ConfidenceStop {
  off(0, 'Off'),
  fourOfFive(4, '4 of 5'),
  fiveOfFive(5, '5 of 5');

  const ConfidenceStop(this.threshold, this.label);
  final int threshold;
  final String label;
}

FidgetLabel? fidgetLabelFromWire(String label) {
  switch (label) {
    case 'not_fidgeting':
      return FidgetLabel.notFidgeting;
    case 'low_fidgeting':
      return FidgetLabel.lowFidgeting;
    case 'high_fidgeting':
      return FidgetLabel.highFidgeting;
    default:
      return null;
  }
}

class AlertSettings {
  const AlertSettings({
    this.readingsInARow = 3,
    this.repeatEvery = const Duration(seconds: 60),
    this.minConfidence = ConfidenceStop.off,
  }) : assert(readingsInARow >= 1 && readingsInARow <= 4);

  //1..4
  final int readingsInARow;
  final Duration repeatEvery;
  final ConfidenceStop minConfidence;

  Duration get nominalRunDuration => predictionInterval * readingsInARow;

  AlertSettings copyWith({
    int? readingsInARow,
    Duration? repeatEvery,
    ConfidenceStop? minConfidence,
  }) {
    return AlertSettings(
      readingsInARow: readingsInARow ?? this.readingsInARow,
      repeatEvery: repeatEvery ?? this.repeatEvery,
      minConfidence: minConfidence ?? this.minConfidence,
    );
  }
}

class Reading {
  const Reading({required this.label, this.votes, required this.at});

  final FidgetLabel label;

  final int? votes;
  final DateTime at;
}

class AlertEvent {
  const AlertEvent({
    required this.tag,
    required this.at,
    required this.isRepeat,
    required this.highs,
    required this.lows,
    this.skipped = 0,
    this.span = Duration.zero,
  });

  final AlertTag tag;
  final DateTime at;
  final bool isRepeat;
  final int highs;
  final int lows;

  final int skipped;

  final Duration span;
}

class AlertEngine {
  AlertEngine({AlertSettings settings = const AlertSettings()})
      : _settings = settings;

  AlertSettings _settings;
  final List<FidgetLabel> _recent = [];
  final List<DateTime> _recentAt = []; //parallel to _recent
  final List<DateTime> _skippedAt = []; //this run's skipped readings
  int _runLength = 0;
  int _skippedInRun = 0;
  bool _alertedInRun = false;
  bool _suppressionCounted = false;
  int _suppressions = 0;
  DateTime? _lastArrivalAt;
  DateTime? _lastAlertAt;
  String _lastDecision = '—';

  AlertSettings get settings => _settings;

  set settings(AlertSettings value) {
    _settings = value;
    _trimRecent(value.readingsInARow);
  }

  int get runLength => _runLength;
  int get skippedInRun => _skippedInRun;
  List<FidgetLabel> get recent => List.unmodifiable(_recent);
  DateTime? get lastAlertAt => _lastAlertAt;
  DateTime? get lastArrivalAt => _lastArrivalAt;

  bool get alertedInRun => _alertedInRun;

  //runs that hit the rule while waiting to repeat
  int get suppressions => _suppressions;

  String get lastDecision => _lastDecision;

  void _trimRecent(int n) {
    if (_recent.length <= n) return;
    _recent.removeRange(0, _recent.length - n);
    _recentAt.removeRange(0, _recentAt.length - n);
  }

  void resetRun() {
    _recent.clear();
    _recentAt.clear();
    _skippedAt.clear();
    _runLength = 0;
    _skippedInRun = 0;
    _alertedInRun = false;
    _suppressionCounted = false;
  }

  AlertEvent? ingest(Reading r) {
    //no reading for too long resets the run
    String? silencePrefix;
    final lastArrival = _lastArrivalAt;
    if (lastArrival != null) {
      final gap = r.at.difference(lastArrival);
      if (gap > silenceThreshold) {
        resetRun();
        final seconds = (gap.inMilliseconds / 1000).round();
        silencePrefix = 'run reset — no reading for $seconds s';
      }
    }
    _lastArrivalAt = r.at;

    String decide(String outcome) => _lastDecision =
        silencePrefix == null ? outcome : '$silencePrefix; then $outcome';

    //low confidence: skip it
    final stop = _settings.minConfidence;
    final votes = r.votes;
    if (stop != ConfidenceStop.off && votes != null && votes < stop.threshold) {
      _skippedInRun++;
      _skippedAt.add(r.at);
      decide('skipped — below ${stop.label}');
      return null;
    }

    //calm breaks the run
    if (r.label == FidgetLabel.notFidgeting) {
      resetRun();
      decide('run broken by calm');
      return null;
    }

    final n = _settings.readingsInARow;
    _recent.add(r.label);
    _recentAt.add(r.at);
    _trimRecent(n);
    _runLength++;

    if (_runLength < n) {
      decide('run advanced');
      return null;
    }

    //fire unless still waiting to repeat
    final lastAlert = _lastAlertAt;
    if (lastAlert != null && r.at.difference(lastAlert) < _settings.repeatEvery) {
      if (!_suppressionCounted) {
        _suppressionCounted = true;
        _suppressions++;
      }
      decide('run advanced — repeat not due yet');
      return null;
    }

    final highs = _recent.where((l) => l == FidgetLabel.highFidgeting).length;
    final lows = _recent.length - highs;
    final event = AlertEvent(
      tag: highs * 2 >= _recent.length ? AlertTag.high : AlertTag.low,
      at: r.at,
      isRepeat: _alertedInRun,
      highs: highs,
      lows: lows,
      skipped: _skippedAt.where((t) => t.isAfter(_recentAt.first)).length,
      span: r.at.difference(_recentAt.first) + predictionInterval,
    );
    _lastAlertAt = r.at;
    _alertedInRun = true;
    decide('ALERT fired');
    return event;
  }
}
