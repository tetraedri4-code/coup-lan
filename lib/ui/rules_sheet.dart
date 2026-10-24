import 'package:flutter/material.dart';

import '../game/models.dart';
import 'cards.dart';

void showRules(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          Text('How to play', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          const Text(
            'Each player starts with 2 coins and 2 face-down influence cards. '
            'Lose both and you\'re out. The last player with influence wins.\n\n'
            'On your turn take one action. You may claim any character — '
            'even one you don\'t hold. Anyone can challenge a claim: if the '
            'claim was a bluff, the bluffer loses an influence; if it was true, '
            'the challenger loses one and the claimer swaps the revealed card '
            'for a new one.',
          ),
          const SizedBox(height: 16),
          Text('General actions',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text('• Income: take 1 coin. Cannot be blocked.\n'
              '• Foreign Aid: take 2 coins. Blocked by Duke.\n'
              '• Coup: pay 7, target loses an influence. Cannot be stopped. '
              'Mandatory with 10+ coins.'),
          const SizedBox(height: 16),
          Text('Characters', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final r in Role.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                InfluenceCard(role: r, width: 52, showAbility: false),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.label,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(r.ability.replaceAll('\n', ' ')),
                    ],
                  ),
                ),
              ]),
            ),
          const SizedBox(height: 8),
          const Text(
            'Assassination costs 3 coins, which are spent even if it is blocked '
            '(but refunded if the Assassin claim is successfully challenged). '
            'Exchange: draw 2 cards, then keep as many as you have influence.',
            style: TextStyle(color: Colors.white70),
          ),
        ],
      ),
    ),
  );
}
