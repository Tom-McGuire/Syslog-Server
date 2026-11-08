import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:provider/provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:syslog_server/data/repositories/syslog_repository.dart';
import 'package:syslog_server/data/services/database/syslog_database_service.dart';
import 'package:syslog_server/data/services/device/mac_address_helper.dart';
import 'package:syslog_server/domain/models/syslog_facility.dart';
import 'package:syslog_server/domain/models/syslog_record.dart';
import 'package:syslog_server/domain/models/syslog_severity.dart';
import 'package:syslog_server/ui/features/server/view_models/syslog_view_model.dart';
import 'package:syslog_server/ui/features/server/views/device_filter_management_dialog.dart';
import 'package:syslog_server/ui/features/server/views/device_mac_chip.dart';
import 'package:syslog_server/ui/features/server/views/rename_device_dialog.dart';
import 'package:syslog_server/ui/features/server/views/syslog_control_bar.dart';
import 'package:syslog_server/ui/features/server/views/syslog_detail_panel.dart';
import 'package:syslog_server/ui/features/server/views/syslog_filter_bar.dart';
import 'package:syslog_server/ui/features/server/views/syslog_table_view.dart';
import 'package:syslog_server/ui/theme/app_theme.dart';

Widget createTestApp({required SyslogViewModel viewModel, required Widget child}) {
  return ChangeNotifierProvider<SyslogViewModel>.value(
    value: viewModel,
    child: MaterialApp(
      theme: AppTheme.darkTheme(),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('UI Components Widget Tests', () {
    late SyslogDatabaseService dbService;
    late SyslogRepository repository;
    late SyslogViewModel viewModel;

    setUp(() async {
      await SharedDeviceDatabase.instance.init(dbPath: ':memory:');
      dbService = SyslogDatabaseService(db: sqlite3.openInMemory());
      repository = SyslogRepository(databaseService: dbService);
      viewModel = SyslogViewModel(repository: repository);
    });

    tearDown(() {
      viewModel.dispose();
    });

    testWidgets('DeviceMacChip renders compact and full modes with friendly name', (tester) async {
      const testMac = '00:1A:2B:3C:4D:5E';
      MacAddressHelper.updateDeviceName(testMac, 'Core Distribution Switch');

      await tester.pumpWidget(
        createTestApp(
          viewModel: viewModel,
          child: const Column(
            children: [
              DeviceMacChip(mac: testMac, compact: true),
              DeviceMacChip(mac: testMac, compact: false),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Core Distribution Switch'), findsNWidgets(2));
    });

    testWidgets('RenameDeviceDialog validates empty input and saves new device name', (tester) async {
      const testMac = '00:11:22:33:44:55';

      await tester.pumpWidget(
        createTestApp(
          viewModel: viewModel,
          child: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () => RenameDeviceDialog.show(ctx, testMac),
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Rename Network Device'), findsOneWidget);
      expect(find.text(testMac), findsOneWidget);

      // Try saving with empty input
      final textFormField = find.byType(TextFormField);
      await tester.enterText(textFormField, '');
      await tester.tap(find.text('Save Name'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a device name'), findsOneWidget);

      // Save valid name
      await tester.enterText(textFormField, 'Lobby Router');
      await tester.tap(find.text('Save Name'));
      await tester.pumpAndSettle();

      // Dialog closed and name persisted
      expect(find.text('Rename Network Device'), findsNothing);
      expect(MacAddressHelper.getCustomName(testMac), 'Lobby Router');
    });

    testWidgets('SyslogDetailPanel displays metadata and raw payload for selected log', (tester) async {
      final sampleRecord = SyslogRecord(
        id: 42,
        receivedAtMs: DateTime.utc(2026, 11, 6, 12, 0, 0).millisecondsSinceEpoch,
        remoteIp: '192.168.1.100',
        remotePort: 514,
        transport: 'UDP',
        facility: SyslogFacility.auth,
        severity: SyslogSeverity.critical,
        hostname: 'auth-server-01',
        appName: 'sshd',
        procId: '1234',
        msgId: 'ID99',
        message: 'Failed root login from 10.0.0.1 on 00:1A:2B:3C:4D:5E',
        rawPayload: '<34>1 2026-11-06T12:00:00Z auth-server-01 sshd 1234 ID99 - Failed root login',
      );

      viewModel.selectRecord(sampleRecord);

      await tester.pumpWidget(
        createTestApp(
          viewModel: viewModel,
          child: const SyslogDetailPanel(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Log Entry #42'), findsOneWidget);
      expect(find.text('Core Distribution Switch [Syslog: auth-server-01]'), findsOneWidget);
      expect(find.text('192.168.1.100:514 (UDP)'), findsOneWidget);
      expect(find.text('HARDWARE IDENTITY & SHARED DEVICES'), findsOneWidget);
    });

    testWidgets('SyslogTableView displays logs, highlights friendly name and handles row selection', (tester) async {
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const mac = '00:1A:2B:3C:4D:5E';
      MacAddressHelper.updateDeviceName(mac, 'Core Switch Alpha');

      final record = SyslogRecord(
        id: 1,
        receivedAtMs: DateTime.now().millisecondsSinceEpoch,
        remoteIp: '192.168.1.1',
        remotePort: 514,
        transport: 'UDP',
        facility: SyslogFacility.local7,
        severity: SyslogSeverity.error,
        hostname: 'sw-01',
        message: 'Interface down for $mac',
        rawPayload: 'Interface down for $mac',
      );
      dbService.insertBatch([record]);
      viewModel.resetFilters();

      await tester.pumpWidget(
        createTestApp(
          viewModel: viewModel,
          child: const SizedBox(height: 600, child: SyslogTableView()),
        ),
      );
      await tester.pumpAndSettle();

      // Verified friendly host name is displayed in table
      expect(find.text('Core Switch Alpha'), findsAtLeastNWidgets(1));

      // Tap row to select
      await tester.tap(find.text('Core Switch Alpha').first);
      await tester.pumpAndSettle();

      expect(viewModel.selectedRecord?.id, 1);
    });

    testWidgets('SyslogFilterBar updates search query, severity, and resets filters', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          viewModel: viewModel,
          child: const SyslogFilterBar(),
        ),
      );
      await tester.pumpAndSettle();

      // Type search query
      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, 'firewall');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(viewModel.filter.searchQuery, 'firewall');

      // Tap a severity chip (e.g. Error)
      final errorChip = find.text('Error');
      if (errorChip.evaluate().isNotEmpty) {
        await tester.tap(errorChip);
        await tester.pumpAndSettle();
        expect(viewModel.filter.selectedSeverities, contains(SyslogSeverity.error));
      }

      // Tap Clear Filters button (visible when active filter exists)
      final clearFiltersBtn = find.text('Clear Filters');
      expect(clearFiltersBtn, findsOneWidget);
      await tester.tap(clearFiltersBtn);
      await tester.pumpAndSettle();

      expect(viewModel.filter.searchQuery, isEmpty);
      expect(viewModel.filter.selectedSeverities, isEmpty);
    });

    testWidgets('SyslogControlBar handles clear logs confirmation dialog', (tester) async {
      viewModel.loadDemoLogs();
      expect(viewModel.logs.isNotEmpty, isTrue);

      await tester.pumpWidget(
        createTestApp(
          viewModel: viewModel,
          child: const SyslogControlBar(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Clear
      final clearButton = find.text('Clear');
      expect(clearButton, findsOneWidget);
      await tester.ensureVisible(clearButton);
      await tester.tap(clearButton);
      await tester.pumpAndSettle();

      expect(find.text('Clear Captured Logs?'), findsOneWidget);

      // Confirm Clear All
      await tester.tap(find.text('Clear All'));
      await tester.pumpAndSettle();

      expect(viewModel.logs, isEmpty);
      expect(viewModel.totalLogCount, 0);
    });

    testWidgets('DeviceMacChip secondary tap opens context menu with options', (tester) async {
      const testMac = '00:1A:2B:3C:4D:5E';
      MacAddressHelper.updateDeviceName(testMac, 'Switch Core 01');

      await tester.pumpWidget(
        createTestApp(
          viewModel: viewModel,
          child: const Center(
            child: DeviceMacChip(mac: testMac, compact: false),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Right-click / secondary tap on chip
      final chipFinder = find.byType(DeviceMacChip);
      await tester.tap(chipFinder, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      expect(find.text('Rename Device ($testMac)'), findsOneWidget);
      expect(find.text('Filter Logs by MAC ($testMac)'), findsOneWidget);
      expect(find.text('Copy MAC Address'), findsOneWidget);

      // Tap Filter Logs by MAC
      await tester.tap(find.text('Filter Logs by MAC ($testMac)'));
      await tester.pumpAndSettle();

      expect(viewModel.filter.searchQuery, testMac);
    });

    testWidgets('SyslogTableView supports column header sort click and drag resizing', (tester) async {
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      viewModel.loadDemoLogs();

      await tester.pumpWidget(
        createTestApp(
          viewModel: viewModel,
          child: const SizedBox(height: 600, child: SyslogTableView()),
        ),
      );
      await tester.pumpAndSettle();

      // Click "Severity" column header to sort
      final severityHeader = find.text('Severity');
      expect(severityHeader, findsOneWidget);
      await tester.tap(severityHeader);
      await tester.pumpAndSettle();

      expect(viewModel.sortColumn, 'severity');

      // Find drag resize handles
      final dragHandles = find.byWidgetPredicate(
        (widget) => widget is MouseRegion && widget.cursor == SystemMouseCursors.resizeColumn,
      );
      expect(dragHandles, findsWidgets);

      // Drag first handle by +50 pixels
      await tester.drag(dragHandles.first, const Offset(50, 0));
      await tester.pumpAndSettle();
    });

    testWidgets('SyslogTableView secondary tap on row opens context menu and filters by IP', (tester) async {
      tester.view.physicalSize = const Size(1400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final record = SyslogRecord(
        id: 99,
        receivedAtMs: DateTime.now().millisecondsSinceEpoch,
        remoteIp: '192.168.10.50',
        remotePort: 514,
        transport: 'UDP',
        facility: SyslogFacility.daemon,
        severity: SyslogSeverity.warning,
        hostname: 'gateway-node',
        message: 'Warning packet detected from gateway',
        rawPayload: 'Warning packet detected from gateway',
      );
      dbService.insertBatch([record]);
      viewModel.resetFilters();

      await tester.pumpWidget(
        createTestApp(
          viewModel: viewModel,
          child: const SizedBox(height: 600, child: SyslogTableView()),
        ),
      );
      await tester.pumpAndSettle();

      // Secondary tap on message row
      final rowText = find.text('Warning packet detected from gateway');
      expect(rowText, findsOneWidget);
      await tester.tap(rowText, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      expect(find.text('Copy Message'), findsOneWidget);
      expect(find.text('Copy Raw Payload'), findsOneWidget);
      expect(find.text('Filter by IP: 192.168.10.50'), findsOneWidget);
      expect(find.text('Filter by Host: gateway-node'), findsOneWidget);

      // Tap Filter by IP
      await tester.tap(find.text('Filter by IP: 192.168.10.50'));
      await tester.pumpAndSettle();

      expect(viewModel.filter.remoteIp, '192.168.10.50');
    });

    testWidgets('SyslogControlBar start/stop server and export popup menu', (tester) async {
      viewModel.loadDemoLogs();

      await tester.pumpWidget(
        createTestApp(
          viewModel: viewModel,
          child: const SyslogControlBar(),
        ),
      );
      await tester.pumpAndSettle();

      // Start Server button
      final startBtn = find.text('Start Server');
      expect(startBtn, findsOneWidget);

      // Open Export Popup Menu
      final exportBtn = find.byTooltip('Export Logs');
      expect(exportBtn, findsOneWidget);
      await tester.ensureVisible(exportBtn);
      await tester.tap(exportBtn);
      await tester.pumpAndSettle();

      expect(find.text('Export as CSV'), findsOneWidget);
      expect(find.text('Export as JSON'), findsOneWidget);
    });

    testWidgets('SyslogFilterBar renders Device row and toggles Auto-Detected sources', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const labeledMac = '00:1A:2B:3C:4D:5E';
      MacAddressHelper.updateDeviceName(labeledMac, 'Core Distribution Switch');
      viewModel.loadDemoLogs();

      await tester.pumpWidget(
        createTestApp(
          viewModel: viewModel,
          child: const SyslogFilterBar(),
        ),
      );
      await tester.pumpAndSettle();

      // Device row header
      expect(find.text('Devices'), findsOneWidget);
      expect(find.text('Add Device'), findsOneWidget);

      // Known labeled device appears
      final deviceChip = find.textContaining('Core Distribution Switch');
      expect(deviceChip, findsOneWidget);

      // Tap to filter by device
      await tester.tap(deviceChip);
      await tester.pumpAndSettle();
      expect(viewModel.selectedDeviceKeys.contains(labeledMac), isTrue);

      // Secondary tap opens context menu
      await tester.tap(deviceChip, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.text('Hide from Device Filters'), findsOneWidget);
      expect(find.text('Copy "$labeledMac"'), findsOneWidget);

      // Tap Hide
      await tester.tap(find.text('Hide from Device Filters'));
      await tester.pumpAndSettle();
      expect(viewModel.hiddenDeviceKeys.contains(labeledMac), isTrue);

      // Toggle Auto-Detected switch
      final autoDetectedSwitch = find.byType(Switch).first;
      await tester.tap(autoDetectedSwitch);
      await tester.pumpAndSettle();
      expect(viewModel.showAutoDetected, isTrue);
    });

    testWidgets('DeviceFilterManagementDialog allows toggling device visibility and unhiding all', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const testMac = '11:22:33:44:55:66';
      MacAddressHelper.updateDeviceName(testMac, 'Edge Router Alpha');
      viewModel.setDeviceHidden(testMac, true);

      await tester.pumpWidget(
        createTestApp(
          viewModel: viewModel,
          child: const DeviceFilterManagementDialog(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Manage Filter Devices'), findsOneWidget);
      expect(find.textContaining('Edge Router Alpha'), findsOneWidget);
      expect(find.text('Hidden'), findsWidgets);

      // Unhide All button
      final unhideAllBtn = find.textContaining('Unhide All');
      expect(unhideAllBtn, findsOneWidget);
      await tester.tap(unhideAllBtn);
      await tester.pumpAndSettle();

      expect(viewModel.hiddenDeviceKeys, isEmpty);
    });
  });
}
