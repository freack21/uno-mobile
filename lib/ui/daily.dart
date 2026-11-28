import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:last_card_core/i18n.dart';
import 'package:last_card_core/modes.dart';
import 'package:last_card_core/rules.dart';
import 'package:material_ui/material_ui.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../online/browser.dart';
import '../online/session.dart';
import 'game_controller.dart';
import 'game_screen.dart';
import 'stats.dart';
import 'theme.dart';

/// Today in Indonesian time (WIB), the same day as the server's.
String dailyToday([DateTime? now]) {
  final d = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 7));
  String two(int x) => x.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

/// The deal of [date]: the same for everyone.
int dailySeed(String date) => int.parse(date.replaceAll('-', ''));

/// Points for the daily game: what is left in the opponents' hands when you
/// win, nothing otherwise.
int dailyScore(GameController c) {
  final r = c.game.lastRound;
  return r != null && r.winner == GameController.human ? r.points : 0;
}

/// This device's daily play: today's result, nickname and device id.
class DailyState {
  DailyState._() {
    try {
      final j = jsonDecode(readStored(_key) ?? '{}') as Map<String, dynamic>;
      date = j['date'] as String?;
      score = j['score'] as int?;
      sent = j['sent'] as bool? ?? false;
    } catch (_) {}
    device = readStored(_deviceKey) ?? _newId();
    writeStored(_deviceKey, device);
    name =
        readStored(_nameKey) ??
        t('Player {n}', {'n': 1000 + Random().nextInt(9000)});
  }

  static final instance = DailyState._();
  static const _key = 'lastcard.daily';
  static const _deviceKey = 'lastcard.device';
  static const _nameKey = 'lastcard.dailyName';

  String? date;

  /// Null while today's game is still going.
  int? score;
  bool sent = false;
  late final String device;
  late String name;

  bool get playedToday => date == dailyToday();

  static String _newId() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  void rename(String value) {
    name = value;
    writeStored(_nameKey, value);
  }

  /// Today's one try begins: leaving it counts as zero.
  void start() {
    date = dailyToday();
    score = 0;
    sent = false;
    _save();
  }

  void finish(int points) {
    score = points;
    sent = false;
    _save();
    Stats.instance.recordDaily();
  }

  void markSent() {
    sent = true;
    _save();
  }

  void _save() => writeStored(
    _key,
    jsonEncode({'date': date, 'score': score, 'sent': sent}),
  );
}

/// Asks the game server for [date]'s leaderboard, submitting [score] first
/// when given. Throws when the server cannot be reached.
Future<Map<String, dynamic>> dailyBoard(String date, {int? score}) async {
  final d = DailyState.instance;
  final channel = WebSocketChannel.connect(gameServerUrl());
  try {
    await channel.ready.timeout(const Duration(seconds: 8));
    channel.sink.add(
      jsonEncode(
        score == null
            ? {'t': 'daily_get', 'date': date, 'device': d.device}
            : {
                't': 'daily_submit',
                'date': date,
                'device': d.device,
                'name': d.name,
                'score': score,
              },
      ),
    );
    final reply = await channel.stream
        .map((m) => jsonDecode(m as String) as Map<String, dynamic>)
        .firstWhere((m) => m['t'] == 'daily' || m['t'] == 'error')
        .timeout(const Duration(seconds: 8));
    if (reply['t'] == 'error') {
      throw StateError(
        t(
          (reply['key'] ?? reply['msg']) as String,
          (reply['args'] as Map?)?.cast<String, Object?>() ?? {},
        ),
      );
    }
    return reply;
  } finally {
    unawaited(channel.sink.close());
  }
}

/// Today's deal, your result and the leaderboard.
class DailyScreen extends StatefulWidget {
  const DailyScreen({super.key});

  @override
  State<DailyScreen> createState() => _DailyScreenState();
}

class _DailyScreenState extends State<DailyScreen> {
  final _d = DailyState.instance;
  Map<String, dynamic>? _board;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final today = dailyToday();
      final send = _d.playedToday && !_d.sent && _d.score != null;
      final board = await dailyBoard(today, score: send ? _d.score : null);
      if (send) _d.markSent();
      _board = board;
    } catch (e) {
      _error = e is StateError
          ? e.message
          : t('Leaderboard unavailable. Check your connection.');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _play() async {
    final today = dailyToday();
    _d.start();
    final mode = gameModes.first;
    final c = GameController(
      mode: mode,
      rules: const RuleSet(),
      playerCount: 4,
      difficulty: Difficulty.normal,
      seed: dailySeed(today),
    );
    var done = false;
    void check() {
      if (!done && c.game.isRoundOver) {
        done = true;
        _d.finish(dailyScore(c));
      }
    }

    c.addListener(check);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GameScreen(mode: mode, controller: c),
      ),
    );
    c.removeListener(check);
    c.dispose();
    if (!done) _d.finish(0);
    if (mounted) await _refresh();
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: _d.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Leaderboard name'), style: font(20, weight: 650)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 16,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(t('Save')),
          ),
        ],
      ),
    );
    controller.dispose();
    final v = name?.trim() ?? '';
    if (v.isNotEmpty) setState(() => _d.rename(v));
  }

  @override
  Widget build(BuildContext context) {
    final board = _board;
    final top = (board?['top'] as List?) ?? const [];
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Palette.ink,
        surfaceTintColor: Colors.transparent,
        title: Text(t('Daily challenge'), style: font(19, weight: 650)),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Palette.surface,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(dailyToday(), style: font(14, color: Palette.muted)),
                  const SizedBox(height: 4),
                  Text(
                    t('Same deal for everyone today'),
                    style: font(20, weight: 700),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t(
                      "Classic against three bots. Win to score the points left in your opponents' hands. One try per day.",
                    ),
                    style: font(14, color: Palette.muted, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  if (_d.playedToday)
                    Text(
                      t('Your score today: {n}', {'n': _d.score ?? 0}),
                      textAlign: TextAlign.center,
                      style: font(18, weight: 700),
                    )
                  else
                    FilledButton.icon(
                      onPressed: _play,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text(t("Play today's deal")),
                    ),
                  if (board?['rank'] != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      t('Rank {rank} of {n}', {
                        'rank': board!['rank'],
                        'n': board['players'],
                      }),
                      textAlign: TextAlign.center,
                      style: font(14, color: Palette.muted),
                    ),
                  ],
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: _rename,
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: Text(t('Playing as {name}', {'name': _d.name})),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(t('Leaderboard'), style: font(20, weight: 700)),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Column(
                children: [
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: font(14, color: Palette.warn),
                  ),
                  TextButton(onPressed: _refresh, child: Text(t('Try again'))),
                ],
              )
            else if (top.isEmpty)
              Text(
                t('No scores yet today. Be the first!'),
                style: font(14, color: Palette.muted),
              )
            else
              for (final (i, e) in top.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 34,
                        child: Text(
                          '${i + 1}.',
                          style: font(
                            16,
                            weight: 700,
                            color: i < 3
                                ? const Color(0xFFF4B620)
                                : Palette.muted,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          e['name'] as String,
                          style: font(16, weight: 600),
                        ),
                      ),
                      Text('${e['score']}', style: font(16, weight: 700)),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
