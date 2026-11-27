import 'package:flutter/services.dart';
import 'package:last_card_core/hold_card.dart';
import 'package:last_card_core/modes.dart';
import 'package:last_card_core/protocol.dart';
import 'package:last_card_core/rules.dart';
import 'package:material_ui/material_ui.dart';

import '../ui/exact_score_screen.dart';
import '../ui/game_controller.dart';
import '../ui/game_screen.dart';
import '../ui/guide_screen.dart';
import '../ui/hold_card_screen.dart';
import '../ui/mode_screen.dart' show customRuleRows;
import '../ui/party_widgets.dart';
import '../ui/theme.dart';
import 'browser.dart';
import 'online_tables.dart';
import 'session.dart';

OnlineSession get _session => OnlineSession.instance;

/// Modes available online: all of them.
List<GameMode> get onlineModes => gameModes;

GameMode modeById(String? id) =>
    gameModes.firstWhere((m) => m.id == id, orElse: () => gameModes.first);

/// Create or join a room.
class OnlineHomeScreen extends StatefulWidget {
  const OnlineHomeScreen({super.key, this.joinCode});

  /// "ROOMID-PASSWORD" from an invite link, joined right away.
  final String? joinCode;

  @override
  State<OnlineHomeScreen> createState() => _OnlineHomeScreenState();
}

