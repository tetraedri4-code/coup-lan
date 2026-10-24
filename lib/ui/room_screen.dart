import 'package:flutter/material.dart';

import '../game/models.dart';
import '../net/client.dart';
import '../net/protocol.dart';
import '../net/server.dart';
import 'cards.dart';
import 'rules_sheet.dart';

typedef Json = Map<String, dynamic>;

/// Read-only helper around the state map the server sends.
class GameView {
  GameView(this.s, this.me);
  final Json s;
  final String? me;

  String get phase => s['phase'] as String;
  List<Json> get players => (s['players'] as List).cast<Json>();
  Json? player(String? id) =>
      id == null ? null : players.where((p) => p['id'] == id).firstOrNull;
  String name(String? id) => (player(id)?['name'] as String?) ?? '?';
  Json? get self => player(me);
  Json get you => (s['you'] as Json?) ?? const {};
  bool get myTurn => s['turn'] == me;
  ActionType? get action =>
      s['action'] == null ? null : ActionType.values.byName(s['action'] as String);
  List<String> get log => (s['log'] as List).cast<String>();

  List<Json> cardsOf(Json p) => (p['cards'] as List).cast<Json>();
  int hiddenCount(Json p) =>
      cardsOf(p).where((c) => c['revealed'] != true).length;
}

class RoomScreen extends StatefulWidget {
  const RoomScreen({super.key, required this.client, this.server});
  final CoupClient client;
  final CoupServer? server;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  int _seenError = 0;
  List<String> _ips = [];

  CoupClient get client => widget.client;

  @override
  void initState() {
    super.initState();
    client.addListener(_onClient);
    if (widget.server != null) {
      localIpAddresses().then((ips) {
        if (mounted) setState(() => _ips = ips);
      });
    }
  }

  @override
  void dispose() {
    client.removeListener(_onClient);
    super.dispose();
  }

