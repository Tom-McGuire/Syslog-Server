class NetworkAdapterInfo {
  const NetworkAdapterInfo({
    required this.name,
    required this.ipAddress,
    this.isAllInterfaces = false,
  });

  final String name;
  final String ipAddress;
  final bool isAllInterfaces;

  static const all = NetworkAdapterInfo(
    name: 'All Interfaces',
    ipAddress: '0.0.0.0',
    isAllInterfaces: true,
  );

  String get displayName {
    if (isAllInterfaces) {
      return 'All Interfaces (0.0.0.0)';
    }
    return '$name ($ipAddress)';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkAdapterInfo &&
          runtimeType == other.runtimeType &&
          ipAddress == other.ipAddress;

  @override
  int get hashCode => ipAddress.hashCode;
}
