import 'cards.dart';
import 'rules.dart';

class GuideSection {
  const GuideSection(this.title, this.points, {this.cards = const []});

  final String title;
  final List<String> points;

  /// Example cards rendered next to the section.
  final List<CardFace> cards;
}

class GameMode {
  const GameMode({
    required this.id,
    required this.name,
    required this.tagline,
    required this.accent,
    required this.rules,
    required this.guide,
    this.minPlayers = 2,
    this.maxPlayers = 6,
    this.defaultPlayers = 4,
    this.tag,
  });

  final String id;
  final String name;
  final String tagline;
  final CardColor accent;
  final RuleSet rules;
  final List<GuideSection> guide;
  final int minPlayers;
  final int maxPlayers;
  final int defaultPlayers;

  /// Small label such as "MVP" or "Hard".
  final String? tag;

  bool get isCustom => id == 'custom';
}

const _red = CardColor.red;
const _yellow = CardColor.yellow;
const _green = CardColor.green;
const _blue = CardColor.blue;
const _wild = CardColor.wild;

/// Shared rules every mode builds on.
const basicsGuide = <GuideSection>[
  GuideSection('Goal', [
    'Be the first player to get rid of every card in your hand.',
    'Each player starts with 7 cards. One card is turned face up to start the discard pile — it is always a number card.',
  ]),
  GuideSection(
    'Matching',
    [
      'On your turn play one card that matches the top card by color, number or symbol.',
      'A Wild card can be played on anything. You choose the next color.',
      'Playable cards in your hand are lifted; the others are dimmed.',
    ],
    cards: [
      CardFace(_blue, CardKind.number, value: 7),
      CardFace(_blue, CardKind.number, value: 2),
      CardFace(_yellow, CardKind.number, value: 7),
    ],
  ),
  GuideSection('Can\'t play?', [
    'Tap the draw pile to draw a card.',
    'If the drawn card fits you may play it straight away, or tap Keep to end your turn.',
  ]),
  GuideSection(
    'Action cards',
    [
      'Skip — the next player loses their turn.',
      'Reverse — the direction of play changes. With two players it works like Skip.',
      '+2 — the next player draws 2 cards and loses their turn.',
      'Wild — choose the next color.',
      'Wild +4 — choose the next color; the next player draws 4 and loses their turn.',
    ],
    cards: [
      CardFace(_red, CardKind.skip),
      CardFace(_green, CardKind.reverse),
      CardFace(_yellow, CardKind.draw, draw: 2),
      CardFace(_wild, CardKind.wild),
      CardFace(_wild, CardKind.wildDraw, draw: 4),
    ],
  ),
  GuideSection('Last card!', [
    'When you are about to play your second-to-last card, tap LAST CARD (you can also tap it right after).',
    'If you forget and another player catches you before the next move, you draw 2.',
    'Bots forget sometimes too — tap CATCH on their seat to make them draw 2.',
  ]),
  GuideSection('Card points', [
    'Number cards: face value.',
    'Skip, Reverse, +2 and other colored actions: 20.',
    'Wild cards: 50 (Wild Draw Color: 60).',
    'Points matter in Point Race and break ties in Elimination.',
  ]),
];