  void _onClient() {
    if (!mounted) return;
    if (client.fatal != null) {
      final msg = client.fatal!;
      client.fatal = null;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Could not join'),
          content: Text(msg),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK')),
          ],
        ),
      ).then((_) {
        if (mounted) Navigator.of(context).pop();
      });
      return;
    }
    if (client.errorSeq != _seenError) {
      _seenError = client.errorSeq;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(client.error ?? 'Error')));
    }
  }

  Future<bool> _confirmLeave() async {
    final host = widget.server != null;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Leave game?'),
        content: Text(host
            ? 'You are the host. Leaving closes the room for everyone.'
            : 'You can rejoin with the same name while the game is running.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Stay')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Leave')),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: ListenableBuilder(
        listenable: client,
        builder: (context, _) {
          final s = client.state;
          return Scaffold(
            appBar: AppBar(
              title: Text((s?['room'] as String?) ?? 'Coup'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () async {
                  if (await _confirmLeave() && context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
              ),
              actions: [
                IconButton(
                    onPressed: () => showRules(context),
                    icon: const Icon(Icons.menu_book)),
              ],
            ),
            body: SafeArea(
              child: Column(children: [
                if (!client.connected)
                  Container(
                    width: double.infinity,
                    color: Colors.orange.shade900,
                    padding: const EdgeInsets.all(8),
                    child: const Text('Connection lost — reconnecting…',
                        textAlign: TextAlign.center),
                  ),
                Expanded(
                  child: s == null
                      ? const Center(child: CircularProgressIndicator())
                      : _body(GameView(s, client.myId)),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }

  Widget _body(GameView v) {
    if (v.phase == Phase.lobby.name) {
      return _Lobby(
          view: v, client: client, ips: _ips, port: widget.server?.port);
    }
    return _Table(view: v, client: client);
  }
}

// =================================================================== LOBBY

class _Lobby extends StatelessWidget {
  const _Lobby(
      {required this.view, required this.client, required this.ips, this.port});
  final GameView view;
  final CoupClient client;
  final List<String> ips;
  final int? port;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final players = view.players;
    final hostId = view.s['hostId'];
    final portSuffix = (port == null || port == kGamePort) ? '' : ':$port';
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (client.isHost) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Invite players', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  const Text(
                      'Players on the same Wi-Fi (or your hotspot) will see '
                      'this room under "Games nearby", or can join with:'),
                  const SizedBox(height: 8),
                  if (ips.isEmpty)
                    const Text('No Wi-Fi address found. Connect to Wi-Fi or '
                        'turn on your hotspot.',
                        style: TextStyle(color: Colors.orangeAccent))
                  else
                    for (final ip in ips)
                      SelectableText('$ip$portSuffix',
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(color: theme.colorScheme.primary)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text('Players (${players.length}/6)', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final p in players)
          ListTile(
            leading: CircleAvatar(
                child: Text((p['name'] as String).substring(0, 1).toUpperCase())),
            title: Text(p['name'] as String),
            trailing: p['id'] == hostId
                ? const Chip(label: Text('Host'))
                : (p['id'] == view.me ? const Chip(label: Text('You')) : null),
          ),
        const SizedBox(height: 20),
        if (client.isHost)
          FilledButton(
            onPressed: players.length >= 2 ? client.startGame : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(players.length >= 2
                  ? 'Start game'
                  : 'Waiting for at least 2 players'),
            ),
          )
        else
          const Center(
            child: Text('Waiting for the host to start…',
                style: TextStyle(color: Colors.white54)),
          ),
      ],
    );
  }
}

// =================================================================== TABLE

class _Table extends StatefulWidget {
  const _Table({required this.view, required this.client});
  final GameView view;
  final CoupClient client;

  @override
  State<_Table> createState() => _TableState();
}

class _TableState extends State<_Table> {
  int? _loseSel;
  final Set<int> _exchangeSel = {};

  GameView get v => widget.view;
  CoupClient get client => widget.client;

  /// Changes whenever a pending choice (card loss / exchange) changes.
  String _choiceKey(GameView view) {
    final me = view.self;
    final revealed = me == null
        ? ''
        : view.cardsOf(me).map((c) => c['revealed'] == true ? 1 : 0).join();
    return '${view.phase}|${view.s['loser']}|$revealed|'
        '${view.you['exchangeOptions']}';
  }

  @override
  void didUpdateWidget(covariant _Table old) {
    super.didUpdateWidget(old);
    if (_choiceKey(old.view) != _choiceKey(v)) {
      _loseSel = null;
      _exchangeSel.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = v.self;
    final opponents = v.players.where((p) => p['id'] != v.me).toList();
    return Column(
      children: [
        // Opponents
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (final p in opponents)
                _OpponentTile(view: v, p: p),
            ],
          ),
        ),
        _StatusBanner(view: v),
        // Log
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF16141A),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ListView.builder(
              reverse: true,
              padding: const EdgeInsets.all(10),
              itemCount: v.log.length,
              itemBuilder: (_, i) {
                final line = v.log[v.log.length - 1 - i];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(line,
                      style: TextStyle(
                          fontSize: 13,
                          color: i == 0 ? Colors.white : Colors.white60)),
                );
              },
            ),
          ),
        ),
        if (me != null) _myArea(me),
      ],
    );
  }

  Widget _myArea(Json me) {
    final cards = v.cardsOf(me);
    final losing = v.phase == Phase.loseCard.name && v.s['loser'] == v.me;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < cards.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: InfluenceCard(
                    role: roleOrNull(cards[i]['role']),
                    revealed: cards[i]['revealed'] == true,
                    width: MediaQuery.of(context).size.height < 720 ? 76 : 96,
                    selected: losing && _loseSel == i,
                    onTap: losing && cards[i]['revealed'] != true
                        ? () => setState(() => _loseSel = i)
                        : null,
                  ),
                ),
              const SizedBox(width: 10),
              _Coins(me['coins'] as int, big: true),
            ],
          ),
          const SizedBox(height: 10),
          _controls(me),
        ],
      ),
    );
  }

  Widget _controls(Json me) {
    final phase = v.phase;
    final you = v.you;

    if (phase == Phase.gameOver.name) {
      final winner = v.name(v.s['winner'] as String?);
      return Column(children: [
        Text(v.s['winner'] == v.me ? 'You win! 👑' : '$winner wins!',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        if (client.isHost)
          Row(children: [
            Expanded(
                child: OutlinedButton(
                    onPressed: client.backToLobby,
                    child: const Text('Back to lobby'))),
            const SizedBox(width: 8),
            Expanded(
                child: FilledButton(
                    onPressed: client.startGame,
                    child: const Text('Play again'))),
          ])
        else
          const Text('Waiting for the host…',
              style: TextStyle(color: Colors.white54)),
      ]);
    }

    if (me['alive'] != true) {
      return const _Hint('You have been eliminated — watching the game.');
    }

    if (phase == Phase.loseCard.name && v.s['loser'] == v.me) {
      return Column(children: [
        const _Hint('Tap the influence you will lose.'),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed:
                _loseSel == null ? null : () => client.loseCard(_loseSel!),
            child: const Text('Lose this influence'),
          ),
        ),
      ]);
    }

    final options = (you['exchangeOptions'] as List? ?? const []).cast<String>();
    if (phase == Phase.exchange.name && options.isNotEmpty) {
      final need = v.hiddenCount(me);
      return Column(children: [
        _Hint('Choose $need card${need == 1 ? '' : 's'} to keep.'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (var i = 0; i < options.length; i++)
            InfluenceCard(
              role: Role.values.byName(options[i]),
              width: 68,
              showAbility: false,
              selected: _exchangeSel.contains(i),
              onTap: () => setState(() {
                if (!_exchangeSel.remove(i) && _exchangeSel.length < need) {
                  _exchangeSel.add(i);
                }
              }),
            ),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _exchangeSel.length == need
                ? () => client.exchange(_exchangeSel.toList())
                : null,
            child: const Text('Keep selected'),
          ),
        ),
      ]);
    }

    if (phase == Phase.action.name && v.myTurn) {
      return _actionGrid(me);
    }

    if (you['mustRespond'] == true) {
      final blockRoles = (you['blockRoles'] as List).cast<String>();
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [
          if (you['canChallenge'] == true)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white),
              onPressed: client.challenge,
              icon: const Icon(Icons.gavel),
              label: const Text('Challenge'),
            ),
          for (final r in blockRoles)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: roleColor(Role.values.byName(r)),
                  foregroundColor: Colors.white),
              onPressed: () => client.block(r),
              icon: const Icon(Icons.block),
              label: Text('Block (${Role.values.byName(r).label})'),
            ),
          OutlinedButton(
              onPressed: client.allow, child: const Text('Allow')),
        ],
      );
    }

    return const _Hint('Waiting for other players…');
  }

  Widget _actionGrid(Json me) {
    final coins = me['coins'] as int;
    final mustCoup = coins >= 10;
    return Column(children: [
      if (mustCoup) const _Hint('You have 10+ coins: you must Coup.'),
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 2.1,
        children: [
          for (final a in ActionType.values)
            _ActionButton(
              action: a,
              enabled: coins >= a.cost && (!mustCoup || a == ActionType.coup),
              onTap: () => _doAction(a),
            ),
        ],
      ),
    ]);
  }

  Future<void> _doAction(ActionType a) async {
    if (!a.needsTarget) {
      client.act(a.name);
      return;
    }
    final targets = v.players
        .where((p) => p['id'] != v.me && p['alive'] == true)
        .toList();
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${a.label}: choose a target',
                style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final p in targets)
              ListTile(
                leading: _Coins(p['coins'] as int),
                title: Text(p['name'] as String),
                subtitle: Text('${v.hiddenCount(p)} influence left'),
                onTap: () => Navigator.pop(ctx, p['id'] as String),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (id != null) client.act(a.name, id);
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton(
      {required this.action, required this.enabled, required this.onTap});
  final ActionType action;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final claim = action.claim;
    final color =
        claim == null ? const Color(0xFF2C2A31) : roleColor(claim);
    return Opacity(
      opacity: enabled ? 1 : 0.35,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  child: Text(action.label,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.white)),
                ),
                FittedBox(
                  child: Text(
                    claim == null
                        ? action.effect
                        : '${claim.label} · ${action.effect}',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OpponentTile extends StatelessWidget {
  const _OpponentTile({required this.view, required this.p});
  final GameView view;
  final Json p;

  @override
  Widget build(BuildContext context) {
    final isTurn = view.s['turn'] == p['id'];
    final alive = p['alive'] == true;
    final waiting = p['waiting'] == true;
    final width = (MediaQuery.of(context).size.width - 16 - 12) / 3;
    return Opacity(
      opacity: alive ? 1 : 0.45,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: const Color(0xFF1C1A21),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isTurn
                ? Theme.of(context).colorScheme.primary
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(children: [
          Row(children: [
            if (p['connected'] != true)
              const Padding(
                padding: EdgeInsets.only(right: 3),
                child: Icon(Icons.wifi_off, size: 13, color: Colors.orange),
              ),
            Expanded(
              child: Text(p['name'] as String,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ]),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                for (final c in view.cardsOf(p))
                  Padding(
                    padding: const EdgeInsets.only(right: 3),
                    child: InfluenceCard(
                      role: roleOrNull(c['role']),
                      revealed: c['revealed'] == true,
                      width: 26,
                      showAbility: false,
                    ),
                  ),
              ]),
              _Coins(p['coins'] as int),
            ],
          ),
          SizedBox(
            height: 14,
            child: waiting
                ? const Text('deciding…',
                    style: TextStyle(fontSize: 10, color: Colors.amber))
                : null,
          ),
        ]),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.view});
  final GameView view;

  String _text() {
    final v = view;
    final a = v.action;
    final actor = v.s['actor'] == v.me ? 'You' : v.name(v.s['actor'] as String?);
    final target =
        v.s['target'] == v.me ? 'you' : v.name(v.s['target'] as String?);
    String claim() => switch (a) {
          ActionType.foreignAid => '$actor want${actor == 'You' ? '' : 's'} Foreign Aid (+2)',
          ActionType.tax => '$actor claim${actor == 'You' ? '' : 's'} Duke: Tax (+3)',
          ActionType.steal => '$actor claim${actor == 'You' ? '' : 's'} Captain: steal from $target',
          ActionType.assassinate => '$actor claim${actor == 'You' ? '' : 's'} Assassin: assassinate $target',
          ActionType.exchange => '$actor claim${actor == 'You' ? '' : 's'} Ambassador: exchange',
          _ => '',
        };
    switch (v.phase) {
      case 'action':
        return v.myTurn ? 'Your turn' : '${v.name(v.s['turn'] as String?)}\'s turn';
      case 'respondAction':
        return claim();
      case 'respondBlock':
        final b = v.s['blocker'] == v.me ? 'You' : v.name(v.s['blocker'] as String?);
        final role = Role.values.byName(v.s['blockRole'] as String).label;
        return '$b block${b == 'You' ? '' : 's'} ${a?.label} with $role';
      case 'loseCard':
        return v.s['loser'] == v.me
            ? 'You must lose an influence'
            : '${v.name(v.s['loser'] as String?)} must lose an influence';
      case 'exchange':
        return '$actor ${actor == 'You' ? 'are' : 'is'} exchanging cards';
      case 'gameOver':
        return 'Game over';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0x1FD4A84B),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(_text(),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
    );
  }
}

class _Coins extends StatelessWidget {
  const _Coins(this.n, {this.big = false});
  final int n;
  final bool big;
  @override
  Widget build(BuildContext context) {
    final size = big ? 44.0 : 24.0;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
            colors: [Color(0xFFF2D27A), Color(0xFFB08530)]),
      ),
      child: Text('$n',
          style: TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: big ? 18 : 12)),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70)),
      );
}