class _OnlineHomeScreenState extends State<OnlineHomeScreen> {
  final _room = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final code = widget.joinCode;
    if (code != null && code.contains('-')) {
      final i = code.indexOf('-');
      _room.text = code.substring(0, i);
      _pass.text = code.substring(i + 1);
      WidgetsBinding.instance.addPostFrameCallback((_) => _join());
    }
  }

  @override
  void dispose() {
    _room.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _run(Future<String?> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final problem = await action();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = problem;
    });
    if (problem == null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LobbyScreen()),
      );
    }
  }

  void _create() => _run(_session.create);
  void _join() => _run(() => _session.join(_room.text, _pass.text));

  @override
  Widget build(BuildContext context) {
    final saved = _session.saved;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Palette.ink,
        surfaceTintColor: Colors.transparent,
        title: Text('Play online', style: font(19, weight: 650)),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          32 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          Text(
            'No account needed. Create a room, share the link, and play with friends.',
            style: font(15, color: Palette.muted, height: 1.4),
          ),
          const SizedBox(height: 20),
          if (saved != null && widget.joinCode == null) ...[
            _Card(
              child: Row(
                children: [
                  const Icon(Icons.history_rounded, color: Palette.muted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Back to room ${saved.$1}',
                      style: font(16, weight: 600),
                    ),
                  ),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() => _session.join(saved.$1, saved.$2)),
                    child: const Text('Rejoin'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Create a room', style: font(18, weight: 650)),
                const SizedBox(height: 4),
                Text(
                  'You get a room ID, a password and a link to share.',
                  style: font(14, color: Palette.muted),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _busy ? null : _create,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Create room'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Join a room', style: font(18, weight: 650)),
                const SizedBox(height: 12),
                TextField(
                  controller: _room,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Room ID',
                    border: OutlineInputBorder(),
                  ),
                  inputFormatters: [LengthLimitingTextInputFormatter(6)],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _pass,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                  inputFormatters: [LengthLimitingTextInputFormatter(4)],
                  onSubmitted: (_) => _join(),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _join,
                  icon: const Icon(Icons.login_rounded),
                  label: const Text('Join room'),
                ),
              ],
            ),
          ),
          if (_busy) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: font(15, weight: 600, color: const Color(0xFFFFB4A8)),
            ),
          ],
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Palette.surface,
        borderRadius: BorderRadius.circular(22),
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------- lobby

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> with WidgetsBindingObserver {
  int _seenError = _session.errorId;
  int? _shownMatch;
  bool _inMatch = false;
  bool _hadRoom = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session.addListener(_onSession);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onSession());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_onSession);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _session.wake();
  }

  void _onSession() {
    if (!mounted) return;
    if (_session.errorId != _seenError) {
      _seenError = _session.errorId;
      final text = _session.error;
      if (text != null && !_inMatch) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(text)));
      }
    }
    if (_session.room == null) {
      // Left the room (or it was closed): back to the online menu.
      if (_hadRoom && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      return;
    }
    _hadRoom = true;
    final room = _session.room!;
    final match = _session.match;
    final playing = room['playing'] == true;
    final mine = (room['members'] as List).any(
      (m) => m['id'] == _session.myId && m['playing'] == true,
    );
    if (playing &&
        mine &&
        match != null &&
        match['id'] == room['matchId'] &&
        match['id'] != _shownMatch &&
        !_inMatch) {
      _shownMatch = match['id'] as int;
      _inMatch = true;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const OnlineMatchScreen()),
      ).then((_) {
        _inMatch = false;
        if (mounted) setState(() {});
      });
    }
    setState(() {});
  }

  Future<void> _share() async {
    final link = _session.inviteLink;
    final shared = await shareLink(
      title: 'Last Card',
      text:
          'Join my Last Card room ${_session.roomId} (password ${_session.password}):',
      url: link,
    );
    if (shared || !mounted) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Invite link copied — paste it in WhatsApp'),
      ),
    );
  }

  Future<void> _rename(String current) async {
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Your nickname', style: font(20, weight: 650)),
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
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.trim() != current) _session.setNick(name.trim());
  }

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Leave the room?', style: font(20, weight: 650)),
        content: Text(
          'Your points stay with the room. A bot takes your seat if a match is running.',
          style: font(15, color: Palette.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (ok == true) _session.leave();
  }

  @override
  Widget build(BuildContext context) {
    final room = _session.room;
    if (room == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final members = (room['members'] as List).cast<Map<String, dynamic>>();
    final host = _session.isHost;
    final playing = room['playing'] == true;
    final finished = room['finished'] == true;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Palette.ink,
          surfaceTintColor: Colors.transparent,
          automaticallyImplyLeading: false,
          title: Text('Room ${room['id']}', style: font(19, weight: 650)),
          actions: [
            if (!_session.connected)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: PartyChip('RECONNECTING', color: Color(0xFF9B2A21)),
              ),
            IconButton(
              tooltip: 'Leave room',
              onPressed: _leave,
              icon: const Icon(Icons.logout_rounded),
            ),
          ],
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            4,
            16,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            if (finished) ...[
              _FinalScore(members: members),
              const SizedBox(height: 14),
            ],
            _InviteCard(room: room, onShare: _share),
            const SizedBox(height: 14),
            _Players(
              members: members,
              me: _session.myId,
              host: room['host'] as String?,
              onRename: _rename,
            ),
            const SizedBox(height: 14),
            if (playing && !_inMatch)
              _Card(
                child: Row(
                  children: [
                    const Icon(Icons.sports_esports_rounded),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        members.any(
                              (m) =>
                                  m['id'] == _session.myId &&
                                  m['playing'] == true,
                            )
                            ? 'Your match is running'
                            : 'A match is running — you join the next one',
                        style: font(15, weight: 600),
                      ),
                    ),
                    if (members.any(
                      (m) => m['id'] == _session.myId && m['playing'] == true,
                    ))
                      FilledButton(
                        onPressed: () {
                          _shownMatch = null;
                          _onSession();
                        },
                        child: const Text('Open'),
                      ),
                  ],
                ),
              )
            else
              _SetupCard(
                room: room,
                host: host,
                players: members.where((m) => m['online'] == true).length,
              ),
            const SizedBox(height: 14),
            _Scoreboard(room: room, members: members),
            if (host && (room['history'] as List).isNotEmpty && !finished) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _session.endSession,
                icon: const Icon(Icons.flag_rounded),
                label: const Text('Show final score'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({required this.room, required this.onShare});

  final Map<String, dynamic> room;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    Widget code(String label, String value) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: font(12, weight: 600, color: Palette.muted)),
          SelectableText(
            value,
            style: font(24, weight: 700).copyWith(letterSpacing: 2),
          ),
        ],
      ),
    );
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              code('ROOM ID', room['id'] as String),
              code('PASSWORD', room['pass'] as String),
            ],
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onShare,
            icon: const Icon(Icons.share_rounded),
            label: const Text('Invite friends'),
          ),
        ],
      ),
    );
  }
}

