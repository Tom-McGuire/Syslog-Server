import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/network_adapter_info.dart';
import '../view_models/syslog_view_model.dart';

class SyslogControlBar extends StatefulWidget {
  const SyslogControlBar({super.key});

  @override
  State<SyslogControlBar> createState() => _SyslogControlBarState();
}

class _SyslogControlBarState extends State<SyslogControlBar> {
  final TextEditingController _portController = TextEditingController(text: '514');
  bool _enableUdp = true;
  bool _enableTcp = true;

  @override
  void dispose() {
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SyslogViewModel>();
    final isListening = vm.serverStatus.isListening;
    final lastError = vm.serverStatus.lastError;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // App Logo / Title
                Icon(
                  Icons.dvr,
                  size: 24,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Syslog Server',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 20),

                // Start / Stop Button
                FilledButton.icon(
                  onPressed: () {
                    if (isListening) {
                      vm.stopServer();
                    } else {
                      final port = int.tryParse(_portController.text.trim()) ?? 514;
                      vm.startServer(
                        port: port,
                        enableUdp: _enableUdp,
                        enableTcp: _enableTcp,
                      );
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: isListening ? Colors.red.shade700 : Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  icon: Icon(
                    isListening ? Icons.stop : Icons.play_arrow,
                    size: 18,
                  ),
                  label: Text(
                    isListening ? 'Stop Server' : 'Start Server',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 16),

                // Network Interface Selector
                const Text('Interface:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(width: 6),
                Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF252526),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF3E3E42)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<NetworkAdapterInfo>(
                      value: vm.adapters.contains(vm.selectedAdapter)
                          ? vm.selectedAdapter
                          : vm.adapters.first,
                      isDense: true,
                      icon: const Icon(Icons.arrow_drop_down, size: 18),
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                      dropdownColor: const Color(0xFF252526),
                      onChanged: isListening
                          ? null
                          : (adapter) {
                              if (adapter != null) vm.selectAdapter(adapter);
                            },
                      items: vm.adapters.map((adapter) {
                        IconData icon = Icons.lan_outlined;
                        if (adapter.isAllInterfaces) {
                          icon = Icons.public;
                        } else if (adapter.name.toLowerCase().contains('wi-fi') ||
                            adapter.name.toLowerCase().contains('wlan')) {
                          icon = Icons.wifi;
                        } else if (adapter.ipAddress == '127.0.0.1') {
                          icon = Icons.loop;
                        }

                        return DropdownMenuItem<NetworkAdapterInfo>(
                          value: adapter,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 6),
                              Text(adapter.displayName),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Copy IP address (${vm.selectedAdapter.ipAddress})',
                  icon: const Icon(Icons.copy, size: 14),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: vm.selectedAdapter.ipAddress));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Copied ${vm.selectedAdapter.ipAddress} to clipboard'),
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'Refresh network interfaces',
                  icon: const Icon(Icons.refresh, size: 14),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: isListening ? null : () => vm.refreshAdapters(),
                ),
                const SizedBox(width: 14),

                // Port configuration
                const Text('Port:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(width: 6),
                SizedBox(
                  width: 75,
                  height: 32,
                  child: TextField(
                    controller: _portController,
                    enabled: !isListening,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Presets dropdown
                if (!isListening)
                  PopupMenuButton<int>(
                    tooltip: 'Port presets',
                    icon: const Icon(Icons.arrow_drop_down, size: 20),
                    onSelected: (port) {
                      setState(() {
                        _portController.text = port.toString();
                      });
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 514, child: Text('514 (Standard Syslog)')),
                      const PopupMenuItem(value: 1514, child: Text('1514 (Unprivileged Syslog)')),
                      const PopupMenuItem(value: 5140, child: Text('5140 (Alternative Syslog)')),
                    ],
                  ),
                const SizedBox(width: 12),

                // Protocol Checkboxes
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: _enableUdp,
                      onChanged: isListening
                          ? null
                          : (val) {
                              if (val != null) setState(() => _enableUdp = val);
                            },
                    ),
                    const Text('UDP', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 8),
                    Checkbox(
                      value: _enableTcp,
                      onChanged: isListening
                          ? null
                          : (val) {
                              if (val != null) setState(() => _enableTcp = val);
                            },
                    ),
                    const Text('TCP', style: TextStyle(fontSize: 12)),
                  ],
                ),
                const SizedBox(width: 24),

                // Demo Logs Button
                OutlinedButton.icon(
                  onPressed: () => vm.loadDemoLogs(),
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('Demo Logs'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
                const SizedBox(width: 8),

                // Clear Logs Button
                OutlinedButton.icon(
                  onPressed: vm.logs.isEmpty ? null : () => _confirmClear(context, vm),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Clear'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade300,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
                const SizedBox(width: 8),

                // Export Menu
                PopupMenuButton<String>(
                  tooltip: 'Export Logs',
                  enabled: vm.logs.isNotEmpty,
                  icon: const Icon(Icons.file_download_outlined, size: 20),
                  onSelected: (val) async {
                    if (val == 'csv') {
                      final path = await vm.exportCsv();
                      if (path != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Exported to: $path')),
                        );
                      }
                    } else if (val == 'json') {
                      final path = await vm.exportJson();
                      if (path != null && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Exported to: $path')),
                        );
                      }
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'csv',
                      child: Row(
                        children: [
                          Icon(Icons.table_chart, size: 16),
                          SizedBox(width: 8),
                          Text('Export as CSV'),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'json',
                      child: Row(
                        children: [
                          Icon(Icons.code, size: 16),
                          SizedBox(width: 8),
                          Text('Export as JSON'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Error banner if socket fails
          if (lastError != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: Colors.red.shade900.withValues(alpha: 0.8),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 16, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      lastError,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context, SyslogViewModel vm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Captured Logs?'),
        content: const Text(
          'This will permanently remove all logs from the active SQLite session.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.of(ctx).pop();
              vm.clearLogs();
            },
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }
}
