import 'dart:async';
import '../../domain/models/server_status.dart';
import '../../domain/models/syslog_filter.dart';
import '../../domain/models/syslog_record.dart';
import '../../domain/models/syslog_severity.dart';
import '../services/database/syslog_database_service.dart';
import '../services/generator/demo_syslog_generator.dart';
import '../services/listener/syslog_listener_service.dart';
import '../services/network/network_adapter_service.dart';
import '../../domain/models/network_adapter_info.dart';

class SyslogRepository {
  SyslogRepository({
    SyslogDatabaseService? databaseService,
  }) : _db = databaseService ?? SyslogDatabaseService() {
    _listener = SyslogListenerService(
      onBatchReceived: _handleBatchReceived,
      onStatusChanged: _handleStatusChanged,
    );
  }

  final SyslogDatabaseService _db;
  late final SyslogListenerService _listener;

  final StreamController<List<SyslogRecord>> _batchStreamController =
      StreamController<List<SyslogRecord>>.broadcast();
  Stream<List<SyslogRecord>> get onBatchInserted => _batchStreamController.stream;

  final StreamController<ServerStatus> _statusStreamController =
      StreamController<ServerStatus>.broadcast();
  Stream<ServerStatus> get onStatusChanged => _statusStreamController.stream;

  ServerStatus get currentStatus => _listener.status;

  Future<List<NetworkAdapterInfo>> getNetworkAdapters() {
    return NetworkAdapterService.getAvailableAdapters();
  }

  void _handleBatchReceived(List<SyslogRecord> rawBatch) {
    if (rawBatch.isEmpty || _batchStreamController.isClosed) return;
    final inserted = _db.insertBatch(rawBatch);
    if (!_batchStreamController.isClosed) {
      _batchStreamController.add(inserted);
    }
  }

  void _handleStatusChanged(ServerStatus status) {
    if (!_statusStreamController.isClosed) {
      _statusStreamController.add(status);
    }
  }

  Future<void> startServer({
    int port = 514,
    String bindAddress = '0.0.0.0',
    bool enableUdp = true,
    bool enableTcp = true,
  }) async {
    await _listener.start(
      port: port,
      bindAddress: bindAddress,
      enableUdp: enableUdp,
      enableTcp: enableTcp,
    );
  }

  Future<void> stopServer() async {
    await _listener.stop();
  }

  List<SyslogRecord> getLogsPaged({
    int offset = 0,
    int limit = 1000,
    required SyslogFilterCriteria filter,
  }) {
    return _db.queryLogs(offset: offset, limit: limit, filter: filter);
  }

  int getLogCount(SyslogFilterCriteria filter) {
    return _db.countLogs(filter);
  }

  Map<SyslogSeverity, int> getSeverityCounts() {
    return _db.getSeverityCounts();
  }

  void loadDemoLogs() {
    final demoLogs = DemoSyslogGenerator.generateDemoLogs();
    final inserted = _db.insertBatch(demoLogs);
    _batchStreamController.add(inserted);
  }

  void clearLogs() {
    _db.clearAll();
    _listener.resetStats();
  }

  void dispose() {
    _listener.stop();
    _batchStreamController.close();
    _statusStreamController.close();
    _db.close();
  }
}
