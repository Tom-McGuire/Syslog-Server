import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/network_adapter_info.dart';
import '../view_models/syslog_view_model.dart';
import 'device_filter_management_dialog.dart';

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
    final loadedFileName = vm.loadedFileName;
    final isImporting = vm.isImporting;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 52,
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E1E),
            border: Border(
              bottom: BorderSide(
                color: Color(0xFF2C2C2C),
                width: 1,
              ),
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Left Section: Zone 1 (Branding) -> Zone 2 (Interface & Port) -> Zone 3 (Primary Actions)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // ==================== ZONE 1: BRANDING ====================
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.asset(
                                'assets/app_icon.png',
                                width: 32,
                                height: 32,
                                fit: BoxFit.cover,
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'SYSLOG SERVER',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.8,
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  'RFC 3164/5424 Receiver',
                                  style: TextStyle(fontSize: 10, color: Colors.white54),
                                ),
                              ],
                            ),
                            const SizedBox(width: 16),

                            // ==================== ZONE 2: INTERFACE & TARGET ====================
                            // Network Interface Selector
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
                            const SizedBox(width: 2),
                            IconButton(
                              tooltip: 'Refresh network interfaces',
                              icon: const Icon(Icons.refresh, size: 16),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                              onPressed: isListening ? null : () => vm.refreshAdapters(),
                            ),
                            const SizedBox(width: 12),

                            // Port configuration
                            const Text('Port:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            const SizedBox(width: 6),
                            Container(
                              height: 32,
                              decoration: BoxDecoration(
                                color: isListening ? const Color(0xFF1E1E1E) : const Color(0xFF252526),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFF3E3E42)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 54,
                                    child: TextField(
                                      controller: _portController,
                                      enabled: !isListening,
                                      keyboardType: TextInputType.number,
                                      textAlignVertical: TextAlignVertical.center,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontFamily: 'monospace',
                                        color: isListening ? Colors.grey : Colors.white,
                                      ),
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        contentPadding: EdgeInsets.symmetric(horizontal: 8),
                                      ),
                                    ),
                                  ),
                                  if (!isListening)
                                    PopupMenuButton<int>(
                                      tooltip: 'Port presets',
                                      padding: EdgeInsets.zero,
                                      child: const Padding(
                                        padding: EdgeInsets.only(right: 6, left: 2),
                                        child: Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey),
                                      ),
                                      onSelected: (port) {
                                        setState(() {
                                          _portController.text = port.toString();
                                        });
                                      },
                                      itemBuilder: (context) => const [
                                        PopupMenuItem(value: 514, child: Text('514 (Standard Syslog)')),
                                        PopupMenuItem(value: 1514, child: Text('1514 (Unprivileged Syslog)')),
                                        PopupMenuItem(value: 5140, child: Text('5140 (Alternative Syslog)')),
                                      ],
                                    )
                                  else
                                    const SizedBox(width: 8),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),

                            // Protocol Checkboxes
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Checkbox(
                                  value: _enableUdp,
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  onChanged: isListening
                                      ? null
                                      : (val) {
                                          if (val != null) setState(() => _enableUdp = val);
                                        },
                                ),
                                const Text('UDP', style: TextStyle(fontSize: 12)),
                                const SizedBox(width: 6),
                                Checkbox(
                                  value: _enableTcp,
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  onChanged: isListening
                                      ? null
                                      : (val) {
                                          if (val != null) setState(() => _enableTcp = val);
                                        },
                                ),
                                const Text('TCP', style: TextStyle(fontSize: 12)),
                              ],
                            ),
                            const SizedBox(width: 16),

                            // ==================== ZONE 3: PRIMARY ACTIONS ====================
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
                                backgroundColor: isListening
                                    ? const Color(0xFFEF4444) // Active Red
                                    : const Color(0xFF10B981), // Idle Emerald Green (from ARP Scout)
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                              icon: Icon(
                                isListening ? Icons.stop : Icons.play_arrow,
                                size: 17,
                              ),
                              label: Text(
                                isListening ? 'Stop Server' : 'Start Server',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(width: 16),

                        // Right Section: Zone 4 (Ecosystem & Demo) -> Zone 5 (Clear & Export)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // ==================== ZONE 4: ECOSYSTEM & DEMO ====================
                            // Loaded File Badge (if active)
                            if (loadedFileName != null) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.insert_drive_file_outlined, size: 14, color: Theme.of(context).colorScheme.primary),
                                    const SizedBox(width: 6),
                                    ConstrainedBox(
                                      constraints: const BoxConstraints(maxWidth: 140),
                                      child: Text(
                                        loadedFileName,
                                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    InkWell(
                                      onTap: () => vm.closeLoadedFile(),
                                      borderRadius: BorderRadius.circular(10),
                                      child: const Padding(
                                        padding: EdgeInsets.all(2),
                                        child: Icon(Icons.close, size: 12, color: Colors.grey),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],

                            // Open CSV Button
                            FilledButton.tonalIcon(
                              onPressed: isImporting ? null : () => _handleImportCsv(context, vm),
                              icon: isImporting
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.file_open_outlined, size: 15),
                              label: Text(isImporting ? 'Importing...' : 'Open CSV', style: const TextStyle(fontSize: 11)),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Device Library Button (Icons.devices)
                            OutlinedButton.icon(
                              onPressed: () => DeviceFilterManagementDialog.show(context),
                              icon: const Icon(Icons.devices, size: 15),
                              label: const Text('Device Library', style: TextStyle(fontSize: 11)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Load Demo Button (Icons.play_circle_outline)
                            OutlinedButton.icon(
                              onPressed: isListening ? null : () => vm.loadDemoLogs(),
                              icon: const Icon(Icons.play_circle_outline, size: 15),
                              label: const Text('Load Demo', style: TextStyle(fontSize: 11)),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // ==================== ZONE 5: CLEAR & EXPORT ====================
                            // Clear Logs Button
                            OutlinedButton.icon(
                              onPressed: vm.logs.isEmpty ? null : () => _confirmClear(context, vm),
                              icon: const Icon(Icons.delete_sweep_outlined, size: 15),
                              label: const Text('Clear', style: TextStyle(fontSize: 11)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red.shade300,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Export Menu Button (Standardized chip style)
                            PopupMenuButton<String>(
                              tooltip: 'Export Logs',
                              enabled: vm.logs.isNotEmpty,
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
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'csv',
                                  child: Row(
                                    children: [
                                      Icon(Icons.table_chart, size: 16),
                                      SizedBox(width: 8),
                                      Text('Export as CSV'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
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
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: vm.logs.isNotEmpty
                                        ? const Color(0xFF3E3E42)
                                        : const Color(0xFF2C2C2C),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.download,
                                      size: 15,
                                      color: vm.logs.isNotEmpty ? Colors.white70 : Colors.grey,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Export',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: vm.logs.isNotEmpty ? Colors.white70 : Colors.grey,
                                      ),
                                    ),
                                    Icon(
                                      Icons.arrow_drop_down,
                                      size: 14,
                                      color: vm.logs.isNotEmpty ? Colors.white70 : Colors.grey,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
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
    );
  }

  Future<void> _handleImportCsv(BuildContext context, SyslogViewModel vm) async {
    bool replaceExisting = true;
    if (vm.logs.isNotEmpty) {
      final choice = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Import CSV File'),
          content: const Text(
            'You currently have logs in the active session. Would you like to replace the current logs or append the imported file?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Append to Existing'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Replace Session'),
            ),
          ],
        ),
      );

      if (choice == null) return;
      replaceExisting = choice;
    }

    final result = await vm.importCsvFile(replaceExisting: replaceExisting);
    if (result != null && context.mounted) {
      final devicesMsg = result.updatedDevicesCount > 0
          ? ' and updated ${result.updatedDevicesCount} device(s) in shared database'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Imported ${result.importedCount} logs$devicesMsg (${result.detectedFormat})'
            '${result.skippedCount > 0 ? ' [${result.skippedCount} skipped]' : ''}',
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
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
