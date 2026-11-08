import 'package:flutter_test/flutter_test.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:syslog_server/data/repositories/syslog_repository.dart';
import 'package:syslog_server/data/services/database/syslog_database_service.dart';
import 'package:syslog_server/data/services/device/mac_address_helper.dart';
import 'package:syslog_server/domain/models/network_adapter_info.dart';
import 'package:syslog_server/domain/models/syslog_facility.dart';
import 'package:syslog_server/domain/models/syslog_record.dart';
import 'package:syslog_server/domain/models/syslog_severity.dart';
import 'package:syslog_server/ui/features/server/view_models/syslog_view_model.dart';

void main() {
  group('SyslogViewModel Unit Tests', () {
    late SyslogDatabaseService dbService;
    late SyslogRepository repository;
    late SyslogViewModel viewModel;

    setUp(() {
      dbService = SyslogDatabaseService(db: sqlite3.openInMemory());
      repository = SyslogRepository(databaseService: dbService);
      viewModel = SyslogViewModel(repository: repository);
    });

    tearDown(() {
      viewModel.dispose();
    });

    test('Initial state is clean and idle', () {
      expect(viewModel.logs, isEmpty);
      expect(viewModel.totalLogCount, 0);
      expect(viewModel.selectedRecord, isNull);
      expect(viewModel.serverStatus.isListening, isFalse);
      expect(viewModel.autoScroll, isTrue);
      expect(viewModel.isLoadingMore, isFalse);
      expect(viewModel.hasMoreLogs, isFalse);
      expect(viewModel.loadedFileName, isNull);
      expect(viewModel.sortColumn, 'id');
      expect(viewModel.sortAscending, isFalse);
    });

    test('loadDemoLogs populates logs and updates counts', () {
      viewModel.loadDemoLogs();

      expect(viewModel.logs.isNotEmpty, isTrue);
      expect(viewModel.totalLogCount, viewModel.logs.length);
      expect(viewModel.loadedFileName, 'demo_traffic.csv');

      final severityCounts = viewModel.severityCounts;
      expect(severityCounts.values.fold(0, (a, b) => a + b), viewModel.totalLogCount);
    });

    test('selectRecord updates selectedRecord state', () {
      viewModel.loadDemoLogs();
      final target = viewModel.logs.first;

      viewModel.selectRecord(target);
      expect(viewModel.selectedRecord, equals(target));

      viewModel.selectRecord(null);
      expect(viewModel.selectedRecord, isNull);
    });

    test('clearLogs removes all records and resets counts', () {
      viewModel.loadDemoLogs();
      expect(viewModel.logs.isNotEmpty, isTrue);

      viewModel.selectRecord(viewModel.logs.first);
      viewModel.clearLogs();

      expect(viewModel.logs, isEmpty);
      expect(viewModel.totalLogCount, 0);
      expect(viewModel.selectedRecord, isNull);
      expect(viewModel.severityCounts.values.every((c) => c == 0), isTrue);
    });

    test('Filters: setSearchQuery filters logs by text query', () {
      viewModel.loadDemoLogs();
      final initialCount = viewModel.totalLogCount;

      viewModel.setSearchQuery('cisco-asa');
      expect(viewModel.totalLogCount, lessThan(initialCount));
      expect(viewModel.logs.every((r) => r.rawPayload.contains('cisco-asa') || r.message.contains('cisco-asa') || (r.appName?.contains('cisco-asa') ?? false)), isTrue);

      viewModel.setSearchQuery('');
      expect(viewModel.totalLogCount, initialCount);
    });

    test('Filters: toggleSeverity filters logs by severity level', () {
      viewModel.loadDemoLogs();
      final initialCount = viewModel.totalLogCount;

      // Toggle emergency
      viewModel.toggleSeverity(SyslogSeverity.emergency);
      expect(viewModel.filter.selectedSeverities, contains(SyslogSeverity.emergency));
      expect(viewModel.totalLogCount, lessThanOrEqualTo(initialCount));

      // Toggle back
      viewModel.toggleSeverity(SyslogSeverity.emergency);
      expect(viewModel.filter.selectedSeverities, isNot(contains(SyslogSeverity.emergency)));
    });

    test('Filters: toggleFacility filters logs by facility', () {
      viewModel.loadDemoLogs();

      viewModel.toggleFacility(SyslogFacility.auth);
      expect(viewModel.filter.selectedFacilities, contains(SyslogFacility.auth));

      viewModel.toggleFacility(SyslogFacility.auth);
      expect(viewModel.filter.selectedFacilities, isNot(contains(SyslogFacility.auth)));
    });

    test('Filters: setRemoteIpFilter filters logs by source IP', () {
      viewModel.loadDemoLogs();

      viewModel.setRemoteIpFilter('192.168.1.1');
      expect(viewModel.filter.remoteIp, '192.168.1.1');
      expect(viewModel.logs.every((r) => r.remoteIp.contains('192.168.1.1')), isTrue);
    });

    test('Sorting: setSort toggles column and direction', () {
      viewModel.loadDemoLogs();

      viewModel.setSort('severity');
      expect(viewModel.sortColumn, 'severity');
      expect(viewModel.sortAscending, isTrue);

      // Same column toggles direction
      viewModel.setSort('severity');
      expect(viewModel.sortColumn, 'severity');
      expect(viewModel.sortAscending, isFalse);

      // New column defaults to ascending
      viewModel.setSort('facility');
      expect(viewModel.sortColumn, 'facility');
      expect(viewModel.sortAscending, isTrue);
    });

    test('resetFilters restores default filter criteria', () {
      viewModel.setSearchQuery('test');
      viewModel.setRemoteIpFilter('10.0.0.1');
      viewModel.setSort('severity');

      viewModel.resetFilters();
      expect(viewModel.filter.searchQuery, isEmpty);
      expect(viewModel.filter.remoteIp, isEmpty);
      expect(viewModel.filter.sortColumn, 'id');
      expect(viewModel.filter.sortAscending, isFalse);
    });

    test('toggleAutoScroll switches autoScroll boolean', () {
      expect(viewModel.autoScroll, isTrue);
      viewModel.toggleAutoScroll();
      expect(viewModel.autoScroll, isFalse);
      viewModel.toggleAutoScroll();
      expect(viewModel.autoScroll, isTrue);
    });

    test('selectAdapter updates selected network adapter', () {
      final custom = const NetworkAdapterInfo(
        name: 'eth0',
        ipAddress: '192.168.1.50',
      );
      viewModel.selectAdapter(custom);
      expect(viewModel.selectedAdapter, equals(custom));
      expect(custom.displayName, 'eth0 (192.168.1.50)');
    });

    test('closeLoadedFile resets file label', () {
      viewModel.loadDemoLogs();
      expect(viewModel.loadedFileName, 'demo_traffic.csv');

      viewModel.closeLoadedFile();
      expect(viewModel.loadedFileName, isNull);
    });

    test('updateDeviceName propagates to SharedDeviceDatabase and notifies', () async {
      await SharedDeviceDatabase.instance.init(dbPath: ':memory:');

      const testMac = '00:1A:2B:3C:4D:5E';
      bool notified = false;
      viewModel.addListener(() => notified = true);

      viewModel.updateDeviceName(testMac, 'Production Gateway');

      expect(notified, isTrue);
      expect(MacAddressHelper.getCustomName(testMac), 'Production Gateway');
    });

    test('Paging: loadMoreLogs appends next page when logs exceed default page size', () async {
      // Insert 1,500 records into database directly
      final testBatch = List.generate(
        1500,
        (i) => SyslogRecord(
          receivedAtMs: DateTime.now().millisecondsSinceEpoch + i,
          remoteIp: '10.0.0.1',
          remotePort: 514,
          transport: 'UDP',
          facility: SyslogFacility.user,
          severity: SyslogSeverity.informational,
          message: 'Bulk log event #$i',
          rawPayload: 'Bulk log event #$i',
        ),
      );
      dbService.insertBatch(testBatch);

      viewModel.resetFilters();
      expect(viewModel.totalLogCount, 1500);
      expect(viewModel.logs.length, 1000);
      expect(viewModel.hasMoreLogs, isTrue);

      await viewModel.loadMoreLogs();
      expect(viewModel.logs.length, 1500);
      expect(viewModel.hasMoreLogs, isFalse);
    });

    test('Auto-Detected toggle, device filtering, and visibility controls', () {
      expect(viewModel.showAutoDetected, isFalse);

      viewModel.setShowAutoDetected(true);
      expect(viewModel.showAutoDetected, isTrue);

      viewModel.loadDemoLogs();
      final autoSources = viewModel.autoDetectedSources;
      expect(autoSources.isNotEmpty, isTrue);

      // Select device key filter
      final targetKey = autoSources.first;
      viewModel.toggleDeviceFilter(targetKey);
      expect(viewModel.selectedDeviceKeys.contains(targetKey), isTrue);
      expect(viewModel.filter.hasActiveFilter, isTrue);

      // Verify filtered logs only match targetKey
      for (final log in viewModel.logs) {
        expect(log.remoteIp == targetKey || log.hostname == targetKey, isTrue);
      }

      // Clear device filters
      viewModel.clearDeviceFilters();
      expect(viewModel.selectedDeviceKeys, isEmpty);

      // Hide device
      viewModel.setDeviceHidden(targetKey, true);
      expect(viewModel.hiddenDeviceKeys.contains(targetKey), isTrue);
      expect(viewModel.autoDetectedSources.contains(targetKey), isFalse);

      // Toggle visibility back
      viewModel.toggleDeviceVisibility(targetKey);
      expect(viewModel.hiddenDeviceKeys.contains(targetKey), isFalse);
      expect(viewModel.autoDetectedSources.contains(targetKey), isTrue);

      // Unhide all
      viewModel.setDeviceHidden(targetKey, true);
      viewModel.unhideAllDevices();
      expect(viewModel.hiddenDeviceKeys, isEmpty);
    });

    test('Combining Triage and Device filters filters down logs and updates dynamic counters', () {
      viewModel.loadDemoLogs();
      final totalInitial = viewModel.totalLogCount;
      expect(totalInitial, greaterThan(0));

      // Select a specific device from auto-detected sources
      viewModel.setShowAutoDetected(true);
      final testDevice = viewModel.autoDetectedSources.first;
      final initialDeviceCount = viewModel.deviceCounts[testDevice] ?? 0;
      expect(initialDeviceCount, greaterThan(0));

      // 1. Filter by Device
      viewModel.toggleDeviceFilter(testDevice);
      expect(viewModel.totalLogCount, initialDeviceCount);

      // Verify Triage severity counters reflect ONLY logs for this device
      final severityCountsForDevice = viewModel.severityCounts;
      final sumSeverities = severityCountsForDevice.values.fold<int>(0, (a, b) => a + b);
      expect(sumSeverities, initialDeviceCount);

      // 2. Also select a Triage severity that has records
      final availableSeverity = severityCountsForDevice.entries.firstWhere((e) => e.value > 0).key;
      viewModel.toggleSeverity(availableSeverity);

      // The total count now represents Device AND Severity combined!
      final combinedCount = viewModel.totalLogCount;
      expect(combinedCount, severityCountsForDevice[availableSeverity]);
      expect(combinedCount, lessThanOrEqualTo(initialDeviceCount));

      // Verify all returned logs match BOTH the selected device AND the severity
      for (final log in viewModel.logs) {
        expect(log.remoteIp == testDevice || log.hostname == testDevice, isTrue);
        expect(log.severity, availableSeverity);
      }

      // Verify device counters also reflect the active severity filter
      final deviceCountUnderSeverity = viewModel.deviceCounts[testDevice] ?? 0;
      expect(deviceCountUnderSeverity, combinedCount);
    });
  });
}
