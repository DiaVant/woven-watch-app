import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trackapp/services/alert_engine.dart';
import 'package:trackapp/services/alert_manager.dart';
import 'package:trackapp/services/watch_ble_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final manager = AlertManager.instance;

  // The manager is a singleton, so each test uses its own class/watch ids.

  test('the same watch keeps separate settings per class', () {
    manager.setSettings(
      'room12',
      'wwWatch-CART',
      const AlertSettings(readingsInARow: 2),
    );
    expect(manager.settingsFor('room12', 'wwWatch-CART').readingsInARow, 2);
    expect(
      manager.settingsFor('art', 'wwWatch-CART').readingsInARow,
      AlertManager.defaultSettings.readingsInARow,
    );
  });

  test('readings and alerts in one class do not touch the other', () {
    for (var i = 0; i < 3; i++) {
      manager.inject('classA', 'wwWatch-SHARE', FidgetLabel.highFidgeting);
    }
    expect(manager.engineFor('classA', 'wwWatch-SHARE').runLength, 3);
    expect(manager.alertCountFor('classA'), 1);
    expect(manager.logFor('classA', 'wwWatch-SHARE'), hasLength(1));

    expect(manager.lastReadingFor('classB', 'wwWatch-SHARE'), isNull);
    expect(manager.engineFor('classB', 'wwWatch-SHARE').runLength, 0);
    expect(manager.alertCountFor('classB'), 0);
    expect(manager.logFor('classB', 'wwWatch-SHARE'), isEmpty);
  });

  group('live readings', () {
    final ble = WatchBleService.instance;

    Future<void> send(String watchId, String line) async {
      ble.debugReceiveBytes(WovenWatch(id: watchId), utf8.encode('$line\n'));
      await Future<void>.delayed(Duration.zero); //broadcast delivery is async
    }

    test('go to the open class only', () async {
      manager.viewClass('open', ['wwWatch-LIVE']);
      await send('wwWatch-LIVE', 'pred,high_fidgeting,4');
      manager.leaveClass('open');

      final reading = manager.lastReadingFor('open', 'wwWatch-LIVE');
      expect(reading?.label, FidgetLabel.highFidgeting);
      expect(reading?.votes, 4);
      expect(manager.lastReadingFor('closed', 'wwWatch-LIVE'), isNull);
    });

    test('are dropped when no class is open', () async {
      manager.viewClass('gone', ['wwWatch-IDLE']);
      manager.leaveClass('gone');
      await send('wwWatch-IDLE', 'pred,high_fidgeting,5');
      expect(manager.lastReadingFor('gone', 'wwWatch-IDLE'), isNull);
    });

    test('are dropped for a watch not on the open roster', () async {
      manager.viewClass('roster', ['wwWatch-IN']);
      await send('wwWatch-OUT', 'pred,low_fidgeting,5');
      manager.leaveClass('roster');
      expect(manager.lastReadingFor('roster', 'wwWatch-OUT'), isNull);
    });

    test('leaving a different class does not close the open one', () async {
      manager.viewClass('second', ['wwWatch-KEEP']);
      manager.leaveClass('first');
      await send('wwWatch-KEEP', 'pred,low_fidgeting,5');
      manager.leaveClass('second');
      expect(manager.lastReadingFor('second', 'wwWatch-KEEP'), isNotNull);
    });
  });
}
