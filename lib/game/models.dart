/// Core definitions for the Coup card game.
library;

enum Role { duke, assassin, captain, ambassador, contessa }

extension RoleInfo on Role {
  String get label => switch (this) {
        Role.duke => 'Duke',
        Role.assassin => 'Assassin',
        Role.captain => 'Captain',
        Role.ambassador => 'Ambassador',
        Role.contessa => 'Contessa',
      };

  String get ability => switch (this) {
        Role.duke => 'Tax: take 3 coins.\nBlocks Foreign Aid.',
        Role.assassin => 'Pay 3 coins to assassinate.',
        Role.captain => 'Steal 2 coins.\nBlocks stealing.',
        Role.ambassador => 'Exchange cards with the deck.\nBlocks stealing.',
        Role.contessa => 'Blocks assassination.',
      };
}

enum ActionType { income, foreignAid, coup, tax, assassinate, steal, exchange }

extension ActionInfo on ActionType {
  String get label => switch (this) {
        ActionType.income => 'Income',
        ActionType.foreignAid => 'Foreign Aid',
        ActionType.coup => 'Coup',
        ActionType.tax => 'Tax',
        ActionType.assassinate => 'Assassinate',
        ActionType.steal => 'Steal',
        ActionType.exchange => 'Exchange',
      };

  String get effect => switch (this) {
        ActionType.income => '+1 coin',
        ActionType.foreignAid => '+2 coins',
        ActionType.coup => 'Pay 7',
        ActionType.tax => '+3 coins',
        ActionType.assassinate => 'Pay 3',
        ActionType.steal => 'Take 2',
        ActionType.exchange => 'Swap cards',
      };

  int get cost => switch (this) {
        ActionType.coup => 7,
        ActionType.assassinate => 3,
        _ => 0,
      };

  /// The character a player claims by taking this action (null = general action).
  Role? get claim => switch (this) {
        ActionType.tax => Role.duke,
        ActionType.assassinate => Role.assassin,
        ActionType.steal => Role.captain,
        ActionType.exchange => Role.ambassador,
        _ => null,
      };

  bool get needsTarget =>
      this == ActionType.coup ||
      this == ActionType.assassinate ||
      this == ActionType.steal;

  /// Characters that can block this action.
  List<Role> get blockers => switch (this) {
        ActionType.foreignAid => const [Role.duke],
        ActionType.assassinate => const [Role.contessa],
        ActionType.steal => const [Role.captain, Role.ambassador],
        _ => const [],
      };

  /// True when only the targeted player may block (otherwise anyone may).
  bool get onlyTargetBlocks =>
      this == ActionType.assassinate || this == ActionType.steal;
}

enum Phase {
  lobby,
  action, // current player chooses an action
  respondAction, // others may challenge / block the action
  respondBlock, // others may challenge the block
  loseCard, // a player must choose an influence to lose
  exchange, // ambassador player picks cards to keep
  gameOver,
}

class GameException implements Exception {
  final String message;
  GameException(this.message);
  @override
  String toString() => message;
}
