import 'dart:async';

import 'package:trackapp/models/care_class.dart';
import 'package:trackapp/services/watch_ble_service.dart';

const demoClassId = 'demo-room-4';

//made-up students on made-up watches
const demoStudents = {
  'wwWatch-3C7E': 'Maya R.',
  'wwWatch-5B12': 'Leo T.',
  'wwWatch-7F40': 'Ava K.',
  'wwWatch-9D21': 'Sam P.',
  'wwWatch-A6E8': 'Noah B.',
};

CareClass demoClass() => CareClass(
  id: demoClassId,
  name: 'Room 4 (Demo)',
  colorHex: '#21BFAF',
  devices: [
    for (final e in demoStudents.entries)
      ClassDevice(deviceId: e.key, studentName: e.value),
  ],
  createdAt: 0,
  updatedAt: 0,
);

//one letter per reading, 2.5 s apart, 48 readings = 2 min loop.
//c calm, l/L low (4/5 votes), s low but only 3 of 5, h/H high (4/5 votes)
const demoPattern = {
  //high alert on reading 5 (~10 s)
  'wwWatch-3C7E': 'ccHHhHHHHhcccccccccccccccccccchHHHhHcccccccccccc',
  //low alert on reading 11 (~25 s)
  'wwWatch-5B12': 'ccccccccLlLLlLLlcccccccccccccccccccccclLlLLlcccc',
  //calm the whole time
  'wwWatch-7F40': 'cccckccccccckccccccckccccccccckccccccccckccccccc',
  //mostly 3 of 5: alerts with confidence off, not at 4 of 5
  'wwWatch-9D21': 'ccccccccccccccsslssslscccccccccccccslssslssccccc',
  //short bursts that only alert at 1 or 2 in a row, then a high run
  'wwWatch-A6E8': 'cccccchHcccccccclhccccccHhHHhHcccccccccccccccccc',
};

String demoLine(String code) => switch (code) {
  'c' => 'pred,not_fidgeting,5',
  'k' => 'pred,not_fidgeting,4',
  'l' => 'pred,low_fidgeting,4',
  'L' => 'pred,low_fidgeting,5',
  's' => 'pred,low_fidgeting,3',
  'h' => 'pred,high_fidgeting,4',
  'H' => 'pred,high_fidgeting,5',
  _ => throw ArgumentError.value(code, 'code'),
};

//sends each demo watch its next line every 2.5 s
class DemoFeed {
  DemoFeed({WatchBleService? ble}) : _ble = ble ?? WatchBleService.instance;

  final WatchBleService _ble;
  Timer? _timer;
  int _tick = 0;

  int get tick => _tick;

  void start() {
    _timer?.cancel();
    step(); //first reading right away
    _timer = Timer.periodic(predictionInterval, (_) => step());
  }

  void step() {
    demoPattern.forEach((id, pattern) {
      _ble.receiveSimulatedLine(id, demoLine(pattern[_tick % pattern.length]));
    });
    _tick++;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}
