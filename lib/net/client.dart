import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Connection from a player's app to the host's game server.
class CoupClient extends ChangeNotifier {
  CoupClient({
    required this.address,
    required this.port,
    required this.name,
    this.hostKey,
  });

  final String address;
  final int port;
  final String name;
  final String? hostKey;

  WebSocket? _ws;
  bool _closed = false;
  Timer? _retry;

  String? myId;
  bool connected = false;
  Map<String, dynamic>? state;

  /// Latest error message from the server; [errorSeq] increments each time.
  String? error;
  int errorSeq = 0;

  /// Fatal problem (e.g. game already running) that ends the session.
  String? fatal;

  bool get isHost => state != null && state!['hostId'] == myId && myId != null;

  Future<void> connect() async {
    final ws = await WebSocket.connect('ws://$address:$port')
        .timeout(const Duration(seconds: 6));
    _attach(ws);
  }

  void _attach(WebSocket ws) {
    _ws = ws;
    ws.pingInterval = const Duration(seconds: 5);
    connected = true;
    notifyListeners();
    ws.listen(_onMessage, onDone: _onDone, onError: (_) => _onDone());
    _send({'t': 'hello', 'name': name, 'id': myId, 'hostKey': hostKey});
  }

  void _onMessage(dynamic data) {
    final msg = jsonDecode(data as String) as Map<String, dynamic>;
    switch (msg['t']) {
      case 'welcome':
        myId = msg['you'] as String;
      case 'state':
        state = msg;
      case 'error':
        final text = msg['msg'] as String;
        if (myId == null) {
          fatal = text; // rejected before joining
          _closed = true;
          _ws?.close();
        }
        error = text;
        errorSeq++;
    }
    notifyListeners();
  }

  void _onDone() {
    connected = false;
    notifyListeners();
    if (_closed) return;
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 2), _reconnect);
  }

  Future<void> _reconnect() async {
    if (_closed) return;
    try {
      final ws = await WebSocket.connect('ws://$address:$port')
          .timeout(const Duration(seconds: 5));
      if (_closed) {
        ws.close();
        return;
      }
      _attach(ws);
    } catch (_) {
      _retry = Timer(const Duration(seconds: 2), _reconnect);
    }
  }

  void _send(Map<String, dynamic> m) {
    try {
      _ws?.add(jsonEncode(m));
    } catch (_) {}
  }

  // ------------------------------------------------------------ commands

  void startGame() => _send({'t': 'start'});
  void backToLobby() => _send({'t': 'lobby'});
  void act(String action, [String? target]) =>
      _send({'t': 'act', 'action': action, 'target': target});
  void challenge() => _send({'t': 'challenge'});
  void block(String role) => _send({'t': 'block', 'role': role});
  void allow() => _send({'t': 'pass'});
  void loseCard(int index) => _send({'t': 'lose', 'index': index});
  void exchange(List<int> keep) => _send({'t': 'exchange', 'keep': keep});

  void leave() {
    _closed = true;
    _retry?.cancel();
    _ws?.close();
  }

  @override
  void dispose() {
    leave();
    super.dispose();
  }
}
