import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../game/engine.dart';
import '../game/models.dart';
import 'protocol.dart';

/// Game server that runs inside the host's app. Other phones connect to it
/// over the local Wi-Fi network with a WebSocket.
class CoupServer {
  CoupServer({required this.roomName});

  final String roomName;
  final CoupGame game = CoupGame();
  final String hostKey = _randomId(16);

  HttpServer? _http;
  RawDatagramSocket? _udp;
  Timer? _beacon;
  String? _hostPlayerId;
  final Map<String, WebSocket> _sockets = {};

  int get port => _http?.port ?? kGamePort;

  Future<void> start() async {
    try {
      _http = await HttpServer.bind(InternetAddress.anyIPv4, kGamePort,
          shared: true);
    } on SocketException {
      // Port busy (e.g. a previous room didn't close yet): use any free port.
      _http = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    }
    _http!.listen(_onRequest, onError: (_) {});
    await _startBeacon();
  }

  Future<void> stop() async {
    _beacon?.cancel();
    _udp?.close();
    for (final ws in _sockets.values.toList()) {
      await ws.close();
    }
    _sockets.clear();
    await _http?.close(force: true);
  }

  // ------------------------------------------------------------ discovery

  Future<void> _startBeacon() async {
    try {
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      _udp!.broadcastEnabled = true;
    } catch (_) {
      return; // Discovery is optional; players can still type the IP.
    }
    final targets = <InternetAddress>{InternetAddress('255.255.255.255')};
    for (final ip in await localIpAddresses()) {
      final parts = ip.split('.');
      if (parts.length == 4) {
        targets.add(InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'));
      }
    }
    void send() {
      final msg = utf8.encode(jsonEncode({
        'coup': 1,
        'name': roomName,
        'port': port,
        'players': game.players.length,
        'open': game.phase == Phase.lobby,
      }));
      for (final t in targets) {
        try {
          _udp?.send(msg, t, kDiscoveryPort);
        } catch (_) {}
      }
    }

    send();
    _beacon = Timer.periodic(const Duration(seconds: 2), (_) => send());
  }

  // ------------------------------------------------------------ connections

  Future<void> _onRequest(HttpRequest req) async {
    if (!WebSocketTransformer.isUpgradeRequest(req)) {
      req.response
        ..statusCode = HttpStatus.ok
        ..write('Coup LAN server')
        ..close();
      return;
    }
    final ws = await WebSocketTransformer.upgrade(req);
    ws.pingInterval = const Duration(seconds: 5);
    String? pid;
    ws.listen(
      (data) {
        try {
          final msg = jsonDecode(data as String) as Map<String, dynamic>;
          if (msg['t'] == 'hello') {
            pid = _hello(ws, msg);
          } else if (pid != null) {
            _handle(pid!, msg);
          }
        } on GameException catch (e) {
          _send(ws, {'t': 'error', 'msg': e.message});
        } catch (e) {
          _send(ws, {'t': 'error', 'msg': 'Bad request: $e'});
        }
        _broadcast();
      },
      onDone: () => _disconnected(pid, ws),
      onError: (_) => _disconnected(pid, ws),
      cancelOnError: true,
    );
  }

  String _hello(WebSocket ws, Map<String, dynamic> msg) {
    var name = (msg['name'] as String? ?? '').trim();
    if (name.isEmpty) name = 'Player';
    if (name.length > 16) name = name.substring(0, 16);
    final wantedId = msg['id'] as String?;

    // 1. Reconnect with the same id.
    var p = game.tryPlayer(wantedId);
    // 2. Rejoin a running game under the same name after an app restart.
    if (p == null && game.phase != Phase.lobby) {
      for (final q in game.players) {
        if (!q.connected && q.name.toLowerCase() == name.toLowerCase()) p = q;
      }
    }
    if (p == null) {
      if (game.phase != Phase.lobby) {
        throw GameException('A game is already in progress.');
      }
      final taken = game.players.map((q) => q.name.toLowerCase()).toSet();
      var unique = name;
      for (var i = 2; taken.contains(unique.toLowerCase()); i++) {
        unique = '$name $i';
      }
      p = Player(_randomId(8), unique);
      game.addPlayer(p.id, p.name);
      p = game.player(p.id);
    }

    final old = _sockets[p.id];
    if (old != null && old != ws) old.close();
    _sockets[p.id] = ws;
    p.connected = true;
    if (msg['hostKey'] == hostKey) _hostPlayerId = p.id;
    _send(ws, {'t': 'welcome', 'you': p.id, 'host': p.id == _hostPlayerId});
    game.onConnectionChanged();
    return p.id;
  }

  void _disconnected(String? pid, WebSocket ws) {
    if (pid == null || _sockets[pid] != ws) return;
    _sockets.remove(pid);
    if (game.phase == Phase.lobby) {
      if (pid != _hostPlayerId) game.removePlayer(pid);
    } else {
      game.tryPlayer(pid)?.connected = false;
      game.onConnectionChanged();
    }
    _broadcast();
  }

  void _handle(String pid, Map<String, dynamic> msg) {
    final isHost = pid == _hostPlayerId;
    switch (msg['t']) {
      case 'start':
        if (!isHost) throw GameException('Only the host can start.');
        game.start();
      case 'lobby':
        if (!isHost) throw GameException('Only the host can do that.');
        game.backToLobby();
      case 'act':
        game.declareAction(pid, ActionType.values.byName(msg['action'] as String),
            msg['target'] as String?);
      case 'challenge':
        game.challenge(pid);
      case 'block':
        game.block(pid, Role.values.byName(msg['role'] as String));
      case 'pass':
        game.pass(pid);
      case 'lose':
        game.chooseLoss(pid, msg['index'] as int);
      case 'exchange':
        game.chooseExchange(
            pid, (msg['keep'] as List).map((e) => e as int).toList());
      default:
        throw GameException('Unknown command.');
    }
  }

  void _broadcast() {
    for (final e in _sockets.entries) {
      _send(e.value, {
        't': 'state',
        'room': roomName,
        'hostId': _hostPlayerId,
        ...game.viewFor(e.key),
      });
    }
  }

  void _send(WebSocket ws, Map<String, dynamic> m) {
    try {
      ws.add(jsonEncode(m));
    } catch (_) {}
  }
}

String _randomId(int n) {
  const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
  final r = Random.secure();
  return List.generate(n, (_) => chars[r.nextInt(chars.length)]).join();
}
