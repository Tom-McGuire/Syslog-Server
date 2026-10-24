import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../../../domain/models/server_status.dart';
import '../../../domain/models/syslog_record.dart';
import '../parser/syslog_parser.dart';

typedef BatchCallback = void Function(List<SyslogRecord> records);
typedef StatusCallback = void Function(ServerStatus status);

class SyslogListenerService {
  SyslogListenerService({
    required this.onBatchReceived,
    required this.onStatusChanged,
  });

  final BatchCallback onBatchReceived;
  final StatusCallback onStatusChanged;

  RawDatagramSocket? _udpSocket;
  ServerSocket? _tcpServer;
  final List<StreamSubscription> _subscriptions = [];
  final Set<Socket> _activeTcpClients = {};

  static const int maxConcurrentTcpClients = 256;
  static const int maxTcpLineLength = 65536; // 64 KB per line cap
  static const Duration tcpIdleTimeout = Duration(seconds: 120);

  final List<SyslogRecord> _buffer = [];
  Timer? _flushTimer;
  Timer? _rateTimer;

  int _totalCount = 0;
  int _totalBytes = 0;
  int _lastSecCount = 0;
  double _msgPerSec = 0.0;

  ServerStatus _currentStatus = const ServerStatus();
  ServerStatus get status => _currentStatus;

  Future<void> start({
    int port = 514,
    String bindAddress = '0.0.0.0',
    bool enableUdp = true,
    bool enableTcp = true,
  }) async {
    await stop();

    _currentStatus = _currentStatus.copyWith(
      port: port,
      bindAddress: bindAddress,
      udpEnabled: enableUdp,
      tcpEnabled: enableTcp,
      clearError: true,
    );
    onStatusChanged(_currentStatus);

    final address = bindAddress == '0.0.0.0'
        ? InternetAddress.anyIPv4
        : InternetAddress(bindAddress);

    try {
      // 1. Start UDP Socket (exclusive bind to detect port collisions reliably)
      if (enableUdp) {
        _udpSocket = await RawDatagramSocket.bind(address, port, reuseAddress: false);
        final sub = _udpSocket!.listen(
          _handleUdpEvent,
          onError: (e) => _handleError('UDP Socket error: $e'),
          onDone: () => _handleError('UDP Socket closed'),
        );
        _subscriptions.add(sub);
      }

      // 2. Start TCP Server (shared: false prevents another process splitting connections)
      if (enableTcp) {
        _tcpServer = await ServerSocket.bind(address, port, shared: false);
        final sub = _tcpServer!.listen(
          _handleTcpClient,
          onError: (e) => _handleError('TCP Server error: $e'),
          onDone: () => _handleError('TCP Server closed'),
        );
        _subscriptions.add(sub);
      }

      // 3. Start batch flush timer (every 50ms)
      _flushTimer = Timer.periodic(const Duration(milliseconds: 50), (_) => _flushBuffer());

      // 4. Start throughput rate calculation timer (every 1s)
      _rateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        final current = _totalCount;
        _msgPerSec = (current - _lastSecCount).toDouble();
        _lastSecCount = current;
        _currentStatus = _currentStatus.copyWith(messagesPerSecond: _msgPerSec);
        onStatusChanged(_currentStatus);
      });

