import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import '../../../domain/models/syslog_record.dart';

class ExportService {
  static String logsToCsv(List<SyslogRecord> logs) {
    final rows = <List<dynamic>>[
      [
        'ID',
        'Received At',
        'Remote IP',
        'Remote Port',
        'Transport',
        'Severity',
        'Facility',
        'Hostname',
        'App / Tag',
        'PID',
        'Message',
        'Raw Payload',
      ],
      ...logs.map((r) => [
            r.id ?? '',
            r.receivedAt.toIso8601String(),
            r.remoteIp,
            r.remotePort,
            r.transport,
            r.severity.label,
            r.facility.nameStr,
            r.hostname ?? '',
            r.appName ?? '',
            r.procId ?? '',
            r.message,
            r.rawPayload,
          ]),
    ];

    return Csv().encode(rows);
  }

  static String logsToJson(List<SyslogRecord> logs) {
    final list = logs.map((r) => r.toMap()).toList();
    return const JsonEncoder.withIndent('  ').convert(list);
  }

  static Future<String?> saveToFile({
    required String content,
    required String defaultFileName,
    required String dialogTitle,
    String? extension,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(content));
    final uri = await FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: defaultFileName,
      bytes: bytes,
    );
    if (uri == null) return null;
    try {
      return uri.toFilePath();
    } catch (_) {
      return uri.path;
    }
  }
}
