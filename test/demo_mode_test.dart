import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackapp/demo/demo_mode.dart';
import 'package:trackapp/demo/demo_script.dart';
import 'package:trackapp/services/alert_engine.dart';
import 'package:trackapp/pages/init_page.dart';
import 'package:trackapp/services/alert_manager.dart';
import 'package:trackapp/services/local_store.dart';
import 'package:trackapp/services/watch_ble_service.dart';

const maya = 'wwWatch-3C7E';
const leo = 'wwWatch-5B12';
const ava = 'wwWatch-7F40';
const sam = 'wwWatch-9D21';

//steps the script by hand instead of waiting on the timer
Future<void> feedTo(int readings) async {
  final f = DemoMode.feed!;
  while (f.tick < readings) {
    f.step();
    await pumpEventQueue(); //predictions arrive async
  }
}

List<AlertTag> tags(String id) =>
    AlertManager.instance
        .logFor(demoClassId, id)
        .map((e) => e.event.tag)
        .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('script', () {
    setUp(() {
      DemoMode.start(); //sends reading 1 right away
      DemoMode.feed!.stop();
      AlertManager.instance.viewClass(demoClassId, demoStudents.keys);
    });
    tearDown(DemoMode.exit);

    test('every pattern is the same length', () {
      expect(demoPattern.values.map((p) => p.length).toSet(), {48});
    });

    test(
      'script fires a high then a low alert early, ava stays calm',
      () async {
        await feedTo(4);
        expect(tags(maya), isEmpty);
        await feedTo(5); //10 s
        expect(tags(maya), [AlertTag.high]);
        await feedTo(10);
        expect(tags(leo), isEmpty);
        await feedTo(11); //~25 s
        expect(tags(leo), [AlertTag.low]);
        await feedTo(48);
        expect(tags(ava), isEmpty);
      },
    );

    test('sam alerts with confidence off', () async {
      await feedTo(48);
      expect(tags(sam), [AlertTag.low]);
    });

    test('sam never alerts at 4 of 5', () async {
      final m = AlertManager.instance;
      m.setSettings(
        demoClassId,
        sam,
        m
            .settingsFor(demoClassId, sam)
            .copyWith(minConfidence: ConfidenceStop.fourOfFive),
      );
      await feedTo(48);
      expect(tags(sam), isEmpty);
    });
  });

  //firebase is never initialised in tests, so any firebase call would throw
  testWidgets('whole demo runs with no firebase, exit resets', (tester) async {
    tester.view.physicalSize = const Size(430, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final realStore = LocalStore.instance;
    final realSessions = realStore.sessions.length;

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigatorKey,
        builder: demoFrame,
        home: const InitPage(),
      ),
    );
    expect(find.text('Demo · made-up students'), findsNothing);

    await tester.tap(find.text('Try the demo'));
    await tester.pumpAndSettle();
    expect(find.text('Demo · made-up students'), findsOneWidget);
    expect(find.text('Room 4 (Demo)'), findsWidgets);
    expect(find.text('5 of 5 watches connected'), findsOneWidget);

    //~12 s of readings: maya's high alert shows in the banner
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 2500));
    }
    expect(find.textContaining('Maya R. · High fidgeting'), findsOneWidget);

    await tester.tap(find.textContaining('Maya R. · High fidgeting'));
    await tester.pumpAndSettle();
    expect(find.text('Session timeline'), findsOneWidget);

    await tester.tap(find.text('Mute'));
    await tester.pump();
    expect(AlertManager.instance.isQuiet(demoClassId, maya), isTrue);
    await tester.tap(find.text('Unmute'));
    await tester.pump();
    expect(AlertManager.instance.isQuiet(demoClassId, maya), isFalse);

    await tester.tap(find.byTooltip('Alert sensitivity'));
    await tester.pumpAndSettle();
    //each slider rebuilds the screen, so look them up again every time
    Future<void> slide(int which, double to) async {
      tester
          .widgetList<Slider>(find.byType(Slider))
          .elementAt(which)
          .onChanged!(to);
      await tester.pump();
    }

    await slide(0, 1); //2 in a row
    await slide(1, 0); //10 s
    await slide(2, 1); //4 of 5
    final s = AlertManager.instance.settingsFor(demoClassId, maya);
    expect(s.readingsInARow, 2);
    expect(s.repeatEvery, const Duration(seconds: 10));
    expect(s.minConfidence, ConfidenceStop.fourOfFive);

    await tester.tap(find.byTooltip('How an alert is decided'));
    await tester.pumpAndSettle();
    expect(find.text('How an alert is decided'), findsOneWidget);

    //back to the home tabs, then devices
    final nav = appNavigatorKey.currentState!;
    nav.popUntil((route) => route.isFirst);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Devices').last);
    await tester.pumpAndSettle();
    expect(find.text('5 of 5 connected'), findsOneWidget);
    await tester.tap(find.text('Add Watch'));
    await tester.pump();
    expect(find.textContaining('needs an account'), findsOneWidget);

    await tester.tap(find.text('Exit demo'));
    await tester.pumpAndSettle();
    expect(find.byType(InitPage), findsOneWidget);
    expect(find.text('Demo · made-up students'), findsNothing);
    expect(DemoMode.isActive, isFalse);
    expect(WatchBleService.instance.watches, isEmpty);
    expect(AlertManager.instance.classLog(demoClassId), isEmpty);
    expect(LocalStore.instance, same(realStore));
    expect(realStore.sessions.length, realSessions);
  });
}