      _currentStatus = _currentStatus.copyWith(
        isListening: true,
        clearError: true,
      );
      onStatusChanged(_currentStatus);
    } catch (e) {
      await stop();
      final errorMsg = _formatSocketError(e, port);
      _currentStatus = _currentStatus.copyWith(
        isListening: false,
        lastError: errorMsg,
      );
      onStatusChanged(_currentStatus);
      rethrow;
    }
  }

  void _handleUdpEvent(RawSocketEvent event) {
    if (!_currentStatus.isListening) return;

    if (event == RawSocketEvent.read && _udpSocket != null) {
      while (true) {
        final dg = _udpSocket!.receive();
        if (dg == null) break;

        _totalBytes += dg.data.length;
        _totalCount++;

        final rawString = utf8.decode(dg.data, allowMalformed: true);
        final record = SyslogParser.parse(
          raw: rawString,
          remoteIp: dg.address.address,
          remotePort: dg.port,
          transport: 'UDP',
        );

        _buffer.add(record);
        if (_buffer.length >= 200) {
          _flushBuffer();
        }
      }
    }
  }

  void _handleTcpClient(Socket client) {
    if (!_currentStatus.isListening || _activeTcpClients.length >= maxConcurrentTcpClients) {
      client.destroy();
      return;
    }

    _activeTcpClients.add(client);
    final clientIp = client.remoteAddress.address;
    final clientPort = client.remotePort;

    final lineBuffer = BytesBuilder(copy: false);
    StreamSubscription? clientSub;

    void cleanupClient() {
      _activeTcpClients.remove(client);
      clientSub?.cancel();
      try {
        client.destroy();
      } catch (_) {}
    }

    clientSub = client
        .timeout(
          tcpIdleTimeout,
          onTimeout: (sink) {
            cleanupClient();
          },
        )
        .listen(
          (Uint8List chunk) {
            if (!_currentStatus.isListening) {
              cleanupClient();
              return;
            }

            // Raw byte count (correct bytes accounting)
            _totalBytes += chunk.length;

            for (int i = 0; i < chunk.length; i++) {
              final byte = chunk[i];
              if (byte == 10) { // \n newline delimiter
                final lineBytes = lineBuffer.takeBytes();
                if (lineBytes.isNotEmpty) {
                  _processTcpLine(lineBytes, clientIp, clientPort);
                }
              } else if (byte != 13) { // ignore \r
                lineBuffer.addByte(byte);
                // Memory exhaustion defense: cap maximum line length
                if (lineBuffer.length >= maxTcpLineLength) {
                  final lineBytes = lineBuffer.takeBytes();
                  _processTcpLine(lineBytes, clientIp, clientPort);
                }
              }
            }
          },
          onError: (_) {
            cleanupClient();
          },
          onDone: () {
            // Process any trailing bytes before closing
            if (lineBuffer.isNotEmpty && _currentStatus.isListening) {
              final trailing = lineBuffer.takeBytes();
              _processTcpLine(trailing, clientIp, clientPort);
            }
            cleanupClient();
          },
          cancelOnError: true,
        );

    _subscriptions.add(clientSub);
  }

  void _processTcpLine(Uint8List lineBytes, String clientIp, int clientPort) {
    final rawLine = utf8.decode(lineBytes, allowMalformed: true).trim();
    if (rawLine.isEmpty) return;

    _totalCount++;
    final record = SyslogParser.parse(
      raw: rawLine,
      remoteIp: clientIp,
      remotePort: clientPort,
      transport: 'TCP',
    );

    _buffer.add(record);
    if (_buffer.length >= 200) {
      _flushBuffer();
    }
  }

  void _flushBuffer() {
    if (_buffer.isEmpty) return;
    final batch = List<SyslogRecord>.from(_buffer);
    _buffer.clear();
    onBatchReceived(batch);

    _currentStatus = _currentStatus.copyWith(
      totalReceivedCount: _totalCount,
      totalBytesReceived: _totalBytes,
    );
    onStatusChanged(_currentStatus);
  }

  void _handleError(String message) {
    _currentStatus = _currentStatus.copyWith(lastError: message);
    onStatusChanged(_currentStatus);
  }

  String _formatSocketError(dynamic e, int port) {
    final str = e.toString();
    if (str.contains('10048') || str.contains('Address already in use')) {
      return 'Port $port is already in use by another application or service.';
    }
    if (str.contains('10013') || str.contains('Permission denied')) {
      if (port < 1024) {
        return 'Binding to port $port requires Administrator / root privileges, or use a port > 1024 (e.g. 1514 or 5140).';
      }
      return 'Permission denied to bind port $port. Check firewall or security policies.';
    }
    return str;
  }

  Future<void> stop() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _rateTimer?.cancel();
    _rateTimer = null;

    _flushBuffer();

    // Close and destroy all active TCP client sockets
    for (final client in _activeTcpClients) {
      try {
        client.destroy();
      } catch (_) {}
    }
    _activeTcpClients.clear();

    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();

    _udpSocket?.close();
    _udpSocket = null;

    await _tcpServer?.close();
    _tcpServer = null;

    _msgPerSec = 0.0;
    _currentStatus = _currentStatus.copyWith(
      isListening: false,
      messagesPerSecond: 0.0,
    );
    onStatusChanged(_currentStatus);
  }

  void resetStats() {
    _totalCount = 0;
    _totalBytes = 0;
    _lastSecCount = 0;
    _msgPerSec = 0.0;
    _currentStatus = _currentStatus.copyWith(
      totalReceivedCount: 0,
      totalBytesReceived: 0,
      messagesPerSecond: 0.0,
    );
    onStatusChanged(_currentStatus);
  }
}
