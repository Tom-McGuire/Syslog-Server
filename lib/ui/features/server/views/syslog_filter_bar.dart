import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/syslog_facility.dart';
import '../../../../domain/models/syslog_severity.dart';
import '../view_models/syslog_view_model.dart';

class SyslogFilterBar extends StatefulWidget {
  const SyslogFilterBar({super.key});

  @override
  State<SyslogFilterBar> createState() => _SyslogFilterBarState();
}

class _SyslogFilterBarState extends State<SyslogFilterBar> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _ipController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SyslogViewModel>();
    final filter = vm.filter;
    final severityCounts = vm.severityCounts;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Search text & IP input & Reset
          Row(
            children: [
              // Search Query
              Expanded(
                flex: 3,
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (val) => vm.setSearchQuery(val),
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Search message, host, app, IP...',
                      prefixIcon: const Icon(Icons.search, size: 16),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14),
                              onPressed: () {
                                _searchController.clear();
                                vm.setSearchQuery('');
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Source IP filter
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _ipController,
                    onChanged: (val) => vm.setRemoteIpFilter(val),
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      hintText: 'Filter Source IP...',
                      prefixIcon: const Icon(Icons.router, size: 16),
                      suffixIcon: _ipController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 14),
                              onPressed: () {
                                _ipController.clear();
                                vm.setRemoteIpFilter('');
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Facility Multi-Select Dropdown
              PopupMenuButton<SyslogFacility>(
                tooltip: 'Filter by Facility',
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
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

              if (filter.hasActiveFilter) ...[
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: () {
                    _searchController.clear();
                    _ipController.clear();
                    vm.resetFilters();
                  },
                  icon: const Icon(Icons.filter_alt_off, size: 16),
                  label: const Text('Clear Filters', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),

          // Row 2: Severity Filter Chips
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: SyslogSeverity.values.map((sev) {
              final isSelected = filter.selectedSeverities.contains(sev);
              final count = severityCounts[sev] ?? 0;

              return FilterChip(
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
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
