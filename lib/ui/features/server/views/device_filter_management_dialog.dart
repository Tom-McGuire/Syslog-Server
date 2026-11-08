import 'package:flutter/material.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:provider/provider.dart';
import '../view_models/syslog_view_model.dart';
import 'rename_device_dialog.dart';

/// Modal dialog allowing users to manage device visibility in Syslog Server's filter bar,
/// inspect known and auto-detected devices, and edit device metadata.
class DeviceFilterManagementDialog extends StatefulWidget {
  const DeviceFilterManagementDialog({super.key});

  static Future<void> show(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => const DeviceFilterManagementDialog(),
    );
  }

  @override
  State<DeviceFilterManagementDialog> createState() => _DeviceFilterManagementDialogState();
}

class _DeviceFilterManagementDialogState extends State<DeviceFilterManagementDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SyslogViewModel>();
    final hiddenKeys = vm.hiddenDeviceKeys;

    // All labeled devices from SharedDeviceDatabase (both visible and hidden)
    final allSharedDevices = SharedDeviceDatabase.instance.isInitialized
        ? SharedDeviceDatabase.instance.getAllDevices(hideDefaultNamed: true)
        : <SharedDevice>[];

    final filteredSharedDevices = allSharedDevices.where((d) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return d.name.toLowerCase().contains(q) ||
          d.macAddress.toLowerCase().contains(q) ||
          (d.vendor?.toLowerCase().contains(q) ?? false);
    }).toList();

    // Auto-detected sources
    final allAutoDetected = vm.autoDetectedSources;
    final filteredAutoDetected = allAutoDetected.where((s) {
      if (_searchQuery.isEmpty) return true;
      return s.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.devices, color: theme.colorScheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Manage Filter Devices',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Show or hide devices in this application\'s filter bar',
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  if (hiddenKeys.isNotEmpty) ...[
                    TextButton.icon(
                      icon: const Icon(Icons.visibility, size: 16),
                      label: Text('Unhide All (${hiddenKeys.length})', style: const TextStyle(fontSize: 12)),
                      onPressed: () => vm.unhideAllDevices(),
                    ),
                    const SizedBox(width: 8),
                  ],
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Search Bar
              SizedBox(
                height: 36,
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(fontSize: 12),
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  decoration: InputDecoration(
                    hintText: 'Search by device name, IP, MAC address, or vendor...',
                    prefixIcon: const Icon(Icons.search, size: 16),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 14),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Tabs
              TabBar(
                controller: _tabController,
                tabs: [
                  Tab(text: 'Known Shared Devices (${filteredSharedDevices.length})'),
                  Tab(text: 'Auto-Detected Sources (${filteredAutoDetected.length})'),
                ],
              ),
              const SizedBox(height: 8),

              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // Tab 1: Known Shared Devices
                    filteredSharedDevices.isEmpty
                        ? Center(
                            child: Text(
                              _searchQuery.isEmpty
                                  ? 'No labeled devices found in the Shared Device Library.'
                                  : 'No devices matched "$_searchQuery"',
                              style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filteredSharedDevices.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              final dev = filteredSharedDevices[i];
                              final isHidden = hiddenKeys.contains(dev.macAddress);
                              final count = vm.deviceCounts[dev.macAddress] ??
                                  vm.repository.getCountForDeviceKey(dev.macAddress);

                              return Opacity(
                                opacity: isHidden ? 0.55 : 1.0,
                                child: ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 14,
                                    backgroundColor: theme.colorScheme.primaryContainer,
                                    child: Icon(dev.category.icon, size: 14, color: theme.colorScheme.primary),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          dev.name,
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isHidden) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'Hidden',
                                            style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                      const SizedBox(width: 8),
                                      Text(
                                        '$count logs',
                                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    '${dev.macAddress}${dev.vendor != null ? ' • ${dev.vendor}' : ''}',
                                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          isHidden ? Icons.visibility_off : Icons.visibility,
                                          size: 18,
                                          color: isHidden ? Colors.grey : theme.colorScheme.primary,
                                        ),
                                        tooltip: isHidden ? 'Show in filter bar' : 'Hide from filter bar',
                                        onPressed: () => vm.toggleDeviceVisibility(dev.macAddress),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit, size: 18),
                                        tooltip: 'Edit Device in Shared Library',
                                        onPressed: () => RenameDeviceDialog.show(context, dev.macAddress),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),

                    // Tab 2: Auto-Detected Sources
                    filteredAutoDetected.isEmpty
                        ? Center(
                            child: Text(
                              _searchQuery.isEmpty
                                  ? 'No auto-detected sources in current capture.'
                                  : 'No sources matched "$_searchQuery"',
                              style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filteredAutoDetected.length,
                            separatorBuilder: (context, index) => const Divider(height: 1),
                            itemBuilder: (ctx, i) {
                              final src = filteredAutoDetected[i];
                              final isHidden = hiddenKeys.contains(src);
                              final count = vm.deviceCounts[src] ?? vm.repository.getCountForDeviceKey(src);

                              return Opacity(
                                opacity: isHidden ? 0.55 : 1.0,
                                child: ListTile(
                                  dense: true,
                                  leading: CircleAvatar(
                                    radius: 14,
                                    backgroundColor: Colors.blueGrey.withValues(alpha: 0.2),
                                    child: const Icon(Icons.sensors, size: 14, color: Colors.blueAccent),
                                  ),
                                  title: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          src,
                                          style: const TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (isHidden) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: Colors.amber.withValues(alpha: 0.2),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'Hidden',
                                            style: TextStyle(fontSize: 10, color: Colors.amber, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                      const SizedBox(width: 8),
                                      Text(
                                        '$count logs',
                                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                  subtitle: const Text(
                                    'Auto-detected from syslog traffic',
                                    style: TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(
                                          isHidden ? Icons.visibility_off : Icons.visibility,
                                          size: 18,
                                          color: isHidden ? Colors.grey : theme.colorScheme.primary,
                                        ),
                                        tooltip: isHidden ? 'Show in filter bar' : 'Hide from filter bar',
                                        onPressed: () => vm.toggleDeviceVisibility(src),
                                      ),
                                      if (SharedDevice.isValidMac(src))
                                        IconButton(
                                          icon: const Icon(Icons.add_circle_outline, size: 18),
                                          tooltip: 'Save & Name in Shared Library',
                                          onPressed: () => RenameDeviceDialog.show(context, src),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
