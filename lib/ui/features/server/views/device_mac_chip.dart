import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../data/services/device/mac_address_helper.dart';
import '../view_models/syslog_view_model.dart';
import 'rename_device_dialog.dart';

/// Interactive chip widget highlighting a detected MAC address in syslog events.
///
/// Resolves hardware manufacturer from IEEE OUI and friendly name from the
/// shared device library. Allows single-click or right-click to rename or filter.
class DeviceMacChip extends StatelessWidget {
  const DeviceMacChip({
    super.key,
    required this.mac,
    this.compact = false,
  });

  final String mac;
  final bool compact;

  void _showContextMenu(BuildContext context, Offset position) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final displayName = MacAddressHelper.getDisplayName(mac);
    final vm = context.read<SyslogViewModel>();

    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Rect.fromLTWH(0, 0, overlay.size.width, overlay.size.height),
      ),
      items: [
        PopupMenuItem(
          value: 'rename',
          child: Row(
            children: [
              const Icon(Icons.edit, size: 16),
              const SizedBox(width: 8),
              Text('Rename Device ($mac)'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'filter',
          child: Row(
            children: [
              const Icon(Icons.filter_alt, size: 16),
              const SizedBox(width: 8),
              Text('Filter Logs by MAC ($mac)'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'copy_mac',
          child: const Row(
            children: [
              Icon(Icons.copy, size: 16),
              SizedBox(width: 8),
              Text('Copy MAC Address'),
            ],
          ),
        ),
        if (displayName != mac)
          PopupMenuItem(
            value: 'copy_name',
            child: Row(
              children: [
                const Icon(Icons.badge, size: 16),
                const SizedBox(width: 8),
                Text('Copy Name: $displayName'),
              ],
            ),
          ),
      ],
    ).then((value) {
      if (!context.mounted) return;
      if (value == 'rename') {
        RenameDeviceDialog.show(context, mac);
      } else if (value == 'filter') {
        vm.setSearchQuery(mac);
      } else if (value == 'copy_mac') {
        Clipboard.setData(ClipboardData(text: mac));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('MAC $mac copied to clipboard'), duration: const Duration(seconds: 1)),
        );
      } else if (value == 'copy_name') {
        Clipboard.setData(ClipboardData(text: displayName));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Name "$displayName" copied to clipboard'), duration: const Duration(seconds: 1)),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = MacAddressHelper.getDisplayName(mac);
    final vendor = MacAddressHelper.getVendor(mac);
    final category = MacAddressHelper.getCategory(mac);
    final hasCustomName = displayName != mac && !displayName.startsWith(vendor);

    final tooltipMessage = StringBuffer()
      ..writeln('Device: $displayName')
      ..writeln('MAC: $mac')
      ..writeln('Vendor: $vendor')
      ..writeln('Category: ${category.label}')
      ..write('Click or right-click to rename or filter');

    if (compact) {
      return Tooltip(
        message: tooltipMessage.toString(),
        child: InkWell(
          onTap: () => RenameDeviceDialog.show(context, mac),
          onSecondaryTapUp: (details) => _showContextMenu(context, details.globalPosition),
          borderRadius: BorderRadius.circular(4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: hasCustomName
                  ? Colors.teal.withValues(alpha: 0.16)
                  : theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: hasCustomName
                    ? Colors.teal.withValues(alpha: 0.5)
                    : theme.colorScheme.primary.withValues(alpha: 0.35),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  category.icon,
                  size: 11,
                  color: hasCustomName ? Colors.tealAccent : theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  displayName,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: hasCustomName ? Colors.tealAccent : theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Full / Expanded Chip (for Detail Panel or Cards)
    return Tooltip(
      message: tooltipMessage.toString(),
      child: InkWell(
        onTap: () => RenameDeviceDialog.show(context, mac),
        onSecondaryTapUp: (details) => _showContextMenu(context, details.globalPosition),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: hasCustomName
                ? Colors.teal.withValues(alpha: 0.15)
                : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: hasCustomName
                  ? Colors.teal.withValues(alpha: 0.45)
                  : theme.dividerColor.withValues(alpha: 0.6),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                category.icon,
                size: 15,
                color: hasCustomName ? Colors.tealAccent : theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: hasCustomName ? Colors.tealAccent : theme.colorScheme.onSurface,
                        ),
                      ),
                      if (hasCustomName) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.check_circle, size: 11, color: Colors.tealAccent.withValues(alpha: 0.8)),
                      ],
                    ],
                  ),
                  Text(
                    '$mac • $vendor',
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.edit,
                size: 12,
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
