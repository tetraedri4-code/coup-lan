import 'dart:math';

import 'models.dart';

class Influence {
  Role role;
  bool revealed;
  Influence(this.role, {this.revealed = false});
}

class Player {
  final String id;
  String name;
  int coins = 2;
  List<Influence> cards = [];
  bool connected = true;

  Player(this.id, this.name);

  bool get alive => cards.any((c) => !c.revealed);
  int get hiddenCount => cards.where((c) => !c.revealed).length;
  bool hasRole(Role r) => cards.any((c) => !c.revealed && c.role == r);
}

/// What happens once a pending influence loss has been resolved.
enum _After { endTurn, actionChallengeWon, resolveAction }

/// Authoritative Coup game state. Runs only on the host device; every
/// client receives a personalised view through [viewFor].
class CoupGame {
  CoupGame({Random? random}) : _rng = random ?? Random.secure();

  static const minPlayers = 2;
  static const maxPlayers = 6;

  final Random _rng;
  final List<Player> players = [];
  List<Role> deck = [];
  Phase phase = Phase.lobby;
  int _turn = 0;

  // Pending action
  ActionType? action;
  String? actorId;
  String? targetId;
  bool actionChallengeDone = false;

  // Pending block
  String? blockerId;
  Role? blockRole;

  /// Players who chose "allow" in the current response window.
  final Set<String> passed = {};

  // Pending influence loss
  String? loserId;
  _After _after = _After.endTurn;

  // Exchange
  List<Role> exchangeOptions = [];

  String? winnerId;
  final List<String> log = [];

  // ---------------------------------------------------------------- helpers

  Player player(String id) => players.firstWhere((p) => p.id == id,
      orElse: () => throw GameException('Unknown player.'));

  Player? tryPlayer(String? id) {
    if (id == null) return null;
    for (final p in players) {
      if (p.id == id) return p;
    }
    return null;
  }

  Player get current => players[_turn];
  List<Player> get alivePlayers => players.where((p) => p.alive).toList();

  void _log(String s) {
    log.add(s);
    if (log.length > 200) log.removeAt(0);
  }

  // ---------------------------------------------------------------- lobby

  void addPlayer(String id, String name) {
    if (phase != Phase.lobby) throw GameException('Game already started.');
    if (players.length >= maxPlayers) throw GameException('Room is full.');
    players.add(Player(id, name));
  }

  void removePlayer(String id) {
    if (phase != Phase.lobby) return;
    players.removeWhere((p) => p.id == id);
  }

  void start() {
    if (phase != Phase.lobby && phase != Phase.gameOver) {
      throw GameException('Game already running.');
    }
    players.removeWhere((p) => !p.connected);
    if (players.length < minPlayers) {
      throw GameException('Need at least $minPlayers players.');
    }
    deck = [
      for (final r in Role.values) ...[r, r, r],
    ]..shuffle(_rng);
    for (final p in players) {
      p.coins = 2;
      p.cards = [Influence(_draw()), Influence(_draw())];
    }
    _turn = _rng.nextInt(players.length);
    // Official 2-player variant: starting player begins with 1 coin.
    if (players.length == 2) current.coins = 1;
    winnerId = null;
    log.clear();
    _clearTurn();
    phase = Phase.action;
    _log('Game started. ${current.name} goes first.');
  }

  void backToLobby() {
    phase = Phase.lobby;
    players.removeWhere((p) => !p.connected);
    for (final p in players) {
      p.cards = [];
      p.coins = 2;
    }
    _clearTurn();
    winnerId = null;
  }

  Role _draw() => deck.removeLast();

  void _clearTurn() {
    action = null;
    actorId = null;
    targetId = null;
    actionChallengeDone = false;
    blockerId = null;
    blockRole = null;
    passed.clear();
    loserId = null;
    exchangeOptions = [];
  }

  // ---------------------------------------------------------------- eligibility

  bool canChallengeAction(Player q) =>
      phase == Phase.respondAction &&
      q.alive &&
      q.id != actorId &&
      action!.claim != null &&
      !actionChallengeDone;

  bool canBlockAction(Player q) =>
      phase == Phase.respondAction &&
      q.alive &&
      q.id != actorId &&
      action!.blockers.isNotEmpty &&
      (!action!.onlyTargetBlocks || q.id == targetId);

  bool canChallengeBlock(Player q) =>
      phase == Phase.respondBlock && q.alive && q.id != blockerId;

  bool mustRespond(Player q) =>
      !passed.contains(q.id) &&
      (canChallengeAction(q) || canBlockAction(q) || canChallengeBlock(q));

  // ---------------------------------------------------------------- actions

