import 'dart:convert';
import 'package:csv/csv.dart';
import '../../../domain/models/syslog_facility.dart';
import '../../../domain/models/syslog_record.dart';
import '../../../domain/models/syslog_severity.dart';
import '../device/mac_address_helper.dart';
import '../parser/syslog_parser.dart';

class CsvImportResult {
  const CsvImportResult({
    required this.records,
    required this.totalLines,
    required this.importedCount,
    required this.skippedCount,
    this.detectedFormat = 'CSV',
    this.updatedDevicesCount = 0,
    this.deviceMappings = const {},
  });

  final List<SyslogRecord> records;
  final int totalLines;
  final int importedCount;
  final int skippedCount;
  final String detectedFormat;
  final int updatedDevicesCount;
  final Map<String, String> deviceMappings;
}

class CsvImportService {
  /// Parse CSV or JSON string into a list of [SyslogRecord]s and extract any device name mappings.
  static CsvImportResult parseCsv(String csvContent) {
    final trimmed = csvContent.trim();
    if (trimmed.isEmpty) {
      return const CsvImportResult(
        records: [],
        totalLines: 0,
        importedCount: 0,
        skippedCount: 0,
      );
    }

    // Check if content is formatted as JSON array or object
    if ((trimmed.startsWith('[') && trimmed.endsWith(']')) ||
        (trimmed.startsWith('{') && trimmed.endsWith('}'))) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is List) {
          return _parseJsonList(decoded);
        } else if (decoded is Map<String, dynamic>) {
          if (decoded['logs'] is List) {
            return _parseJsonList(decoded['logs'] as List);
          } else if (decoded['records'] is List) {
            return _parseJsonList(decoded['records'] as List);
          } else {
            return _parseJsonList([decoded]);
          }
        }
      } catch (_) {
        // Fall back to standard CSV parsing if jsonDecode fails
      }
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
    final deviceMappings = <String, String>{};
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
          final parsed = _parseStructuredRow(row, headerIndexMap, nowMs - (rows.length - i) * 10);
          final record = parsed.record;
          if (record != null) {
            records.add(record);

            final devName = parsed.deviceName;
            if (devName != null && devName.trim().isNotEmpty) {
              final macs = <String>{};
              if (parsed.macAddress != null && parsed.macAddress!.isNotEmpty) {
                macs.addAll(MacAddressHelper.extractMacs(parsed.macAddress!));
              }
              macs.addAll(record.detectedMacs);

              for (final mac in macs) {
                deviceMappings[mac] = devName.trim();
              }
            }
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
      deviceMappings: deviceMappings,
    );
  }

  static CsvImportResult _parseJsonList(List<dynamic> list) {
    final records = <SyslogRecord>[];
    final deviceMappings = <String, String>{};
    int skippedCount = 0;

    for (final item in list) {
      if (item is! Map<String, dynamic>) {
        skippedCount++;
        continue;
      }

      try {
        final record = SyslogRecord.fromMap(item);
        records.add(record);

        final devName = (item['device_name'] as String?)?.trim();
        if (devName != null && devName.isNotEmpty) {
          final macs = <String>{};
          final explicitMac = item['mac_address'] as String?;
          final explicitMacs = item['detected_macs'];

          if (explicitMac != null && explicitMac.trim().isNotEmpty) {
            macs.addAll(MacAddressHelper.extractMacs(explicitMac));
          }
          if (explicitMacs is List) {
            for (final m in explicitMacs) {
              macs.addAll(MacAddressHelper.extractMacs(m.toString()));
            }
          }
          macs.addAll(record.detectedMacs);

          for (final mac in macs) {
            deviceMappings[mac] = devName;
          }
        }
      } catch (_) {
        skippedCount++;
      }
    }

    return CsvImportResult(
      records: records,
      totalLines: list.length,
      importedCount: records.length,
      skippedCount: skippedCount,
      detectedFormat: 'JSON',
      deviceMappings: deviceMappings,
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
      } else if (_matches(h, ['devicename', 'friendlyname', 'customname', 'devicealias']) && !map.containsKey('deviceName')) {
        map['deviceName'] = i;
      } else if (_matches(h, ['macaddress', 'mac', 'hardwareaddress', 'hwaddr', 'ethernet']) && !map.containsKey('macAddress')) {
        map['macAddress'] = i;
      } else if (_matches(h, ['hostname', 'host', 'device', 'sourcename', 'node', 'machinename']) && !map.containsKey('hostname')) {
        map['hostname'] = i;
      } else if (_matches(h, ['appname', 'app', 'tag', 'program', 'process']) && !map.containsKey('appName')) {
        map['appName'] = i;
      } else if (_matches(h, ['procid', 'pid', 'processid']) && !map.containsKey('procId')) {
        map['procId'] = i;
      } else if (_matches(h, ['msgid', 'eventid']) && !map.containsKey('msgId')) {
        map['msgId'] = i;
      } else if (_matches(h, ['rawpayload', 'raw', 'packet', 'rawmessage']) && !map.containsKey('rawPayload')) {
        map['rawPayload'] = i;
      }
    }

    // Must have at least 1 recognizable core field to be considered a header
    final recognizedKeys = {'message', 'severity', 'timestamp', 'hostname', 'remoteIp', 'deviceName', 'macAddress'};
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

  static ({SyslogRecord? record, String? deviceName, String? macAddress}) _parseStructuredRow(
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
    if (message == null && row.isEmpty) {
      return (record: null, deviceName: null, macAddress: null);
    }

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
    final deviceName = getCol('deviceName');
    final macAddress = getCol('macAddress');
    final appName = getCol('appName');
    final procId = getCol('procId');
    final msgId = getCol('msgId');

    final effectiveHostname = (hostname != null && hostname.isNotEmpty)
        ? hostname
        : deviceName;

    final record = SyslogRecord(
      receivedAtMs: receivedAtMs,
      remoteIp: remoteIp,
      remotePort: remotePort,
      transport: transport,
      facility: facility,
      severity: severity,
      timestampStr: originalTsStr,
      hostname: effectiveHostname,
      appName: appName,
      procId: procId,
      msgId: msgId,
      message: message ?? rawPayload,
      rawPayload: rawPayload,
    );

    return (record: record, deviceName: deviceName, macAddress: macAddress);
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
