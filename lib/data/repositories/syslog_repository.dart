import 'dart:async';
import '../../domain/models/network_adapter_info.dart';
import '../../domain/models/server_status.dart';
import '../../domain/models/syslog_filter.dart';
import '../../domain/models/syslog_record.dart';
import '../../domain/models/syslog_severity.dart';
import '../services/database/syslog_database_service.dart';
import '../services/generator/demo_syslog_generator.dart';
import '../services/import/csv_import_service.dart';
import '../services/listener/syslog_listener_service.dart';
import '../services/network/network_adapter_service.dart';

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
  String? _loadedFileName;

  final StreamController<List<SyslogRecord>> _batchStreamController =
      StreamController<List<SyslogRecord>>.broadcast();
  Stream<List<SyslogRecord>> get onBatchInserted => _batchStreamController.stream;

  final StreamController<ServerStatus> _statusStreamController =
      StreamController<ServerStatus>.broadcast();
  Stream<ServerStatus> get onStatusChanged => _statusStreamController.stream;

  ServerStatus get currentStatus => _listener.status;
  String? get loadedFileName => _loadedFileName;

  Future<List<NetworkAdapterInfo>> getNetworkAdapters() {
    return NetworkAdapterService.getAvailableAdapters();
  }

  void _handleBatchReceived(List<SyslogRecord> rawBatch) {
    if (rawBatch.isEmpty || _batchStreamController.isClosed) return;
    try {
      final inserted = _db.insertBatch(rawBatch);
      if (!_batchStreamController.isClosed) {
        _batchStreamController.add(inserted);
      }
    } catch (e) {
      _handleStatusChanged(_listener.status.copyWith(lastError: 'Database insert error: $e'));
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
    _loadedFileName = 'demo_traffic.csv';
    if (!_batchStreamController.isClosed) {
      _batchStreamController.add(inserted);
    }
  }

  Future<CsvImportResult> importCsvContent(
    String csvContent, {
    String? fileName,
    bool replaceExisting = false,
  }) async {
    if (replaceExisting) {
      clearLogs();
    }

    final result = CsvImportService.parseCsv(csvContent);
    if (result.records.isNotEmpty) {
      const chunkSize = 500;
      for (int i = 0; i < result.records.length; i += chunkSize) {
        final end = (i + chunkSize < result.records.length) ? i + chunkSize : result.records.length;
        final chunk = result.records.sublist(i, end);
        final inserted = _db.insertBatch(chunk);
        if (!_batchStreamController.isClosed) {
          _batchStreamController.add(inserted);
        }
      }
    }

    _loadedFileName = fileName ?? 'imported_logs.csv';
    return result;
  }

  void closeLoadedFile() {
    _loadedFileName = null;
  }

  void clearLogs() {
    _db.clearAll();
    _listener.resetStats();
    _loadedFileName = null;
  }

  void dispose() {
    _listener.stop();
    _batchStreamController.close();
    _statusStreamController.close();
    _db.close();
  }
}