  void declareAction(String pid, ActionType a, String? target) {
    if (phase != Phase.action) throw GameException('Not the time to act.');
    final me = current;
    if (me.id != pid) throw GameException('It is not your turn.');
    if (me.coins >= 10 && a != ActionType.coup) {
      throw GameException('With 10 or more coins you must Coup.');
    }
    if (me.coins < a.cost) {
      throw GameException('${a.label} costs ${a.cost} coins.');
    }
    Player? t;
    if (a.needsTarget) {
      t = tryPlayer(target);
      if (t == null || !t.alive || t.id == pid) {
        throw GameException('Choose a valid target.');
      }
    }

    _clearTurn();
    action = a;
    actorId = pid;
    targetId = t?.id;
    me.coins -= a.cost;

    switch (a) {
      case ActionType.income:
        me.coins += 1;
        _log('${me.name} takes Income (+1).');
        _endTurn();
        return;
      case ActionType.coup:
        _log('${me.name} launches a Coup against ${t!.name}.');
        _loseInfluence(t.id, _After.endTurn);
        return;
      case ActionType.foreignAid:
        _log('${me.name} attempts Foreign Aid.');
      case ActionType.tax:
        _log('${me.name} claims Duke to collect Tax.');
      case ActionType.assassinate:
        _log('${me.name} claims Assassin and pays 3 to assassinate ${t!.name}.');
      case ActionType.steal:
        _log('${me.name} claims Captain to steal from ${t!.name}.');
      case ActionType.exchange:
        _log('${me.name} claims Ambassador to exchange cards.');
    }
    phase = Phase.respondAction;
    _checkResponses();
  }

  void challenge(String pid) {
    final me = player(pid);
    if (canChallengeAction(me) && !passed.contains(pid)) {
      final actor = player(actorId!);
      final role = action!.claim!;
      _log('${me.name} challenges ${actor.name}\'s ${role.label}.');
      if (actor.hasRole(role)) {
        _revealAndReplace(actor, role);
        actionChallengeDone = true;
        _log('${me.name} loses the challenge.');
        _loseInfluence(me.id, _After.actionChallengeWon);
      } else {
        _log('${actor.name} was bluffing!');
        if (action == ActionType.assassinate) actor.coins += action!.cost;
        _loseInfluence(actor.id, _After.endTurn);
      }
      return;
    }
    if (canChallengeBlock(me) && !passed.contains(pid)) {
      final blocker = player(blockerId!);
      final role = blockRole!;
      _log('${me.name} challenges ${blocker.name}\'s ${role.label}.');
      if (blocker.hasRole(role)) {
        _revealAndReplace(blocker, role);
        _log('${me.name} loses the challenge. The block stands.');
        _loseInfluence(me.id, _After.endTurn);
      } else {
        _log('${blocker.name} was bluffing! The block fails.');
        _loseInfluence(blocker.id, _After.resolveAction);
      }
      return;
    }
    throw GameException('You cannot challenge now.');
  }

  void block(String pid, Role role) {
    final me = player(pid);
    if (!canBlockAction(me) || passed.contains(pid)) {
      throw GameException('You cannot block now.');
    }
    if (!action!.blockers.contains(role)) {
      throw GameException('${role.label} cannot block ${action!.label}.');
    }
    blockerId = pid;
    blockRole = role;
    passed.clear();
    phase = Phase.respondBlock;
    _log('${me.name} claims ${role.label} to block ${action!.label}.');
    _checkResponses();
  }

  void pass(String pid) {
    final me = player(pid);
    if (!mustRespond(me)) throw GameException('Nothing to respond to.');
    passed.add(pid);
    _checkResponses();
  }

  /// Called when a player's connection changes so a disconnected player
  /// doesn't freeze the game in a response window or card loss.
  void onConnectionChanged() {
    if (phase == Phase.loseCard) {
      final l = tryPlayer(loserId);
      if (l != null && !l.connected) {
        final i = l.cards.indexWhere((c) => !c.revealed);
        if (i >= 0) chooseLoss(l.id, i);
        return;
      }
    }
    if (phase == Phase.respondAction || phase == Phase.respondBlock) {
      _checkResponses();
    }
  }

  void _checkResponses() {
    final waiting = players.any((q) => q.connected && mustRespond(q));
    if (waiting) return;
    if (phase == Phase.respondAction) {
      _resolveAction();
    } else if (phase == Phase.respondBlock) {
      _log('${action!.label} is blocked.');
      _endTurn();
    }
  }

  void _revealAndReplace(Player p, Role role) {
    final card = p.cards.firstWhere((c) => !c.revealed && c.role == role);
    deck.add(role);
    deck.shuffle(_rng);
    card.role = _draw();
    _log('${p.name} reveals ${role.label}, shuffles it in and draws a new card.');
  }

  void _resolveAction() {
    final actor = player(actorId!);
    if (!actor.alive) {
      _endTurn();
      return;
    }
    final target = tryPlayer(targetId);
    switch (action!) {
      case ActionType.foreignAid:
        actor.coins += 2;
        _log('${actor.name} takes 2 coins of Foreign Aid.');
      case ActionType.tax:
        actor.coins += 3;
        _log('${actor.name} collects 3 coins of Tax.');
      case ActionType.steal:
        final n = min(2, target!.coins);
        target.coins -= n;
        actor.coins += n;
        _log('${actor.name} steals $n from ${target.name}.');
      case ActionType.assassinate:
        if (target != null && target.alive) {
          _log('${target.name} is assassinated.');
          _loseInfluence(target.id, _After.endTurn);
          return;
        }
      case ActionType.exchange:
        final drawn = [_draw(), _draw()];
        exchangeOptions = [
          ...actor.cards.where((c) => !c.revealed).map((c) => c.role),
          ...drawn,
        ];
        phase = Phase.exchange;
        return;
      case ActionType.income:
      case ActionType.coup:
        break;
    }
    _endTurn();
  }

