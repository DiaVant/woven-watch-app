// Basic smoke tests for screens that don't require Firebase or Bluetooth.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trackapp/pages/init_page.dart';

void main() {
  testWidgets('InitPage shows the entry actions', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: InitPage()));

    expect(find.text('Create New Account'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
  });
}
