import 'package:flutter/material.dart';
import 'package:network_suite_shared/network_suite_shared.dart';

/// Helper utility for extracting, normalizing, and resolving MAC addresses
/// in syslog messages using the Network Suite's [SharedDeviceDatabase].
class MacAddressHelper {
  // Regex matching:
  // 1. Standard IEEE 802 colon or hyphen delimited: 00:1A:2B:3C:4D:5E or 00-1A-2B-3C-4D-5E
  // 2. Cisco dotted quad: 001a.2b3c.4d5e
  static final RegExp _macPattern = RegExp(
    r'\b(?:[0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}\b|\b(?:[0-9A-Fa-f]{4}\.){2}[0-9A-Fa-f]{4}\b',
    caseSensitive: false,
  );

  /// Extracts all unique, normalized MAC addresses from [text].
  static List<String> extractMacs(String text) {
    if (text.isEmpty) return const [];
    final matches = _macPattern.allMatches(text);
    if (matches.isEmpty) return const [];

    final seen = <String>{};
    final result = <String>[];
    for (final match in matches) {
      final raw = match.group(0);
      if (raw == null) continue;
      final normalized = SharedDevice.normalizeMac(raw);
      if (SharedDevice.isValidMac(normalized) && seen.add(normalized)) {
        result.add(normalized);
      }
    }
    return result;
  }

  /// Safely retrieves a registered [SharedDevice] from the shared database.
  /// Returns `null` if not found or if the shared database is uninitialized.
  static SharedDevice? getDevice(String mac) {
    try {
      if (SharedDeviceDatabase.instance.isInitialized) {
        final normalized = SharedDevice.normalizeMac(mac);
        return SharedDeviceDatabase.instance.getDeviceByMac(normalized);
      }
    } catch (_) {}
    return null;
  }

  /// Resolves the most friendly display name for a given [mac].
  ///
  /// Priority:
  /// 1. User-assigned custom friendly name in [SharedDeviceDatabase].
  /// 2. Hardware Vendor (from IEEE OUI) + last 3 bytes of MAC.
  /// 3. Normalized MAC address.
  static String getDisplayName(String mac) {
    final device = getDevice(mac);
    if (device != null && device.name.trim().isNotEmpty) {
      return device.name.trim();
    }

    final normalized = SharedDevice.normalizeMac(mac);
    final vendor = OuiLookup.lookupVendor(normalized);
    if (vendor != 'Unknown Vendor' &&
        vendor != 'Unknown Hardware' &&
        vendor != 'Randomized / Private MAC') {
      final suffix = normalized.length >= 17 ? normalized.substring(9) : normalized;
      return '$vendor ($suffix)';
    }

    return normalized;
  }

  /// Returns the hardware manufacturer for a MAC address via OUI lookup.
  static String getVendor(String mac) {
    final normalized = SharedDevice.normalizeMac(mac);
    final device = getDevice(normalized);
    if (device != null && device.vendor != null && device.vendor!.isNotEmpty) {
      return device.vendor!;
    }
    return OuiLookup.lookupVendor(normalized);
  }

  /// Returns the inferred or assigned [DeviceCategory] for a MAC address.
  static DeviceCategory getCategory(String mac) {
    final normalized = SharedDevice.normalizeMac(mac);
    final device = getDevice(normalized);
    if (device != null) {
      return device.category;
    }
    final vendor = OuiLookup.lookupVendor(normalized);
    return OuiLookup.inferCategory(vendor);
  }

  /// Updates an existing device's name or registers a new device
  /// in the shared hardware database.
  static void updateDeviceName(String mac, String newName) {
    try {
      if (!SharedDeviceDatabase.instance.isInitialized) return;
      final normalized = SharedDevice.normalizeMac(mac);
      final existing = SharedDeviceDatabase.instance.getDeviceByMac(normalized);

      if (existing != null) {
        SharedDeviceDatabase.instance.updateDeviceName(normalized, newName);
      } else {
        final vendor = OuiLookup.lookupVendor(normalized);
        final category = OuiLookup.inferCategory(vendor);
        final cleanVendor = (vendor != 'Unknown Vendor' && vendor != 'Unknown Hardware') ? vendor : null;

        SharedDeviceDatabase.instance.upsertDevice(SharedDevice(
          macAddress: normalized,
          name: newName.trim(),
          vendor: cleanVendor,
          deviceType: category.key,
          notes: 'Discovered in syslog packet',
          sourceApp: 'syslog-server',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ));
      }
    } catch (e) {
      debugPrint('Error updating device name in shared database: $e');
    }
  }
}
