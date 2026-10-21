import 'package:flutter_test/flutter_test.dart';
import 'package:syslog_server/data/services/parser/syslog_parser.dart';
import 'package:syslog_server/domain/models/syslog_facility.dart';
import 'package:syslog_server/domain/models/syslog_severity.dart';

void main() {
  group('SyslogParser Tests', () {
    test('Parses RFC 5424 structured syslog message correctly', () {
      const raw =
          '<34>1 2026-10-21T22:14:15.003Z mymachine.example.com su 12345 ID47 [exampleSDID@32473 iut="3"] \'su root\' failed for lonvick';
      final record = SyslogParser.parse(
        raw: raw,
        remoteIp: '192.168.1.50',
        remotePort: 514,
        transport: 'UDP',
      );

      // PRI 34: 34 >> 3 = 4 (auth), 34 & 7 = 2 (critical)
      expect(record.facility, SyslogFacility.auth);
      expect(record.severity, SyslogSeverity.critical);
      expect(record.hostname, 'mymachine.example.com');
      expect(record.appName, 'su');
      expect(record.procId, '12345');
      expect(record.msgId, 'ID47');
      expect(record.message, "'su root' failed for lonvick");
      expect(record.remoteIp, '192.168.1.50');
      expect(record.transport, 'UDP');
    });

    test('Parses RFC 3164 BSD syslog message correctly', () {
      const raw =
          '<13>Oct 11 22:14:15 mymachine su[1234]: \'su root\' failed for lonvick on /dev/pts/8';
      final record = SyslogParser.parse(
        raw: raw,
        remoteIp: '10.0.0.1',
        remotePort: 514,
        transport: 'UDP',
      );

      // PRI 13: 13 >> 3 = 1 (user), 13 & 7 = 5 (notice)
      expect(record.facility, SyslogFacility.user);
      expect(record.severity, SyslogSeverity.notice);
      expect(record.timestampStr, 'Oct 11 22:14:15');
      expect(record.hostname, 'mymachine');
      expect(record.appName, 'su');
      expect(record.procId, '1234');
      expect(record.message, "'su root' failed for lonvick on /dev/pts/8");
    });

    test('Parses Cisco ASA log message correctly', () {
      const raw =
          '<189>1 2026-10-21T19:30:00.123Z fw01.corp.local cisco-asa 412001 - - %ASA-5-111008: User \'admin\' executed the \'show running-config\' command.';
      final record = SyslogParser.parse(
        raw: raw,
        remoteIp: '192.168.1.1',
        remotePort: 514,
        transport: 'UDP',
      );

      // PRI 189: 189 >> 3 = 23 (local7), 189 & 7 = 5 (notice)
      expect(record.facility, SyslogFacility.local7);
      expect(record.severity, SyslogSeverity.notice);
      expect(record.hostname, 'fw01.corp.local');
      expect(record.appName, 'cisco-asa');
      expect(record.message, "%ASA-5-111008: User 'admin' executed the 'show running-config' command.");
    });

    test('Handles unstructured plain text gracefully', () {
      const raw = 'Simple plain log message with no headers';
      final record = SyslogParser.parse(
        raw: raw,
        remoteIp: '127.0.0.1',
        remotePort: 55432,
        transport: 'TCP',
      );

      expect(record.facility, SyslogFacility.user);
      expect(record.severity, SyslogSeverity.informational);
      expect(record.message, 'Simple plain log message with no headers');
    });
  });
}
