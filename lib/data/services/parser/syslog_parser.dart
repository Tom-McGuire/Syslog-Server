import '../../../domain/models/syslog_facility.dart';
import '../../../domain/models/syslog_record.dart';
import '../../../domain/models/syslog_severity.dart';

class SyslogParser {
  // RFC 5424 regex: <PRI>VERSION TIMESTAMP HOSTNAME APP-NAME PROCID MSGID [SD] MSG
  static final RegExp _rfc5424Pattern = RegExp(
    r'^<(\d{1,3})>1\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)(?:\s+(\[.*?\]|-))?(?:\s+(.*))?$',
    dotAll: true,
  );

  // RFC 3164 timestamp regex: "Mmm dd hh:mm:ss" or "Mmm  d hh:mm:ss"
  static final RegExp _rfc3164Pattern = RegExp(
    r'^<(\d{1,3})>([A-Za-z]{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+(\S+)\s+(.*)$',
    dotAll: true,
  );

  // Fallback pattern with PRI: <PRI> ...
  static final RegExp _priPattern = RegExp(r'^<(\d{1,3})>(.*)$', dotAll: true);

  // Tag / App name pattern: "appname[1234]:" or "appname:"
  static final RegExp _tagPattern = RegExp(r'^([a-zA-Z0-9_\-\./]+)(?:\[(\d+)\])?:\s*(.*)$', dotAll: true);

  /// Strips dangerous unicode control characters (bidi overrides, zero-width spaces)
  /// from text to prevent display spoofing, while preserving normal content.
  static String sanitizeDisplay(String text) {
    return text
        // Remove Unicode Bidirectional overrides (U+202A to U+202E, U+2066 to U+2069)
        .replaceAll(RegExp(r'[\u202A-\u202E\u2066-\u2069]'), '')
        // Remove zero-width characters (U+200B to U+200D, U+FEFF)
        .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
        // Strip ASCII control characters except \n, \r, \t
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '');
  }

  /// Sanitizes nullable text or returns null if text is null or '-'.
  static String? sanitizeDisplayNullable(String? text) {
    if (text == null || text == '-') return null;
    return sanitizeDisplay(text);
  }

  /// Parse incoming raw payload string into a [SyslogRecord].
  static SyslogRecord parse({
    required String raw,
    required String remoteIp,
    required int remotePort,
    required String transport,
    int? receivedAtMs,
  }) {
    final nowMs = receivedAtMs ?? DateTime.now().millisecondsSinceEpoch;
    final trimmed = raw.trim();

    // 1. Try RFC 5424
    final match5424 = _rfc5424Pattern.firstMatch(trimmed);
    if (match5424 != null) {
      final pri = int.tryParse(match5424.group(1) ?? '') ?? 13;
      if (pri >= 0 && pri <= 191) {
        final facility = SyslogFacility.fromCode(pri >> 3);
        final severity = SyslogSeverity.fromCode(pri & 0x07);

        final tsStr = match5424.group(2);
        final hostname = match5424.group(3);
        final appName = match5424.group(4);
        final procId = match5424.group(5);
        final msgId = match5424.group(6);
        final sd = match5424.group(7);
        final msgBody = match5424.group(8) ?? '';

        final effectiveMsg = (sd != null && sd != '-' && !sd.startsWith('['))
            ? '$sd $msgBody'
            : msgBody;

        return SyslogRecord(
          receivedAtMs: nowMs,
          remoteIp: sanitizeDisplay(remoteIp),
          remotePort: remotePort,
          transport: transport,
          facility: facility,
          severity: severity,
          timestampStr: tsStr == '-' ? null : tsStr,
          hostname: sanitizeDisplayNullable(hostname),
          appName: sanitizeDisplayNullable(appName),
          procId: sanitizeDisplayNullable(procId),
          msgId: sanitizeDisplayNullable(msgId),
          message: sanitizeDisplay(effectiveMsg.trim()),
          rawPayload: raw,
        );
      }
    }

    // 2. Try RFC 3164 (BSD syslog)
    final match3164 = _rfc3164Pattern.firstMatch(trimmed);
    if (match3164 != null) {
      final pri = int.tryParse(match3164.group(1) ?? '') ?? 13;
      if (pri >= 0 && pri <= 191) {
        final facility = SyslogFacility.fromCode(pri >> 3);
        final severity = SyslogSeverity.fromCode(pri & 0x07);

        final tsStr = match3164.group(2);
        final hostname = match3164.group(3);
        final rest = match3164.group(4) ?? '';

        String? appName;
        String? procId;
        String message = rest;

        final tagMatch = _tagPattern.firstMatch(rest);
        if (tagMatch != null) {
          appName = tagMatch.group(1);
          procId = tagMatch.group(2);
          message = tagMatch.group(3) ?? '';
        }

        return SyslogRecord(
          receivedAtMs: nowMs,
          remoteIp: sanitizeDisplay(remoteIp),
          remotePort: remotePort,
          transport: transport,
          facility: facility,
          severity: severity,
          timestampStr: tsStr,
          hostname: sanitizeDisplayNullable(hostname),
          appName: sanitizeDisplayNullable(appName),
          procId: sanitizeDisplayNullable(procId),
          message: sanitizeDisplay(message.trim()),
          rawPayload: raw,
        );
      }
    }

    // 3. Fallback: <PRI> followed by anything
    final priMatch = _priPattern.firstMatch(trimmed);
    if (priMatch != null) {
      final pri = int.tryParse(priMatch.group(1) ?? '') ?? 13;
      if (pri >= 0 && pri <= 191) {
        final facility = SyslogFacility.fromCode(pri >> 3);
        final severity = SyslogSeverity.fromCode(pri & 0x07);
        final rest = priMatch.group(2) ?? '';

        String? appName;
        String? procId;
        String message = rest;

        final tagMatch = _tagPattern.firstMatch(rest);
        if (tagMatch != null) {
          appName = tagMatch.group(1);
          procId = tagMatch.group(2);
          message = tagMatch.group(3) ?? '';
        }

        return SyslogRecord(
          receivedAtMs: nowMs,
          remoteIp: sanitizeDisplay(remoteIp),
          remotePort: remotePort,
          transport: transport,
          facility: facility,
          severity: severity,
          message: sanitizeDisplay(message.trim()),
          appName: sanitizeDisplayNullable(appName),
          procId: sanitizeDisplayNullable(procId),
          rawPayload: raw,
        );
      }
    }

    // 4. Plain text without PRI header (or invalid PRI > 191)
    return SyslogRecord(
      receivedAtMs: nowMs,
      remoteIp: sanitizeDisplay(remoteIp),
      remotePort: remotePort,
      transport: transport,
      facility: SyslogFacility.user,
      severity: SyslogSeverity.informational,
      message: sanitizeDisplay(trimmed),
      rawPayload: raw,
    );
  }
}
