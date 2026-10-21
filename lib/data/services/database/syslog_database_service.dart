import 'package:sqlite3/sqlite3.dart';
import '../../../domain/models/syslog_facility.dart';
import '../../../domain/models/syslog_filter.dart';
import '../../../domain/models/syslog_record.dart';
import '../../../domain/models/syslog_severity.dart';

class SyslogDatabaseService {
  SyslogDatabaseService({Database? db}) : _db = db ?? sqlite3.openInMemory() {
    _initSchema();
  }

  final Database _db;
  Database get db => _db;

  void _initSchema() {
    // Optimize performance with WAL and synchronous normal if file-backed
    try {
      _db.execute('PRAGMA journal_mode = WAL;');
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
    ''');
  }

  /// Batch insert syslog records inside a single transaction for maximum throughput.
  List<SyslogRecord> insertBatch(List<SyslogRecord> records) {
    if (records.isEmpty) return [];

    final inserted = <SyslogRecord>[];
    _db.execute('BEGIN TRANSACTION');
    try {
      final stmt = _db.prepare('''
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
      stmt.close();
      _db.execute('COMMIT');
    } catch (e) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    return inserted;
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

  /// Severity counts for quick badges
  Map<SyslogSeverity, int> getSeverityCounts() {
    final counts = <SyslogSeverity, int>{
      for (final s in SyslogSeverity.values) s: 0,
    };
    final result = _db.select('''
      SELECT severity, COUNT(*) as count
      FROM syslog_records
      GROUP BY severity
    ''');
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

  (String, List<dynamic>) _buildWhereClause(SyslogFilterCriteria filter) {
    final clauses = <String>[];
    final params = <dynamic>[];

    // Search query matches message, hostname, app_name, or remote_ip
    if (filter.searchQuery.trim().isNotEmpty) {
      final q = '%${filter.searchQuery.trim()}%';
      clauses.add('(message LIKE ? OR hostname LIKE ? OR app_name LIKE ? OR remote_ip LIKE ?)');
      params.addAll([q, q, q, q]);
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

    // Remote IP filter
    if (filter.remoteIp.trim().isNotEmpty) {
      clauses.add('remote_ip LIKE ?');
      params.add('%${filter.remoteIp.trim()}%');
    }

    // Hostname filter
    if (filter.hostname.trim().isNotEmpty) {
      clauses.add('hostname LIKE ?');
      params.add('%${filter.hostname.trim()}%');
    }

    // App name filter
    if (filter.appName.trim().isNotEmpty) {
      clauses.add('app_name LIKE ?');
      params.add('%${filter.appName.trim()}%');
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
