import 'dart:math';

import 'i18n.dart';

/// Card colors. Light colors are used by the standard decks and the light
/// side of the Flipside deck; dark colors only exist on the dark side.
enum CardColor {
  red,
  yellow,
  green,
  blue,
  pink,
  teal,
  orange,
  purple,
  wild;

  bool get isWild => this == CardColor.wild;

  static const light = [red, yellow, green, blue];
  static const dark = [pink, teal, orange, purple];

  /// In the current language.
  String get label => colorLabel(this);
}

enum CardKind {
  number,
  skip,
  reverse,
  draw, // colored draw card: +1, +2, +4 or +5
  skipAll, // skip everyone, play again
  discardAll, // discard every card of this color
  flip, // flips every card to its other side
  wild,
  wildDraw, // wild +2 / +4 / +6 / +10
  wildReverseDraw, // reverse direction, then +4
  wildDrawColor; // next player draws until they reveal the chosen color

  bool get isWild =>
      this == wild ||
      this == wildDraw ||
      this == wildReverseDraw ||
      this == wildDrawColor;
}

enum Side {
  light,
  dark;

  Side get other => this == light ? dark : light;
}

/// One printed face of a card.
class CardFace {
  const CardFace(this.color, this.kind, {this.value = 0, this.draw = 0});

  final CardColor color;
  final CardKind kind;

  /// Face value for number cards.
  final int value;

  /// Penalty for draw cards.
  final int draw;

  bool get isWild => kind.isWild;
  bool get isDrawCard => draw > 0 && kind != CardKind.wildDrawColor;

  /// Two faces are "the same card" for matching symbols and for Jump-In.
  bool sameSymbol(CardFace o) =>
      kind == o.kind && value == o.value && draw == o.draw;

  int get points => switch (kind) {
    CardKind.number => value,
    CardKind.skip ||
    CardKind.reverse ||
    CardKind.draw ||
    CardKind.flip ||
    CardKind.discardAll => 20,
    CardKind.skipAll => 30,
    CardKind.wildDrawColor => 60,
    _ => 50,
  };

  String get symbol => switch (kind) {
    CardKind.number => '$value',
    CardKind.draw || CardKind.wildDraw || CardKind.wildReverseDraw => '+$draw',
    CardKind.skip => 'Skip',
    CardKind.reverse => 'Reverse',
    CardKind.skipAll => 'Skip All',
    CardKind.discardAll => 'Discard All',
    CardKind.flip => 'Flip',
    CardKind.wild => 'Wild',
    CardKind.wildDrawColor => 'Draw Color',
  };

  /// "Red 7", "Wild +4" in the current language.
  String get label => faceLabel(this);

  @override
  String toString() => label;
}

/// A physical card. Only Flipside cards have a [dark] face.
class GameCard {
  GameCard(this.id, this.light, [this.dark]);

  final int id;
  final CardFace light;
  final CardFace? dark;

  CardFace face(Side side) => side == Side.dark ? (dark ?? light) : light;

  @override
  String toString() => dark == null ? '$light' : '$light/$dark';
}

enum DeckType {
  classic,
  merciless,
  flipside;

  String get label => switch (this) {
    classic => t('Classic'),
    merciless => t('Merciless'),
    flipside => t('Flipside'),
  };
}

List<GameCard> buildDeck(DeckType type, Random rng) {
  var id = 0;
  GameCard c(CardFace f) => GameCard(id++, f);
  final cards = <GameCard>[];

  switch (type) {
    case DeckType.classic:
      for (final color in CardColor.light) {
        cards.add(c(CardFace(color, CardKind.number, value: 0)));
        for (var n = 0; n < 2; n++) {
          for (var v = 1; v <= 9; v++) {
            cards.add(c(CardFace(color, CardKind.number, value: v)));
          }
          cards
            ..add(c(CardFace(color, CardKind.skip)))
            ..add(c(CardFace(color, CardKind.reverse)))
            ..add(c(CardFace(color, CardKind.draw, draw: 2)));
        }
      }
      for (var n = 0; n < 4; n++) {
        cards
          ..add(c(const CardFace(CardColor.wild, CardKind.wild)))
          ..add(c(const CardFace(CardColor.wild, CardKind.wildDraw, draw: 4)));
      }
    case DeckType.merciless:
      for (final color in CardColor.light) {
        for (var n = 0; n < 2; n++) {
          for (var v = 0; v <= 9; v++) {
            cards.add(c(CardFace(color, CardKind.number, value: v)));
          }
          cards
            ..add(c(CardFace(color, CardKind.draw, draw: 2)))
            ..add(c(CardFace(color, CardKind.draw, draw: 4)))
            ..add(c(CardFace(color, CardKind.skipAll)));
        }
        for (var n = 0; n < 3; n++) {
          cards
            ..add(c(CardFace(color, CardKind.skip)))
            ..add(c(CardFace(color, CardKind.reverse)))
            ..add(c(CardFace(color, CardKind.discardAll)));
        }
      }
      for (var n = 0; n < 4; n++) {
        cards
          ..add(c(const CardFace(CardColor.wild, CardKind.wildDraw, draw: 6)))
          ..add(c(const CardFace(CardColor.wild, CardKind.wildDraw, draw: 10)));
      }
      for (var n = 0; n < 8; n++) {
        cards
          ..add(
            c(
              const CardFace(CardColor.wild, CardKind.wildReverseDraw, draw: 4),
            ),
          )
          ..add(c(const CardFace(CardColor.wild, CardKind.wildDrawColor)));
      }
    case DeckType.flipside:
      final light = <CardFace>[];
      final dark = <CardFace>[];
      for (var i = 0; i < 4; i++) {
        final lc = CardColor.light[i];
        final dc = CardColor.dark[i];
        for (var n = 0; n < 2; n++) {
          for (var v = 1; v <= 9; v++) {
            light.add(CardFace(lc, CardKind.number, value: v));
            dark.add(CardFace(dc, CardKind.number, value: v));
          }
          light
            ..add(CardFace(lc, CardKind.draw, draw: 1))
            ..add(CardFace(lc, CardKind.reverse))
            ..add(CardFace(lc, CardKind.skip))
            ..add(CardFace(lc, CardKind.flip));
          dark
            ..add(CardFace(dc, CardKind.draw, draw: 5))
            ..add(CardFace(dc, CardKind.reverse))
            ..add(CardFace(dc, CardKind.skipAll))
            ..add(CardFace(dc, CardKind.flip));
        }
      }
      for (var n = 0; n < 4; n++) {
        light
          ..add(const CardFace(CardColor.wild, CardKind.wild))
          ..add(const CardFace(CardColor.wild, CardKind.wildDraw, draw: 2));
        dark
          ..add(const CardFace(CardColor.wild, CardKind.wild))
          ..add(const CardFace(CardColor.wild, CardKind.wildDrawColor));
      }
      dark.shuffle(rng);
      for (var i = 0; i < light.length; i++) {
        cards.add(GameCard(id++, light[i], dark[i]));
      }
  }
  return cards..shuffle(rng);
}
