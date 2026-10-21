import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../../domain/models/syslog_record.dart';
import '../../../../domain/models/syslog_severity.dart';
import '../view_models/syslog_view_model.dart';

enum SyslogTableColumn {
  no('ID', 'id', 65.0, 45.0),
  time('Time', 'received_at_ms', 160.0, 110.0),
  severity('Severity', 'severity', 110.0, 75.0),
  facility('Facility', 'facility', 95.0, 65.0),
  source('Source IP', 'remote_ip', 135.0, 85.0),
  host('Host', 'hostname', 125.0, 75.0),
  app('App / Tag', 'app_name', 115.0, 70.0),
  message('Message', 'message', 400.0, 150.0);

  const SyslogTableColumn(this.label, this.sortKey, this.defaultWidth, this.minWidth);
  final String label;
  final String sortKey;
  final double defaultWidth;
  final double minWidth;
}

class SyslogTableView extends StatefulWidget {
  const SyslogTableView({super.key});

  @override
  State<SyslogTableView> createState() => _SyslogTableViewState();
}

class _SyslogTableViewState extends State<SyslogTableView> {
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _verticalScrollController = ScrollController();
  late Map<SyslogTableColumn, double> _columnWidths;
  final DateFormat _timeFormatter = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');

  @override
  void initState() {
    super.initState();
    _columnWidths = {
      for (final col in SyslogTableColumn.values) col: col.defaultWidth,
    };
    _verticalScrollController.addListener(_onVerticalScroll);
  }

  void _onVerticalScroll() {
    if (!_verticalScrollController.hasClients) return;
    final maxScroll = _verticalScrollController.position.maxScrollExtent;
    final currentScroll = _verticalScrollController.position.pixels;
    if (maxScroll - currentScroll <= 400) {
      final vm = context.read<SyslogViewModel>();
      if (vm.hasMoreLogs && !vm.isLoadingMore) {
        vm.loadMoreLogs();
      }
    }
  }

