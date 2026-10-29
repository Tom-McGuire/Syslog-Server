import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../data/services/device/mac_address_helper.dart';
import '../view_models/syslog_view_model.dart';

/// Modal dialog allowing the user to rename or assign a friendly name
/// to a network device identified by its hardware MAC address.
class RenameDeviceDialog extends StatefulWidget {
  const RenameDeviceDialog({
    super.key,
    required this.macAddress,
    this.currentName,
  });

  final String macAddress;
  final String? currentName;

  static Future<void> show(BuildContext context, String macAddress) async {
    final existingDevice = MacAddressHelper.getDevice(macAddress);
    final currentName = existingDevice?.name ??
        (MacAddressHelper.getDisplayName(macAddress) != macAddress
            ? MacAddressHelper.getDisplayName(macAddress)
            : null);

    await showDialog<void>(
      context: context,
      builder: (ctx) => RenameDeviceDialog(
        macAddress: macAddress,
        currentName: currentName,
      ),
    );
  }

  @override
  State<RenameDeviceDialog> createState() => _RenameDeviceDialogState();
}

class _RenameDeviceDialogState extends State<RenameDeviceDialog> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      final newName = _controller.text.trim();
      context.read<SyslogViewModel>().updateDeviceName(widget.macAddress, newName);
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Device ${widget.macAddress} renamed to "$newName"'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vendor = MacAddressHelper.getVendor(widget.macAddress);
    final category = MacAddressHelper.getCategory(widget.macAddress);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.edit_note, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          const Text('Rename Network Device'),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hardware Identity Card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.dividerColor.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(category.icon, size: 24, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.macAddress,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$vendor • ${category.label}',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Text(
                'Assign a friendly name to identify this device across the Network Suite:',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),

              TextFormField(
                controller: _controller,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Friendly Device Name',
                  hintText: 'e.g. Core Switch, Living Room TV, CEO Laptop',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.label_outline, size: 18),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'Please enter a device name';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.check, size: 16),
          label: const Text('Save Name'),
          onPressed: _submit,
        ),
      ],
    );
  }
}
