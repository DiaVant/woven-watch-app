import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackapp/models/care_class.dart';
import 'package:trackapp/screens/home/class_page.dart';
import 'package:trackapp/screens/student_detail_screen.dart';
import 'package:trackapp/services/alert_engine.dart';
import 'package:trackapp/services/alert_manager.dart';
import 'package:trackapp/services/class_service.dart';
import 'package:trackapp/services/local_store.dart';
import 'package:trackapp/services/watch_ble_service.dart';
import 'package:trackapp/widgets/student_live.dart';

class FakeClassService implements ClassService {
  FakeClassService(this.classes);

  final List<CareClass> classes;

  @override
  Stream<List<CareClass>> watchClasses() => Stream.value(classes);

  final renames = <String>[];

  @override
  Future<void> updateStudentName({
    required String classId,
    required String deviceId,
    required String studentName,
  }) async =>
      renames.add('$classId/$deviceId=$studentName');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CareClass careClass(String id, Map<String, String> students) => CareClass(
      id: id,
      name: 'Room 12',
      colorHex: '#6662D9',
      createdAt: 0,
      updatedAt: 0,
      devices: [
        for (final e in students.entries)
          ClassDevice(deviceId: e.key, studentName: e.value),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final manager = AlertManager.instance;
  final store = LocalStore.instance;

  setUp(WatchBleService.instance.debugClearWatches);

  group('session recording', () {
    test('readings and alerts go into a running class session only', () {
      manager.inject('rec', 'w1', FidgetLabel.highFidgeting);
      expect(store.latestSession('rec', 'w1'), isNull,
          reason: 'no session running yet');

      store.startClassSession('rec', ['w1']);
      for (var i = 0; i < 3; i++) {
        manager.inject('rec', 'w1', FidgetLabel.highFidgeting);
      }
      final open = store.openSession('rec', 'w1')!;
      expect(open.readings, hasLength(3));
      expect(open.alerts.single.tag, AlertTag.high);

      store.endClassSession('rec');
      manager.inject('rec', 'w1', FidgetLabel.lowFidgeting);
      expect(store.latestSession('rec', 'w1')!.readings, hasLength(3));
      expect(store.isClassSessionRunning('rec'), isFalse);
    });

    test('a watch added mid-session joins the running session', () {
      store.startClassSession('join', ['w1']);
      manager.inject('join', 'w-new', FidgetLabel.notFidgeting);
      expect(store.openSession('join', 'w-new')?.readings, hasLength(1));
      store.endClassSession('join');
    });
  });

  test('history keeps the last 12 readings, oldest first', () {
    for (var i = 0; i < 15; i++) {
      manager.inject(
        'hist',
        'w',
        i.isEven ? FidgetLabel.notFidgeting : FidgetLabel.highFidgeting,
      );
    }
    final history = manager.recentReadings('hist', 'w');
    expect(history, hasLength(AlertManager.historyLength));
    expect(history.last.label, FidgetLabel.notFidgeting); //i = 14
  });

  test('state duration restarts when calm turns to fidgeting', () {
    for (var i = 0; i < 4; i++) {
      manager.inject('dur', 'w', FidgetLabel.notFidgeting);
    }
    expect(manager.stateDuration('dur', 'w'), const Duration(seconds: 10));
    manager.inject('dur', 'w', FidgetLabel.lowFidgeting);
    manager.inject('dur', 'w', FidgetLabel.highFidgeting); //still fidgeting
    expect(manager.stateDuration('dur', 'w'), const Duration(seconds: 5));
  });

  group('live state', () {
    test('live, then signal lost after 7.5 s without a reading', () {
      manager.inject('live', 'w', FidgetLabel.highFidgeting);
      final received = manager.lastReadingFor('live', 'w')!.receivedAt;
      expect(studentLive('live', 'w', now: received).kind, LiveKind.live);
      expect(
        studentLive('live', 'w',
                now: received.add(const Duration(seconds: 8)))
            .kind,
        LiveKind.signalLost,
      );
    });

    test('connected with no reading is waiting; unseen is offline', () {
      WatchBleService.instance
          .debugAddWatch(WovenWatch(id: 'w-wait')..isConnected = true);
      expect(studentLive('wait', 'w-wait').kind, LiveKind.waiting);
      expect(studentLive('wait', 'w-none').kind, LiveKind.offline);
    });
  });

  group('screens', () {
    final cls = careClass('screen', {
      'wwWatch-S404': 'Avery R.',
      'wwWatch-S2C9': 'Sam O.',
    });

    Future<void> pump(WidgetTester tester, Widget screen) async {
      tester.view.physicalSize = const Size(390, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(home: screen));
      await tester.pump();
    }

    testWidgets('class view shows live state and runs a session',
        (tester) async {
      await pump(
        tester,
        ClassPage(
          initialCareClass: cls,
          classService: FakeClassService([cls]),
          onEditClass: (_) {},
          onStudentTap: (_, _) {},
        ),
      );
      for (var i = 0; i < 3; i++) {
        manager.inject('screen', 'wwWatch-S404', FidgetLabel.highFidgeting);
      }
      await tester.pump();
      expect(find.text('High fidgeting'), findsOneWidget);
      expect(find.textContaining('ALERTED'), findsOneWidget);
      expect(find.text('Not connected'), findsOneWidget); //Sam, never seen

      await tester.tap(find.text('Start session'));
      await tester.pump();
      expect(find.text('End session'), findsOneWidget);
      expect(store.isClassSessionRunning('screen'), isTrue);

      store.endClassSession('screen');
      await tester.pumpWidget(const SizedBox()); //dispose the 1 s ticker
      await tester.pump(const Duration(seconds: 3)); //debounced save
    });

    testWidgets('alert banner opens the student and can be dismissed',
        (tester) async {
      final banner = careClass('banner', {'wwWatch-B404': 'Avery R.'});
      ClassDevice? opened;
      await pump(
        tester,
        ClassPage(
          initialCareClass: banner,
          classService: FakeClassService([banner]),
          onEditClass: (_) {},
          onStudentTap: (_, device) => opened = device,
        ),
      );
      expect(find.byType(AlertBanner), findsNothing);

      for (var i = 0; i < 3; i++) {
        manager.inject('banner', 'wwWatch-B404', FidgetLabel.highFidgeting);
      }
      await tester.pump();
      expect(find.text('Avery R. · High fidgeting'), findsOneWidget);

      await tester.tap(find.text('Avery R. · High fidgeting'));
      await tester.pump();
      expect(opened?.deviceId, 'wwWatch-B404');
      expect(find.byType(AlertBanner), findsNothing,
          reason: 'opening it counts as handled');

      // a repeat (60 s = 24 readings later in reading time) brings it back
      for (var i = 0; i < 24; i++) {
        manager.inject('banner', 'wwWatch-B404', FidgetLabel.highFidgeting);
      }
      await tester.pump();
      expect(find.byType(AlertBanner), findsOneWidget);
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pump();
      expect(find.byType(AlertBanner), findsNothing);

      await tester.pumpWidget(const SizedBox()); //dispose the 1 s ticker
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('the pencil on a tile renames the student in this class',
        (tester) async {
      final service = FakeClassService([cls]);
      await pump(
        tester,
        ClassPage(
          initialCareClass: cls,
          classService: service,
          onEditClass: (_) {},
          onStudentTap: (_, _) => fail('the pencil should not open the student'),
        ),
      );
      await tester.tap(find.byTooltip('Edit name').first);
      await tester.pumpAndSettle();
      expect(find.text('Name for wwWatch-S404'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Maya');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(service.renames, ['screen/wwWatch-S404=Maya']);

      await tester.pumpWidget(const SizedBox()); //dispose the 1 s ticker
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('student detail mutes and unmutes alerts', (tester) async {
      await pump(
        tester,
        StudentDetailScreen(careClass: cls, student: cls.devices.first),
      );
      final deviceId = cls.devices.first.deviceId;
      expect(find.text('Alerts on'), findsOneWidget);
      await tester.tap(find.text('Mute'));
      await tester.pump();
      expect(manager.isQuiet('screen', deviceId), isTrue);
      expect(find.text('Alerts muted'), findsOneWidget);
      await tester.tap(find.text('Unmute'));
      await tester.pump();
      expect(manager.isQuiet('screen', deviceId), isFalse);

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('student detail shows the timeline and six stats',
        (tester) async {
      store.startClassSession('screen', ['wwWatch-S404']);
      for (final label in [
        FidgetLabel.notFidgeting,
        FidgetLabel.lowFidgeting,
        FidgetLabel.highFidgeting,
      ]) {
        manager.inject('screen', 'wwWatch-S404', label);
      }
      await pump(
        tester,
        StudentDetailScreen(careClass: cls, student: cls.devices.first),
      );
      expect(find.text('Session timeline'), findsOneWidget);
      for (final label in [
        'Longest fidget',
        'Alerts',
        'Received readings',
        'Low fidgeting',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.text('Alert sensitivity'), findsOneWidget);
      store.endClassSession('screen');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });
  });
}
