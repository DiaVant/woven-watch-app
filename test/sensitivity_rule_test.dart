import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackapp/models/care_class.dart';
import 'package:trackapp/screens/alert_rule_screen.dart';
import 'package:trackapp/screens/alert_sensitivity_screen.dart';
import 'package:trackapp/screens/alerts_screen.dart';
import 'package:trackapp/screens/student_detail_screen.dart';
import 'package:trackapp/services/alert_engine.dart';
import 'package:trackapp/services/alert_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final manager = AlertManager.instance;

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(390, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3)); //debounced save
  }

  group('sensitivity', () {
    testWidgets('each slider changes this student\'s settings in this class',
        (tester) async {
      await pump(
        tester,
        const AlertSensitivityScreen(
          classId: 'sens',
          deviceId: 'w1',
          studentName: 'Avery R.',
        ),
      );
      final sliders = find.byType(Slider);
      expect(sliders, findsNWidgets(3));

      // rebuild between changes, as dragging does
      tester.widget<Slider>(sliders.at(0)).onChanged!(3); //N = 4
      await tester.pump();
      tester.widget<Slider>(sliders.at(1)).onChanged!(3); //120 s
      await tester.pump();
      tester.widget<Slider>(sliders.at(2)).onChanged!(1); //4 of 5
      await tester.pump();

      final s = manager.settingsFor('sens', 'w1');
      expect(s.readingsInARow, 4);
      expect(s.repeatEvery, const Duration(seconds: 120));
      expect(s.minConfidence, ConfidenceStop.fourOfFive);
      expect(find.text('About 10 seconds of unbroken fidgeting'), findsOneWidget);
      expect(find.text('80%'), findsNWidgets(2)); //value + stop label

      // only for this class
      expect(manager.settingsFor('other', 'w1').readingsInARow, 3);
      await finish(tester);
    });

    testWidgets('the info icon opens the rule explainer', (tester) async {
      await pump(
        tester,
        const AlertSensitivityScreen(
          classId: 'sens',
          deviceId: 'w1',
          studentName: 'Avery R.',
        ),
      );
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();
      expect(find.text('How an alert is decided'), findsOneWidget);
      await finish(tester);
    });
  });

  group('rule explainer', () {
    testWidgets('shows the AlertRule.png trace', (tester) async {
      await pump(
        tester,
        const AlertRuleScreen(classId: 'rule', deviceId: 'w1'),
      );
      for (final t in ['+0.0s', '+7.5s', '+10.0s', '+22.5s', '+70.0s']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('HIGH ALERT'), findsOneWidget);
      expect(find.text('LOW ALERT'), findsOneWidget);
      expect(find.text('rule met · wait 47 s'), findsOneWidget);
      await finish(tester);
    });
  });

  testWidgets('Open on the alerts feed goes to student detail',
      (tester) async {
    const student = ClassDevice(deviceId: 'w-open', studentName: 'Sam O.');
    final cls = CareClass(
      id: 'open',
      name: 'Room 12',
      colorHex: '#6662D9',
      createdAt: 0,
      updatedAt: 0,
      devices: const [student],
    );
    for (var i = 0; i < 3; i++) {
      manager.inject('open', 'w-open', FidgetLabel.highFidgeting);
    }
    await pump(tester, AlertsScreen(careClass: cls));
    await tester.tap(find.text('Open Sam'));
    await tester.pumpAndSettle();
    expect(find.byType(StudentDetailScreen), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a past alert opens the student; its settings icon opens settings',
      (tester) async {
    const student = ClassDevice(deviceId: 'w-past', studentName: 'Leo T.');
    final cls = CareClass(
      id: 'past',
      name: 'Room 12',
      colorHex: '#6662D9',
      createdAt: 0,
      updatedAt: 0,
      devices: const [student],
    );
    for (var i = 0; i < 3; i++) {
      manager.inject('past', 'w-past', FidgetLabel.lowFidgeting);
    }
    await pump(tester, AlertsScreen(careClass: cls));

    await tester.tap(find.byTooltip('Alert sensitivity'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertSensitivityScreen), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Leo T.').last); //the past row, not the now card
    await tester.pumpAndSettle();
    expect(find.byType(StudentDetailScreen), findsOneWidget);
    expect(find.byType(AlertSensitivityScreen), findsNothing);
    await finish(tester);
  });
}
