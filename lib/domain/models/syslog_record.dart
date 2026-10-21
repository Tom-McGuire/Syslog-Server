import 'package:sqlite3/sqlite3.dart';
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

  Map<String, dynamic> toMap() => {
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
        'app_name': appName,
        'proc_id': procId,
        'msg_id': msgId,
        'message': message,
        'raw_payload': rawPayload,
      };

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
