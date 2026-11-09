import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackapp/models/care_class.dart';
import 'package:trackapp/pages/account_page.dart';
import 'package:trackapp/screens/alerts_screen.dart';
import 'package:trackapp/services/alert_engine.dart';
import 'package:trackapp/services/alert_manager.dart';
import 'package:trackapp/services/watch_ble_service.dart'
    show WatchBleService, WovenWatch;
import 'package:trackapp/widgets/watch_detail_dialog.dart';

class FakeUser implements User {
  FakeUser({this.name});

  final String? name;
  int passwordChanges = 0;

  @override
  String? get displayName => name;

  @override
  String? get email => 'teacher@example.com';

  @override
  Future<void> updatePassword(String newPassword) async => passwordChanges++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAuth implements FirebaseAuth {
  FakeAuth(this.user);

  final FakeUser user;

  @override
  User? get currentUser => user;

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pump();
  }

  group('account', () {
    testWidgets('the display name is the identity; email is a detail',
        (tester) async {
      await pump(tester, AccountPage(auth: FakeAuth(FakeUser(name: 'Ms. Zhu'))));
      expect(find.text('Ms. Zhu'), findsOneWidget);
      expect(find.text('Shown to anyone you share a student with'),
          findsOneWidget);
      expect(find.text('Signed in with email & password'), findsOneWidget);
      expect(find.text('teacher@example.com'), findsOneWidget);
      for (final action in ['Change password', 'Sign out', 'Delete account']) {
        expect(find.text(action), findsOneWidget, reason: action);
      }
    });

    testWidgets('no display name yet asks for one', (tester) async {
      await pump(tester, AccountPage(auth: FakeAuth(FakeUser())));
      expect(find.text('Add your name'), findsOneWidget);
    });

    testWidgets('change password checks the new one before calling Firebase',
        (tester) async {
      final user = FakeUser(name: 'Ms. Zhu');
      await pump(tester, AccountPage(auth: FakeAuth(user)));
      await tester.tap(find.text('Change password'));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'old-password');
      await tester.enterText(fields.at(1), 'new-password');
      await tester.enterText(fields.at(2), 'different');
      await tester.tap(find.text('Change'));
      await tester.pump();
      expect(find.text('The new passwords do not match.'), findsOneWidget);

      await tester.enterText(fields.at(2), 'new');
      await tester.enterText(fields.at(1), 'new');
      await tester.tap(find.text('Change'));
      await tester.pump();
      expect(find.text('Use at least 6 characters.'), findsOneWidget);
      expect(user.passwordChanges, 0);
    });
  });

  group('watch detail', () {
    final room = careClass('wd-room', 'Room 12', {'wwWatch-W7B1': 'Jordan M.'});
    final art =
        careClass('wd-art', 'Art Workshop', {'wwWatch-W7B1': 'Priya N.'});

    Future<void> open(WidgetTester tester, List<CareClass> classes) async {
      await pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showWatchDetailDialog(
                context,
                deviceId: 'wwWatch-W7B1',
                assignments: [
                  for (final c in classes)
                    (careClass: c, student: c.devices.single),
                ],
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('lists every student the watch is worn by',
        (tester) async {
      WatchBleService.instance.debugAddWatch(
        WovenWatch(id: 'wwWatch-W7B1')
          ..isConnected = true
          ..prediction = 'not_fidgeting',
      );
      await open(tester, [room, art]);
      expect(find.text('WORN BY 2 STUDENTS'), findsOneWidget);
      expect(find.text('Jordan M.'), findsOneWidget);
      expect(find.text('Priya N.'), findsOneWidget);
      expect(find.textContaining('A cart watch can be assigned'),
          findsOneWidget);
      expect(find.text('Calm'), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);
    });

    testWidgets('one student: no cart-watch note', (tester) async {
      await open(tester, [room]);
      expect(find.text('WORN BY 1 STUDENT'), findsOneWidget);
      expect(find.textContaining('A cart watch'), findsNothing);
    });
  });

  testWidgets('alerts feed notes readings skipped inside an alert',
      (tester) async {
    final manager = AlertManager.instance;
    final cls = careClass('skip', 'Room 12', {'w-skip': 'Sam O.'});
    manager.setSettings(
      'skip',
      'w-skip',
      const AlertSettings(minConfidence: ConfidenceStop.fourOfFive),
    );
    for (final (label, votes) in [
      (FidgetLabel.lowFidgeting, 5),
      (FidgetLabel.lowFidgeting, 3),
      (FidgetLabel.highFidgeting, 3),
      (FidgetLabel.lowFidgeting, 5),
      (FidgetLabel.lowFidgeting, 3),
      (FidgetLabel.highFidgeting, 3),
      (FidgetLabel.highFidgeting, 4),
    ]) {
      manager.inject('skip', 'w-skip', label, votes: votes);
    }
    await pump(tester, AlertsScreen(careClass: cls));
    expect(
      find.text('4 readings skipped · alert spanned 17.5 s'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 6)); //ticker + debounced save
  });
}
