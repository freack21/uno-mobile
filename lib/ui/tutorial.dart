import 'package:last_card_core/game.dart';
import 'package:last_card_core/i18n.dart';
import 'package:last_card_core/modes.dart';
import 'package:last_card_core/rules.dart';
import 'package:material_ui/material_ui.dart';

import '../online/browser.dart';
import 'game_controller.dart';
import 'game_screen.dart';
import 'theme.dart';

const _doneKey = 'lastcard.tutorial';

/// Whether the guided first game was offered already.
bool get tutorialSeen => readStored(_doneKey) != null;

/// A short Classic game against one easy bot, five cards each, with a tip
/// for whatever is happening on the table.
Future<void> playTutorial(BuildContext context) async {
  writeStored(_doneKey, '1');
  final mode = gameModes.first;
  final c = GameController(
    mode: mode,
    rules: const RuleSet(handSize: 5),
    playerCount: 2,
    difficulty: Difficulty.easy,
  );
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => GameScreen(mode: mode, controller: c, coach: coachFor),
    ),
  );
  c.dispose();
}

/// Offers the tutorial once, on the first visit to the home screen.
Future<void> offerTutorial(BuildContext context) async {
  if (tutorialSeen) return;
  writeStored(_doneKey, '1');
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(t('New to Last Card?'), style: font(20, weight: 650)),
      content: Text(
        t('Play a short guided game: tips show you what to do at every step.'),
        style: font(15, color: Palette.muted),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(t('Skip')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(t('Show me')),
        ),
      ],
    ),
  );
  if (yes == true && context.mounted) await playTutorial(context);
}

/// The tip for the table right now.
String? coachFor(GameController c) {
  final g = c.game;
  const me = GameController.human;
  if (c.inIntro) {
    return t('The dealer shuffles and deals 5 cards each. Tap to skip.');
  }
  if (g.isRoundOver) return null;
  final forgot = g.vulnerable;
  if (forgot != null && forgot != me) {
    return t(
      '{a} has one card and forgot to call LAST CARD! Tap LAST CARD now: they draw 2.',
      {'a': g.players[forgot].name},
    );
  }
  if (!c.isMyTurn) {
    return t('The bot is playing. Watch how the top card changes.');
  }
  final hand = g.players[me].hand;
  if (g.pendingDraw > 0) {
    return t('A draw card hit you. Tap the deck to take the cards.');
  }
  if (g.phase == Phase.afterDraw) {
    return t('You drew a card. Play it if it fits, or tap Keep.');
  }
  final playable = g.playableCards(me);
  if (playable.isEmpty) {
    return t('Nothing matches the top card. Tap the deck to draw one.');
  }
  if (hand.length == 2 && !g.players[me].calledLast) {
    return t(
      'Two cards left! Tap LAST CARD before you play, or you can be caught.',
    );
  }
  if (hand.length == 1) return t('Your last card! Play it to win.');
  if (playable.every((card) => g.face(card).isWild)) {
    return t('A Wild fits anything. Play it and pick the next color.');
  }
  return t(
    'Your turn: play a card with the same color or number as the top card. Glowing cards can be played.',
  );
}
