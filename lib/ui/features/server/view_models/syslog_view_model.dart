import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import '../../../../data/repositories/syslog_repository.dart';
import '../../../../data/services/device/mac_address_helper.dart';
import '../../../../data/services/export/export_service.dart';
import '../../../../data/services/import/csv_import_service.dart';
import '../../../../domain/models/network_adapter_info.dart';
import '../../../../domain/models/server_status.dart';
import '../../../../domain/models/syslog_facility.dart';
import '../../../../domain/models/syslog_filter.dart';
import '../../../../domain/models/syslog_record.dart';
import '../../../../domain/models/syslog_severity.dart';

class SyslogViewModel extends ChangeNotifier {
  SyslogViewModel({SyslogRepository? repository})
      : _repository = repository ?? SyslogRepository() {
    _init();
  }

  final SyslogRepository _repository;
  SyslogRepository get repository => _repository;

  StreamSubscription? _batchSubscription;
  StreamSubscription? _statusSubscription;
  StreamSubscription? _sharedDeviceSubscription;
  Timer? _uiThrottleTimer;
  bool _pendingThrottleRefresh = false;

  List<SyslogRecord> _logs = [];
  SyslogRecord? _selectedRecord;
  int _totalLogCount = 0;
  Map<SyslogSeverity, int> _severityCounts = {
    for (final s in SyslogSeverity.values) s: 0,
  };

  SyslogFilterCriteria _filter = const SyslogFilterCriteria(
    sortColumn: 'id',
    sortAscending: false,
  );

  ServerStatus _serverStatus = const ServerStatus();
  List<NetworkAdapterInfo> _adapters = [NetworkAdapterInfo.all];
  NetworkAdapterInfo _selectedAdapter = NetworkAdapterInfo.all;

  bool _autoScroll = true;
  bool _isLoadingMore = false;
  bool _isImporting = false;
  static const int defaultPageSize = 1000;

  // Getters
  List<SyslogRecord> get logs => _logs;
  SyslogRecord? get selectedRecord => _selectedRecord;
  int get totalLogCount => _totalLogCount;
  Map<SyslogSeverity, int> get severityCounts => _severityCounts;
  SyslogFilterCriteria get filter => _filter;
  ServerStatus get serverStatus => _serverStatus;
  List<NetworkAdapterInfo> get adapters => _adapters;
  NetworkAdapterInfo get selectedAdapter => _selectedAdapter;
  String? get loadedFileName => _repository.loadedFileName;
  bool get autoScroll => _autoScroll;
  bool get isLoadingMore => _isLoadingMore;
  bool get isImporting => _isImporting;
  bool get hasMoreLogs => _logs.length < _totalLogCount;
  String get sortColumn => _filter.sortColumn;
  bool get sortAscending => _filter.sortAscending;

  void _init() {
    _serverStatus = _repository.currentStatus;

    _statusSubscription = _repository.onStatusChanged.listen((status) {
      _serverStatus = status;
      notifyListeners();
    });

    _batchSubscription = _repository.onBatchInserted.listen((newRecords) {
      if (_autoScroll) {
        _onBatchInsertedThrottled();
      } else {
        _totalLogCount = _repository.getLogCount(_filter);
        _severityCounts = _repository.getSeverityCounts();
        notifyListeners();
      }
    });

    try {
      _sharedDeviceSubscription =
          SharedDeviceDatabase.instance.onDatabaseChanged.listen((_) {
        notifyListeners();
      });
    } catch (_) {}

    _refreshState();
    refreshAdapters();
  }

  void _onBatchInsertedThrottled() {
    _pendingThrottleRefresh = true;
    if (_uiThrottleTimer != null && _uiThrottleTimer!.isActive) {
      return;
    }

    _uiThrottleTimer = Timer(const Duration(milliseconds: 250), () {
      if (_pendingThrottleRefresh) {
        _pendingThrottleRefresh = false;
        _refreshState();
      }
    });
  }

  Future<void> refreshAdapters() async {
    final list = await _repository.getNetworkAdapters();
    _adapters = list;
    if (!_adapters.contains(_selectedAdapter)) {
      _selectedAdapter = NetworkAdapterInfo.all;
    }
    notifyListeners();
  }

  void selectAdapter(NetworkAdapterInfo adapter) {
    if (_selectedAdapter == adapter) return;
    _selectedAdapter = adapter;
    notifyListeners();
  }

  void _refreshState() {
    _totalLogCount = _repository.getLogCount(_filter);
    _severityCounts = _repository.getSeverityCounts();
    final countToFetch = (_logs.isEmpty ? defaultPageSize : _logs.length).clamp(defaultPageSize, 20000);
    _logs = _repository.getLogsPaged(
      offset: 0,
      limit: countToFetch,
      filter: _filter,
    );
    notifyListeners();
  }

