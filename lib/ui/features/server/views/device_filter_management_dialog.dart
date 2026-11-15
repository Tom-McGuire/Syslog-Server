import 'package:material_ui/material_ui.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:provider/provider.dart';
import '../../../theme/app_theme.dart';
import '../view_models/syslog_view_model.dart';
import 'edit_device_dialog.dart';

/// Modal dialog allowing users to manage devices in the Custom Library,
/// edit device details, and show/hide devices as filter options in the filter bar.
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
    final theme = Theme.of(context);

    // Fetch all devices from SharedDeviceDatabase
    final allDevices = SharedDeviceDatabase.instance.isInitialized
        ? SharedDeviceDatabase.instance.getAllDevices()
        : <SharedDevice>[];

    // Filter by search query
    final matchingDevices = allDevices.where((d) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return d.name.toLowerCase().contains(q) ||
          d.macAddress.toLowerCase().contains(q) ||
          (d.vendor?.toLowerCase().contains(q) ?? false) ||
          (d.notes?.toLowerCase().contains(q) ?? false);
    }).toList();

    // Known devices: devices in the database which have been given a custom name
    final knownDevices = matchingDevices.where((d) => d.hasCustomName).toList();

    // Unknown devices: devices in the database without custom names
    final unknownDevices = matchingDevices.where((d) => !d.hasCustomName).toList();

    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppTheme.border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
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
                    child: Icon(Icons.menu_book, color: theme.colorScheme.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Custom Library',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        Text(
                          'Manage known and unknown devices in the shared database and configure filter visibility.',
                          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Device'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: () {
                      EditDeviceDialog.show(context, macAddress: '');
                    },
                  ),
                  const SizedBox(width: 8),
                  if (vm.devicePreferences.isNotEmpty) ...[
                    TextButton.icon(
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Reset Visibility', style: TextStyle(fontSize: 12)),
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
              const SizedBox(height: 14),

              // Search Bar
              SizedBox(
                height: 36,
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  decoration: InputDecoration(
                    hintText: 'Search devices by name, MAC, vendor, or notes...',
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
                    filled: true,
                    fillColor: AppTheme.surfaceHigh,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppTheme.inputBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppTheme.inputBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: AppTheme.accent, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Tabs
              TabBar(
                controller: _tabController,
                indicatorColor: theme.colorScheme.primary,
                labelColor: theme.colorScheme.primary,
                unselectedLabelColor: AppTheme.textSecondary,
                tabs: [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.verified_outlined, size: 16),
                        const SizedBox(width: 8),
                        Text('Known Devices (${knownDevices.length})'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.help_outline, size: 16),
                        const SizedBox(width: 8),
                        Text('Unknown Devices (${unknownDevices.length})'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildDeviceList(context, vm, knownDevices, isKnownTab: true),
                    _buildDeviceList(context, vm, unknownDevices, isKnownTab: false),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceList(
    BuildContext context,
    SyslogViewModel vm,
    List<SharedDevice> devices, {
    required bool isKnownTab,
  }) {
    if (devices.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isKnownTab ? Icons.devices : Icons.device_unknown,
              size: 40,
              color: AppTheme.textMuted,
            ),
            const SizedBox(height: 10),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No matching devices found.'
                  : isKnownTab
                      ? 'No known devices with custom names in database.'
                      : 'No unknown devices in database.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final deviceCounts = vm.deviceCounts;

    return ListView.separated(
      itemCount: devices.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final device = devices[index];
        final isVisible = vm.isDeviceVisible(device);
        final count = deviceCounts[device.macAddress] ?? 0;

        return Opacity(
          opacity: isVisible ? 1.0 : 0.55,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.surfaceHigh,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isVisible
                    ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.35)
                    : AppTheme.inputBorder,
              ),
            ),
            child: Row(
              children: [
                // Category Icon
                CircleAvatar(
                  radius: 16,
                  backgroundColor: isVisible
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                      : AppTheme.textMuted.withValues(alpha: 0.2),
                  child: Icon(
                    device.category.icon,
                    size: 16,
                    color: isVisible ? Theme.of(context).colorScheme.primary : AppTheme.textMuted,
                  ),
                ),
                const SizedBox(width: 12),

                // Device Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              device.name,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: AppTheme.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (isKnownTab)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppTheme.success.withValues(alpha: AppTheme.isDark ? 0.2 : 0.14),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Custom Name',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.success,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppTheme.warning.withValues(alpha: AppTheme.isDark ? 0.2 : 0.14),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'No Custom Name',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.warning,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          if (!isVisible) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppTheme.textMuted.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Hidden from Filters',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.textSecondary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                          if (count > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppTheme.info.withValues(alpha: AppTheme.isDark ? 0.2 : 0.14),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '$count logs',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.info,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${device.macAddress} • ${device.vendor ?? "Unknown Vendor"} • ${device.category.label}',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      if (device.notes != null && device.notes!.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          device.notes!,
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: AppTheme.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),

                // Visibility Toggle Button
                IconButton(
                  icon: Icon(
                    isVisible ? Icons.visibility : Icons.visibility_off,
                    size: 18,
                    color: isVisible ? Theme.of(context).colorScheme.primary : AppTheme.textMuted,
                  ),
                  tooltip: isVisible
                      ? 'Visible in filter bar (Click to hide)'
                      : 'Hidden from filter bar (Click to show)',
                  onPressed: () {
                    vm.toggleDeviceVisibility(device.macAddress);
                  },
                ),

                // Edit Details Button
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  tooltip: 'Edit Device Details in Shared Library',
                  onPressed: () {
                    EditDeviceDialog.show(
                      context,
                      macAddress: device.macAddress,
                      initialName: device.name,
                      initialCategory: device.deviceType,
                      initialVendor: device.vendor,
                      initialNotes: device.notes,
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
