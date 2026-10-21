class ServerStatus {
  const ServerStatus({
    this.isListening = false,
    this.port = 514,
    this.bindAddress = '0.0.0.0',
    this.udpEnabled = true,
    this.tcpEnabled = true,
    this.totalReceivedCount = 0,
    this.totalBytesReceived = 0,
    this.messagesPerSecond = 0.0,
    this.lastError,
  });

  final bool isListening;
  final int port;
  final String bindAddress;
  final bool udpEnabled;
  final bool tcpEnabled;
  final int totalReceivedCount;
  final int totalBytesReceived;
  final double messagesPerSecond;
  final String? lastError;

  ServerStatus copyWith({
    bool? isListening,
    int? port,
    String? bindAddress,
    bool? udpEnabled,
    bool? tcpEnabled,
    int? totalReceivedCount,
    int? totalBytesReceived,
    double? messagesPerSecond,
    String? lastError,
    bool clearError = false,
  }) {
    return ServerStatus(
      isListening: isListening ?? this.isListening,
      port: port ?? this.port,
      bindAddress: bindAddress ?? this.bindAddress,
      udpEnabled: udpEnabled ?? this.udpEnabled,
      tcpEnabled: tcpEnabled ?? this.tcpEnabled,
      totalReceivedCount: totalReceivedCount ?? this.totalReceivedCount,
      totalBytesReceived: totalBytesReceived ?? this.totalBytesReceived,
      messagesPerSecond: messagesPerSecond ?? this.messagesPerSecond,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}
