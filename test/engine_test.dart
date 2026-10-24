import 'dart:math';

import 'package:coup_lan/game/engine.dart';
import 'package:coup_lan/game/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// 3-player game where it's A's turn and hands are set explicitly.
CoupGame setup(List<Role> a, List<Role> b, List<Role> c) {
  final g = CoupGame(random: Random(1));
  g.addPlayer('a', 'Ann');
  g.addPlayer('b', 'Bob');
  g.addPlayer('c', 'Cat');
  g.start();
  for (final (id, roles) in [('a', a), ('b', b), ('c', c)]) {
    final p = g.player(id);
    p.cards = roles.map((r) => Influence(r)).toList();
    p.coins = 2;
  }
  // Rotate until it's A's turn.
  while (g.current.id != 'a') {
    g.declareAction(g.current.id, ActionType.income, null);
    g.player('b').coins = 2;
    g.player('c').coins = 2;
  }
  return g;
}

void main() {
  test('income ends the turn', () {
    final g = setup([Role.duke, Role.duke], [Role.captain, Role.captain],
        [Role.contessa, Role.contessa]);
    g.declareAction('a', ActionType.income, null);
    expect(g.player('a').coins, 3);
    expect(g.current.id, 'b');
    expect(g.phase, Phase.action);
  });

  test('unchallenged tax gives 3 coins', () {
    final g = setup([Role.captain, Role.captain], [Role.captain, Role.captain],
        [Role.contessa, Role.contessa]);
    g.declareAction('a', ActionType.tax, null);
    expect(g.phase, Phase.respondAction);
    g.pass('b');
    g.pass('c');
    expect(g.player('a').coins, 5);
    expect(g.current.id, 'b');
  });

  test('bluff caught: actor loses influence, no coins', () {
    final g = setup([Role.captain, Role.contessa], [Role.captain, Role.captain],
        [Role.contessa, Role.contessa]);
    g.declareAction('a', ActionType.tax, null);
    g.challenge('b');
    expect(g.phase, Phase.loseCard);
    expect(g.loserId, 'a');
    g.chooseLoss('a', 0);
    expect(g.player('a').coins, 2);
    expect(g.player('a').hiddenCount, 1);
    expect(g.current.id, 'b');
  });

  test('true claim: challenger loses, action resolves', () {
    final g = setup([Role.duke, Role.contessa], [Role.captain, Role.captain],
        [Role.contessa, Role.contessa]);
    g.declareAction('a', ActionType.tax, null);
    g.challenge('c');
    g.chooseLoss('c', 1);
    expect(g.player('a').coins, 5);
    expect(g.player('c').hiddenCount, 1);
    expect(g.player('a').hiddenCount, 2); // duke replaced, not lost
  });

  test('steal blocked by ambassador', () {
    final g = setup([Role.captain, Role.duke], [Role.ambassador, Role.duke],
        [Role.contessa, Role.contessa]);
    g.declareAction('a', ActionType.steal, 'b');
    expect(g.canBlockAction(g.player('c')), isFalse);
    g.block('b', Role.ambassador);
    expect(g.phase, Phase.respondBlock);
    g.pass('a');
    g.pass('c');
    expect(g.player('a').coins, 2);
    expect(g.player('b').coins, 2);
    expect(g.current.id, 'b');
  });

  test('failed challenge then contessa bluff = double loss', () {
    final g = setup([Role.assassin, Role.duke], [Role.duke, Role.captain],
        [Role.duke, Role.duke]);
    g.player('a').coins = 3;
    g.declareAction('a', ActionType.assassinate, 'b');
    expect(g.player('a').coins, 0);
    g.challenge('b'); // A really has the assassin
    g.chooseLoss('b', 0); // B loses Duke, keeps Captain
    // B may still block after the failed challenge.
    expect(g.phase, Phase.respondAction);
    g.block('b', Role.contessa);
    g.challenge('a'); // B was bluffing
    expect(g.player('b').alive, isFalse);
    expect(g.current.id, 'c');
  });

  test('exchange keeps the same number of cards', () {
    final g = setup([Role.ambassador, Role.duke], [Role.captain, Role.captain],
        [Role.contessa, Role.contessa]);
    final deckBefore = g.deck.length;
    g.declareAction('a', ActionType.exchange, null);
    g.pass('b');
    g.pass('c');
    expect(g.phase, Phase.exchange);
    expect(g.exchangeOptions.length, 4);
    expect(() => g.chooseExchange('a', [0]), throwsA(isA<GameException>()));
    g.chooseExchange('a', [2, 3]);
    expect(g.player('a').hiddenCount, 2);
    expect(g.deck.length, deckBefore);
  });

  test('must coup with 10 coins and game ends with one survivor', () {
    final g = setup([Role.duke, Role.duke], [Role.captain],
        [Role.contessa]);
    g.player('b').cards = [Influence(Role.captain)];
    g.player('c').cards = [Influence(Role.contessa, revealed: true)];
    g.player('a').coins = 10;
    expect(() => g.declareAction('a', ActionType.income, null),
        throwsA(isA<GameException>()));
    g.declareAction('a', ActionType.coup, 'b');
    expect(g.phase, Phase.gameOver);
    expect(g.winnerId, 'a');
  });

  test('views hide other players\' cards', () {
    final g = setup([Role.duke, Role.duke], [Role.captain, Role.captain],
        [Role.contessa, Role.contessa]);
    final view = g.viewFor('a');
    final players = (view['players'] as List).cast<Map<String, dynamic>>();
    final bob = players.firstWhere((p) => p['id'] == 'b');
    final ann = players.firstWhere((p) => p['id'] == 'a');
    expect((bob['cards'] as List).every((c) => c['role'] == null), isTrue);
    expect((ann['cards'] as List).every((c) => c['role'] == 'duke'), isTrue);
  });
}
