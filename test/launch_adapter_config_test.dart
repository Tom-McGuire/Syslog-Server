import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:syslog_server/data/repositories/syslog_repository.dart';
import 'package:syslog_server/data/services/database/syslog_database_service.dart';
import 'package:syslog_server/domain/models/launch_adapter_config.dart';
import 'package:syslog_server/domain/models/network_adapter_info.dart';
import 'package:syslog_server/ui/features/server/view_models/syslog_view_model.dart';

void main() {
  const loopback = NetworkAdapterInfo(name: 'lo', ipAddress: '127.0.0.1');
  const eth01 = NetworkAdapterInfo(name: 'eth01', ipAddress: '192.168.1.51');
  const eth0 = NetworkAdapterInfo(name: 'eth0', ipAddress: '192.168.1.50');
  const wlan0 = NetworkAdapterInfo(name: 'wlan0', ipAddress: '10.0.0.5');
  const wifi = NetworkAdapterInfo(name: 'Wi-Fi', ipAddress: '172.16.0.10');

  const sampleAdapters = [
    NetworkAdapterInfo.all,
    loopback,
    eth01,
    eth0,
    wlan0,
    wifi,
  ];

  group('LaunchAdapterConfig.fromArgs', () {
    test('returns empty config with no override for empty args', () {
      final config = LaunchAdapterConfig.fromArgs(const []);

      expect(config.adapterIp, isNull);
      expect(config.adapterName, isNull);
      expect(config.hasOverride, isFalse);
      expect(config.hasAdapterOverride, isFalse);
    });

    test('parses space-separated --adapter-ip and --adapter-name flags', () {
      final config = LaunchAdapterConfig.fromArgs(const [
        '--adapter-ip',
        '192.168.1.50',
        '--adapter-name',
        'eth0',
      ]);

      expect(config.adapterIp, '192.168.1.50');
      expect(config.adapterName, 'eth0');
      expect(config.hasOverride, isTrue);
      expect(config.hasAdapterOverride, isTrue);
    });

    test('parses equals-separated --adapter-ip= and --adapter-name= flags', () {
      final config = LaunchAdapterConfig.fromArgs(const [
        '--adapter-ip=10.0.0.5',
        '--adapter-name=wlan0',
      ]);

      expect(config.adapterIp, '10.0.0.5');
      expect(config.adapterName, 'wlan0');
      expect(config.hasOverride, isTrue);
      expect(config.hasAdapterOverride, isTrue);
    });

    test('ignores trailing flags without values safely', () {
      final ipOnlyTrailing = LaunchAdapterConfig.fromArgs(const [
        '--adapter-ip',
      ]);
      expect(ipOnlyTrailing.adapterIp, isNull);
      expect(ipOnlyTrailing.adapterName, isNull);
      expect(ipOnlyTrailing.hasOverride, isFalse);

      final nameTrailingAfterIp = LaunchAdapterConfig.fromArgs(const [
        '--adapter-ip',
        '192.168.1.50',
        '--adapter-name',
      ]);
      expect(nameTrailingAfterIp.adapterIp, '192.168.1.50');
      expect(nameTrailingAfterIp.adapterName, isNull);
      expect(nameTrailingAfterIp.hasOverride, isTrue);

      final ipFollowedByFlag = LaunchAdapterConfig.fromArgs(const [
        '--adapter-ip',
        '--adapter-name',
        'eth0',
      ]);
      expect(ipFollowedByFlag.adapterIp, isNull);
      expect(ipFollowedByFlag.adapterName, 'eth0');
    });

    test('ignores unknown flags and positional arguments safely', () {
      final config = LaunchAdapterConfig.fromArgs(const [
        '--verbose',
        '--port',
        '1514',
        'positional',
        '--adapter-ip=10.0.0.5',
        '--unknown=ignored',
        '--adapter-name',
        'Wi-Fi',
        '--trailing-unknown',
      ]);

      expect(config.adapterIp, '10.0.0.5');
      expect(config.adapterName, 'Wi-Fi');
      expect(config.hasOverride, isTrue);
    });

    test('trims whitespace and treats whitespace-only values as empty', () {
      final trimmed = LaunchAdapterConfig.fromArgs(const [
        '--adapter-ip',
        '  192.168.1.50  ',
        '--adapter-name=  eth0  ',
      ]);
      expect(trimmed.adapterIp, '192.168.1.50');
      expect(trimmed.adapterName, 'eth0');
      expect(trimmed.hasOverride, isTrue);

      final blankArgs = LaunchAdapterConfig.fromArgs(const [
        '--adapter-ip',
        '   ',
        '--adapter-name= \t ',
      ]);
      expect(blankArgs.adapterIp, isNull);
      expect(blankArgs.adapterName, isNull);
      expect(blankArgs.hasOverride, isFalse);
      expect(blankArgs.hasAdapterOverride, isFalse);

      const blankConstructed = LaunchAdapterConfig(
        adapterIp: '   ',
        adapterName: '\n\t',
      );
      expect(blankConstructed.hasOverride, isFalse);
      expect(blankConstructed.hasAdapterOverride, isFalse);
    });
  });

  group('LaunchAdapterConfig.matchAdapter', () {
    test('returns null when override is absent or adapters list is empty', () {
      expect(const LaunchAdapterConfig().matchAdapter(sampleAdapters), isNull);
      expect(
        const LaunchAdapterConfig(
          adapterIp: '   ',
          adapterName: '  ',
        ).matchAdapter(sampleAdapters),
        isNull,
      );
      expect(
        const LaunchAdapterConfig(adapterIp: '192.168.1.50')
            .matchAdapter(const []),
        isNull,
      );
    });

    test('Priority 1: matches exact IPv4 address even when name differs', () {
      const config = LaunchAdapterConfig(
        adapterIp: ' 192.168.1.50 ',
        adapterName: 'wlan0',
      );

      final matched = config.matchAdapter(sampleAdapters);
      expect(matched, equals(eth0));
      expect(matched?.name, 'eth0');
    });

    test('Priority 1: matches 0.0.0.0 when explicitly requested by IP', () {
      const config = LaunchAdapterConfig(adapterIp: '0.0.0.0');

      final matched = config.matchAdapter(sampleAdapters);
      expect(matched, equals(NetworkAdapterInfo.all));
    });

    test('falls back to Priority 2 name match when Priority 1 IPv4 misses', () {
      const config = LaunchAdapterConfig(
        adapterIp: '192.168.99.99',
        adapterName: 'wlan0',
      );

      final matched = config.matchAdapter(sampleAdapters);
      expect(matched, equals(wlan0));
    });

    test(
      'Priority 2: matches exact name case-insensitively before substrings',
      () {
        const exactNameConfig = LaunchAdapterConfig(adapterName: ' ETH0 ');
        final matchedByName = exactNameConfig.matchAdapter(sampleAdapters);
        expect(matchedByName, equals(eth0));
        expect(matchedByName?.name, 'eth0');

        const exactDisplayNameConfig = LaunchAdapterConfig(
          adapterName: 'wi-fi (172.16.0.10)',
        );
        final matchedByDisplay = exactDisplayNameConfig.matchAdapter(
          sampleAdapters,
        );
        expect(matchedByDisplay, equals(wifi));
      },
    );

    test(
      'Priority 2: matches substring name and displayName case-insensitively',
      () {
        const substringNameConfig = LaunchAdapterConfig(adapterName: 'LAN');
        expect(substringNameConfig.matchAdapter(sampleAdapters), equals(wlan0));

        const substringDisplayConfig = LaunchAdapterConfig(
          adapterName: '172.16.0',
        );
        expect(
          substringDisplayConfig.matchAdapter(sampleAdapters),
          equals(wifi),
        );
      },
    );

    test('Priority 2: skips NetworkAdapterInfo.all and 0.0.0.0 entries', () {
      const adaptersWithCustomZero = [
        NetworkAdapterInfo.all,
        NetworkAdapterInfo(name: 'Wildcard', ipAddress: '0.0.0.0'),
        eth0,
      ];

      expect(
        const LaunchAdapterConfig(adapterName: 'All Interfaces')
            .matchAdapter(adaptersWithCustomZero),
        isNull,
      );
      expect(
        const LaunchAdapterConfig(adapterName: 'all')
            .matchAdapter(adaptersWithCustomZero),
        isNull,
      );
      expect(
        const LaunchAdapterConfig(adapterName: '0.0.0.0')
            .matchAdapter(adaptersWithCustomZero),
        isNull,
      );
      expect(
        const LaunchAdapterConfig(adapterName: 'Wildcard')
            .matchAdapter(adaptersWithCustomZero),
        isNull,
      );
    });

    test('Priority 3: returns null when neither IP nor name matches', () {
      const config = LaunchAdapterConfig(
        adapterIp: '203.0.113.10',
        adapterName: 'nonexistent-nic',
      );

      expect(config.matchAdapter(sampleAdapters), isNull);
    });
  });

  group('SyslogRepository adapterProvider', () {
    test('returns adapters from custom adapterProvider', () async {
      final repository = SyslogRepository(
        databaseService: SyslogDatabaseService(db: sqlite3.openInMemory()),
        adapterProvider: () async => [NetworkAdapterInfo.all, eth0, wlan0],
      );
      addTearDown(repository.dispose);

      final adapters = await repository.getNetworkAdapters();
      expect(adapters, equals([NetworkAdapterInfo.all, eth0, wlan0]));
    });
  });

  group('SyslogViewModel initialAdapterConfig integration', () {
    SyslogViewModel createViewModel({
      required Future<List<NetworkAdapterInfo>> Function() adapterProvider,
      LaunchAdapterConfig? initialAdapterConfig,
    }) {
      final repository = SyslogRepository(
        databaseService: SyslogDatabaseService(db: sqlite3.openInMemory()),
        adapterProvider: adapterProvider,
      );
      final vm = SyslogViewModel(
        repository: repository,
        initialAdapterConfig: initialAdapterConfig,
      );
      addTearDown(vm.dispose);
      return vm;
    }

    test(
      'applies Priority 1 IPv4 pre-selection once on initial load',
      () async {
        final vm = createViewModel(
          adapterProvider: () async => [NetworkAdapterInfo.all, eth0, wlan0],
          initialAdapterConfig: const LaunchAdapterConfig(
            adapterIp: '10.0.0.5',
            adapterName: 'eth0',
          ),
        );

        await pumpEventQueue();

        expect(vm.adapters, equals([NetworkAdapterInfo.all, eth0, wlan0]));
        expect(vm.selectedAdapter, equals(wlan0));
        expect(vm.selectedAdapter.ipAddress, '10.0.0.5');
      },
    );

    test('applies Priority 2 name pre-selection on initial load', () async {
      final vmByName = createViewModel(
        adapterProvider: () async => [NetworkAdapterInfo.all, eth0, wlan0],
        initialAdapterConfig: const LaunchAdapterConfig(adapterName: 'ETH0'),
      );

      await pumpEventQueue();

      expect(vmByName.selectedAdapter, equals(eth0));

      final vmFallbackFromIp = createViewModel(
        adapterProvider: () async => [NetworkAdapterInfo.all, eth0, wlan0],
        initialAdapterConfig: const LaunchAdapterConfig(
          adapterIp: '192.168.99.99',
          adapterName: 'wlan',
        ),
      );

      await pumpEventQueue();

      expect(vmFallbackFromIp.selectedAdapter, equals(wlan0));
    });

    test('falls back to NetworkAdapterInfo.all when initialAdapterConfig misses or is null', () async {
      final vmNoMatch = createViewModel(
        adapterProvider: () async => [NetworkAdapterInfo.all, eth0, wlan0],
        initialAdapterConfig: const LaunchAdapterConfig(
          adapterIp: '203.0.113.99',
          adapterName: 'missing',
        ),
      );

      await pumpEventQueue();
      expect(vmNoMatch.selectedAdapter, equals(NetworkAdapterInfo.all));

      final vmNullConfig = createViewModel(
        adapterProvider: () async => [NetworkAdapterInfo.all, eth0, wlan0],
      );

      await pumpEventQueue();
      expect(vmNullConfig.selectedAdapter, equals(NetworkAdapterInfo.all));
    });

    test('does not overwrite manual selectAdapter when refreshAdapters is called again', () async {
      var availableAdapters = [NetworkAdapterInfo.all, eth0, wlan0];
      final vm = createViewModel(
        adapterProvider: () async => availableAdapters,
        initialAdapterConfig: const LaunchAdapterConfig(
          adapterIp: '192.168.1.50',
        ),
      );

      await pumpEventQueue();
      expect(vm.selectedAdapter, equals(eth0));

      // Manual selection to another adapter must persist across refresh.
      vm.selectAdapter(wlan0);
      expect(vm.selectedAdapter, equals(wlan0));

      await vm.refreshAdapters();
      expect(vm.selectedAdapter, equals(wlan0));

      // Manual selection to All Interfaces must also persist across refresh.
      vm.selectAdapter(NetworkAdapterInfo.all);
      expect(vm.selectedAdapter, equals(NetworkAdapterInfo.all));

      await vm.refreshAdapters();
      expect(vm.selectedAdapter, equals(NetworkAdapterInfo.all));

      // If a manually selected adapter disappears, fall back to All Interfaces
      // rather than re-applying initialAdapterConfig.
      vm.selectAdapter(wlan0);
      availableAdapters = [NetworkAdapterInfo.all, eth0];
      await vm.refreshAdapters();
      expect(vm.selectedAdapter, equals(NetworkAdapterInfo.all));
    });
  });
}
