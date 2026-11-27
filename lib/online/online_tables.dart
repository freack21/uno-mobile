import 'package:last_card_core/hold_card.dart';
import 'package:last_card_core/party_tables.dart';
import 'package:last_card_core/protocol.dart';
import 'package:last_card_core/table.dart';

import 'session.dart';

List<TableNote> _notes(Map<String, dynamic> msg) => [
  for (final n in msg['notes'] as List)
    TableNote.fromJson(n as Map<String, dynamic>),
];

/// Exact Score as shown to one online player: the server runs the table,
/// this mirror holds its latest state and forwards the player's choices.
class OnlineExactTable extends ExactScoreTable {
  OnlineExactTable(Map<String, dynamic> msg, this.session)
    : super(
        game: exactFromView(msg['view'] as Map<String, dynamic>),
        humans: {0},
      ) {
    apply(msg);
  }

  final OnlineSession session;
  bool _over = false;

  void apply(Map<String, dynamic> msg) {
    game = exactFromView(msg['view'] as Map<String, dynamic>);
    final stageIndex = msg['stage'] as int?;
    stage = stageIndex == null ? null : ExactStage.values[stageIndex];
    turnId = msg['turnId'] as int;
    fillFrom
      ..clear()
      ..addAll({
        for (final e in (msg['fillFrom'] as Map<String, dynamic>).entries)
          int.parse(e.key): e.value as int,
      });
    final lastCard = msg['last'] as List?;
    last = lastCard == null ? null : cardFromJson(lastCard);
    notes
      ..clear()
      ..addAll(_notes(msg));
    _over = msg['over'] as bool;
    changed();
  }

  @override
  bool get isOver => _over || super.isOver;

  @override
  void start() {}

  @override
  void resume() {}

  @override
  bool draw(int seat) {
    session.act({'a': 'draw'});
    return true;
  }

  @override
  bool chooseWild(int seat, int value) {
    session.act({'a': 'wild', 'value': value});
    return true;
  }

  @override
  bool chooseVictim(int seat, int victim) {
    session.act({'a': 'victim', 'target': victim});
    return true;
  }
}

/// Hold Card as shown to one online player.
class OnlineHoldTable extends HoldCardTable {
  OnlineHoldTable(Map<String, dynamic> msg, this.session)
    : super(
        game: holdFromView(msg['view'] as Map<String, dynamic>),
        humans: {0},
      ) {
    apply(msg);
  }

  final OnlineSession session;
  bool _over = false;

  void apply(Map<String, dynamic> msg) {
    game = holdFromView(msg['view'] as Map<String, dynamic>);
    playId = msg['playId'] as int;
    notes
      ..clear()
      ..addAll(_notes(msg));
    _over = msg['over'] as bool;
    changed();
  }

  @override
  bool get isOver => _over || super.isOver;

  @override
  void start() {}

  @override
  void resume() {}

  @override
  bool place(int seat, HoldCall call, int index) {
    session.act({
      'a': 'place',
      'number': call.number,
      'color': call.color?.index,
      'index': index,
    });
    return true;
  }

  @override
  bool press(int seat) {
    session.act({'a': 'press'});
    return true;
  }
}
