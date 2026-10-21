import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:syslog_server/data/repositories/syslog_repository.dart';
import 'package:syslog_server/data/services/database/syslog_database_service.dart';
import 'package:syslog_server/domain/models/syslog_facility.dart';
import 'package:syslog_server/domain/models/syslog_filter.dart';
import 'package:syslog_server/domain/models/syslog_severity.dart';

void main() {
  group('Live Syslog Network Listener Tests', () {
    late SyslogDatabaseService dbService;
    late SyslogRepository repository;
    const testPort = 15514;

    setUp(() {
      dbService = SyslogDatabaseService(db: sqlite3.openInMemory());
      repository = SyslogRepository(databaseService: dbService);
    });

    tearDown(() async {
      await repository.stopServer();
      repository.dispose();
    });

    test('Receives and parses live UDP syslog packets into SQLite', () async {
      await repository.startServer(
        port: testPort,
        bindAddress: '127.0.0.1',
        enableUdp: true,
        enableTcp: false,
      );

      final completer = Completer<void>();
      final sub = repository.onBatchInserted.listen((batch) {
        if (batch.isNotEmpty && !completer.isCompleted) {
          completer.complete();
        }
      });

      // Send a UDP packet from a test client
      final clientSocket = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
      const testMsg = '<134>1 2026-10-21T20:00:00Z test-device testapp 999 ID01 - Live network syslog test';
      final data = utf8.encode(testMsg);
      clientSocket.send(data, InternetAddress.loopbackIPv4, testPort);
      clientSocket.close();

      // Wait for ingestion
      await completer.future.timeout(const Duration(seconds: 3));
      await sub.cancel();

      final count = repository.getLogCount(const SyslogFilterCriteria());
      expect(count, greaterThanOrEqualTo(1));

      final logs = repository.getLogsPaged(filter: const SyslogFilterCriteria());
      final match = logs.firstWhere((l) => l.message == 'Live network syslog test');
      expect(match.remoteIp, '127.0.0.1');
      expect(match.appName, 'testapp');
      expect(match.procId, '999');
      // PRI 134: 134 >> 3 = 16 (local0), 134 & 7 = 6 (informational)
      expect(match.facility, SyslogFacility.local0);
      expect(match.severity, SyslogSeverity.informational);
    });
  });
}
