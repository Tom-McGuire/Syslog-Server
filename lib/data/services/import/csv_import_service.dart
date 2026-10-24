import 'package:csv/csv.dart';
import '../../../domain/models/syslog_facility.dart';
import '../../../domain/models/syslog_record.dart';
import '../../../domain/models/syslog_severity.dart';
import '../parser/syslog_parser.dart';

class CsvImportResult {
  const CsvImportResult({
    required this.records,
    required this.totalLines,
    required this.importedCount,
    required this.skippedCount,
    this.detectedFormat = 'CSV',
  });

  final List<SyslogRecord> records;
  final int totalLines;
  final int importedCount;
  final int skippedCount;
  final String detectedFormat;
}

class CsvImportService {
  /// Parse CSV string into a list of [SyslogRecord]s.
  static CsvImportResult parseCsv(String csvContent) {
    if (csvContent.trim().isEmpty) {
      return const CsvImportResult(
        records: [],
        totalLines: 0,
        importedCount: 0,
        skippedCount: 0,
      );
    }

    final rows = const CsvDecoder().convert(csvContent);
    if (rows.isEmpty) {
      return const CsvImportResult(
        records: [],
        totalLines: 0,
        importedCount: 0,
        skippedCount: 0,
      );
    }

    // Check if row 0 is a recognized header
    final firstRow = rows.first.map((e) => e.toString().trim()).toList();
    final headerIndexMap = _detectHeaders(firstRow);

    final records = <SyslogRecord>[];
    int skippedCount = 0;
    final int startRowIndex = headerIndexMap.isNotEmpty ? 1 : 0;
    final String format = headerIndexMap.isNotEmpty ? 'Structured CSV' : 'Raw Lines CSV';

    final nowMs = DateTime.now().millisecondsSinceEpoch;

    for (int i = startRowIndex; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty || (row.length == 1 && row.first.toString().trim().isEmpty)) {
        continue;
      }

      try {
        if (headerIndexMap.isNotEmpty) {
          // Structured row parsing using mapped header indices
          final record = _parseStructuredRow(row, headerIndexMap, nowMs - (rows.length - i) * 10);
          if (record != null) {
            records.add(record);
          } else {
            skippedCount++;
          }
        } else {
          // Unstructured single/multi column: join and pass through SyslogParser
          final line = row.join(' ').trim();
          if (line.isNotEmpty) {
            final record = SyslogParser.parse(
              raw: line,
              remoteIp: '127.0.0.1',
              remotePort: 514,
              transport: 'CSV',
              receivedAtMs: nowMs - (rows.length - i) * 10,
            );
            records.add(record);
          } else {
            skippedCount++;
          }
        }
      } catch (_) {
        skippedCount++;
      }
    }