  @override
  void dispose() {
    _verticalScrollController.removeListener(_onVerticalScroll);
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SyslogViewModel>();
    final logs = vm.logs;

    if (logs.isEmpty) {
      return _buildEmptyState(context, vm);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final sumExceptMessage = _columnWidths.entries
            .where((e) => e.key != SyslogTableColumn.message)
            .fold(0.0, (acc, e) => acc + e.value);
        // 32px accounts for row padding (16 left + 16 right)
        final baseMessageWidth = _columnWidths[SyslogTableColumn.message]!;
        final effectiveMessageWidth =
            max(baseMessageWidth, availableWidth - sumExceptMessage - 32.0);

        final effectiveWidths = Map<SyslogTableColumn, double>.from(_columnWidths);
        effectiveWidths[SyslogTableColumn.message] = effectiveMessageWidth;

        final totalContentWidth =
            effectiveWidths.values.fold(0.0, (acc, w) => acc + w) + 32.0;
        final totalTableWidth = max(availableWidth, totalContentWidth);

        return Scrollbar(
          controller: _horizontalScrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _horizontalScrollController,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: totalTableWidth,
              child: Column(
                children: [
                  // Table Header
                  _buildHeaderRow(context, vm, effectiveWidths),
                  const Divider(height: 1),

                  // Virtualized rows list with infinite scroll pagination
                  Expanded(
                    child: Scrollbar(
                      controller: _verticalScrollController,
                      thumbVisibility: true,
                      child: ListView.separated(
                        controller: _verticalScrollController,
                        itemCount: logs.length + (vm.hasMoreLogs ? 1 : 0),
                        separatorBuilder: (_, index) {
                          if (index >= logs.length) return const SizedBox.shrink();
                          return const Divider(height: 1, indent: 8, endIndent: 8);
                        },
                        itemBuilder: (context, index) {
                          if (index == logs.length) {
                            return _buildLoadingMoreIndicator(context, vm, logs.length);
                          }
                          final record = logs[index];
                          return _buildRow(context, vm, record, effectiveWidths);
                        },
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  _buildStatusBar(context, vm, logs.length),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, SyslogViewModel vm) {
    final hasActiveFilter = vm.filter.hasActiveFilter;
    final isListening = vm.serverStatus.isListening;

    return Container(
      color: Theme.of(context).colorScheme.surface,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
            ),
            child: Icon(
              hasActiveFilter
                  ? Icons.filter_alt_off_outlined
                  : (isListening ? Icons.hearing : Icons.dns_outlined),
              size: 52,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            hasActiveFilter
                ? 'No Logs Match Active Filter'
                : (isListening
                    ? 'Listening for Syslog Messages...'
                    : 'Syslog Server is Stopped'),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            hasActiveFilter
                ? 'Try clearing search terms or selecting more severity levels.'
                : (isListening
                    ? 'Waiting for UDP/TCP packets on port ${vm.serverStatus.port} from network devices.'
                    : 'Start the server above or load demo traffic to inspect sample logs.'),
            style: const TextStyle(color: Colors.grey, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (hasActiveFilter)
            FilledButton.tonalIcon(
              icon: const Icon(Icons.clear_all, size: 16),
              label: const Text('Reset Filters'),
              onPressed: () => vm.resetFilters(),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isListening) ...[
                  FilledButton.icon(
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('Start Server (Port 514)'),
                    onPressed: () => vm.startServer(),
                  ),
                  const SizedBox(width: 12),
                ],
                OutlinedButton.icon(
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('Load Demo Logs'),
                  onPressed: () => vm.loadDemoLogs(),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderRow(
    BuildContext context,
    SyslogViewModel vm,
    Map<SyslogTableColumn, double> widths,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.8),
      child: Row(
        children: SyslogTableColumn.values.map((col) {
          return _buildHeaderCell(context, vm, col, widths[col]!);
        }).toList(),
      ),
    );
  }

  Widget _buildHeaderCell(
    BuildContext context,
    SyslogViewModel vm,
    SyslogTableColumn col,
    double width,
  ) {
    final isSorted = vm.sortColumn == col.sortKey;
    final isAsc = vm.sortAscending;

    return SizedBox(
      width: width,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => vm.setSort(col.sortKey),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        col.label,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: isSorted
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isSorted) ...[
                      const SizedBox(width: 4),
                      Icon(
                        isAsc ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // Drag handle to resize column
          MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (details) {
                setState(() {
                  final newWidth = max(
                    col.minWidth,
                    (_columnWidths[col] ?? col.defaultWidth) + details.delta.dx,
                  );
                  _columnWidths[col] = newWidth;
                });
              },
              child: Container(
                width: 12,
                height: 24,
                alignment: Alignment.center,
                child: Container(
                  width: 1.5,
                  height: 14,
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(
    BuildContext context,
    SyslogViewModel vm,
    SyslogRecord record,
    Map<SyslogTableColumn, double> widths,
  ) {
    final isSelected = vm.selectedRecord?.id == record.id;

    Color? rowBackground;
    if (isSelected) {
      rowBackground = Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35);
    } else if (record.severity.code <= 2) {
      // Emergency / Alert / Critical gets a subtle red tint
      rowBackground = Colors.red.withValues(alpha: 0.06);
    } else if (record.severity.code == 3) {
      // Error gets subtle orange/red tint
      rowBackground = Colors.orange.withValues(alpha: 0.04);
    }

    return InkWell(
      onTap: () => vm.selectRecord(record),
      onSecondaryTapUp: (details) => _showContextMenu(context, vm, record, details.globalPosition),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        color: rowBackground ?? Colors.transparent,
        child: Row(
          children: [
            // ID
            SizedBox(
              width: widths[SyslogTableColumn.no],
              child: Text(
                '${record.id ?? ""}',
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
            // Time
            SizedBox(
              width: widths[SyslogTableColumn.time],
              child: Tooltip(
                message: 'Local: ${_timeFormatter.format(record.receivedAt)}\nRaw Header: ${record.timestampStr ?? "None"}',
                child: Text(
                  _timeFormatter.format(record.receivedAt),
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            // Severity Pill
            SizedBox(
              width: widths[SyslogTableColumn.severity],
              child: _buildSeverityPill(context, record.severity),
            ),
            // Facility
            SizedBox(
              width: widths[SyslogTableColumn.facility],
              child: Text(
                record.facility.nameStr,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Source IP
            SizedBox(
              width: widths[SyslogTableColumn.source],
              child: Text(
                '${record.remoteIp}:${record.remotePort}',
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Hostname
            SizedBox(
              width: widths[SyslogTableColumn.host],
              child: Text(
                record.hostname ?? '-',
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // App / Tag
            SizedBox(
              width: widths[SyslogTableColumn.app],
              child: Text(
                record.appName != null
                    ? (record.procId != null
                        ? '${record.appName}[${record.procId}]'
                        : record.appName!)
                    : '-',
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Message
            SizedBox(
              width: widths[SyslogTableColumn.message],
              child: Text(
                record.message.isEmpty ? record.rawPayload : record.message,
                style: const TextStyle(fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeverityPill(BuildContext context, SyslogSeverity severity) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: severity.color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: severity.color.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: Text(
          severity.label,
          style: TextStyle(
            color: severity.color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingMoreIndicator(BuildContext context, SyslogViewModel vm, int currentCount) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text(
            'Loading more logs... ($currentCount of ${vm.totalLogCount} loaded)',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBar(BuildContext context, SyslogViewModel vm, int loadedCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Row(
        children: [
          Icon(Icons.format_list_bulleted, size: 14, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            'Showing $loadedCount of ${vm.totalLogCount} logs',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          if (vm.hasMoreLogs) ...[
            const SizedBox(width: 8),
            const Text(
              '• Scroll down to load next batch of 1,000',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
          const Spacer(),
          // Auto-scroll indicator
          InkWell(
            onTap: () => vm.toggleAutoScroll(),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Row(
                children: [
                  Icon(
                    vm.autoScroll ? Icons.lock_clock : Icons.pause_circle_outline,
                    size: 14,
                    color: vm.autoScroll ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    vm.autoScroll ? 'Live Stream Active' : 'Live Stream Paused',
                    style: TextStyle(
                      fontSize: 11,
                      color: vm.autoScroll ? Colors.green : Colors.grey,
                      fontWeight: FontWeight.w500,
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

  void _showContextMenu(
    BuildContext context,
    SyslogViewModel vm,
    SyslogRecord record,
    Offset position,
  ) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Rect.fromLTWH(0, 0, overlay.size.width, overlay.size.height),
      ),
      items: [
        const PopupMenuItem(
          value: 'copy_msg',
          child: Row(
            children: [
              Icon(Icons.copy, size: 16),
              SizedBox(width: 8),
              Text('Copy Message'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'copy_raw',
          child: Row(
            children: [
              Icon(Icons.raw_on, size: 16),
              SizedBox(width: 8),
              Text('Copy Raw Payload'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'filter_ip',
          child: Row(
            children: [
              const Icon(Icons.filter_alt, size: 16),
              const SizedBox(width: 8),
              Text('Filter by IP: ${record.remoteIp}'),
            ],
          ),
        ),
        if (record.hostname != null && record.hostname!.isNotEmpty)
          PopupMenuItem(
            value: 'filter_host',
            child: Row(
              children: [
                const Icon(Icons.dns, size: 16),
                const SizedBox(width: 8),
                Text('Filter by Host: ${record.hostname}'),
              ],
            ),
          ),
      ],
    ).then((value) {
      if (!context.mounted) return;
      if (value == 'copy_msg') {
        Clipboard.setData(ClipboardData(text: record.message));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message copied to clipboard'), duration: Duration(seconds: 1)),
        );
      } else if (value == 'copy_raw') {
        Clipboard.setData(ClipboardData(text: record.rawPayload));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Raw payload copied to clipboard'), duration: Duration(seconds: 1)),
        );
      } else if (value == 'filter_ip') {
        vm.setRemoteIpFilter(record.remoteIp);
      } else if (value == 'filter_host') {
        vm.setSearchQuery(record.hostname!);
      }
    });
  }
}
