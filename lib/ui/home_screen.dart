import 'package:flutter/material.dart';

import '../net/client.dart';
import '../net/discovery.dart';
import '../net/protocol.dart';
import '../net/server.dart';
import 'room_screen.dart';
import 'rules_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _name = TextEditingController();
  final _ip = TextEditingController();
  final _discovery = Discovery();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _discovery.start();
  }

  @override
  void dispose() {
    _discovery.dispose();
    _name.dispose();
    _ip.dispose();
    super.dispose();
  }

  String? _playerName() {
    final n = _name.text.trim();
    if (n.isEmpty) {
      _toast('Enter your name first.');
      return null;
    }
    return n;
  }

  void _toast(String s) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(s)));

  Future<void> _host() async {
    final name = _playerName();
    if (name == null) return;
    setState(() => _busy = true);
    final server = CoupServer(roomName: "$name's room");
    try {
      await server.start();
      final client = CoupClient(
          address: '127.0.0.1',
          port: server.port,
          name: name,
          hostKey: server.hostKey);
      await client.connect();
      await _openRoom(client, server);
    } catch (e) {
      await server.stop();
      _toast('Could not host: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join(String address, int port) async {
    final name = _playerName();
    if (name == null) return;
    setState(() => _busy = true);
    final client = CoupClient(address: address, port: port, name: name);
    try {
      await client.connect();
      await _openRoom(client, null);
    } catch (e) {
      client.leave();
      _toast('Could not connect to $address. Same Wi-Fi?');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openRoom(CoupClient client, CoupServer? server) async {
    _discovery.stop();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RoomScreen(client: client, server: server)));
    client.leave();
    await server?.stop();
    _discovery.start();
  }

  void _joinManual() {
    var text = _ip.text.trim();
    if (text.isEmpty) {
      _toast('Enter the host\'s IP address.');
      return;
    }
    var port = kGamePort;
    final i = text.lastIndexOf(':');
    if (i > 0) {
      port = int.tryParse(text.substring(i + 1)) ?? kGamePort;
      text = text.substring(0, i);
    }
    _join(text, port);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _busy,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 24),
              Text('COUP',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displayMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      letterSpacing: 12,
                      fontWeight: FontWeight.w300)),
              Text('Local multiplayer',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: Colors.white54)),
              const SizedBox(height: 32),
              TextField(
                controller: _name,
                maxLength: 16,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Your name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _host,
                icon: const Icon(Icons.wifi_tethering),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('Host a game'),
                ),
              ),
              const SizedBox(height: 28),
              Row(children: [
                Text('Games nearby', style: theme.textTheme.titleMedium),
                const SizedBox(width: 8),
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
              ]),
              const SizedBox(height: 8),
              ListenableBuilder(
                listenable: _discovery,
                builder: (context, _) {
                  final games = _discovery.games;
                  if (games.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _discovery.failed
                            ? 'Automatic search is unavailable on this device. '
                                'Enter the host\'s IP below.'
                            : 'Searching… Make sure everyone is on the same '
                                'Wi-Fi (or the host\'s hotspot).',
                        style: const TextStyle(color: Colors.white54),
                      ),
                    );
                  }
                  return Column(children: [
                    for (final g in games)
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.groups),
                          title: Text(g.name),
                          subtitle: Text(
                              '${g.address} · ${g.players}/6 players'
                              '${g.open ? '' : ' · in progress'}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _join(g.address, g.port),
                        ),
                      ),
                  ]);
                },
              ),
              const SizedBox(height: 20),
              Text('Join by IP address', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _ip,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        hintText: 'e.g. 192.168.1.23',
                        border: OutlineInputBorder()),
                    onSubmitted: (_) => _joinManual(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                    onPressed: _joinManual, child: const Text('Join')),
              ]),
              const SizedBox(height: 28),
              TextButton.icon(
                onPressed: () => showRules(context),
                icon: const Icon(Icons.menu_book),
                label: const Text('How to play'),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
