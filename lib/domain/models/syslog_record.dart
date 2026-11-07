import 'package:sqlite3/sqlite3.dart';
import '../../data/services/device/mac_address_helper.dart';
import 'syslog_severity.dart';
import 'syslog_facility.dart';

class SyslogRecord {
  const SyslogRecord({
    this.id,
    required this.receivedAtMs,
    required this.remoteIp,
    required this.remotePort,
    required this.transport,
    required this.facility,
    required this.severity,
    this.timestampStr,
    this.hostname,
    this.appName,
    this.procId,
    this.msgId,
    required this.message,
    required this.rawPayload,
  });

  final int? id;
  final int receivedAtMs;
  final String remoteIp;
  final int remotePort;
  final String transport; // 'UDP' or 'TCP'
  final SyslogFacility facility;
  final SyslogSeverity severity;
  final String? timestampStr;
  final String? hostname;
  final String? appName;
  final String? procId;
  final String? msgId;
  final String message;
  final String rawPayload;

  DateTime get receivedAt => DateTime.fromMillisecondsSinceEpoch(receivedAtMs);

  /// Unique normalized MAC addresses detected in this log entry.
  List<String> get detectedMacs => MacAddressHelper.extractMacs('$message $rawPayload ${hostname ?? ""}');

  /// Friendly device name from SharedDeviceDatabase if any detected MAC has a custom name.
  String? get customDeviceName {
    for (final mac in detectedMacs) {
      final name = MacAddressHelper.getCustomName(mac);
      if (name != null && name.isNotEmpty) return name;
    }
    return null;
  }

  factory SyslogRecord.fromRow(Row row) {
    final facilityCode = row['facility'] as int? ?? 1;
    final severityCode = row['severity'] as int? ?? 6;

    return SyslogRecord(
      id: row['id'] as int?,
      receivedAtMs: row['received_at_ms'] as int,
      remoteIp: row['remote_ip'] as String,
      remotePort: row['remote_port'] as int,
      transport: row['transport'] as String? ?? 'UDP',
      facility: SyslogFacility.fromCode(facilityCode),
      severity: SyslogSeverity.fromCode(severityCode),
      timestampStr: row['timestamp_str'] as String?,
      hostname: row['hostname'] as String?,
      appName: row['app_name'] as String?,
      procId: row['proc_id'] as String?,
      msgId: row['msg_id'] as String?,
      message: row['message'] as String? ?? '',
      rawPayload: row['raw_payload'] as String? ?? '',
    );
  }

  factory SyslogRecord.fromMap(Map<String, dynamic> map) {
    final facilityCode = map['facility'] as int? ?? 1;
    final severityCode = map['severity'] as int? ?? 6;

    return SyslogRecord(
      id: map['id'] as int?,
      receivedAtMs: map['received_at_ms'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      remoteIp: map['remote_ip'] as String? ?? '127.0.0.1',
      remotePort: map['remote_port'] as int? ?? 514,
      transport: map['transport'] as String? ?? 'UDP',
      facility: SyslogFacility.fromCode(facilityCode),
      severity: SyslogSeverity.fromCode(severityCode),
      timestampStr: map['timestamp_str'] as String?,
      hostname: map['hostname'] as String?,
      appName: map['app_name'] as String?,
      procId: map['proc_id'] as String?,
      msgId: map['msg_id'] as String?,
      message: map['message'] as String? ?? '',
      rawPayload: map['raw_payload'] as String? ?? (map['message'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toMap() {
    final customName = customDeviceName;
    return {
      if (id != null) 'id': id,
      'received_at_ms': receivedAtMs,
      'remote_ip': remoteIp,
      'remote_port': remotePort,
      'transport': transport,
      'facility': facility.code,
      'facility_name': facility.nameStr,
      'severity': severity.code,
      'severity_name': severity.label,
      'timestamp_str': timestampStr,
      'hostname': hostname,
      if (customName != null && customName.isNotEmpty) 'device_name': customName,
      if (detectedMacs.isNotEmpty) 'mac_address': detectedMacs.first,
      if (detectedMacs.isNotEmpty) 'detected_macs': detectedMacs,
      'app_name': appName,
      'proc_id': procId,
      'msg_id': msgId,
      'message': message,
      'raw_payload': rawPayload,
    };
  }

  SyslogRecord copyWith({int? id}) {
    return SyslogRecord(
      id: id ?? this.id,
      receivedAtMs: receivedAtMs,
      remoteIp: remoteIp,
      remotePort: remotePort,
      transport: transport,
      facility: facility,
      severity: severity,
      timestampStr: timestampStr,
      hostname: hostname,
      appName: appName,
      procId: procId,
      msgId: msgId,
      message: message,
      rawPayload: rawPayload,
    );
  }
}
