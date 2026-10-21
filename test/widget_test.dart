import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syslog_server/main.dart';

void main() {
  testWidgets('SyslogServerApp renders initial screen', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(const SyslogServerApp());
    await tester.pumpAndSettle();

    expect(find.text('Syslog Server'), findsOneWidget);
    expect(find.text('Start Server'), findsOneWidget);
    expect(find.text('Demo Logs'), findsOneWidget);
  });
}
