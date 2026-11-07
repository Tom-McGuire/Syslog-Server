import 'package:flutter_test/flutter_test.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:syslog_server/data/repositories/syslog_repository.dart';
import 'package:syslog_server/data/services/database/syslog_database_service.dart';
import 'package:syslog_server/data/services/device/mac_address_helper.dart';
import 'package:syslog_server/data/services/export/export_service.dart';
import 'package:syslog_server/data/services/generator/demo_syslog_generator.dart';
import 'package:syslog_server/data/services/import/csv_import_service.dart';
import 'package:syslog_server/domain/models/syslog_facility.dart';
import 'package:syslog_server/domain/models/syslog_filter.dart';
import 'package:syslog_server/domain/models/syslog_record.dart';
import 'package:syslog_server/domain/models/syslog_severity.dart';

void main() {
  group('CsvImportService Tests', () {
    test('Round-trip export and import preserves syslog records', () {
      final original = DemoSyslogGenerator.generateDemoLogs();
      expect(original.isNotEmpty, isTrue);

      final csvString = ExportService.logsToCsv(original);
      expect(csvString.isNotEmpty, isTrue);

      final importResult = CsvImportService.parseCsv(csvString);
      expect(importResult.importedCount, original.length);
      expect(importResult.records.length, original.length);

      final firstOriginal = original.first;
      final firstImported = importResult.records.first;

      expect(firstImported.message, firstOriginal.message);
      expect(firstImported.remoteIp, firstOriginal.remoteIp);
      expect(firstImported.severity, firstOriginal.severity);
      expect(firstImported.facility, firstOriginal.facility);
      expect(firstImported.hostname, firstOriginal.hostname);
      expect(firstImported.appName, firstOriginal.appName);
    });

    test('Imports third-party CSV with non-standard column headers', () {
      const thirdPartyCsv = '''Timestamp,Device,Level,Program,Msg
2026-10-24T08:30:00Z,router-core-01,Error,bgpd,"BGP peer 10.0.0.1 transitioned to DOWN"
2026-10-24T08:30:05Z,firewall-edge,Warning,packet-filter,"Blocked inbound connection on port 22"
2026-10-24T08:30:10Z,srv-auth,Info,sshd,"Accepted publickey for admin from 192.168.1.100"
''';

      final result = CsvImportService.parseCsv(thirdPartyCsv);
      expect(result.importedCount, 3);
      expect(result.detectedFormat, 'Structured CSV');

      final r1 = result.records[0];
      expect(r1.hostname, 'router-core-01');
      expect(r1.severity, SyslogSeverity.error);
      expect(r1.appName, 'bgpd');
      expect(r1.message, 'BGP peer 10.0.0.1 transitioned to DOWN');

      final r2 = result.records[1];
      expect(r2.hostname, 'firewall-edge');
      expect(r2.severity, SyslogSeverity.warning);
      expect(r2.appName, 'packet-filter');

      final r3 = result.records[2];
      expect(r3.hostname, 'srv-auth');
      expect(r3.severity, SyslogSeverity.informational);
      expect(r3.appName, 'sshd');
    });

    test('Imports raw packet lines from single-column CSV', () {
      const rawLinesCsv = '''<34>1 2026-10-24T08:00:00Z auth01.corp su 998 ID47 - Failed authentication for user guest
<187>Oct 24 08:05:00 switch-01 %LINK-3-UPDOWN: Interface GigabitEthernet0/1, changed state to down
''';

      final result = CsvImportService.parseCsv(rawLinesCsv);
      expect(result.importedCount, 2);

      final r1 = result.records[0];
      expect(r1.facility, SyslogFacility.auth);
      expect(r1.severity, SyslogSeverity.critical);
      expect(r1.hostname, 'auth01.corp');
      expect(r1.appName, 'su');
      expect(r1.message, 'Failed authentication for user guest');

      final r2 = result.records[1];
      expect(r2.facility, SyslogFacility.local7);
      expect(r2.severity, SyslogSeverity.error);
      expect(r2.hostname, 'switch-01');
    });

    test('Handles empty and malformed CSV input gracefully', () {
      final emptyResult = CsvImportService.parseCsv('');
      expect(emptyResult.importedCount, 0);

      final whitespaceResult = CsvImportService.parseCsv('   \n\n   ');
      expect(whitespaceResult.importedCount, 0);
    });

    test('SyslogRepository imports CSV and commits into SQLite database', () async {
      final dbService = SyslogDatabaseService(db: sqlite3.openInMemory());
      final repo = SyslogRepository(databaseService: dbService);

      const testCsv = '''Received At,Remote IP,Severity,Facility,Hostname,Message
2026-10-24T09:00:00Z,192.168.1.10,Error,daemon,web-01,"502 Bad Gateway"
2026-10-24T09:00:01Z,192.168.1.11,Warning,daemon,web-02,"High memory consumption"
''';

      final importResult = await repo.importCsvContent(
        testCsv,
        fileName: 'test_logs.csv',
        replaceExisting: true,
      );

      expect(importResult.importedCount, 2);
      expect(repo.loadedFileName, 'test_logs.csv');

      final totalInDb = repo.getLogCount(const SyslogFilterCriteria());
      expect(totalInDb, 2);

      final records = repo.getLogsPaged(filter: const SyslogFilterCriteria());
      expect(records.length, 2);
      expect(records.any((r) => r.message.contains('502 Bad Gateway')), isTrue);

      repo.dispose();
    });

    test('Export and import preserves manually entered device friendly names and updates SharedDeviceDatabase', () async {
      await SharedDeviceDatabase.instance.init(dbPath: ':memory:');

      const testMac = '00:1A:2B:3C:4D:5E';
      const friendlyName = 'Main Core Switch 01';

      // Manually register device name
      MacAddressHelper.updateDeviceName(testMac, friendlyName);
      expect(MacAddressHelper.getCustomName(testMac), friendlyName);

      // Create record referencing this device MAC
      final record = SyslogRecord(
        receivedAtMs: DateTime.now().millisecondsSinceEpoch,
        remoteIp: '192.168.1.1',
        remotePort: 514,
        transport: 'UDP',
        facility: SyslogFacility.local7,
        severity: SyslogSeverity.informational,
        hostname: 'sw-core-01',
        message: 'DHCPACK on 192.168.1.100 to $testMac via Gi1/0/1',
        rawPayload: '<189>1 2026-10-24T10:00:00Z sw-core-01 dhcpd - - - DHCPACK on 192.168.1.100 to $testMac via Gi1/0/1',
      );

      expect(record.customDeviceName, friendlyName);

      // Export to CSV
      final csvString = ExportService.logsToCsv([record]);
      expect(csvString, contains('Device Name'));
      expect(csvString, contains('MAC Address'));
      expect(csvString, contains(friendlyName));
      expect(csvString, contains(testMac));

      // Now reset the device name in database to verify import updates it
      SharedDeviceDatabase.instance.updateDeviceName(testMac, 'Old Switch');
      expect(MacAddressHelper.getCustomName(testMac), 'Old Switch');

      // Import the CSV via SyslogRepository
      final dbService = SyslogDatabaseService(db: sqlite3.openInMemory());
      final repo = SyslogRepository(databaseService: dbService);

      final importResult = await repo.importCsvContent(
        csvString,
        fileName: 'export_with_names.csv',
      );

      expect(importResult.importedCount, 1);
      expect(importResult.updatedDevicesCount, 1);
      expect(importResult.deviceMappings[testMac], friendlyName);

      // SharedDeviceDatabase should now be updated!
      expect(MacAddressHelper.getCustomName(testMac), friendlyName);

      // The imported record should also resolve customDeviceName
      final importedRecords = repo.getLogsPaged(filter: const SyslogFilterCriteria());
      expect(importedRecords.length, 1);
      expect(importedRecords.first.customDeviceName, friendlyName);

      repo.dispose();
    });

    test('Export and import via JSON updates SharedDeviceDatabase and restores logs', () async {
      await SharedDeviceDatabase.instance.init(dbPath: ':memory:');

      const testMac = '00:11:22:33:44:55';
      const friendlyName = 'Lobby Access Point';

      MacAddressHelper.updateDeviceName(testMac, friendlyName);

      final record = SyslogRecord(
        receivedAtMs: DateTime.now().millisecondsSinceEpoch,
        remoteIp: '192.168.1.254',
        remotePort: 514,
        transport: 'UDP',
        facility: SyslogFacility.local7,
        severity: SyslogSeverity.notice,
        hostname: 'ap-lobby-01',
        message: 'Client connected: $testMac',
        rawPayload: 'Client connected: $testMac',
      );

      final jsonString = ExportService.logsToJson([record]);
      expect(jsonString, contains('"device_name": "$friendlyName"'));
      expect(jsonString, contains('"mac_address": "$testMac"'));

      // Remove device from database
      SharedDeviceDatabase.instance.deleteDevice(testMac);
      expect(SharedDeviceDatabase.instance.getDeviceByMac(testMac), isNull);

      // Import JSON
      final dbService = SyslogDatabaseService(db: sqlite3.openInMemory());
      final repo = SyslogRepository(databaseService: dbService);

      final importResult = await repo.importCsvContent(
        jsonString,
        fileName: 'export.json',
      );

      expect(importResult.importedCount, 1);
      expect(importResult.detectedFormat, 'JSON');
      expect(importResult.updatedDevicesCount, 1);

      // Verified device was re-created in SharedDeviceDatabase
      final dev = SharedDeviceDatabase.instance.getDeviceByMac(testMac);
      expect(dev, isNotNull);
      expect(dev!.name, friendlyName);

      repo.dispose();
    });
  });
}
