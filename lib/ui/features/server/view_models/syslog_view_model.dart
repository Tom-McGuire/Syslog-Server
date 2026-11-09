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
  bool _isDisposed = false;

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
  bool _showAutoDetected = false;
  Map<String, bool> _devicePreferences = {};
  Map<String, int> _deviceCounts = {};
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
  bool get showAutoDetected => _showAutoDetected;
  Set<String> get selectedDeviceKeys => _filter.selectedDeviceKeys;
  Map<String, bool> get devicePreferences => _devicePreferences;
  Map<String, int> get deviceCounts => _deviceCounts;

  /// Checks whether a specific [SharedDevice] is visible as a filter pill in this application.
  /// Devices without custom names are automatically hidden by default unless explicitly unhidden.
  /// Devices with custom names are visible by default unless explicitly hidden.
  bool isDeviceVisible(SharedDevice d) {
    if (_devicePreferences.containsKey(d.macAddress)) {
      return !_devicePreferences[d.macAddress]!;
    }
    return d.hasCustomName;
  }

  /// Checks whether an arbitrary device key (MAC, IP, Hostname) is visible in this application.
  bool isDeviceKeyVisible(String key) {
    if (SharedDevice.isValidMac(key)) {
      try {
        if (SharedDeviceDatabase.instance.isInitialized) {
          final d = SharedDeviceDatabase.instance.getDeviceByMac(key);
          if (d != null) {
            return isDeviceVisible(d);
          }
        }
      } catch (_) {}
      if (_devicePreferences.containsKey(key)) {
        return !_devicePreferences[key]!;
      }
      return false;
    }
    if (_devicePreferences.containsKey(key)) {
      return !_devicePreferences[key]!;
    }
    return true;
  }

  /// Known devices from SharedDeviceDatabase that have been given a custom name
  List<SharedDevice> get knownDevices {
    try {
      if (!SharedDeviceDatabase.instance.isInitialized) return [];
      return SharedDeviceDatabase.instance
          .getAllDevices()
          .where((d) => d.hasCustomName)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Unknown devices in SharedDeviceDatabase without custom names
  List<SharedDevice> get unknownDevices {
    try {
      if (!SharedDeviceDatabase.instance.isInitialized) return [];
      return SharedDeviceDatabase.instance
          .getAllDevices()
          .where((d) => !d.hasCustomName)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// All devices from SharedDeviceDatabase currently visible in the filter bar
  List<SharedDevice> get visibleDevices {
    try {
      if (!SharedDeviceDatabase.instance.isInitialized) return [];
      return SharedDeviceDatabase.instance
          .getAllDevices()
          .where(isDeviceVisible)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Backward-compatible alias for [visibleDevices]
  List<SharedDevice> get knownLabeledDevices => visibleDevices;

  /// Set of device keys currently hidden in this application
  Set<String> get hiddenDeviceKeys {
    final hidden = <String>{};
    try {
      if (SharedDeviceDatabase.instance.isInitialized) {
        final all = SharedDeviceDatabase.instance.getAllDevices();
        for (final d in all) {
          if (!isDeviceVisible(d)) {
            hidden.add(d.macAddress);
          }
        }
      }
    } catch (_) {}
    for (final entry in _devicePreferences.entries) {
      if (entry.value) {
        hidden.add(entry.key);
      }
    }
    return hidden;
  }

  /// Discovered syslog sending IPs or hostnames that are not in visible devices and not hidden
  List<String> get autoDetectedSources {
    final sources = <String>[];
    final visibleMacs = visibleDevices.map((d) => d.macAddress.toUpperCase()).toSet();
    final visibleNames = visibleDevices.map((d) => d.name.toLowerCase()).toSet();

    final ipCounts = _repository.getRemoteIpCounts(_filter);
    for (final ip in ipCounts.keys) {
      if ((_devicePreferences[ip] != true) && !visibleNames.contains(ip.toLowerCase())) {
        sources.add(ip);
      }
    }

    final hostCounts = _repository.getHostnameCounts(_filter);
    for (final host in hostCounts.keys) {
      if ((_devicePreferences[host] != true) &&
          !visibleNames.contains(host.toLowerCase()) &&
          !visibleMacs.contains(host.toUpperCase()) &&
          !sources.contains(host)) {
        sources.add(host);
      }
    }
    return sources;
  }

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
        _severityCounts = _repository.getSeverityCounts(_filter);
        notifyListeners();
      }
    });

    try {
      _sharedDeviceSubscription =
          SharedDeviceDatabase.instance.onDatabaseChanged.listen((_) {
        notifyListeners();
      });
    } catch (_) {}

    try {
      _devicePreferences = _repository.getDevicePreferences();
    } catch (_) {}

    try {
      final savedShowAuto = _repository.getAppState('show_auto_detected');
      if (savedShowAuto != null) {
        _showAutoDetected = savedShowAuto == 'true';
      }
      final savedSelected = _repository.getAppState('selected_device_keys');
      if (savedSelected != null && savedSelected.isNotEmpty) {
        final decoded = jsonDecode(savedSelected);
        if (decoded is List) {
          _filter = _filter.copyWith(selectedDeviceKeys: decoded.cast<String>().toSet());
        }
      }
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
      if (_isDisposed) return;
      if (_pendingThrottleRefresh) {
        _pendingThrottleRefresh = false;
        _refreshState();
      }
    });
  }

  Future<void> refreshAdapters() async {
    final list = await _repository.getNetworkAdapters();
    if (_isDisposed) return;
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
    _severityCounts = _repository.getSeverityCounts(_filter);

    final newDeviceCounts = <String, int>{};
    for (final dev in knownLabeledDevices) {
      newDeviceCounts[dev.macAddress] = _repository.getCountForDeviceKey(dev.macAddress, _filter);
    }
    if (_showAutoDetected) {
      for (final src in autoDetectedSources) {
        newDeviceCounts[src] = _repository.getCountForDeviceKey(src, _filter);
      }
    }
    _deviceCounts = newDeviceCounts;

    final countToFetch = (_logs.isEmpty ? defaultPageSize : _logs.length).clamp(defaultPageSize, 20000);
    _logs = _repository.getLogsPaged(
      offset: 0,
      limit: countToFetch,
      filter: _filter,
    );
    notifyListeners();
  }

  Future<void> loadMoreLogs() async {
    if (_isLoadingMore || !hasMoreLogs || _isDisposed) return;

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
      if (!_isDisposed) {
        notifyListeners();
      }
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

  void setShowAutoDetected(bool value) {
    if (_showAutoDetected == value) return;
    _showAutoDetected = value;
    try {
      _repository.setAppState('show_auto_detected', value.toString());
    } catch (_) {}
    _refreshState();
  }

  void _persistSelectedDeviceKeys() {
    try {
      _repository.setAppState(
        'selected_device_keys',
        jsonEncode(_filter.selectedDeviceKeys.toList()),
      );
    } catch (_) {}
  }

  void toggleDeviceFilter(String key) {
    final updated = Set<String>.from(_filter.selectedDeviceKeys);
    if (updated.contains(key)) {
      updated.remove(key);
    } else {
      updated.add(key);
    }
    _filter = _filter.copyWith(selectedDeviceKeys: updated);
    _persistSelectedDeviceKeys();
    _refreshState();
  }

  void clearDeviceFilters() {
    if (_filter.selectedDeviceKeys.isEmpty) return;
    _filter = _filter.copyWith(selectedDeviceKeys: const {});
    _persistSelectedDeviceKeys();
    _refreshState();
  }

  void toggleDeviceVisibility(String key) {
    final currentlyVisible = isDeviceKeyVisible(key);
    setDeviceHidden(key, currentlyVisible);
  }

  void setDeviceHidden(String key, bool isHidden) {
    _repository.setDeviceHidden(key, isHidden);
    _devicePreferences[key] = isHidden;
    if (isHidden && _filter.selectedDeviceKeys.contains(key)) {
      final updated = Set<String>.from(_filter.selectedDeviceKeys)..remove(key);
      _filter = _filter.copyWith(selectedDeviceKeys: updated);
      _persistSelectedDeviceKeys();
    }
    _refreshState();
  }

  void unhideAllDevices() {
    _repository.unhideAllDevices();
    _devicePreferences.clear();
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
        allowedExtensions: ['csv', 'txt', 'log', 'json'],
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

  /// Updates or assigns full device metadata in the shared database
  void updateDeviceDetails({
    required String mac,
    required String name,
    String? category,
    String? vendor,
    String? notes,
  }) {
    if (!SharedDeviceDatabase.instance.isInitialized) return;
    final normalizedMac = SharedDevice.normalizeMac(mac);
    final existing = SharedDeviceDatabase.instance.getDeviceByMac(normalizedMac);
    final updated = SharedDevice(
      macAddress: normalizedMac,
      name: name.trim(),
      deviceType: category?.trim(),
      vendor: vendor?.trim(),
      notes: notes?.trim(),
      sourceApp: 'Syslog Server',
      createdAt: existing?.createdAt ?? DateTime.now(),
      updatedAt: DateTime.now(),
    );
    SharedDeviceDatabase.instance.upsertDevice(updated);

    // If it was given a custom name and was explicitly hidden before as an unnamed device,
    // clear the explicit preference so it automatically shows as a known device.
    if (updated.hasCustomName && _devicePreferences.containsKey(normalizedMac)) {
      _repository.clearDevicePreference(normalizedMac);
      _devicePreferences.remove(normalizedMac);
    }

    notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _uiThrottleTimer?.cancel();
    _batchSubscription?.cancel();
    _statusSubscription?.cancel();
    _sharedDeviceSubscription?.cancel();
    _repository.dispose();
    super.dispose();
  }
}
