import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:sqlite3/sqlite3.dart';
import '../../../domain/models/syslog_facility.dart';
import '../../../domain/models/syslog_filter.dart';
import '../../../domain/models/syslog_record.dart';
import '../../../domain/models/syslog_severity.dart';

class SyslogDatabaseService {
  SyslogDatabaseService({
    Database? db,
    this.maxRows = 500000,
  }) : _db = db ?? sqlite3.openInMemory() {
    _initSchema();
  }

  final Database _db;
  final int maxRows;
  Database get db => _db;

  void _initSchema() {
    try {
      _db.execute('PRAGMA synchronous = NORMAL;');
    } catch (_) {}

    _db.execute('''
      CREATE TABLE IF NOT EXISTS syslog_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        received_at_ms INTEGER NOT NULL,
        remote_ip TEXT NOT NULL,
        remote_port INTEGER NOT NULL,
        transport TEXT NOT NULL,
        facility INTEGER NOT NULL,
        facility_name TEXT NOT NULL,
        severity INTEGER NOT NULL,
        severity_name TEXT NOT NULL,
        timestamp_str TEXT,
        hostname TEXT,
        app_name TEXT,
        proc_id TEXT,
        msg_id TEXT,
        message TEXT NOT NULL,
        raw_payload TEXT NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_syslog_received ON syslog_records(received_at_ms);
      CREATE INDEX IF NOT EXISTS idx_syslog_sev ON syslog_records(severity);
      CREATE INDEX IF NOT EXISTS idx_syslog_fac ON syslog_records(facility);
      CREATE INDEX IF NOT EXISTS idx_syslog_ip ON syslog_records(remote_ip);
      CREATE INDEX IF NOT EXISTS idx_syslog_host ON syslog_records(hostname);
      CREATE INDEX IF NOT EXISTS idx_syslog_app ON syslog_records(app_name);

      CREATE TABLE IF NOT EXISTS app_device_preferences (
        device_key TEXT PRIMARY KEY NOT NULL,
        is_hidden INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      );
    ''');
  }

  /// Batch insert syslog records inside a single transaction with automatic retention pruning.
  List<SyslogRecord> insertBatch(List<SyslogRecord> records) {
    if (records.isEmpty) return [];

    final inserted = <SyslogRecord>[];
    PreparedStatement? stmt;

    _db.execute('BEGIN TRANSACTION');
    try {
      stmt = _db.prepare('''
        INSERT INTO syslog_records (
          received_at_ms, remote_ip, remote_port, transport,
          facility, facility_name, severity, severity_name,
          timestamp_str, hostname, app_name, proc_id, msg_id,
          message, raw_payload
        ) VALUES (
          ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
        )
      ''');

      for (final r in records) {
        stmt.execute([
          r.receivedAtMs,
          r.remoteIp,
          r.remotePort,
          r.transport,
          r.facility.code,
          r.facility.nameStr,
          r.severity.code,
          r.severity.label,
          r.timestampStr,
          r.hostname,
          r.appName,
          r.procId,
          r.msgId,
          r.message,
          r.rawPayload,
        ]);
        final id = _db.lastInsertRowId;
        inserted.add(r.copyWith(id: id));
      }
      _db.execute('COMMIT');
    } catch (e) {
      _db.execute('ROLLBACK');
      rethrow;
    } finally {
      stmt?.close();
    }

    _enforceRetentionCap();
    return inserted;
  }

  void _enforceRetentionCap() {
    if (maxRows <= 0) return;
    try {
      final cntResult = _db.select('SELECT COUNT(*) as cnt FROM syslog_records');
      final currentCount = cntResult.first['cnt'] as int? ?? 0;
      if (currentCount > maxRows) {
        final excess = currentCount - maxRows;
        _db.execute(
          'DELETE FROM syslog_records WHERE id IN (SELECT id FROM syslog_records ORDER BY id ASC LIMIT ?)',
          [excess],
        );
      }
    } catch (_) {}
  }

  /// Query logs with pagination and filters
  List<SyslogRecord> queryLogs({
    int offset = 0,
    int limit = 1000,
    required SyslogFilterCriteria filter,
  }) {
    final (whereClause, params) = _buildWhereClause(filter);

    final allowedSortColumns = {
      'id': 'id',
      'received_at_ms': 'received_at_ms',
      'severity': 'severity',
      'facility': 'facility',
      'remote_ip': 'remote_ip',
      'hostname': 'hostname',
      'app_name': 'app_name',
    };
    final sortCol = allowedSortColumns[filter.sortColumn] ?? 'id';
    final sortDirection = filter.sortAscending ? 'ASC' : 'DESC';

    final sql = StringBuffer('SELECT * FROM syslog_records');
    if (whereClause.isNotEmpty) {
      sql.write(' WHERE $whereClause');
    }
    sql.write(' ORDER BY $sortCol $sortDirection LIMIT ? OFFSET ?');
    params.addAll([limit, offset]);

    final result = _db.select(sql.toString(), params);
    return result.map((row) => SyslogRecord.fromRow(row)).toList();
  }

