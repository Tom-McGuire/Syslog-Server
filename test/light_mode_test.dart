import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import 'package:syslog_server/data/repositories/syslog_repository.dart';
import 'package:syslog_server/data/services/database/syslog_database_service.dart';
import 'package:syslog_server/domain/models/network_adapter_info.dart';
import 'package:syslog_server/main.dart';
import 'package:syslog_server/ui/features/server/view_models/syslog_view_model.dart';
import 'package:syslog_server/ui/theme/app_theme.dart';

void main() {
  tearDown(() async {
    AppTheme.applyThemeMode('dark');
    if (SharedDeviceDatabase.instance.isInitialized) {
      await SharedDeviceDatabase.instance.setThemeMode('dark');
    }
  });

  group('AppTheme Palette & SharedDeviceDatabase Persistence', () {
    test('AppTheme switches accurately between Dark and Light palettes', () {
      AppTheme.applyThemeMode('dark');
      expect(AppTheme.isDark, isTrue);
      expect(AppTheme.themeMode, 'dark');
      expect(AppTheme.scaffoldBg, const Color(0xFF141414));
      expect(AppTheme.surface, const Color(0xFF1E1E1E));
      expect(AppTheme.surfaceHigh, const Color(0xFF252526));
      expect(AppTheme.textPrimary, const Color(0xFFE0E0E0));

      AppTheme.applyThemeMode('light');
      expect(AppTheme.isDark, isFalse);
      expect(AppTheme.themeMode, 'light');
      expect(AppTheme.scaffoldBg, const Color(0xFFF3F4F6));
      expect(AppTheme.surface, const Color(0xFFFFFFFF));
      expect(AppTheme.surfaceHigh, const Color(0xFFF9FAFB));
      expect(AppTheme.border, const Color(0xFFE5E7EB));
      expect(AppTheme.textPrimary, const Color(0xFF111827));
      expect(AppTheme.textSecondary, const Color(0xFF4B5563));
      expect(AppTheme.textMuted, const Color(0xFF6B7280));
    });

    test('lightTheme and darkTheme produce proper Material 3 ThemeData', () {
      final dark = AppTheme.darkTheme();
      final light = AppTheme.lightTheme();

      expect(dark.brightness, Brightness.dark);
      expect(dark.scaffoldBackgroundColor, const Color(0xFF141414));
      expect(light.brightness, Brightness.light);
      expect(light.scaffoldBackgroundColor, const Color(0xFFF3F4F6));
    });

    test(
      'SharedDeviceDatabaseThemeExt persists theme mode across instances on disk',
      () async {
        final tempDir = await Directory.systemTemp.createTemp(
          'syslog_theme_test_',
        );
        try {
          final dbPath = p.join(tempDir.path, 'shared_devices.db');

          final dbWriter = SharedDeviceDatabase();
          await dbWriter.init(dbPath: dbPath);
          expect(await dbWriter.getThemeMode(), 'dark');

          await dbWriter.setThemeMode('light');
          expect(await dbWriter.getThemeMode(), 'light');

          final dbReader = SharedDeviceDatabase();
          await dbReader.init(dbPath: dbPath);
          expect(await dbReader.getThemeMode(), 'light');

          await dbWriter.setThemeMode('dark');
          expect(await dbReader.getThemeMode(), 'dark');
        } finally {
          await tempDir.delete(recursive: true);
        }
      },
    );
  });

  group('SyslogServerApp Light Mode Widget Rendering', () {
    late SyslogDatabaseService dbService;
    late SyslogRepository repository;
    late SyslogViewModel viewModel;

    setUp(() async {
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
    });

    testWidgets(
      'Starts cleanly in Light Mode and renders UI & Demo Overlay without overflow',
      (tester) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await SharedDeviceDatabase.instance.setThemeMode('light');
        AppTheme.applyThemeMode('light');

        await tester.pumpWidget(
          SyslogServerApp(
            viewModel: viewModel,
            database: SharedDeviceDatabase.instance,
          ),
        );
        await tester.pumpAndSettle();

        final materialApp = tester.widget<MaterialApp>(
          find.byType(MaterialApp),
        );
        expect(materialApp.themeMode, ThemeMode.light);

        final titleText = tester.widget<Text>(find.text('SYSLOG SERVER'));
        expect(titleText.style?.color, const Color(0xFF111827));

        // Verify demo walkthrough renders cleanly in Light Mode too.
        await tester.tap(find.text('Load Demo'));
        await tester.pumpAndSettle();
        expect(find.text('DEMO WALKTHROUGH • STEP 1 OF 5'), findsOneWidget);

        await tester.tap(find.text('End Demo'));
        await tester.pumpAndSettle();
        expect(viewModel.logs, isEmpty);
      },
    );

    testWidgets('Starts cleanly in Dark Mode with dark palette tokens', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await SharedDeviceDatabase.instance.setThemeMode('dark');
      AppTheme.applyThemeMode('dark');

      await tester.pumpWidget(
        SyslogServerApp(
          viewModel: viewModel,
          database: SharedDeviceDatabase.instance,
        ),
      );
      await tester.pumpAndSettle();

      final materialApp = tester.widget<MaterialApp>(
        find.byType(MaterialApp),
      );
      expect(materialApp.themeMode, ThemeMode.dark);

      final titleText = tester.widget<Text>(find.text('SYSLOG SERVER'));
      expect(titleText.style?.color, const Color(0xFFE0E0E0));
    });
  });
}