  void chooseExchange(String pid, List<int> keep) {
    if (phase != Phase.exchange || pid != actorId) {
      throw GameException('You are not exchanging.');
    }
    final me = player(pid);
    final need = me.hiddenCount;
    final unique = keep.toSet();
    if (unique.length != need ||
        unique.any((i) => i < 0 || i >= exchangeOptions.length)) {
      throw GameException('Pick exactly $need card${need == 1 ? '' : 's'}.');
    }
    final kept = [for (final i in unique) exchangeOptions[i]];
    final returned = [
      for (var i = 0; i < exchangeOptions.length; i++)
        if (!unique.contains(i)) exchangeOptions[i],
    ];
    me.cards = [
      ...me.cards.where((c) => c.revealed),
      ...kept.map((r) => Influence(r)),
    ];
    deck.addAll(returned);
    deck.shuffle(_rng);
    exchangeOptions = [];
    _log('${me.name} exchanges cards with the Court deck.');
    _endTurn();
  }

  // ---------------------------------------------------------------- influence

  void _loseInfluence(String pid, _After after) {
    final p = player(pid);
    if (!p.alive) {
      _continue(after);
      return;
    }
    if (p.hiddenCount == 1) {
      final card = p.cards.firstWhere((c) => !c.revealed);
      _reveal(p, card);
      _continue(after);
      return;
    }
    phase = Phase.loseCard;
    loserId = pid;
    _after = after;
    if (!p.connected) onConnectionChanged();
  }

  void chooseLoss(String pid, int index) {
    if (phase != Phase.loseCard || pid != loserId) {
      throw GameException('You don\'t need to lose a card.');
    }
    final p = player(pid);
    if (index < 0 || index >= p.cards.length || p.cards[index].revealed) {
      throw GameException('Pick one of your hidden cards.');
    }
    _reveal(p, p.cards[index]);
    loserId = null;
    _continue(_after);
  }

  void _reveal(Player p, Influence card) {
    card.revealed = true;
    _log('${p.name} loses a ${card.role.label}.');
    if (!p.alive) _log('${p.name} is out of the game.');
  }

  void _continue(_After after) {
    if (alivePlayers.length <= 1) {
      _finish();
      return;
    }
    switch (after) {
      case _After.endTurn:
        _endTurn();
      case _After.resolveAction:
        phase = Phase.respondAction; // so _resolveAction sees a consistent state
        _resolveAction();
      case _After.actionChallengeWon:
        // The action stands; blocks are still possible.
        phase = Phase.respondAction;
        passed.clear();
        _checkResponses();
    }
  }

  void _endTurn() {
    if (alivePlayers.length <= 1) {
      _finish();
      return;
    }
    _clearTurn();
    do {
      _turn = (_turn + 1) % players.length;
    } while (!players[_turn].alive);
    phase = Phase.action;
  }

  void _finish() {
    _clearTurn();
    final alive = alivePlayers;
    winnerId = alive.isEmpty ? null : alive.first.id;
    phase = Phase.gameOver;
    if (alive.isNotEmpty) _log('${alive.first.name} wins the game!');
  }

  // ---------------------------------------------------------------- views

  /// State as seen by [viewerId]: hidden cards of others are masked.
  Map<String, dynamic> viewFor(String viewerId) {
    final me = tryPlayer(viewerId);
    final inGame = phase != Phase.lobby;
    return {
      'phase': phase.name,
      'turn': inGame && phase != Phase.gameOver ? current.id : null,
      'action': action?.name,
      'actor': actorId,
      'target': targetId,
      'blocker': blockerId,
      'blockRole': blockRole?.name,
      'loser': loserId,
      'winner': winnerId,
      'deck': deck.length,
      'passed': passed.toList(),
      'log': log.length > 60 ? log.sublist(log.length - 60) : log,
      'players': [
        for (final p in players)
          {
            'id': p.id,
            'name': p.name,
            'coins': p.coins,
            'connected': p.connected,
            'alive': p.alive,
            'waiting': inGame && p.connected && mustRespond(p),
            'cards': [
              for (final c in p.cards)
                {
                  'role': (c.revealed || p.id == viewerId) ? c.role.name : null,
                  'revealed': c.revealed,
                }
            ],
          }
      ],
      'you': me == null
          ? null
          : {
              'canChallenge': !passed.contains(me.id) &&
                  (canChallengeAction(me) || canChallengeBlock(me)),
              'blockRoles': canBlockAction(me) && !passed.contains(me.id)
                  ? action!.blockers.map((r) => r.name).toList()
                  : <String>[],
              'mustRespond': mustRespond(me),
              'exchangeOptions': phase == Phase.exchange && me.id == actorId
                  ? exchangeOptions.map((r) => r.name).toList()
                  : <String>[],
            },
    };
  }
}