  /// Get total count of logs matching filter
  int countLogs(SyslogFilterCriteria filter) {
    final (whereClause, params) = _buildWhereClause(filter);
    final sql = StringBuffer('SELECT COUNT(*) as count FROM syslog_records');
    if (whereClause.isNotEmpty) {
      sql.write(' WHERE $whereClause');
    }
    final result = _db.select(sql.toString(), params);
    if (result.isEmpty) return 0;
    return result.first['count'] as int? ?? 0;
  }

  /// Severity counts for quick badges under active filters (excluding selected severities to show available facets)
  Map<SyslogSeverity, int> getSeverityCounts([SyslogFilterCriteria? filter]) {
    final counts = <SyslogSeverity, int>{
      for (final s in SyslogSeverity.values) s: 0,
    };
    final baseFilter = filter?.copyWith(selectedSeverities: const {}) ?? const SyslogFilterCriteria();
    final (whereClause, params) = _buildWhereClause(baseFilter);

    final sql = StringBuffer('''
      SELECT severity, COUNT(*) as count
      FROM syslog_records
    ''');
    if (whereClause.isNotEmpty) {
      sql.write(' WHERE $whereClause');
    }
    sql.write(' GROUP BY severity');

    final result = _db.select(sql.toString(), params);
    for (final row in result) {
      final code = row['severity'] as int;
      final count = row['count'] as int;
      final sev = SyslogSeverity.fromCode(code);
      counts[sev] = count;
    }
    return counts;
  }

  /// Clear all stored records
  void clearAll() {
    _db.execute('DELETE FROM syslog_records');
    try {
      _db.execute("DELETE FROM sqlite_sequence WHERE name = 'syslog_records'");
    } catch (_) {}
  }

  /// Retrieves keys (MAC addresses or IPs/hostnames) marked as hidden in this application
  Set<String> getHiddenDeviceKeys() {
    try {
      final rows = _db.select('SELECT device_key FROM app_device_preferences WHERE is_hidden = 1');
      return rows.map((r) => r['device_key'] as String).toSet();
    } catch (_) {
      return {};
    }
  }

  /// Sets whether a specific device key is hidden in this application
  void setDeviceHidden(String deviceKey, bool isHidden) {
    try {
      final now = DateTime.now().toIso8601String();
      _db.execute('''
        INSERT INTO app_device_preferences (device_key, is_hidden, updated_at)
        VALUES (?, ?, ?)
        ON CONFLICT(device_key) DO UPDATE SET
          is_hidden = excluded.is_hidden,
          updated_at = excluded.updated_at
      ''', [deviceKey.trim(), isHidden ? 1 : 0, now]);
    } catch (_) {}
  }

  /// Restores visibility for all hidden devices in this application
  void unhideAllDevices() {
    try {
      _db.execute('DELETE FROM app_device_preferences');
    } catch (_) {}
  }

  /// Counts of syslog records grouped by remote IP under active filters (excluding selectedDeviceKeys)
  Map<String, int> getRemoteIpCounts([SyslogFilterCriteria? filter]) {
    final counts = <String, int>{};
    try {
      final baseFilter = filter?.copyWith(selectedDeviceKeys: const {}) ?? const SyslogFilterCriteria();
      final (whereClause, params) = _buildWhereClause(baseFilter);

      final sql = StringBuffer('''
        SELECT remote_ip, COUNT(*) as count
        FROM syslog_records
      ''');
      if (whereClause.isNotEmpty) {
        sql.write(' WHERE $whereClause');
      }
      sql.write(' GROUP BY remote_ip ORDER BY count DESC');

      final result = _db.select(sql.toString(), params);
      for (final row in result) {
        final ip = row['remote_ip'] as String?;
        final count = row['count'] as int? ?? 0;
        if (ip != null && ip.isNotEmpty) {
          counts[ip] = count;
        }
      }
    } catch (_) {}
    return counts;
  }

  /// Counts of syslog records grouped by hostname under active filters (excluding selectedDeviceKeys)
  Map<String, int> getHostnameCounts([SyslogFilterCriteria? filter]) {
    final counts = <String, int>{};
    try {
      final baseFilter = filter?.copyWith(selectedDeviceKeys: const {}) ?? const SyslogFilterCriteria();
      final (whereClause, params) = _buildWhereClause(baseFilter);

      final sql = StringBuffer('''
        SELECT hostname, COUNT(*) as count
        FROM syslog_records
      ''');
      if (whereClause.isNotEmpty) {
        sql.write(' WHERE $whereClause AND (hostname IS NOT NULL AND TRIM(hostname) != \'\')');
      } else {
        sql.write(' WHERE hostname IS NOT NULL AND TRIM(hostname) != \'\'');
      }
      sql.write(' GROUP BY hostname ORDER BY count DESC');

      final result = _db.select(sql.toString(), params);
      for (final row in result) {
        final host = row['hostname'] as String?;
        final count = row['count'] as int? ?? 0;
        if (host != null && host.isNotEmpty) {
          counts[host] = count;
        }
      }
    } catch (_) {}
    return counts;
  }

