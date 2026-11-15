import 'network_adapter_info.dart';

/// Launch-time CLI configuration for pre-selecting a network adapter.
class LaunchAdapterConfig {
  /// Creates a [LaunchAdapterConfig] with optional IP and name overrides.
  const LaunchAdapterConfig({this.adapterIp, this.adapterName});

  /// Parses adapter selection overrides from command-line [args].
  ///
  /// Supports `--adapter-ip <ip>`, `--adapter-ip=<ip>`,
  /// `--adapter-name <name>`, and `--adapter-name=<name>`. Unknown flags and
  /// trailing flags without values are safely ignored.
  factory LaunchAdapterConfig.fromArgs(List<String> args) {
    String? adapterIp;
    String? adapterName;

    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--adapter-ip' || arg == '--adapter-name') {
        if (i + 1 < args.length && !args[i + 1].startsWith('--')) {
          final value = _normalizeArgValue(args[++i]);
          if (arg == '--adapter-ip') {
            adapterIp = value;
          } else {
            adapterName = value;
          }
        }
      } else if (arg.startsWith('--adapter-ip=')) {
        adapterIp = _normalizeArgValue(arg.substring('--adapter-ip='.length));
      } else if (arg.startsWith('--adapter-name=')) {
        adapterName = _normalizeArgValue(
          arg.substring('--adapter-name='.length),
        );
      }
    }

    return LaunchAdapterConfig(adapterIp: adapterIp, adapterName: adapterName);
  }

  /// The requested IPv4 bind address override, if any.
  final String? adapterIp;

  /// The requested adapter name or display-name override, if any.
  final String? adapterName;

  /// Whether either [adapterIp] or [adapterName] is non-empty after trimming.
  bool get hasOverride =>
      (adapterIp != null && adapterIp!.trim().isNotEmpty) ||
      (adapterName != null && adapterName!.trim().isNotEmpty);

  /// Whether any launch-time adapter override is configured.
  bool get hasAdapterOverride => hasOverride;

  /// Matches the highest-priority adapter from [adapters], or `null` if none match.
  ///
  /// Priority 1 matches an exact IPv4 address against [adapterIp].
  /// Priority 2 matches [adapterName] case-insensitively (exact match first,
  /// then substring match) against `name` and `displayName`, skipping
  /// `NetworkAdapterInfo.all` (`0.0.0.0`).
  /// Priority 3 returns `null` when no candidate matches.
  NetworkAdapterInfo? matchAdapter(List<NetworkAdapterInfo> adapters) {
    if (!hasOverride || adapters.isEmpty) {
      return null;
    }

    final targetIp = adapterIp?.trim();
    if (targetIp != null && targetIp.isNotEmpty) {
      for (final adapter in adapters) {
        if (adapter.ipAddress == targetIp) {
          return adapter;
        }
      }
    }

    final rawName = adapterName?.trim();
    if (rawName != null && rawName.isNotEmpty) {
      final targetName = rawName.toLowerCase();
      final candidates = adapters
          .where((a) => !a.isAllInterfaces && a.ipAddress != '0.0.0.0')
          .toList();

      for (final adapter in candidates) {
        if (adapter.name.toLowerCase() == targetName ||
            adapter.displayName.toLowerCase() == targetName) {
          return adapter;
        }
      }

      for (final adapter in candidates) {
        if (adapter.name.toLowerCase().contains(targetName) ||
            adapter.displayName.toLowerCase().contains(targetName)) {
          return adapter;
        }
      }
    }

    return null;
  }

  static String? _normalizeArgValue(String raw) {
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LaunchAdapterConfig &&
          runtimeType == other.runtimeType &&
          adapterIp == other.adapterIp &&
          adapterName == other.adapterName;

  @override
  int get hashCode => Object.hash(adapterIp, adapterName);

  @override
  String toString() =>
      'LaunchAdapterConfig(adapterIp: $adapterIp, adapterName: $adapterName)';
}
