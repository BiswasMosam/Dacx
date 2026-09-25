import 'package:flutter/material.dart';

import '../link.dart';
import '../pacing.dart';
import '../theme.dart';
import '../widgets/deck_key.dart';
import '../widgets/volume_knob.dart';

/// Pause, Play, Previous and Next as tall keys, plus a rotary volume knob.
/// Works on whatever is playing on the PC: Spotify, a browser, VLC.
class MediaScreen extends StatefulWidget {
  const MediaScreen({super.key});

  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> {
  late final DeckLink _link = LinkScope.read(context);
  late final _poll = Poller(const Duration(seconds: 2), _fetch);
  late final _volume = LatestSender<int>(
    (v) => _link.send('volume', {'action': 'set', 'value': v}),
  );

  int _level = 0;
  bool _muted = false;
  Map<String, dynamic>? _session;

  // Replies to polls that started before a tap are stale; drop them.
  int _epoch = 0;
  // After the knob moves, the PC's reading lags for a moment; trust ours.
  DateTime _holdLevel = DateTime(0);

  @override
  void initState() {
    super.initState();
    _poll.start();
  }

  @override
  void dispose() {
    _poll.stop();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (!_link.online) return;
    final e = _epoch;
    final r = await _link.send('media', {'action': 'state'});
    if (!mounted || e != _epoch) return;
    setState(() {
      if (DateTime.now().isAfter(_holdLevel)) {
        _level = (r['volume'] as num?)?.round() ?? _level;
        _muted = r['muted'] as bool? ?? _muted;
      }
      _session = r['session'] as Map<String, dynamic>?;
    });
  }

  bool? get _playing => _session?['playing'] as bool?;

  Future<void> _transport(String action) async {
    _epoch++;
    if (_session != null && (action == 'play' || action == 'pause')) {
      setState(() => _session = {..._session!, 'playing': action == 'play'});
    }
    try {
      await _link.send('media', {'action': action});
    } on DeckError catch (e) {
      if (mounted) toast(context, e.message);
    }
    _poll.after(const Duration(milliseconds: 500));
  }

  void _setLevel(int v) {
    _epoch++;
    _holdLevel = DateTime.now().add(const Duration(milliseconds: 1500));
    if (_muted) {
      // Turning the knob while muted should bring the sound back.
      _muted = false;
      _link.send('volume', {'action': 'mute'}).ignore();
    }
    setState(() => _level = v);
    _volume.push(v);
  }

  Future<void> _toggleMute() async {
    _epoch++;
    _holdLevel = DateTime.now().add(const Duration(milliseconds: 1500));
    setState(() => _muted = !_muted);
    try {
      final r = await _link.send('volume', {'action': 'mute'});
      if (mounted) setState(() => _muted = r['muted'] as bool? ?? _muted);
    } on DeckError catch (e) {
      if (mounted) toast(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth > box.maxHeight;
            return Column(children: [
              Row(children: [
                const BackKey(),
                const SizedBox(width: 14),
                Text('MEDIA', style: capsLabel(color: Deck.text, size: 14)),
                const SizedBox(width: 16),
                Expanded(child: _NowPlaying(session: _session, pcName: _link.pcName)),
              ]),
              SizedBox(height: wide ? 12 : 18),
              Expanded(child: _panel(wide)),
            ]);
          }),
        ),
      ),
    );
  }

  /// The controller body from the sketch: keys on one side, knob on the other.
  Widget _panel(bool wide) {
    final keys = Row(children: [
      for (final (i, k) in [
        ('pause', Icons.pause_rounded, 'PAUSE', _playing == false ? Deck.warn : null),
        ('play', Icons.play_arrow_rounded, 'PLAY', _playing == true ? Deck.ok : null),
        ('prev', Icons.skip_previous_rounded, 'PREV', null),
        ('next', Icons.skip_next_rounded, 'NEXT', null),
      ].indexed) ...[
        if (i > 0) const SizedBox(width: 10),
        Expanded(
          child: DeckKey(
            glow: Deck.accent,
            lit: k.$4 != null,
            onTap: () => _transport(k.$1),
            child: LayoutBuilder(
              builder: (context, box) => KeyFace(
                icon: Icon(k.$2, color: Deck.text, size: (box.maxWidth * 0.46).clamp(22.0, 44.0)),
                label: k.$3,
                led: k.$4,
              ),
            ),
          ),
        ),
      ],
    ]);

    final knob = VolumeKnob(
      value: _level,
      muted: _muted,
      onChanged: _setLevel,
      onMute: _toggleMute,
    );

    return Container(
      padding: EdgeInsets.all(wide ? 18 : 16),
      decoration: BoxDecoration(
        color: Deck.body,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF1C1C23)),
        boxShadow: const [BoxShadow(color: Colors.black, blurRadius: 30, offset: Offset(0, 12))],
      ),
      child: wide
          ? Row(children: [
              Expanded(flex: 11, child: keys),
              const SizedBox(width: 20),
              Expanded(flex: 9, child: knob),
            ])
          : LayoutBuilder(builder: (context, box) {
              return Column(children: [
                SizedBox(height: (box.maxHeight * 0.34).clamp(130.0, 210.0), child: keys),
                const SizedBox(height: 18),
                Expanded(child: knob),
              ]);
            }),
    );
  }
}

/// Short app name from a Windows media session id. Store apps look like
/// "SpotifyAB.SpotifyMusic_zpdnekdrzrea0!Spotify" (→ "SpotifyMusic"); desktop
/// apps like "Spotify.exe" or "Comet.KVLEPZX…" (→ "Spotify", "Comet"). Hash
/// ids, which some browsers use, give null.
String? mediaAppName(String? id) {
  if (id == null || id.isEmpty) return null;
  String name;
  if (id.contains('!')) {
    name = id.split('!').first.split('_').first.split('.').last;
  } else {
    name = id.split('\\').last;
    if (name.toLowerCase().endsWith('.exe')) name = name.substring(0, name.length - 4);
    name = name.split('.').first;
  }
  if (RegExp(r'^[0-9A-F]{8,}$').hasMatch(name)) return null;
  return name.isEmpty ? null : name;
}

/// A slim LCD strip with what the PC is playing right now.
class _NowPlaying extends StatelessWidget {
  const _NowPlaying({required this.session, required this.pcName});

  final Map<String, dynamic>? session;
  final String? pcName;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final title = (s?['title'] as String? ?? '').trim();
    final artist = (s?['artist'] as String? ?? '').trim();
    final app = mediaAppName(s?['app'] as String?);
    final playing = s?['playing'] == true;
    final idle = s == null || title.isEmpty;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Deck.lcd,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1C1C23)),
      ),
      child: Row(children: [
        Icon(
          idle ? Icons.music_off_rounded : (playing ? Icons.graphic_eq_rounded : Icons.pause_rounded),
          size: 16,
          color: idle ? Deck.faint : (playing ? Deck.accent : Deck.muted),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text.rich(
              key: ValueKey('$title|$artist'),
              TextSpan(children: [
                TextSpan(
                  text: idle ? 'Nothing playing on ${pcName ?? 'your PC'}' : title,
                  style: TextStyle(color: idle ? Deck.muted : Deck.text, fontWeight: FontWeight.w600),
                ),
                if (!idle && artist.isNotEmpty)
                  TextSpan(text: '  ·  $artist', style: const TextStyle(color: Deck.muted)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ),
        if (!idle && app != null) ...[
          const SizedBox(width: 10),
          Text(app.toUpperCase(), style: capsLabel(size: 9)),
        ],
      ]),
    );
  }
}
