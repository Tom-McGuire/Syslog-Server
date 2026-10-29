import 'package:flutter_test/flutter_test.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:syslog_server/data/services/device/mac_address_helper.dart';
import 'package:syslog_server/data/services/generator/demo_syslog_generator.dart';
import 'package:syslog_server/data/services/parser/syslog_parser.dart';

void main() {
  group('Shared Device Library & MAC Dissection Tests', () {
    test('extractMacs detects and normalizes colon, hyphen, and Cisco dot formats', () {
      const text =
          'DHCPACK on 192.168.1.100 to 00:1a:2b:3c:4d:5e, dot1x client (00-11-22-33-44-55), '
          'and arp inspect 001a.2b3c.4d5e. Duplicate 00:1A:2B:3C:4D:5E ignored.';

      final macs = MacAddressHelper.extractMacs(text);

      expect(macs.length, 2);
      expect(macs, contains('00:1A:2B:3C:4D:5E'));
      expect(macs, contains('00:11:22:33:44:55'));
    });

    test('extractMacs rejects invalid or malformed strings', () {
      const invalid = '192.168.1.1 00:11:22:33:44 1234567890123 abcdefghijkl test string';
      final macs = MacAddressHelper.extractMacs(invalid);
      expect(macs, isEmpty);
    });

    test('SyslogRecord exposes detectedMacs from message payload', () {
      final record = SyslogParser.parse(
        raw: '<134>1 2026-10-21T19:30:36.100Z core-sw01 dhcpd 1245 - - DHCPACK to 00:1A:2B:3C:4D:5E via Gi1/0/5',
        remoteIp: '192.168.1.1',
        remotePort: 514,
        transport: 'UDP',
      );

      expect(record.detectedMacs, isNotEmpty);
      expect(record.detectedMacs.first, '00:1A:2B:3C:4D:5E');
    });

    test('DemoSyslogGenerator produces logs with detectable MAC addresses', () {
      final demoLogs = DemoSyslogGenerator.generateDemoLogs();
      final logsWithMacs = demoLogs.where((r) => r.detectedMacs.isNotEmpty).toList();

      expect(logsWithMacs.length, greaterThanOrEqualTo(3));
      expect(logsWithMacs.any((r) => r.detectedMacs.contains('00:1A:2B:3C:4D:5E')), isTrue);
    });

    test('SharedDeviceDatabase resolves device friendly name and handles updateDeviceName', () async {
      final db = SharedDeviceDatabase();
      await db.init(dbPath: ':memory:');

      const testMac = '00:1A:2B:3C:4D:5E';

      // Initially no custom name
      expect(db.getDeviceByMac(testMac), isNull);

      // Register device
      db.upsertDevice(SharedDevice(
        macAddress: testMac,
        name: 'Core Distribution Switch',
        vendor: 'Cisco Systems',
        deviceType: 'switch',
        sourceApp: 'syslog-server',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ));

      final retrieved = db.getDeviceByMac(testMac);
      expect(retrieved, isNotNull);
      expect(retrieved!.name, 'Core Distribution Switch');
      expect(retrieved.vendor, 'Cisco Systems');

      // Update name
      db.updateDeviceName(testMac, 'Main Core Switch 01');
      final updated = db.getDeviceByMac(testMac);
      expect(updated!.name, 'Main Core Switch 01');
    });

    test('MacAddressHelper gracefully falls back when database is uninitialized', () {
      // Without initializing SharedDeviceDatabase.instance
      const testMac = '00:1A:2B:3C:4D:5E';
      final displayName = MacAddressHelper.getDisplayName(testMac);
      expect(displayName, isNotEmpty);

      final vendor = MacAddressHelper.getVendor(testMac);
      expect(vendor, isNotEmpty);

      // Does not throw
      expect(() => MacAddressHelper.getCategory(testMac), returnsNormally);
    });
  });
}