  /// Calculates count of logs that match a specific device key (MAC address, IP, or Hostname) under active filters
  int getCountForDeviceKey(String key, [SyslogFilterCriteria? filter]) {
    try {
      final baseFilter = filter ?? const SyslogFilterCriteria();
      final targetFilter = baseFilter.copyWith(selectedDeviceKeys: {key});
      return countLogs(targetFilter);
    } catch (_) {
      return 0;
    }
  }

  static String _escapeLike(String text) {
    return text
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }

  (String, List<dynamic>) _buildWhereClause(SyslogFilterCriteria filter) {
    final clauses = <String>[];
    final params = <dynamic>[];

    // Search query matches message, hostname, app_name, or remote_ip with LIKE wildcard escaping
    if (filter.searchQuery.trim().isNotEmpty) {
      final queryText = filter.searchQuery.trim();
      final q = '%${_escapeLike(queryText)}%';
      final searchClauses = <String>[
        "message LIKE ? ESCAPE '\\'",
        "hostname LIKE ? ESCAPE '\\'",
        "app_name LIKE ? ESCAPE '\\'",
        "remote_ip LIKE ? ESCAPE '\\'",
      ];
      final searchParams = <dynamic>[q, q, q, q];

      // Also match MAC addresses of any devices in SharedDeviceDatabase whose friendly name matches query
      try {
        if (SharedDeviceDatabase.instance.isInitialized) {
          final matchingDevices = SharedDeviceDatabase.instance.getAllDevices(query: queryText);
          for (final device in matchingDevices) {
            searchClauses.add("message LIKE ? ESCAPE '\\'");
            searchClauses.add("raw_payload LIKE ? ESCAPE '\\'");
            final macPattern = '%${_escapeLike(device.macAddress)}%';
            searchParams.addAll([macPattern, macPattern]);
          }
        }
      } catch (_) {}

      clauses.add('(${searchClauses.join(' OR ')})');
      params.addAll(searchParams);
    }

    // Selected device keys filter (MACs, IPs, or Hostnames)
    if (filter.selectedDeviceKeys.isNotEmpty) {
      final deviceClauses = <String>[];
      final deviceParams = <dynamic>[];

      for (final key in filter.selectedDeviceKeys) {
        if (SharedDevice.isValidMac(key)) {
          final normMac = SharedDevice.normalizeMac(key);
          final pattern = '%${_escapeLike(normMac)}%';
          deviceClauses.add("(message LIKE ? ESCAPE '\\' OR raw_payload LIKE ? ESCAPE '\\' OR hostname LIKE ? ESCAPE '\\')");
          deviceParams.addAll([pattern, pattern, pattern]);
        } else {
          deviceClauses.add('(remote_ip = ? OR hostname = ?)');
          deviceParams.addAll([key, key]);
        }
      }

      if (deviceClauses.isNotEmpty) {
        clauses.add('(${deviceClauses.join(' OR ')})');
        params.addAll(deviceParams);
      }
    }

    // Severity filter
    if (filter.selectedSeverities.isNotEmpty &&
        filter.selectedSeverities.length < SyslogSeverity.values.length) {
      final placeholders = List.filled(filter.selectedSeverities.length, '?').join(',');
      clauses.add('severity IN ($placeholders)');
      params.addAll(filter.selectedSeverities.map((s) => s.code));
    }

    // Facility filter
    if (filter.selectedFacilities.isNotEmpty &&
        filter.selectedFacilities.length < SyslogFacility.values.length) {
      final placeholders = List.filled(filter.selectedFacilities.length, '?').join(',');
      clauses.add('facility IN ($placeholders)');
      params.addAll(filter.selectedFacilities.map((f) => f.code));
    }

    // Remote IP filter with wildcard escaping
    if (filter.remoteIp.trim().isNotEmpty) {
      clauses.add("remote_ip LIKE ? ESCAPE '\\'");
      params.add('%${_escapeLike(filter.remoteIp.trim())}%');
    }

    // Hostname filter with wildcard escaping
    if (filter.hostname.trim().isNotEmpty) {
      clauses.add("hostname LIKE ? ESCAPE '\\'");
      params.add('%${_escapeLike(filter.hostname.trim())}%');
    }

    // App name filter with wildcard escaping
    if (filter.appName.trim().isNotEmpty) {
      clauses.add("app_name LIKE ? ESCAPE '\\'");
      params.add('%${_escapeLike(filter.appName.trim())}%');
    }

    // Time window
    if (filter.timeStartMs != null) {
      clauses.add('received_at_ms >= ?');
      params.add(filter.timeStartMs!);
    }
    if (filter.timeEndMs != null) {
      clauses.add('received_at_ms <= ?');
      params.add(filter.timeEndMs!);
    }

    return (clauses.join(' AND '), params);
  }

  void close() {
    _db.close();
  }
}