    return CsvImportResult(
      records: records,
      totalLines: rows.length,
      importedCount: records.length,
      skippedCount: skippedCount,
      detectedFormat: format,
    );
  }

  static Map<String, int> _detectHeaders(List<String> firstRow) {
    final map = <String, int>{};
    for (int i = 0; i < firstRow.length; i++) {
      final h = firstRow[i].toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (h.isEmpty) continue;

      if (_matches(h, ['message', 'msg', 'log', 'text', 'payload', 'rawpayload', 'description', 'details', 'data', 'body']) && !map.containsKey('message')) {
        map['message'] = i;
      } else if (_matches(h, ['severity', 'severityname', 'level', 'priority', 'pri', 'loglevel', 'status', 'sev']) && !map.containsKey('severity')) {
        map['severity'] = i;
      } else if (_matches(h, ['facility', 'facilityname', 'category', 'fac']) && !map.containsKey('facility')) {
        map['facility'] = i;
      } else if (_matches(h, ['receivedat', 'timestamp', 'time', 'date', 'datetime', 'eventtime', 'loggedtime']) && !map.containsKey('timestamp')) {
        map['timestamp'] = i;
      } else if (_matches(h, ['remoteip', 'sourceip', 'srcip', 'clientip', 'source', 'ip', 'hostip', 'senderip']) && !map.containsKey('remoteIp')) {
        map['remoteIp'] = i;
      } else if (_matches(h, ['remoteport', 'sourceport', 'srcport', 'port']) && !map.containsKey('remotePort')) {
        map['remotePort'] = i;
      } else if (_matches(h, ['transport', 'proto', 'protocol']) && !map.containsKey('transport')) {
        map['transport'] = i;
      } else if (_matches(h, ['hostname', 'host', 'device', 'sourcename', 'node', 'machinename']) && !map.containsKey('hostname')) {
        map['hostname'] = i;
      } else if (_matches(h, ['appname', 'app', 'tag', 'program', 'process']) && !map.containsKey('appName')) {
        map['appName'] = i;
      } else if (_matches(h, ['procid', 'pid', 'processid']) && !map.containsKey('procId')) {
        map['procId'] = i;
      } else if (_matches(h, ['msgid', 'eventid', 'msgid']) && !map.containsKey('msgId')) {
        map['msgId'] = i;
      } else if (_matches(h, ['rawpayload', 'raw', 'packet', 'rawmessage']) && !map.containsKey('rawPayload')) {
        map['rawPayload'] = i;
      }
    }

    // Must have at least 1 recognizable core field to be considered a header
    final recognizedKeys = {'message', 'severity', 'timestamp', 'hostname', 'remoteIp'};
    if (map.keys.any(recognizedKeys.contains)) {
      return map;
    }
    return {};
  }

  static bool _matches(String actual, List<String> candidates) {
    for (final c in candidates) {
      if (actual == c || actual.contains(c)) return true;
    }
    return false;
  }

  static String? _unsanitizeCsv(String? val) {
    if (val != null && val.length > 1 && val.startsWith("'")) {
      final nextChar = val[1];
      if (nextChar == '=' ||
          nextChar == '+' ||
          nextChar == '-' ||
          nextChar == '@' ||
          nextChar == '\t' ||
          nextChar == '\r') {
        return val.substring(1);
      }
    }
    return (val != null && val.isNotEmpty) ? val : null;
  }

  static SyslogRecord? _parseStructuredRow(
    List<dynamic> row,
    Map<String, int> headerMap,
    int defaultTimeMs,
  ) {
    String? getCol(String key) {
      final idx = headerMap[key];
      if (idx != null && idx < row.length) {
        final val = row[idx]?.toString().trim();
        return _unsanitizeCsv(val);
      }
      return null;
    }

    final message = getCol('message') ?? getCol('rawPayload');
    if (message == null && row.isEmpty) return null;

    final rawPayload = getCol('rawPayload') ?? message ?? row.join(' ');

    // Parse Severity
    final sevStr = getCol('severity');
    final severity = _parseSeverity(sevStr);

    // Parse Facility
    final facStr = getCol('facility');
    final facility = _parseFacility(facStr);

    // Parse Timestamp
    final tsStr = getCol('timestamp');
    final (receivedAtMs, originalTsStr) = _parseTimestamp(tsStr, defaultTimeMs);

    final remoteIp = getCol('remoteIp') ?? '127.0.0.1';
    final portStr = getCol('remotePort');
    final remotePort = int.tryParse(portStr ?? '') ?? 514;
    final transport = getCol('transport') ?? 'CSV';
    final hostname = getCol('hostname');
    final appName = getCol('appName');
    final procId = getCol('procId');
    final msgId = getCol('msgId');

    return SyslogRecord(
      receivedAtMs: receivedAtMs,
      remoteIp: remoteIp,
      remotePort: remotePort,
      transport: transport,
      facility: facility,
      severity: severity,
      timestampStr: originalTsStr,
      hostname: hostname,
      appName: appName,
      procId: procId,
      msgId: msgId,
      message: message ?? rawPayload,
      rawPayload: rawPayload,
    );
  }

  static SyslogSeverity _parseSeverity(String? value) {
    if (value == null || value.trim().isEmpty) {
      return SyslogSeverity.informational;
    }
    final clean = value.trim().toLowerCase();

    // Check integer code 0..7
    final code = int.tryParse(clean);
    if (code != null) {
      return SyslogSeverity.fromCode(code);
    }

    // Check string names
    if (clean.contains('emerg')) return SyslogSeverity.emergency;
    if (clean.contains('alert')) return SyslogSeverity.alert;
    if (clean.contains('crit')) return SyslogSeverity.critical;
    if (clean.contains('err')) return SyslogSeverity.error;
    if (clean.contains('warn')) return SyslogSeverity.warning;
    if (clean.contains('notice')) return SyslogSeverity.notice;
    if (clean.contains('info')) return SyslogSeverity.informational;
    if (clean.contains('debug')) return SyslogSeverity.debug;

    return SyslogSeverity.informational;
  }

  static SyslogFacility _parseFacility(String? value) {
    if (value == null || value.trim().isEmpty) {
      return SyslogFacility.user;
    }
    final clean = value.trim().toLowerCase();

    // Check integer code 0..23
    final code = int.tryParse(clean);
    if (code != null) {
      return SyslogFacility.fromCode(code);
    }

    for (final fac in SyslogFacility.values) {
      if (clean == fac.nameStr.toLowerCase() || clean == fac.name.toLowerCase()) {
        return fac;
      }
    }

    return SyslogFacility.user;
  }

  static (int, String?) _parseTimestamp(String? value, int fallbackMs) {
    if (value == null || value.trim().isEmpty) {
      return (fallbackMs, null);
    }
    final clean = value.trim();

    // Try ISO-8601
    final parsedDt = DateTime.tryParse(clean);
    if (parsedDt != null) {
      return (parsedDt.millisecondsSinceEpoch, clean);
    }

    // Try UNIX Epoch ms or seconds
    final epoch = int.tryParse(clean);
    if (epoch != null) {
      // If seconds (e.g. 1700000000)
      if (epoch < 10000000000) {
        return (epoch * 1000, clean);
      }
      return (epoch, clean);
    }

    return (fallbackMs, clean);
  }
}