  Future<void> loadMoreLogs() async {
    if (_isLoadingMore || !hasMoreLogs) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      final nextBatch = _repository.getLogsPaged(
        offset: _logs.length,
        limit: defaultPageSize,
        filter: _filter,
      );
      _logs.addAll(nextBatch);
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  void selectRecord(SyslogRecord? record) {
    _selectedRecord = record;
    notifyListeners();
  }

  void toggleAutoScroll() {
    _autoScroll = !_autoScroll;
    notifyListeners();
  }

  // Server management
  Future<void> startServer({
    int port = 514,
    String? bindAddress,
    bool enableUdp = true,
    bool enableTcp = true,
  }) async {
    try {
      await _repository.startServer(
        port: port,
        bindAddress: bindAddress ?? _selectedAdapter.ipAddress,
        enableUdp: enableUdp,
        enableTcp: enableTcp,
      );
    } catch (_) {
      // Server error is handled and published via status stream
    }
  }

  Future<void> stopServer() async {
    await _repository.stopServer();
  }

  // Filter management
  void setSearchQuery(String query) {
    _filter = _filter.copyWith(searchQuery: query);
    _refreshState();
  }

  void toggleSeverity(SyslogSeverity severity) {
    final updated = Set<SyslogSeverity>.from(_filter.selectedSeverities);
    if (updated.contains(severity)) {
      updated.remove(severity);
    } else {
      updated.add(severity);
    }
    _filter = _filter.copyWith(selectedSeverities: updated);
    _refreshState();
  }

  void toggleFacility(SyslogFacility facility) {
    final updated = Set<SyslogFacility>.from(_filter.selectedFacilities);
    if (updated.contains(facility)) {
      updated.remove(facility);
    } else {
      updated.add(facility);
    }
    _filter = _filter.copyWith(selectedFacilities: updated);
    _refreshState();
  }

  void setRemoteIpFilter(String ip) {
    _filter = _filter.copyWith(remoteIp: ip);
    _refreshState();
  }

  void setSort(String column) {
    if (_filter.sortColumn == column) {
      _filter = _filter.copyWith(sortAscending: !_filter.sortAscending);
    } else {
      _filter = _filter.copyWith(sortColumn: column, sortAscending: true);
    }
    _refreshState();
  }

  void resetFilters() {
    _filter = const SyslogFilterCriteria(
      sortColumn: 'id',
      sortAscending: false,
    );
    _refreshState();
  }

  void clearLogs() {
    _repository.clearLogs();
    _logs.clear();
    _selectedRecord = null;
    _totalLogCount = 0;
    _severityCounts = {
      for (final s in SyslogSeverity.values) s: 0,
    };
    notifyListeners();
  }

  void loadDemoLogs() {
    _repository.loadDemoLogs();
    _refreshState();
  }

  Future<CsvImportResult?> importCsvFile({bool replaceExisting = true}) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'txt', 'log'],
      );

      if (result.isEmpty) return null;
      final file = result.first;
      String content;

      if (file.path != null) {
        content = await File(file.path!).readAsString();
      } else {
        final bytes = await file.readAsBytes();
        content = utf8.decode(bytes, allowMalformed: true);
      }

      _isImporting = true;
      notifyListeners();

      final importResult = await _repository.importCsvContent(
        content,
        fileName: file.name,
        replaceExisting: replaceExisting,
      );

      _refreshState();
      return importResult;
    } finally {
      _isImporting = false;
      notifyListeners();
    }
  }

  void closeLoadedFile() {
    _repository.closeLoadedFile();
    notifyListeners();
  }

  Future<String?> exportCsv() async {
    final allLogs = _repository.getLogsPaged(
      offset: 0,
      limit: 1000000,
      filter: _filter,
    );
    final csv = ExportService.logsToCsv(allLogs);
    return ExportService.saveToFile(
      content: csv,
      defaultFileName: 'syslog_export_${DateTime.now().millisecondsSinceEpoch}.csv',
      dialogTitle: 'Export Syslog to CSV',
    );
  }

  Future<String?> exportJson() async {
    final allLogs = _repository.getLogsPaged(
      offset: 0,
      limit: 1000000,
      filter: _filter,
    );
    final json = ExportService.logsToJson(allLogs);
    return ExportService.saveToFile(
      content: json,
      defaultFileName: 'syslog_export_${DateTime.now().millisecondsSinceEpoch}.json',
      dialogTitle: 'Export Syslog to JSON',
    );
  }

  /// Updates or assigns a friendly name to a device by MAC address in the shared database.
  void updateDeviceName(String mac, String newName) {
    MacAddressHelper.updateDeviceName(mac, newName);
    notifyListeners();
  }

  @override
  void dispose() {
    _uiThrottleTimer?.cancel();
    _batchSubscription?.cancel();
    _statusSubscription?.cancel();
    _sharedDeviceSubscription?.cancel();
    _repository.dispose();
    super.dispose();
  }
}
