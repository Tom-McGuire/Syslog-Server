import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/network_adapter_info.dart';
import '../../../theme/app_theme.dart';
import '../view_models/syslog_view_model.dart';
import 'device_filter_management_dialog.dart';

class SyslogControlBar extends StatefulWidget {
  const SyslogControlBar({
    super.key,
    this.zone2Key,
    this.zone3Key,
  });

  final GlobalKey? zone2Key;
  final GlobalKey? zone3Key;

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
    final isDemo = vm.isDemoMode;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 52,
          decoration: BoxDecoration(
            color: AppTheme.surface,
            border: Border(
              bottom: BorderSide(
                color: AppTheme.border,
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
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'SYSLOG SERVER',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.8,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                Text(
                                  'RFC 3164/5424 Receiver',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(width: 16),

                            // ==================== ZONE 2: INTERFACE & TARGET ====================
                            Row(
                              key: widget.zone2Key,
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Network Interface Selector
                                Container(
                                  height: 32,
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(
                                    color: AppTheme.surfaceHigh,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: AppTheme.inputBorder),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<NetworkAdapterInfo>(
                                      value: vm.adapters.contains(vm.selectedAdapter)
                                          ? vm.selectedAdapter
                                          : vm.adapters.first,
                                      isDense: true,
                                      icon: const Icon(Icons.arrow_drop_down, size: 18),
                                      style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                                      dropdownColor: AppTheme.surfaceHigh,
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
                                Text('Port:', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                                const SizedBox(width: 6),
                                Container(
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: isListening ? AppTheme.surface : AppTheme.surfaceHigh,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: AppTheme.inputBorder),
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
                                            color: isListening ? AppTheme.textMuted : AppTheme.textPrimary,
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
                                          child: Padding(
                                            padding: const EdgeInsets.only(right: 6, left: 2),
                                            child: Icon(Icons.arrow_drop_down, size: 18, color: AppTheme.textSecondary),
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
                              ],
                            ),
                            const SizedBox(width: 16),

                            // ==================== ZONE 3: PRIMARY ACTIONS ====================
                            FilledButton.icon(
                              key: widget.zone3Key,
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
                                      child: Padding(
                                        padding: const EdgeInsets.all(2),
                                        child: Icon(Icons.close, size: 12, color: AppTheme.textSecondary),
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

                            // Load Demo / Exit Demo Button
                            OutlinedButton.icon(
                              onPressed: (!isDemo && isListening)
                                  ? null
                                  : (isDemo
                                      ? () => vm.endDemoWalkthrough()
                                      : () => vm.startDemoWalkthrough()),
                              icon: Icon(
                                isDemo ? Icons.stop_circle_outlined : Icons.play_circle_outline,
                                size: 15,
                                color: isDemo ? AppTheme.warning : null,
                              ),
                              label: Text(
                                isDemo ? 'Exit Demo' : 'Load Demo',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDemo ? AppTheme.warning : null,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                side: isDemo
                                    ? BorderSide(color: AppTheme.warning.withValues(alpha: 0.7))
                                    : null,
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
                                foregroundColor: AppTheme.isDark ? Colors.red.shade300 : AppTheme.error,
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
                                        ? AppTheme.inputBorder
                                        : AppTheme.border,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.download,
                                      size: 15,
                                      color: vm.logs.isNotEmpty
                                          ? (AppTheme.isDark ? Colors.white70 : AppTheme.textPrimary)
                                          : AppTheme.textMuted,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Export',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: vm.logs.isNotEmpty
                                            ? (AppTheme.isDark ? Colors.white70 : AppTheme.textPrimary)
                                            : AppTheme.textMuted,
                                      ),
                                    ),
                                    Icon(
                                      Icons.arrow_drop_down,
                                      size: 14,
                                      color: vm.logs.isNotEmpty
                                          ? (AppTheme.isDark ? Colors.white70 : AppTheme.textPrimary)
                                          : AppTheme.textMuted,
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
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.error,
              foregroundColor: Colors.white,
            ),
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
