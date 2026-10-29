import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../view_models/syslog_view_model.dart';
import 'device_mac_chip.dart';

class SyslogDetailPanel extends StatelessWidget {
  const SyslogDetailPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SyslogViewModel>();
    final record = vm.selectedRecord;

    if (record == null) {
      return const SizedBox.shrink();
    }

    final timeFormatter = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');

    return Container(
      height: 260,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: record.severity.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: record.severity.color, width: 1),
                  ),
                  child: Text(
                    record.severity.label.toUpperCase(),
                    style: TextStyle(
                      color: record.severity.color,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Log Entry #${record.id ?? ""}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(width: 12),
                Text(
                  timeFormatter.format(record.receivedAt),
                  style: const TextStyle(color: Colors.grey, fontSize: 12, fontFamily: 'monospace'),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Copy Message',
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: record.message));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Message copied to clipboard'), duration: Duration(seconds: 1)),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Copy Raw Payload',
                  icon: const Icon(Icons.raw_on, size: 16),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: record.rawPayload));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Raw payload copied to clipboard'), duration: Duration(seconds: 1)),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Close Details',
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => vm.selectRecord(null),
                ),
              ],
            ),
          ),

          // Detail Content Body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Meta grid
                  Wrap(
                    spacing: 24,
                    runSpacing: 10,
                    children: [
                      _buildMetaItem('Source IP', '${record.remoteIp}:${record.remotePort} (${record.transport})'),
                      _buildMetaItem('Facility', '${record.facility.nameStr} (${record.facility.code})'),
                      _buildMetaItem('Hostname', record.hostname ?? 'None'),
                      _buildMetaItem('App / Tag', record.appName ?? 'None'),
                      if (record.procId != null) _buildMetaItem('PID', record.procId!),
                      if (record.msgId != null) _buildMetaItem('Msg ID', record.msgId!),
                      if (record.timestampStr != null) _buildMetaItem('Header Timestamp', record.timestampStr!),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(height: 1),

                  // Detected Hardware / MAC Addresses from Network Suite
                  if (record.detectedMacs.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.devices, size: 14, color: Colors.tealAccent),
                        const SizedBox(width: 6),
                        const Text(
                          'HARDWARE IDENTITY & SHARED DEVICES',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.tealAccent),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '(${record.detectedMacs.length} detected)',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: record.detectedMacs.map((mac) {
                        return DeviceMacChip(mac: mac, compact: false);
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1),
                  ],

                  const SizedBox(height: 12),

                  // Message Section
                  const Text(
                    'PARSED MESSAGE',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    record.message.isEmpty ? '(Empty message body)' : record.message,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 14),

                  // Raw Payload Section
                  const Text(
                    'RAW SYSLOG PACKET',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141414),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF2C2C2C)),
                    ),
                    child: SelectableText(
                      record.rawPayload,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Color(0xFFD4D4D4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