class _Players extends StatelessWidget {
  const _Players({
    required this.members,
    required this.me,
    required this.host,
    required this.onRename,
  });

  final List<Map<String, dynamic>> members;
  final String? me;
  final String? host;
  final void Function(String current) onRename;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Players · ${members.length}/6', style: font(18, weight: 650)),
          const SizedBox(height: 8),
          for (final (i, m) in members.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Opacity(
                    opacity: m['online'] == true ? 1 : 0.4,
                    child: SeatAvatar(
                      seat: i,
                      color: m['color'] as int?,
                      name: m['name'] as String,
                      size: 34,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            m['name'] as String,
                            overflow: TextOverflow.ellipsis,
                            style: font(
                              16,
                              weight: m['id'] == me ? 700 : 550,
                              color: m['online'] == true
                                  ? Palette.text
                                  : Palette.muted,
                            ),
                          ),
                        ),
                        if (m['id'] == host) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.workspace_premium_rounded,
                            size: 18,
                            color: Color(0xFFF4B620),
                          ),
                        ],
                        if (m['id'] == me) ...[
                          const SizedBox(width: 6),
                          const PartyChip('YOU', color: Color(0xFF2475D6)),
                        ],
                        if (m['online'] != true) ...[
                          const SizedBox(width: 6),
                          Text(
                            'offline',
                            style: font(12, color: Palette.muted),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text('${m['points']} pts', style: font(14, weight: 650)),
                  if (m['id'] == me)
                    IconButton(
                      tooltip: 'Change nickname',
                      onPressed: () => onRename(m['name'] as String),
                      icon: const Icon(Icons.edit_rounded, size: 20),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({
    required this.room,
    required this.host,
    required this.players,
  });

  final Map<String, dynamic> room;
  final bool host;
  final int players;

  @override
  Widget build(BuildContext context) {
    final setup = room['setup'] as Map<String, dynamic>;
    final mode = modeById(setup['mode'] as String?);
    final bots = setup['bots'] as int;
    final difficulty = Difficulty.values[setup['difficulty'] as int];
    final custom = mode.isCustom
        ? rulesFromJson(setup['custom'] as Map<String, dynamic>)
        : null;
    void set(Map<String, Object?> change) => _session.setup(change);

    Widget row(String label, Widget child) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 78, child: Text(label, style: font(15, weight: 600))),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(fit: BoxFit.scaleDown, child: child),
            ),
          ),
        ],
      ),
    );

    Widget segments<T>(
      List<T> values,
      T selected,
      String Function(T) label,
      void Function(T) onTap,
    ) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final v in values)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: ChoiceChip(
              label: Text(label(v)),
              selected: v == selected,
              onSelected: host ? (_) => onTap(v) : null,
            ),
          ),
      ],
    );

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            host ? 'Next match' : 'Next match (host decides)',
            style: font(18, weight: 650),
          ),
          const SizedBox(height: 8),
          Material(
            color: Palette.surfaceHigh,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: host
                  ? () async {
                      final picked = await showModalBottomSheet<String>(
                        context: context,
                        isScrollControlled: true,
                        builder: (context) => _ModePicker(current: mode.id),
                      );
                      if (picked != null) set({'mode': picked});
                    }
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Palette.of(mode.accent),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(modeIcon(mode.id), color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(mode.name, style: font(16, weight: 650)),
                          Text(
                            mode.tagline,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: font(13, color: Palette.muted),
                          ),
                        ],
                      ),
                    ),
                    if (host) const Icon(Icons.expand_more_rounded),
                  ],
                ),
              ),
            ),
          ),
          row(
            'Bots',
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: host && bots > 0
                      ? () => set({'bots': bots - 1})
                      : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                Text('$bots', style: font(18, weight: 700)),
                IconButton(
                  onPressed: host && bots < 5
                      ? () => set({'bots': bots + 1})
                      : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ),
          if (bots > 0)
            row(
              'Bot level',
              segments(
                Difficulty.values,
                difficulty,
                (d) => d.label,
                (d) => set({'difficulty': d.index}),
              ),
            ),
          if (mode.kind == GameKind.exactScore)
            row(
              'Target',
              segments(
                const [0, 20, 30, 40, 50],
                setup['target'] as int,
                (v) => v == 0 ? 'Random' : '$v',
                (v) => set({'target': v}),
              ),
            ),
          if (mode.isCustom) ...[
            if (custom!.format == MatchFormat.points)
              row(
                'Target',
                segments(
                  const [250, 500, 1000],
                  custom.targetScore,
                  (v) => '$v',
                  (v) => set({
                    'custom': rulesToJson(custom.copyWith(targetScore: v)),
                  }),
                ),
              ),
            ..._customRules(custom, host),
          ],
          if (mode.kind == GameKind.holdCard)
            row(
              'Guess',
              segments(
                HoldGuess.values,
                HoldGuess.values[setup['guess'] as int],
                (g) => g.label,
                (g) => set({'guess': g.index}),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            '${players + bots} player${players + bots == 1 ? '' : 's'} at the table',
            textAlign: TextAlign.center,
            style: font(13, color: Palette.muted),
          ),
          const SizedBox(height: 10),
          if (host)
            FilledButton.icon(
              onPressed: _session.start,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text('Start ${mode.name}'),
            )
          else
            Text(
              'Waiting for the host to start…',
              textAlign: TextAlign.center,
              style: font(15, weight: 600, color: Palette.muted),
            ),
          const SizedBox(height: 6),
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => GuideScreen(mode: mode)),
            ),
            icon: const Icon(Icons.menu_book_rounded, size: 18),
            label: Text('How to play ${mode.name}'),
          ),
        ],
      ),
    );
  }
}

