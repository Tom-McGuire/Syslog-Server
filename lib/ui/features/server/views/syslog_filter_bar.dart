import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/syslog_facility.dart';
import '../../../../domain/models/syslog_severity.dart';
import '../view_models/syslog_view_model.dart';
import 'rename_device_dialog.dart';

class SyslogFilterBar extends StatefulWidget {
  const SyslogFilterBar({super.key});

  @override
  State<SyslogFilterBar> createState() => _SyslogFilterBarState();
}

class _SyslogFilterBarState extends State<SyslogFilterBar> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _ipController = TextEditingController();
  Timer? _searchDebounce;
  Timer? _ipDebounce;
  bool _isExpanded = true;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _ipDebounce?.cancel();
    _searchController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String val, SyslogViewModel vm) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      vm.setSearchQuery(val);
    });
  }

  void _onIpChanged(String val, SyslogViewModel vm) {
    _ipDebounce?.cancel();
    _ipDebounce = Timer(const Duration(milliseconds: 250), () {
      vm.setRemoteIpFilter(val);
    });
  }

  Future<void> _showDeviceContextMenu(
    SyslogViewModel vm,
    String key,
    String displayName,
    Offset position,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final isMac = SharedDevice.isValidMac(key);
    final messenger = ScaffoldMessenger.of(context);

    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Rect.fromLTWH(0, 0, overlay.size.width, overlay.size.height),
      ),
      items: [
        PopupMenuItem(
          value: 'filter',
          child: Row(
            children: [
              const Icon(Icons.filter_alt, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text('Filter by $displayName', overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              const Icon(Icons.edit, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isMac ? 'Edit Device in Shared Library' : 'Save & Name in Shared Library',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'hide',
          child: Row(
            children: [
              Icon(Icons.visibility_off, size: 16),
              SizedBox(width: 8),
              Expanded(child: Text('Hide from Device Filters', overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'copy',
          child: Row(
            children: [
              const Icon(Icons.copy, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text('Copy "$key"', overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      ],
    );

    if (choice == null || !mounted) return;
    switch (choice) {
      case 'filter':
        vm.toggleDeviceFilter(key);
        break;
      case 'edit':
        if (!mounted) return;
        await RenameDeviceDialog.show(context, isMac ? key : '');
        break;
      case 'hide':
        vm.setDeviceHidden(key, true);
        break;
      case 'copy':
        await Clipboard.setData(ClipboardData(text: key));
        messenger.showSnackBar(
          SnackBar(
            content: Text('Copied $key to clipboard'),
            duration: const Duration(seconds: 2),
          ),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SyslogViewModel>();
    final filter = vm.filter;
    final severityCounts = vm.severityCounts;
    final hasActiveQuickFilters = filter.hasActiveFilter;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Search text, IP input, Facility, Auto-Detected Switch & Expand/Collapse
          Row(
            children: [
              // Search Query with 250ms debounce
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => _onSearchChanged(val, vm),
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Search message, host, app, IP...',
                      prefixIcon: const Icon(Icons.search, size: 16),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14),
                              onPressed: () {
                                _searchDebounce?.cancel();
                                _searchController.clear();
                                vm.setSearchQuery('');
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Source IP filter with 250ms debounce
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _ipController,
                    onChanged: (val) => _onIpChanged(val, vm),
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      hintText: 'Filter Source IP...',
                      prefixIcon: const Icon(Icons.router, size: 16),
                      suffixIcon: _ipController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14),
                              onPressed: () {
                                _ipDebounce?.cancel();
                                _ipController.clear();
                                vm.setRemoteIpFilter('');
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Facility Multi-Select Dropdown
              PopupMenuButton<SyslogFacility>(
                tooltip: 'Filter by Facility',
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFF3E3E42)),
                    color: const Color(0xFF252526),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.category_outlined, size: 16, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                        filter.selectedFacilities.isEmpty
                            ? 'All Facilities'
                            : '${filter.selectedFacilities.length} Facilities',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_drop_down, size: 18),
                    ],
                  ),
                ),
                itemBuilder: (context) {
                  return SyslogFacility.values.map((fac) {
                    final isChecked = filter.selectedFacilities.contains(fac);
                    return CheckedPopupMenuItem<SyslogFacility>(
                      value: fac,
                      checked: isChecked,
                      child: Text('${fac.nameStr} (${fac.description})', style: const TextStyle(fontSize: 12)),
                    );
                  }).toList();
                },
                onSelected: (fac) {
                  vm.toggleFacility(fac);
                },
              ),
              const SizedBox(width: 10),

              // Auto-Detected Switch Container (Consistent with Packet Inspector)
              Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: vm.showAutoDetected
                        ? Theme.of(context).colorScheme.primary
                        : const Color(0xFF3E3E42),
                  ),
                  color: const Color(0xFF252526),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.sensors,
                      size: 16,
                      color: vm.showAutoDetected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey,
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Auto-Detected',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 4),
                    Switch(
                      value: vm.showAutoDetected,
                      onChanged: (val) => vm.setShowAutoDetected(val),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
              ),

              if (hasActiveQuickFilters) ...[
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(Icons.filter_alt_off, size: 14),
                  label: const Text('Clear Filters', style: TextStyle(fontSize: 11)),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onPressed: () {
                    _searchDebounce?.cancel();
                    _ipDebounce?.cancel();
                    _searchController.clear();
                    _ipController.clear();
                    vm.resetFilters();
                  },
                ),
              ],

              const Spacer(),

              // Collapse / Expand Toggle
              Tooltip(
                message: _isExpanded ? 'Collapse filter rows' : 'Expand filter rows',
                child: IconButton(
                  icon: Icon(_isExpanded ? Icons.unfold_less : Icons.unfold_more, size: 18),
                  onPressed: () => setState(() => _isExpanded = !_isExpanded),
                ),
              ),
            ],
          ),

          if (_isExpanded) ...[
            const SizedBox(height: 8),
            // Row 2: Triage Severity Filter Row (Above Devices Row, matching Packet Inspector)
            _buildTriageFilterRow(context, vm, filter, severityCounts),

            const SizedBox(height: 8),
            // Row 3: Scrollable Device Filter Row
            _buildDeviceFilterRow(context, vm),
          ],
        ],
      ),
    );
  }

  Widget _buildDeviceFilterRow(BuildContext context, SyslogViewModel vm) {
    final knownDevices = vm.knownLabeledDevices;
    final autoDetected = vm.showAutoDetected ? vm.autoDetectedSources : const <String>[];
    final deviceCounts = vm.deviceCounts;

    return Row(
      children: [
        const Padding(
          padding: EdgeInsets.only(right: 8.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.devices, size: 14, color: Colors.blueAccent),
              SizedBox(width: 4),
              Text('Devices', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // 1. Known Labeled Devices from Shared Library
                ...knownDevices.map((device) {
                  final isSelected = vm.selectedDeviceKeys.contains(device.macAddress);
                  final count = deviceCounts[device.macAddress] ?? 0;

                  return Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: GestureDetector(
                      onSecondaryTapUp: (details) {
                        _showDeviceContextMenu(vm, device.macAddress, device.name, details.globalPosition);
                      },
                      child: FilterChip(
                        selected: isSelected,
                        showCheckmark: false,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        avatar: CircleAvatar(
                          radius: 7,
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          child: Icon(device.category.icon, size: 9, color: Theme.of(context).colorScheme.primary),
                        ),
                        label: Text(
                          '${device.name} ($count)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.white : Colors.grey.shade300,
                          ),
                        ),
                        tooltip: 'Device: ${device.name}\nMAC: ${device.macAddress}${device.vendor != null ? '\nVendor: ${device.vendor}' : ''}\n(Right-click for options)',
                        selectedColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
                        backgroundColor: const Color(0xFF252526),
                        side: BorderSide(
                          color: isSelected ? Theme.of(context).colorScheme.primary : const Color(0xFF3E3E42),
                          width: 1,
                        ),
                        onSelected: (_) => vm.toggleDeviceFilter(device.macAddress),
                      ),
                    ),
                  );
                }),

                // 2. Add Device Chip Button
                Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: ActionChip(
                    avatar: const Icon(Icons.add, size: 14),
                    label: const Text('Add Device', style: TextStyle(fontSize: 11)),
                    tooltip: 'Add new device to Shared Device Library',
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    backgroundColor: const Color(0xFF252526),
                    side: const BorderSide(color: Color(0xFF3E3E42)),
                    onPressed: () {
                      RenameDeviceDialog.show(context, '');
                    },
                  ),
                ),

                if (knownDevices.isNotEmpty && autoDetected.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Container(
                    height: 18,
                    width: 1,
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                  ),
                  const SizedBox(width: 8),
                ],

                // 3. Auto-Detected Sources
                ...autoDetected.map((src) {
                  final isSelected = vm.selectedDeviceKeys.contains(src);
                  final count = deviceCounts[src] ?? 0;

                  return Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: GestureDetector(
                      onSecondaryTapUp: (details) {
                        _showDeviceContextMenu(vm, src, src, details.globalPosition);
                      },
                      child: FilterChip(
                        selected: isSelected,
                        showCheckmark: false,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        avatar: CircleAvatar(
                          radius: 7,
                          backgroundColor: Colors.blueGrey.withValues(alpha: 0.2),
                          child: const Icon(Icons.sensors, size: 9, color: Colors.blueAccent),
                        ),
                        label: Text(
                          '$src ($count)',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.white : Colors.grey.shade300,
                          ),
                        ),
                        tooltip: 'Auto-Detected Source: $src\n(Right-click for options)',
                        selectedColor: Colors.blueAccent.withValues(alpha: 0.35),
                        backgroundColor: const Color(0xFF252526),
                        side: BorderSide(
                          color: isSelected ? Colors.blueAccent : const Color(0xFF3E3E42),
                          width: 1,
                        ),
                        onSelected: (_) => vm.toggleDeviceFilter(src),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTriageFilterRow(
    BuildContext context,
    SyslogViewModel vm,
    dynamic filter,
    Map<SyslogSeverity, int> severityCounts,
  ) {
    return Row(
      children: [
        const Padding(
          padding: EdgeInsets.only(right: 8.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.shield_outlined, size: 14, color: Colors.orangeAccent),
              SizedBox(width: 4),
              Text('Triage', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: SyslogSeverity.values.map((sev) {
                final isSelected = filter.selectedSeverities.contains(sev);
                final count = severityCounts[sev] ?? 0;

                return Padding(
                  padding: const EdgeInsets.only(right: 6.0),
                  child: FilterChip(
                    selected: isSelected,
                    showCheckmark: false,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    avatar: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: sev.color,
                      ),
                    ),
                    label: Text(
                      '${sev.label} ($count)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.white : Colors.grey.shade400,
                      ),
                    ),
                    selectedColor: sev.color.withValues(alpha: 0.35),
                    backgroundColor: const Color(0xFF252526),
                    side: BorderSide(
                      color: isSelected ? sev.color : const Color(0xFF3E3E42),
                      width: 1,
                    ),
                    onSelected: (_) => vm.toggleSeverity(sev),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }
}
