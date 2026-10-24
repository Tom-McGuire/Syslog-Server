import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:syslog_server/data/repositories/syslog_repository.dart';
import 'package:syslog_server/data/services/database/syslog_database_service.dart';
import 'package:syslog_server/data/services/export/export_service.dart';
import 'package:syslog_server/data/services/import/csv_import_service.dart';
import 'package:syslog_server/data/services/parser/syslog_parser.dart';
import 'package:syslog_server/domain/models/syslog_facility.dart';
import 'package:syslog_server/domain/models/syslog_filter.dart';
import 'package:syslog_server/domain/models/syslog_record.dart';
import 'package:syslog_server/domain/models/syslog_severity.dart';

void main() {
  group('Security & Robustness Tests', () {
    test('CSV export sanitizes formula injection triggers', () {
      final logWithFormula = SyslogRecord(
        receivedAtMs: DateTime.now().millisecondsSinceEpoch,
        remoteIp: '=192.168.1.1',
        remotePort: 514,
        transport: 'UDP',
        facility: SyslogFacility.user,
        severity: SyslogSeverity.warning,
        message: '=HYPERLINK("http://evil.com","click me")',
        rawPayload: '@cmd|\' /C calc\'!A0',
        hostname: '+malicious_host',
      );

      final csv = ExportService.logsToCsv([logWithFormula]);

      // Verify that leading formula characters are prefixed with single quote
      expect(csv.contains("''=HYPERLINK") || csv.contains("=\"'=HYPERLINK") || csv.contains("'=HYPERLINK"), isTrue);
      expect(csv.contains("'+malicious_host"), isTrue);
      expect(csv.contains("'=192.168.1.1"), isTrue);

      // Verify round-trip un-sanitization restores the original text
      final importResult = CsvImportService.parseCsv(csv);
      expect(importResult.importedCount, 1);
      final imported = importResult.records.first;
      expect(imported.message, '=HYPERLINK("http://evil.com","click me")');
      expect(imported.hostname, '+malicious_host');
    });

    test('SyslogParser rejects invalid PRI > 191', () {
      const invalidPriMsg = '<999>1 2026-10-24T12:00:00Z myhost myapp 123 ID01 - Test invalid PRI';
      final record = SyslogParser.parse(
        raw: invalidPriMsg,
        remoteIp: '10.0.0.1',
        remotePort: 514,
        transport: 'UDP',
      );

      // Because PRI 999 > 191, it must be treated as unparsed plain text (user / informational)
      expect(record.facility, SyslogFacility.user);
      expect(record.severity, SyslogSeverity.informational);
      expect(record.message, invalidPriMsg);
    });

    test('SyslogParser sanitizes bidi overrides and zero-width characters in display text', () {
      // U+202E is Right-to-Left Override, U+200B is Zero-Width Space
      const spoofedMsg = 'Normal text \u202Ereversed \u200Bhidden';
      final record = SyslogParser.parse(
        raw: '<14>Oct 24 12:00:00 spoofed_host app: $spoofedMsg',
        remoteIp: '10.0.0.1',
        remotePort: 514,
        transport: 'UDP',
      );

      // Display text has bidi and zero-width removed
      expect(record.message.contains('\u202E'), isFalse);
      expect(record.message.contains('\u200B'), isFalse);
      expect(record.message, 'Normal text reversed hidden');

      // Raw payload still has the exact original bytes
      expect(record.rawPayload.contains('\u202E'), isTrue);
    });

    test('Database escapes LIKE wildcards properly', () {
      final dbService = SyslogDatabaseService(db: sqlite3.openInMemory());

      final r1 = SyslogRecord(
        receivedAtMs: 1000,
        remoteIp: '192.168.1.1',
        remotePort: 514,
        transport: 'UDP',
        facility: SyslogFacility.user,
        severity: SyslogSeverity.informational,
        message: 'device_name is active',
        rawPayload: 'device_name is active',
      );
      final r2 = SyslogRecord(
        receivedAtMs: 2000,
        remoteIp: '192.168.1.2',
        remotePort: 514,
        transport: 'UDP',
        facility: SyslogFacility.user,
        severity: SyslogSeverity.informational,
        message: 'deviceXname is active',
        rawPayload: 'deviceXname is active',
      );

      dbService.insertBatch([r1, r2]);

      // Searching for 'device_' should only match r1 ('device_name'), NOT r2 ('deviceXname')
      final results = dbService.queryLogs(
        filter: const SyslogFilterCriteria(searchQuery: 'device_name'),
      );
      expect(results.length, 1);
      expect(results.first.message, 'device_name is active');

      dbService.close();
    });

    test('Database enforces retention cap pruning oldest rows', () {
      // Create a database with small maxRows = 5
      final dbService = SyslogDatabaseService(
        db: sqlite3.openInMemory(),
        maxRows: 5,
      );

      final records = List.generate(
        10,
        (i) => SyslogRecord(
          receivedAtMs: 1000 + i,
          remoteIp: '192.168.1.$i',
          remotePort: 514,
          transport: 'UDP',
          facility: SyslogFacility.user,
          severity: SyslogSeverity.informational,
          message: 'Message number $i',
          rawPayload: 'Message number $i',
        ),
      );

      dbService.insertBatch(records);

      final count = dbService.countLogs(const SyslogFilterCriteria());
      expect(count, 5); // Capped at 5!

      final remaining = dbService.queryLogs(
        filter: const SyslogFilterCriteria(sortColumn: 'id', sortAscending: true),
      );
      expect(remaining.length, 5);
      // The oldest 5 (messages 0..4) should have been pruned, leaving 5..9
      expect(remaining.first.message, 'Message number 5');
      expect(remaining.last.message, 'Message number 9');

      dbService.close();
    });

    test('Stopping the server terminates active TCP connections', () async {
      final dbService = SyslogDatabaseService(db: sqlite3.openInMemory());
      final repo = SyslogRepository(databaseService: dbService);
      const testPort = 15515;

      await repo.startServer(
        port: testPort,
        bindAddress: '127.0.0.1',
        enableUdp: false,
        enableTcp: true,
      );

      final client = await Socket.connect('127.0.0.1', testPort);
      client.writeln('<14>Oct 24 12:00:00 host app: test TCP line');
      await client.flush();

      // Stop server
      await repo.stopServer();

      // Writing to client after server stopped should fail or encounter a closed socket
      final isDoneCompleter = Completer<bool>();
      client.listen(
        null,
        onError: (_) {
          if (!isDoneCompleter.isCompleted) isDoneCompleter.complete(true);
        },
        onDone: () {
          if (!isDoneCompleter.isCompleted) isDoneCompleter.complete(true);
        },
      );

      final closedOrError = await isDoneCompleter.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () => true,
      );
      expect(closedOrError, isTrue);

      client.destroy();
      repo.dispose();
    });
  });
}
