import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'protocol.dart';

class FoundGame {
  FoundGame(this.name, this.address, this.port, this.players, this.open);
  final String name;
  final String address;
  final int port;
  final int players;
  final bool open;
  DateTime seen = DateTime.now();
}

/// Listens for hosts announcing games on the local network.
class Discovery extends ChangeNotifier {
  RawDatagramSocket? _socket;
  Timer? _prune;
  final Map<String, FoundGame> _games = {};
  bool failed = false;

  List<FoundGame> get games => _games.values.toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  Future<void> start() async {
    try {
      _socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4, kDiscoveryPort,
          reuseAddress: true);
      _socket!.broadcastEnabled = true;
      _socket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final d = _socket?.receive();
        if (d == null) return;
        try {
          final m = jsonDecode(utf8.decode(d.data)) as Map<String, dynamic>;
          if (m['coup'] != 1) return;
          final g = FoundGame(
            m['name'] as String,
            d.address.address,
            m['port'] as int,
            m['players'] as int,
            m['open'] as bool,
          );
          _games['${g.address}:${g.port}'] = g;
          notifyListeners();
        } catch (_) {}
      });
    } catch (_) {
      failed = true;
      notifyListeners();
    }
    _prune = Timer.periodic(const Duration(seconds: 2), (_) {
      final cutoff = DateTime.now().subtract(const Duration(seconds: 7));
      final before = _games.length;
      _games.removeWhere((_, g) => g.seen.isBefore(cutoff));
      if (_games.length != before) notifyListeners();
    });
  }

  void stop() {
    _prune?.cancel();
    _socket?.close();
    _socket = null;
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