const gameModes = <GameMode>[
  GameMode(
    id: 'classic',
    name: 'Classic',
    tagline: 'The original. Match, attack, empty your hand.',
    accent: _red,
    tag: 'Start here',
    rules: RuleSet(),
    guide: [
      GuideSection('How it works', [
        'Standard 108-card deck: numbers 0–9, Skip, Reverse, +2 in four colors, plus Wild and Wild +4.',
        'One round. The first player to empty their hand wins.',
        'Draw one card when you cannot play. Wild +4 may be played at any time.',
        'Penalty cards cannot be stacked: the victim simply draws.',
      ]),
      GuideSection('Tips', [
        'Save Wild cards for when you are stuck.',
        'Hit the next player with Skip or +2 when they are down to one or two cards.',
        'Change to the color you hold the most of.',
      ]),
    ],
  ),
  GameMode(
    id: 'points',
    name: 'Point Race',
    tagline: 'Win rounds, bank the leftovers. First to 500.',
    accent: _yellow,
    rules: RuleSet(format: MatchFormat.points),
    guide: [
      GuideSection('How it works', [
        'Classic rules, played over several rounds.',
        'The round winner scores the points of every card left in the other hands.',
        'The first player to reach the target score (500 by default) wins the match.',
      ]),
      GuideSection(
        'Scoring',
        [
          'Number cards: face value (a 9 is worth 9).',
          'Skip, Reverse, +2: 20 points each.',
          'Wild and Wild +4: 50 points each.',
        ],
        cards: [
          CardFace(_green, CardKind.number, value: 9),
          CardFace(_red, CardKind.draw, draw: 2),
          CardFace(_wild, CardKind.wildDraw, draw: 4),
        ],
      ),
      GuideSection('Tips', [
        'Dump high cards early — getting stuck with a Wild costs 50 if someone else goes out.',
        'A short game is worth fewer points: if you are far behind, slow the leader down.',
      ]),
    ],
  ),
  GameMode(
    id: 'stacking',
    name: 'Stacking',
    tagline: 'Pass the pain along. +2 on +2, +4 on +4.',
    accent: _blue,
    rules: RuleSet(stack: StackRule.same),
    guide: [
      GuideSection(
        'How it works',
        [
          'When a +2 is played on you, answer with any +2 to pass the penalty on, adding 2.',
          'A Wild +4 can be answered with another Wild +4.',
          'You cannot mix them: no +4 on +2 and no +2 on +4.',
          'The first player who cannot (or will not) stack draws the whole total and loses their turn.',
        ],
        cards: [
          CardFace(_red, CardKind.draw, draw: 2),
          CardFace(_blue, CardKind.draw, draw: 2),
          CardFace(_wild, CardKind.wildDraw, draw: 4),
          CardFace(_wild, CardKind.wildDraw, draw: 4),
        ],
      ),
      GuideSection('Controls', [
        'While a stack is aimed at you only matching draw cards are lifted.',
        'Tap the draw pile (it shows "Take +N") to accept the penalty.',
      ]),
      GuideSection('Tips', [
        'Hold a +2 as a shield instead of throwing it away early.',
        'A long stack is a big swing — be ready when the player before you is low on cards.',
      ]),
    ],
  ),
  GameMode(
    id: 'seven_o',
    name: 'Seven-O',
    tagline: '7 swaps hands. 0 passes them all around.',
    accent: _green,
    rules: RuleSet(sevenZero: true),
    guide: [
      GuideSection(
        'How it works',
        [
          'Play a 7 and choose any player: you swap your whole hand with theirs.',
          'Play a 0 and every hand moves one seat in the direction of play.',
          'If the 7 or 0 is your last card you simply win — no swap.',
        ],
        cards: [
          CardFace(_green, CardKind.number, value: 7),
          CardFace(_red, CardKind.number, value: 0),
        ],
      ),
      GuideSection('Good to know', [
        'After a swap or rotation anyone left with a single card counts as having called Last Card.',
        'Swaps are mandatory: a 7 always takes a target.',
      ]),
      GuideSection('Tips', [
        'Save a 7 for when someone else is close to winning, then take their hand.',
        'Watch the direction before playing a 0 — your hand goes to the next player.',
      ]),
    ],
  ),
  GameMode(
    id: 'jump_in',
    name: 'Jump-In',
    tagline: 'Same card? Slam it down, even out of turn.',
    accent: _red,
    rules: RuleSet(jumpIn: true),
    guide: [
      GuideSection(
        'How it works',
        [
          'If you hold the exact same card as the top card — same color and same number or symbol — you may play it at any time, even when it is not your turn.',
          'Play continues from you, as if it had been your turn.',
          'Wild cards can never be jumped in.',
          'No jumping while a penalty is waiting to be taken.',
        ],
        cards: [
          CardFace(_blue, CardKind.number, value: 5),
          CardFace(_blue, CardKind.number, value: 5),
        ],
      ),
      GuideSection('Controls', [
        'Matching cards glow with a JUMP badge — tap one fast before the bots do.',
        'Bots react too: the harder the bot, the quicker the hands.',
      ]),
      GuideSection('Tips', [
        'Jumping in skips everyone between the previous player and you.',
        'Jumping in with a Skip or +2 can turn the attack around.',
      ]),
    ],
  ),
  GameMode(
    id: 'doubles',
    name: 'Doubles',
    tagline: 'Got two 6s? Throw them both in one go.',
    accent: _yellow,
    rules: RuleSet(combos: true),
    guide: [
      GuideSection(
        'How it works',
        [
          'Play your first card as usual: it must match the color or the symbol.',
          'Then add any other cards with the same number or symbol from your hand, in any color, in the same turn.',
          'The last card you put down sets the next color, so pick the order wisely.',
          'Wild cards combo with the same kind of Wild; Flip cards never combo.',
        ],
        cards: [
          CardFace(_yellow, CardKind.number, value: 6),
          CardFace(_red, CardKind.number, value: 6),
          CardFace(_blue, CardKind.number, value: 6),
        ],
      ),
      GuideSection(
        'Action combos add up',
        [
          'Two Skips skip the next two players.',
          'Two +2s make the next player draw 4 (or answer with a stack if Stacking is on).',
          'Two Reverses cancel out: play keeps its direction.',
          'Seven-O (Custom): 7s swap hands once and 0s pass hands once, however many you play.',
        ],
        cards: [
          CardFace(_green, CardKind.skip),
          CardFace(_blue, CardKind.skip),
          CardFace(_red, CardKind.draw, draw: 2),
          CardFace(_yellow, CardKind.draw, draw: 2),
        ],
      ),
      GuideSection('Controls', [
        'Tap your first card: matching cards light up with a badge.',
        'Tap them in the order you want to play them, then tap Play.',
        'Tap the first card again (or Cancel) to back out.',
        'You can call Last Card early when a combo would leave you with one card.',
      ]),
      GuideSection('Tips', [
        'Combos empty your hand fast — keep pairs instead of splitting them.',
        'End on the color you hold the most of.',
      ]),
    ],
  ),
  GameMode(
    id: 'draw_until',
    name: 'Draw Until Playable',
    tagline: 'No easy outs. Keep drawing until something fits.',
    accent: _yellow,
    rules: RuleSet(drawUntilPlayable: true),
    guide: [
      GuideSection('How it works', [
        'When you draw, you keep drawing until you get a card you can play.',
        'You may then play it or keep it and end your turn.',
        'If the draw pile runs out it is reshuffled from the discard pile.',
      ]),
      GuideSection('Tips', [
        'Hands swing hard: keep a Wild to avoid long draws.',
        'Changing to a color nobody has played for a while hurts opponents more than usual.',
      ]),
    ],
  ),
  GameMode(
    id: 'merciless',
    name: 'Merciless',
    tagline: '+10s, skip-everyone and a 25-card knockout.',
    accent: _wild,
    tag: 'Brutal',
    defaultPlayers: 4,
    rules: RuleSet(
      deck: DeckType.merciless,
      stack: StackRule.escalating,
      drawUntilPlayable: true,
      sevenZero: true,
      handLimit: 25,
    ),
    guide: [
      GuideSection(
        'The deck',
        [
          '164 cards with heavy hitters on top of numbers, Skip and Reverse.',
          'Colored +2 and +4, and Wild +6 and Wild +10.',
          'Wild Reverse +4: reverses direction, then the new next player gets +4.',
        ],
        cards: [
          CardFace(_blue, CardKind.draw, draw: 4),
          CardFace(_wild, CardKind.wildDraw, draw: 6),
          CardFace(_wild, CardKind.wildDraw, draw: 10),
          CardFace(_wild, CardKind.wildReverseDraw, draw: 4),
        ],
      ),
      GuideSection(
        'New actions',
        [
          'Skip All — everyone else is skipped and you play again.',
          'Discard All — also throw away every other card of that color from your hand.',
          'Wild Draw Color — pick a color; the next player turns cards from the deck until they hit that color, keeps them all and loses their turn.',
        ],
        cards: [
          CardFace(_green, CardKind.skipAll),
          CardFace(_red, CardKind.discardAll),
          CardFace(_wild, CardKind.wildDrawColor),
        ],
      ),
      GuideSection('Merciless rules', [
        'Stacking: answer any draw card with one of equal or higher value (+4 on +2, +10 on +6, …).',
        'Draw until playable is always on.',
        'Seven-O is on: 7 swaps hands, 0 passes them along.',
        'Mercy rule: reach 25 cards and you are knocked out. Last one standing — or first one out of cards — wins.',
      ]),
      GuideSection('Tips', [
        'Keep a big draw card to bounce a stack back.',
        'Discard All is the fastest way out: build up one color before playing it.',
      ]),
    ],
  ),
  GameMode(
    id: 'flipside',
    name: 'Flipside',
    tagline: 'Two-sided deck. One Flip and everything turns dark.',
    accent: CardColor.purple,
    tag: 'Two sides',
    rules: RuleSet(deck: DeckType.flipside),
    guide: [
      GuideSection(
        'Light side',
        [
          'Red, yellow, green and blue. Numbers 1–9, Skip, Reverse and Flip.',
          '+1 — next player draws 1 and loses their turn.',
          'Wild +2 — choose a color; next player draws 2.',
        ],
        cards: [
          CardFace(_red, CardKind.draw, draw: 1),
          CardFace(_blue, CardKind.flip),
          CardFace(_wild, CardKind.wildDraw, draw: 2),
        ],
      ),
      GuideSection(
        'Dark side',
        [
          'Pink, teal, orange and purple — and much meaner.',
          '+5 — next player draws 5 and loses their turn.',
          'Skip All — everyone is skipped; you play again.',
          'Wild Draw Color — next player draws until they reveal the chosen color.',
        ],
        cards: [
          CardFace(CardColor.pink, CardKind.draw, draw: 5),
          CardFace(CardColor.teal, CardKind.skipAll),
          CardFace(_wild, CardKind.wildDrawColor),
        ],
      ),
      GuideSection('Flipping', [
        'Every card has a light face and a dark face.',
        'Playing Flip turns every card over — hands, deck and discard pile. Play continues on the other side.',
        'The new top card is the other face of the Flip card. If it is a Wild, the flipper picks the color.',
        'The backs of opponents\' cards (and the deck) show their other side, so you can see what is coming.',
      ]),
      GuideSection('Tips', [
        'Look at your dark faces before you flip: flip when they are better than your light ones.',
        'Watch the deck: its top shows the face you would draw on the other side.',
      ]),
    ],
  ),
  GameMode(
    id: 'teams',
    name: 'Team 2v2',
    tagline: 'You and a partner bot against two rivals.',
    accent: _blue,
    minPlayers: 4,
    maxPlayers: 4,
    defaultPlayers: 4,
    rules: RuleSet(teams: true),
    guide: [
      GuideSection('How it works', [
        'Four players: you sit opposite your partner. Your rivals sit left and right.',
        'Classic rules. The moment either partner empties their hand, the team wins.',
        'Your partner is marked with a team badge.',
      ]),
      GuideSection('Tips', [
        'Avoid hitting your partner with Skip or +2 — play your attack when a rival is next.',
        'If your partner is close to going out, keep the color they are likely to hold.',
      ]),
    ],
  ),
  GameMode(
    id: 'elimination',
    name: 'Elimination',
    tagline: 'Each round the biggest hand is knocked out.',
    accent: _red,
    minPlayers: 3,
    maxPlayers: 6,
    defaultPlayers: 5,
    rules: RuleSet(format: MatchFormat.elimination),
    guide: [
      GuideSection('How it works', [
        'Classic rules, played over several rounds.',
        'When someone goes out, the player holding the most cards is eliminated.',
        'Ties are broken by card points, then at random.',
        'The last player standing wins the match.',
      ]),
      GuideSection('Tips', [
        'You do not need to win rounds — just never hold the biggest hand.',
        'When one player is close to going out, dump cards fast, even good ones.',
      ]),
    ],
  ),
  GameMode(
    id: 'speed',
    name: 'Speed',
    tagline: '8 seconds per turn. Think fast or draw 2.',
    accent: _yellow,
    rules: RuleSet(turnSeconds: 8),
    guide: [
      GuideSection('How it works', [
        'Classic rules with a turn clock: you have 8 seconds to act.',
        'The ring around your seat shows the time left.',
        'If time runs out you draw 2 and your turn ends. If a penalty is waiting you take that instead.',
        'After drawing a playable card, running out of time keeps it.',
      ]),
      GuideSection('Tips', [
        'Look at your hand while the bots play — plan your move before your turn.',
        'Lifted cards are playable: pick from those.',
      ]),
    ],
  ),
  GameMode(
    id: 'challenge',
    name: 'Challenge +4',
    tagline: 'Bluff a Wild +4. Or call out the bluffer.',
    accent: _green,
    rules: RuleSet(challengeWild4: true),
    guide: [
      GuideSection(
        'How it works',
        [
          'Officially a Wild +4 may only be played when you hold no card of the current color — but nobody checks… unless challenged.',
          'When a Wild +4 hits you, choose Challenge or Take +4.',
          'Bluff caught (they held the color): they draw 4 instead and you play your turn.',
          'Honest play: you draw 6 and lose your turn.',
        ],
        cards: [CardFace(_wild, CardKind.wildDraw, draw: 4)],
      ),
      GuideSection('Good to know', [
        'Only the color counts. Holding the same number in another color is not a bluff.',
        'Bots bluff too, mostly when someone is about to win.',
      ]),
      GuideSection('Tips', [
        'A player with many cards is more likely to hold the old color.',
        'If you are the one bluffing, do it when the payoff is big.',
      ]),
    ],
  ),
  GameMode(
    id: 'custom',
    name: 'Custom',
    tagline: 'Pick your deck and mix any house rules.',
    accent: _wild,
    tag: 'Sandbox',
    rules: RuleSet(),
    guide: [
      GuideSection('How it works', [
        'Choose the deck: Classic, Merciless or Flipside.',
        'Choose a match format: single round, Point Race or Elimination.',
        'Toggle any house rule: stacking, Seven-O, Jump-In, Doubles, draw until playable, Wild +4 challenge, turn timer, 25-card knockout or 2v2 teams.',
        'Each rule works exactly as described in its own mode guide.',
      ]),
      GuideSection('Combos worth trying', [
        'Seven-O + Jump-In: chaotic and fast.',
        'Flipside + Stacking: dark-side +5 chains.',
        'Point Race + Challenge: bluffs that really cost.',
      ]),
    ],
  ),
];
