import 'package:flutter_test/flutter_test.dart';
import 'package:trackapp/services/alert_engine.dart';
import 'package:trackapp/services/local_data_mover.dart';
import 'package:trackapp/services/watch_settings_service.dart';

void main() {
  //what the account already has in firebase
  final classes = {
    'room12': {
      'name': 'Room 12',
      'devices': {
        'w-a': {'deviceId': 'w-a'},
        'w-b': {'deviceId': 'w-b'},
      },
      'alertSettings': {
        'w-b': {
          'readingsInARow': 4,
          'repeatEverySeconds': 30,
          'minConfidence': 'off',
        },
      },
      'quiet': {'w-b': true},
    },
  };
  const two = AlertSettings(readingsInARow: 2);

  Map<String, Object?> paths({
    Map<String, AlertSettings> settings = const {},
    Set<String> quiet = const {},
    AlertSettings? localDefault,
    bool hasDefault = false,
  }) =>
      legacyMovePaths(
        classes: classes,
        hasDefault: hasDefault,
        localDefault: localDefault,
        localSettings: settings,
        localQuiet: quiet,
      );

  test('a watch in this account with nothing saved yet moves up', () {
    final out = paths(
      settings: {'room12/w-a': two},
      quiet: {'room12/w-a'},
    );
    expect(out.keys, {
      'classes/room12/alertSettings/w-a',
      'classes/room12/quiet/w-a',
    });
    expect((out['classes/room12/alertSettings/w-a'] as Map)['readingsInARow'], 2);
    expect(out['classes/room12/quiet/w-a'], true);
  });

  test('what the account already has wins', () {
    expect(paths(settings: {'room12/w-b': two}, quiet: {'room12/w-b'}), isEmpty);
  });

  test("another teacher's class or a removed watch is skipped", () {
    expect(
      paths(
        settings: {'otherTeacher/w-a': two, 'room12/w-gone': two},
        quiet: {'otherTeacher/w-a', 'bad-key'},
      ),
      isEmpty,
    );
  });

  test('the local default only moves if the account has none', () {
    expect(paths(localDefault: two).keys, ['prefs/defaultAlert']);
    expect(paths(localDefault: two, hasDefault: true), isEmpty);
  });

  test('nothing local, nothing to write', () {
    expect(paths(), isEmpty);
    expect(
      legacyMovePaths(
        classes: null,
        hasDefault: false,
        localDefault: null,
        localSettings: {'room12/w-a': two},
        localQuiet: const {},
      ),
      isEmpty,
      reason: 'an account with no classes takes no watch settings',
    );
  });

  test('old repeat times snap to the stops firebase allows', () {
    Duration snap(int secs) =>
        snapToStops(AlertSettings(repeatEvery: Duration(seconds: secs)))
            .repeatEvery;
    expect(snap(300), const Duration(seconds: 120));
    expect(snap(45), const Duration(seconds: 30));
    expect(snap(5), const Duration(seconds: 10));
    expect(snap(60), const Duration(seconds: 60));
  });
}
