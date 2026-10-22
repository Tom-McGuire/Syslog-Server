import 'dart:io';
import '../../../domain/models/network_adapter_info.dart';

class NetworkAdapterService {
  static Future<List<NetworkAdapterInfo>> getAvailableAdapters() async {
    final adapters = <NetworkAdapterInfo>[NetworkAdapterInfo.all];

    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: true,
        type: InternetAddressType.IPv4,
      );

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            adapters.add(
              NetworkAdapterInfo(
                name: interface.name,
                ipAddress: addr.address,
              ),
            );
          }
        }
      }
    } catch (_) {
      // In case of platform permission or lookup restriction, fallback to All & Loopback
      adapters.add(
        const NetworkAdapterInfo(
          name: 'Loopback',
          ipAddress: '127.0.0.1',
        ),
      );
    }

    return adapters;
  }
}
