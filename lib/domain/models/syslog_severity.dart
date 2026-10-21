import 'package:flutter/material.dart';

enum SyslogSeverity {
  emergency(0, 'Emergency', 'System is unusable', Color(0xFFD32F2F)),
  alert(1, 'Alert', 'Action must be taken immediately', Color(0xFFE64A19)),
  critical(2, 'Critical', 'Critical conditions', Color(0xFFF57C00)),
  error(3, 'Error', 'Error conditions', Color(0xFFE53935)),
  warning(4, 'Warning', 'Warning conditions', Color(0xFFFFA000)),
  notice(5, 'Notice', 'Normal but significant condition', Color(0xFF00ACC1)),
  informational(6, 'Info', 'Informational messages', Color(0xFF1E88E5)),
  debug(7, 'Debug', 'Debug-level messages', Color(0xFF757575));

  const SyslogSeverity(this.code, this.label, this.description, this.color);

  final int code;
  final String label;
  final String description;
  final Color color;

  static SyslogSeverity fromCode(int code) {
    if (code >= 0 && code < SyslogSeverity.values.length) {
      return SyslogSeverity.values[code];
    }
    return SyslogSeverity.informational;
  }
}
