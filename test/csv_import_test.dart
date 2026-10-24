import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:syslog_server/data/repositories/syslog_repository.dart';
import 'package:syslog_server/data/services/database/syslog_database_service.dart';
import 'package:syslog_server/data/services/export/export_service.dart';
import 'package:syslog_server/data/services/generator/demo_syslog_generator.dart';
import 'package:syslog_server/data/services/import/csv_import_service.dart';
import 'package:syslog_server/domain/models/syslog_facility.dart';
import 'package:syslog_server/domain/models/syslog_filter.dart';
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
  });
}
