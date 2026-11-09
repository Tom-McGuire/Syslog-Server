import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:syslog_server/data/services/database/syslog_database_service.dart';
import 'package:syslog_server/data/services/generator/demo_syslog_generator.dart';
import 'package:syslog_server/domain/models/syslog_filter.dart';

void main() {
  group('SyslogDatabaseService Tests', () {
    late SyslogDatabaseService dbService;

    setUp(() {
      dbService = SyslogDatabaseService(db: sqlite3.openInMemory());
    });

    tearDown(() {
      dbService.close();
    });

    test('Batch insert and retrieval works correctly', () {
      final demoLogs = DemoSyslogGenerator.generateDemoLogs();
      expect(demoLogs.isNotEmpty, isTrue);

      final inserted = dbService.insertBatch(demoLogs);
      expect(inserted.length, demoLogs.length);
      expect(inserted.first.id, isNotNull);

      final count = dbService.countLogs(const SyslogFilterCriteria());
      expect(count, demoLogs.length);

      final queried = dbService.queryLogs(
        offset: 0,
        limit: 10,
        filter: const SyslogFilterCriteria(),
      );
      expect(queried.length, 10);
    });

    test('Filter by search query finds matching records', () {
      final demoLogs = DemoSyslogGenerator.generateDemoLogs();
      dbService.insertBatch(demoLogs);

      final filtered = dbService.queryLogs(
        filter: const SyslogFilterCriteria(searchQuery: 'nginx'),
      );
      expect(filtered.isNotEmpty, isTrue);
      for (final r in filtered) {
        final matches = r.message.contains('nginx') ||
            (r.appName?.contains('nginx') ?? false) ||
            (r.hostname?.contains('nginx') ?? false);
        expect(matches, isTrue);
      }
    });

    test('Severity counts aggregate properly', () {
      final demoLogs = DemoSyslogGenerator.generateDemoLogs();
      dbService.insertBatch(demoLogs);

      final counts = dbService.getSeverityCounts();
      final totalFromCounts = counts.values.fold<int>(0, (sum, c) => sum + c);
      expect(totalFromCounts, demoLogs.length);
    });

    test('Clear all removes all logs', () {
      final demoLogs = DemoSyslogGenerator.generateDemoLogs();
      dbService.insertBatch(demoLogs);

      expect(dbService.countLogs(const SyslogFilterCriteria()), demoLogs.length);

      dbService.clearAll();
      expect(dbService.countLogs(const SyslogFilterCriteria()), 0);
    });

    test('Device preferences persistence and unhide operations', () {
      expect(dbService.getHiddenDeviceKeys(), isEmpty);

      dbService.setDeviceHidden('00:11:22:33:44:55', true);
      dbService.setDeviceHidden('192.168.1.100', true);
      expect(dbService.getHiddenDeviceKeys(), containsAll(['00:11:22:33:44:55', '192.168.1.100']));

      // Unhide single
      dbService.setDeviceHidden('192.168.1.100', false);
      expect(dbService.getHiddenDeviceKeys().contains('192.168.1.100'), isFalse);
      expect(dbService.getHiddenDeviceKeys().contains('00:11:22:33:44:55'), isTrue);

      // Unhide all
      dbService.unhideAllDevices();
      expect(dbService.getHiddenDeviceKeys(), isEmpty);
    });

    test('App state and device preferences key-value persistence', () {
      expect(dbService.getAppState('show_auto_detected'), isNull);
      dbService.setAppState('show_auto_detected', 'true');
      expect(dbService.getAppState('show_auto_detected'), 'true');

      dbService.setAppState('selected_device_keys', '["00:11:22:33:44:55"]');
      expect(dbService.getAppState('selected_device_keys'), '["00:11:22:33:44:55"]');

      dbService.removeAppState('show_auto_detected');
      expect(dbService.getAppState('show_auto_detected'), isNull);

      // getDevicePreferences map returns explicit 0 or 1
      dbService.setDeviceHidden('00:AA:BB:CC:DD:EE', false); // explicitly shown
      dbService.setDeviceHidden('00:11:22:33:44:55', true);  // explicitly hidden
      final prefs = dbService.getDevicePreferences();
      expect(prefs['00:AA:BB:CC:DD:EE'], isFalse);
      expect(prefs['00:11:22:33:44:55'], isTrue);

      dbService.clearDevicePreference('00:AA:BB:CC:DD:EE');
      expect(dbService.getDevicePreferences().containsKey('00:AA:BB:CC:DD:EE'), isFalse);
    });

    test('Source aggregation counts and device key log counting', () {
      final demoLogs = DemoSyslogGenerator.generateDemoLogs();
      dbService.insertBatch(demoLogs);

      final ipCounts = dbService.getRemoteIpCounts();
      expect(ipCounts.isNotEmpty, isTrue);

      final hostCounts = dbService.getHostnameCounts();
      expect(hostCounts.isNotEmpty, isTrue);

      final firstIp = ipCounts.keys.first;
      final ipCount = dbService.getCountForDeviceKey(firstIp);
      expect(ipCount, ipCounts[firstIp]);

      // Query logs filtering by selectedDeviceKeys
      final filteredByIp = dbService.queryLogs(
        filter: SyslogFilterCriteria(selectedDeviceKeys: {firstIp}),
      );
      expect(filteredByIp.isNotEmpty, isTrue);
      for (final r in filteredByIp) {
        expect(r.remoteIp == firstIp || r.hostname == firstIp, isTrue);
      }
    });
  });
}
