import 'dart:io';

/// TCP port the host's game server listens on.
const kGamePort = 4040;

/// UDP port used to announce hosted games on the local network.
const kDiscoveryPort = 4041;

/// IPv4 addresses of this device on the local network (Wi-Fi / hotspot).
Future<List<String>> localIpAddresses() async {
  try {
    final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false);
    final ips = <String>[];
    for (final i in interfaces) {
      for (final a in i.addresses) {
        final ip = a.address;
        // Skip cellular-only ranges like 100.64.x.x (CGNAT) and link-local.
        if (ip.startsWith('169.254.') || ip.startsWith('100.')) continue;
        ips.add(ip);
      }
    }
    // Prefer typical home/hotspot ranges first.
    int rank(String ip) => ip.startsWith('192.168.')
        ? 0
        : ip.startsWith('10.')
            ? 1
            : ip.startsWith('172.')
                ? 2
                : 3;
    ips.sort((a, b) => rank(a).compareTo(rank(b)));
    return ips;
  } catch (_) {
    return [];
  }
}
