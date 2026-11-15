import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:syslog_server/data/repositories/syslog_repository.dart';
import 'package:syslog_server/data/services/database/syslog_database_service.dart';
import 'package:syslog_server/domain/models/network_adapter_info.dart';
import 'package:syslog_server/main.dart';
import 'package:syslog_server/ui/features/server/view_models/syslog_view_model.dart';
import 'package:syslog_server/ui/theme/app_theme.dart';
import 'package:syslog_server/ui/widgets/guided_tour_overlay.dart';

void main() {
  late SyslogDatabaseService dbService;
  late SyslogRepository repository;
  late SyslogViewModel viewModel;

  setUp(() async {
    AppTheme.applyThemeMode('dark');
    await SharedDeviceDatabase.instance.init(dbPath: ':memory:');
    dbService = SyslogDatabaseService(db: sqlite3.openInMemory());
    repository = SyslogRepository(
      databaseService: dbService,
      adapterProvider: () async => [NetworkAdapterInfo.all],
    );
    viewModel = SyslogViewModel(repository: repository);
    await viewModel.refreshAdapters();
  });

  tearDown(() async {
    viewModel.dispose();
    repository.dispose();
    dbService.close();
    AppTheme.applyThemeMode('dark');
  });

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      SyslogServerApp(
        viewModel: viewModel,
        database: SharedDeviceDatabase.instance,
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Demo Walkthrough Spotlight & Auto-Clear', () {
    testWidgets(
      'Load Demo starts walkthrough, highlights Step 1, and toggles toolbar button to amber Exit Demo',
      (tester) async {
        await pumpApp(tester);

        expect(viewModel.isDemoMode, isFalse);
        expect(viewModel.logs, isEmpty);
        expect(find.text('Load Demo'), findsOneWidget);
        expect(find.byType(GuidedTourOverlay), findsOneWidget);

        await tester.tap(find.text('Load Demo'));
        await tester.pumpAndSettle();

        expect(viewModel.isDemoMode, isTrue);
        expect(viewModel.logs, isNotEmpty);
        expect(viewModel.selectedRecord, isNotNull);

        expect(find.text('DEMO WALKTHROUGH • STEP 1 OF 5'), findsOneWidget);
        expect(
          find.text('Zone 2: Bind Interface, Protocol & Port'),
          findsOneWidget,
        );
        expect(find.text('Exit Demo'), findsOneWidget);
        expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);

        final stopIcon = tester.widget<Icon>(
          find.byIcon(Icons.stop_circle_outlined),
        );
        expect(stopIcon.color, AppTheme.warning);
      },
    );

    testWidgets(
      'Walkthrough steps 1..5 in order and Finish & Clear auto-clears demo logs',
      (tester) async {
        await pumpApp(tester);

        await tester.tap(find.text('Load Demo'));
        await tester.pumpAndSettle();

        expect(
          find.text('Zone 2: Bind Interface, Protocol & Port'),
          findsOneWidget,
        );

        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text('DEMO WALKTHROUGH • STEP 2 OF 5'), findsOneWidget);
        expect(find.text('Zone 3: Start / Pause Listener'), findsOneWidget);

        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text('DEMO WALKTHROUGH • STEP 3 OF 5'), findsOneWidget);
        expect(find.text('Severity & Facility Filter Bar'), findsOneWidget);

        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text('DEMO WALKTHROUGH • STEP 4 OF 5'), findsOneWidget);
        expect(find.text('Real-Time Syslog Stream Table'), findsOneWidget);

        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text('DEMO WALKTHROUGH • STEP 5 OF 5'), findsOneWidget);
        expect(
          find.text('Message Inspector & Shared Device Naming'),
          findsOneWidget,
        );
        expect(find.text('Finish & Clear'), findsOneWidget);

        // Verify Back navigation works from final step.
        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        expect(find.text('DEMO WALKTHROUGH • STEP 4 OF 5'), findsOneWidget);

        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text('Finish & Clear'), findsOneWidget);

        await tester.tap(find.text('Finish & Clear'));
        await tester.pumpAndSettle();

        expect(viewModel.isDemoMode, isFalse);
        expect(viewModel.logs, isEmpty);
        expect(viewModel.selectedRecord, isNull);
        expect(find.text('Load Demo'), findsOneWidget);
        expect(find.text('Exit Demo'), findsNothing);
      },
    );

    testWidgets(
      'End Demo button and empty-state Load Demo Logs respect walkthrough & auto-clear lifecycle',
      (tester) async {
        await pumpApp(tester);

        await tester.tap(find.text('Load Demo Logs'));
        await tester.pumpAndSettle();

        expect(viewModel.isDemoMode, isTrue);
        expect(viewModel.logs, isNotEmpty);
        expect(find.text('End Demo'), findsOneWidget);

        await tester.tap(find.text('End Demo'));
        await tester.pumpAndSettle();

        expect(viewModel.isDemoMode, isFalse);
        expect(viewModel.logs, isEmpty);
        expect(find.text('Load Demo Logs'), findsOneWidget);
      },
    );

    testWidgets(
      'Keyboard navigation supports ArrowRight, ArrowLeft, and Escape auto-clear',
      (tester) async {
        await pumpApp(tester);

        await tester.tap(find.text('Load Demo'));
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(find.text('DEMO WALKTHROUGH • STEP 2 OF 5'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pumpAndSettle();
        expect(find.text('DEMO WALKTHROUGH • STEP 1 OF 5'), findsOneWidget);

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();

        expect(viewModel.isDemoMode, isFalse);
        expect(viewModel.logs, isEmpty);
        expect(find.text('Load Demo'), findsOneWidget);
      },
    );

    testWidgets(
      'Demo walkthrough strictly isolates SharedDeviceDatabase without inserting devices',
      (tester) async {
        await pumpApp(tester);

        expect(SharedDeviceDatabase.instance.getAllDevices(), isEmpty);

        await tester.tap(find.text('Load Demo'));
        await tester.pumpAndSettle();
        expect(SharedDeviceDatabase.instance.getAllDevices(), isEmpty);

        // Advance through every step and finish.
        for (var i = 0; i < 4; i++) {
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
          expect(SharedDeviceDatabase.instance.getAllDevices(), isEmpty);
        }

        await tester.tap(find.text('Finish & Clear'));
        await tester.pumpAndSettle();
        expect(SharedDeviceDatabase.instance.getAllDevices(), isEmpty);
      },
    );
  });
}
