import 'package:flutter/material.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:provider/provider.dart';
import '../view_models/syslog_view_model.dart';

/// Modal dialog allowing the user to view and edit full device details
/// (Friendly Name, Device Category, Hardware Vendor, and Notes) in the Shared Device Library.
class EditDeviceDialog extends StatefulWidget {
  const EditDeviceDialog({
    super.key,
    required this.macAddress,
    this.initialName,
    this.initialCategory,
    this.initialVendor,
    this.initialNotes,
  });

  final String macAddress;
  final String? initialName;
  final String? initialCategory;
  final String? initialVendor;
  final String? initialNotes;

  static Future<void> show(
    BuildContext context, {
    required String macAddress,
    String? initialName,
    String? initialCategory,
    String? initialVendor,
    String? initialNotes,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => EditDeviceDialog(
        macAddress: macAddress,
        initialName: initialName,
        initialCategory: initialCategory,
        initialVendor: initialVendor,
        initialNotes: initialNotes,
      ),
    );
  }

  @override
  State<EditDeviceDialog> createState() => _EditDeviceDialogState();
}

class _EditDeviceDialogState extends State<EditDeviceDialog> {
  late final TextEditingController _macCtrl;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _vendorCtrl;
  late final TextEditingController _notesCtrl;
  late String _selectedCategoryKey;
  final _formKey = GlobalKey<FormState>();

  bool get _isNewDevice => widget.macAddress.trim().isEmpty;

  @override
  void initState() {
    super.initState();
    _macCtrl = TextEditingController(text: widget.macAddress);
    _nameCtrl = TextEditingController(text: widget.initialName ?? '');
    _vendorCtrl = TextEditingController(text: widget.initialVendor ?? '');
    _notesCtrl = TextEditingController(text: widget.initialNotes ?? '');
    _selectedCategoryKey = widget.initialCategory ?? 'other';
  }

  @override
  void dispose() {
    _macCtrl.dispose();
    _nameCtrl.dispose();
    _vendorCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final targetMac = _isNewDevice ? _macCtrl.text.trim() : widget.macAddress.trim();
    if (!SharedDevice.isValidMac(targetMac)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid MAC address format (must be 6 hex bytes, e.g. 00:11:22:33:44:55)'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final name = _nameCtrl.text.trim();
    final vendor = _vendorCtrl.text.trim().isNotEmpty ? _vendorCtrl.text.trim() : null;
    final notes = _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null;

    final vm = context.read<SyslogViewModel>();
    vm.updateDeviceDetails(
      mac: targetMac,
      name: name,
      category: _selectedCategoryKey,
      vendor: vendor,
      notes: notes,
    );

    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Device $targetMac updated in Shared Library ("$name")'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cat = DeviceCategory.fromKey(_selectedCategoryKey);

    return Dialog(
      backgroundColor: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
                      radius: 16,
                      child: Icon(cat.icon, size: 18, color: theme.colorScheme.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _isNewDevice ? 'Add Device to Shared Library' : 'Edit Device in Shared Library',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // MAC Address
                if (!_isNewDevice)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF252526),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF3E3E42)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.memory, size: 16, color: Colors.grey),
                        const SizedBox(width: 8),
                        const Text('MAC: ', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        Text(
                          widget.macAddress,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  TextFormField(
                    controller: _macCtrl,
                    style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      labelText: 'Hardware MAC Address *',
                      hintText: 'e.g. 00:1A:2B:3C:4D:5E',
                      prefixIcon: Icon(Icons.memory, size: 18),
                      border: OutlineInputBorder(),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Please enter a MAC address';
                      }
                      if (!SharedDevice.isValidMac(val.trim())) {
                        return 'Invalid MAC format (e.g. 00:11:22:33:44:55)';
                      }
                      return null;
                    },
                  ),
                const SizedBox(height: 14),

                // Device Friendly Name
                TextFormField(
                  controller: _nameCtrl,
                  autofocus: true,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Friendly Device Name *',
                    hintText: 'e.g. Primary Gateway, Core Switch, Living Room TV',
                    prefixIcon: Icon(Icons.label_outline, size: 18),
                    border: OutlineInputBorder(),
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Please enter a friendly device name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // Category Selector Dropdown
                DropdownButtonFormField<String>(
                  initialValue: _selectedCategoryKey,
                  dropdownColor: const Color(0xFF252526),
                  decoration: const InputDecoration(
                    labelText: 'Device Category',
                    prefixIcon: Icon(Icons.category_outlined, size: 18),
                    border: OutlineInputBorder(),
                  ),
                  items: DeviceCategory.values.map((c) {
                    return DropdownMenuItem<String>(
                      value: c.key,
                      child: Row(
                        children: [
                          Icon(c.icon, size: 16, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(c.label, style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedCategoryKey = val);
                    }
                  },
                ),
                const SizedBox(height: 14),

                // Hardware Vendor
                TextFormField(
                  controller: _vendorCtrl,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Hardware Vendor (Optional)',
                    hintText: 'e.g. Ubiquiti, Apple, Cisco, MikroTik',
                    prefixIcon: Icon(Icons.business, size: 18),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),

                // Notes
                TextFormField(
                  controller: _notesCtrl,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Notes & Inventory (Optional)',
                    hintText: 'e.g. Rack 2, Port 4, 10GbE Uplink',
                    prefixIcon: Icon(Icons.notes, size: 18),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),

                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Save to Library'),
                      onPressed: _submit,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
