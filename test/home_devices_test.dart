import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackapp/models/care_class.dart';
import 'package:trackapp/screens/devices_screen.dart';
import 'package:trackapp/screens/home_screen.dart';
import 'package:trackapp/services/class_service.dart';
import 'package:trackapp/services/local_store.dart';
import 'package:trackapp/services/watch_ble_service.dart';
import 'package:trackapp/widgets/watch_roster.dart';

class FakeClassService implements ClassService {
  FakeClassService(this.classes);

  final List<CareClass> classes;

  @override
  Stream<List<CareClass>> watchClasses() => Stream.value(classes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

CareClass careClass(String id, String name, Map<String, String> students) =>
    CareClass(
      id: id,
      name: name,
      colorHex: '#6662D9',
      createdAt: 0,
      updatedAt: 0,
      devices: [
        for (final e in students.entries)
          ClassDevice(deviceId: e.key, studentName: e.value),
      ],
    );

WovenWatch watch(String id, {bool connected = false, String? prediction}) {
  final w = WovenWatch(id: id)
    ..rssi = -60
    ..lastSeen = DateTime.now()
    ..isConnected = connected
    ..prediction = prediction
    ..predictionAt = prediction == null ? null : DateTime.now();
  WatchBleService.instance.debugAddWatch(w);
  return w;
}

Future<void> pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: screen)));
  await tester.pump();
  await tester.pump();
}

void main() {
  setUp(WatchBleService.instance.debugClearWatches);

  // ids are unique per test: the BLE service and the store are singletons
  final room12 = careClass('room12', 'Room 12', {
    'wwWatch-A7B1': 'Jordan M.',
    'wwWatch-A404': 'Avery R.',
  });
  final art = careClass('art', 'Art Workshop', {'wwWatch-A7B1': 'Priya N.'});

  test('the roster carries every (class, student) a cart watch is in', () {
    watch('wwWatch-A7B1', connected: true);
    watch('wwWatch-A8A5'); //seen, in no class
    final roster = buildWatchRoster([room12, art], WatchBleService.instance);
    final cart = roster.firstWhere((e) => e.id == 'wwWatch-A7B1');
    expect(
      cart.assignments.map(
          (a) => '${a.careClass.name}: ${a.student.studentName}'),
      ['Room 12: Jordan M.', 'Art Workshop: Priya N.'],
    );
    final avery = roster.firstWhere((e) => e.id == 'wwWatch-A404');
    expect(avery.watch, isNull, reason: 'assigned but never seen');
    final loose = roster.firstWhere((e) => e.id == 'wwWatch-A8A5');
    expect(loose.isAssigned, isFalse);
  });

  group('Devices', () {
    final cls = careClass('dev', 'Room 12', {'wwWatch-D7B1': 'Jordan M.'});
    final other =
        careClass('dev-art', 'Art Workshop', {'wwWatch-D7B1': 'Priya N.'});

    testWidgets('does not scan when the tab opens', (tester) async {
      await pump(tester, DevicesScreen(classService: FakeClassService([cls])));
      expect(find.textContaining('Not scanned yet'), findsOneWidget);
      expect(find.textContaining('scan failed'), findsNothing);
      expect(WatchBleService.instance.isScanning, isFalse);
    });

    testWidgets('lists every class a cart watch is assigned in',
        (tester) async {
      watch('wwWatch-D7B1', connected: true);
      await pump(
        tester,
        DevicesScreen(classService: FakeClassService([cls, other])),
      );
      expect(find.text('ASSIGNED IN 2 CLASSES'), findsOneWidget);
      expect(find.textContaining('Jordan M.', findRichText: true),
          findsOneWidget);
      expect(find.textContaining('Priya N.', findRichText: true),
          findsOneWidget);
      expect(find.text('1 of 1 connected'), findsOneWidget);
    });

    testWidgets('Disconnected reconnects on tap; Connected does not',
        (tester) async {
      watch('wwWatch-D7B1', connected: true);
      final two = careClass('two', 'Room 12', {
        'wwWatch-D7B1': 'Jordan M.',
        'wwWatch-D0FF': 'Avery R.', //never seen
      });
      await pump(tester, DevicesScreen(classService: FakeClassService([two])));
      expect(find.byTooltip('Reconnect'), findsOneWidget,
          reason: 'only the disconnected watch');

      //no bluetooth in tests, so the search fails and says so
      await tester.tap(find.byTooltip('Reconnect'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Disconnected'), findsOneWidget,
          reason: 'back to tappable after the failure');
    });

    testWidgets('a watch is shown by its BLE id, with no rename',
        (tester) async {
      watch('wwWatch-D7B1', connected: true);
      await pump(tester, DevicesScreen(classService: FakeClassService([cls])));
      expect(find.text('wwWatch-D7B1'), findsOneWidget);
      expect(find.text('Unnamed'), findsNothing);
      expect(find.byTooltip('Rename watch'), findsNothing);
    });

    testWidgets('a watch in no class gets an Assign card', (tester) async {
      watch('wwWatch-D8A5');
      await pump(tester, DevicesScreen(classService: FakeClassService([cls])));
      expect(find.text('Assign'), findsOneWidget);
      expect(find.text('Not in any of your classes'), findsOneWidget);
    });
  });

  group('Home', () {
    final cls = careClass('home', 'Room 12', {
      'wwWatch-H404': 'Avery R.',
      'wwWatch-H5D3': 'Noor A.',
    });

    testWidgets('header count agrees with the class card', (tester) async {
      watch('wwWatch-H404', connected: true, prediction: 'high_fidgeting');
      await pump(tester, HomeScreen(classService: FakeClassService([cls])));
      expect(find.text('1/2 connected'), findsOneWidget);
      expect(find.text('2 students · 1 watch connected'), findsOneWidget);
    });

    testWidgets('devices list starts collapsed and remembers',
        (tester) async {
      final store = LocalStore.instance;
      store.devicesListExpanded = null; //first run
      watch('wwWatch-H404', connected: true, prediction: 'high_fidgeting');
      await pump(tester, HomeScreen(classService: FakeClassService([cls])));
      expect(find.text('High fidgeting'), findsNothing); //collapsed

      await tester.tap(find.text('Devices list'));
      await tester.pump();
      expect(find.text('High fidgeting'), findsOneWidget);
      expect(store.devicesListExpanded, isTrue);

      // a fresh Home (e.g. after switching tabs) opens expanded
      await tester.pumpWidget(const SizedBox());
      await pump(tester, HomeScreen(classService: FakeClassService([cls])));
      expect(find.text('High fidgeting'), findsOneWidget);
      store.devicesListExpanded = null;
      await tester.pump(const Duration(seconds: 3)); //let the debounced save run
    });

    testWidgets('class edit and delete sit in opposite top corners',
        (tester) async {
      await pump(tester, HomeScreen(classService: FakeClassService([cls])));
      final delete = tester.getCenter(find.byTooltip('Delete class'));
      final edit = tester.getCenter(find.byTooltip('Edit class'));
      final card = tester.getRect(find.text('Room 12').first);
      expect(delete.dx, lessThan(card.left));
      expect(edit.dx, greaterThan(card.right));
      expect(delete.dy, closeTo(edit.dy, 1));
    });
  });
}