/// Custom mode: the host edits the rules; everyone else sees them.
List<Widget> _customRules(RuleSet rules, bool host) {
  void set(RuleSet r) => _session.setup({'custom': rulesToJson(r)});
  return [
    const SizedBox(height: 4),
    IgnorePointer(
      ignoring: !host,
      child: Column(children: [...customRuleRows(rules, host ? set : null)]),
    ),
  ];
}

class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.current});

  final String current;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text('Choose a mode', style: font(22, weight: 700)),
          const SizedBox(height: 10),
          for (final m in onlineModes)
            ListTile(
              selected: m.id == current,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              leading: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Palette.of(m.accent),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(modeIcon(m.id), color: Colors.white, size: 20),
              ),
              title: Text(m.name, style: font(16, weight: 650)),
              subtitle: Text(m.tagline, style: font(13, color: Palette.muted)),
              onTap: () => Navigator.pop(context, m.id),
            ),
        ],
      ),
    );
  }
}

class _Scoreboard extends StatelessWidget {
  const _Scoreboard({required this.room, required this.members});

  final Map<String, dynamic> room;
  final List<Map<String, dynamic>> members;

  @override
  Widget build(BuildContext context) {
    final history = (room['history'] as List).cast<Map<String, dynamic>>();
    final ranked = List.of(members)
      ..sort((a, b) => (b['points'] as int).compareTo(a['points'] as int));
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Scoreboard', style: font(18, weight: 650)),
          const SizedBox(height: 4),
          Text(
            '1st 10 · 2nd 6 · 3rd 3 · others 1 point per match',
            style: font(12.5, color: Palette.muted),
          ),
          const SizedBox(height: 10),
          if (history.isEmpty)
            Text(
              'No matches yet. Points add up over every mode you play.',
              style: font(14, color: Palette.muted),
            )
          else ...[
            for (final (i, m) in ranked.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 26,
                      child: Text('${i + 1}.', style: font(15, weight: 700)),
                    ),
                    Expanded(
                      child: Text(
                        m['name'] as String,
                        style: font(15, weight: 600),
                      ),
                    ),
                    Text('${m['points']} pts', style: font(15, weight: 700)),
                  ],
                ),
              ),
            const Divider(height: 24, color: Palette.line),
            for (final (i, h) in history.reversed.indexed)
              _MatchRow(number: history.length - i, record: h),
          ],
        ],
      ),
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.number, required this.record});

  final int number;
  final Map<String, dynamic> record;

  @override
  Widget build(BuildContext context) {
    final ranks = (record['ranks'] as List).cast<Map<String, dynamic>>();
    final winners = ranks
        .where((r) => r['place'] == 1)
        .map((r) => r['name'])
        .join(' & ');
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text('#$number ${record['mode']}', style: font(15, weight: 650)),
        subtitle: Text(
          '🏆 $winners · +${ranks.first['points']}',
          style: font(13, color: Palette.muted),
        ),
        children: [
          for (final r in ranks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: Text('${r['place']}', style: font(14, weight: 650)),
                  ),
                  Expanded(
                    child: Text(
                      r['name'] as String,
                      style: font(
                        14,
                        color: r['bot'] == true ? Palette.muted : Palette.text,
                      ),
                    ),
                  ),
                  Text('+${r['points']}', style: font(14, weight: 650)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FinalScore extends StatelessWidget {
  const _FinalScore({required this.members});

  final List<Map<String, dynamic>> members;

  @override
  Widget build(BuildContext context) {
    final ranked = List.of(members)
      ..sort((a, b) => (b['points'] as int).compareTo(a['points'] as int));
    const medals = [Color(0xFFF4B620), Color(0xFFB8C0CC), Color(0xFFCD7F4A)];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3A2A10), Palette.surface],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF6B5420)),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.emoji_events_rounded,
            size: 44,
            color: Color(0xFFF4B620),
          ),
          const SizedBox(height: 6),
          Text('Final score', style: font(24, weight: 700)),
          const SizedBox(height: 12),
          for (final (i, m) in ranked.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    i < 3 ? Icons.military_tech_rounded : Icons.circle,
                    size: i < 3 ? 24 : 8,
                    color: i < 3 ? medals[i] : Palette.muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      m['name'] as String,
                      style: font(i == 0 ? 18 : 16, weight: i == 0 ? 700 : 600),
                    ),
                  ),
                  Text('${m['points']} pts', style: font(16, weight: 700)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- match

/// Shows the running online match with the right game screen and feeds it
/// every update from the server.
class OnlineMatchScreen extends StatefulWidget {
  const OnlineMatchScreen({super.key});

  @override
  State<OnlineMatchScreen> createState() => _OnlineMatchScreenState();
}

class _OnlineMatchScreenState extends State<OnlineMatchScreen> {
  GameController? _shed;
  OnlineExactTable? _exact;
  OnlineHoldTable? _hold;
  late final int _matchId;
  late final GameMode _mode;
  int _seenError = _session.errorId;

  @override
  void initState() {
    super.initState();
    final m = _session.match!;
    _matchId = m['id'] as int;
    _mode = modeById(m['mode'] as String?);
    seatColorMap = (m['colors'] as List?)?.cast<int>();
    switch (m['kind']) {
      case 'shed':
        _shed = GameController.online(
          mode: _mode,
          match: m,
          send: _session.act,
        );
      case 'exact':
        _exact = OnlineExactTable(m, _session);
      case 'hold':
        _hold = OnlineHoldTable(m, _session);
    }
    _session.addListener(_onSession);
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    seatColorMap = null;
    _shed?.dispose();
    _exact?.dispose();
    _hold?.dispose();
    super.dispose();
  }

  void _onSession() {
    if (!mounted) return;
    if (_session.errorId != _seenError) {
      _seenError = _session.errorId;
      final text = _session.error;
      if (text != null) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(text)));
      }
    }
    final m = _session.match;
    if (m != null && m['id'] == _matchId && m['t'] == 'match') {
      _shed?.applyRemote(m);
      _exact?.apply(m);
      _hold?.apply(m);
    }
    if (_session.room == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final screen = _shed != null
        ? GameScreen(mode: _mode, controller: _shed)
        : _exact != null
        ? ExactScoreScreen(mode: _mode, table: _exact)
        : HoldCardScreen(mode: _mode, table: _hold);
    return Stack(
      children: [
        screen,
        if (!_session.connected)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: PartyChip('RECONNECTING…', color: Color(0xFF9B2A21)),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
