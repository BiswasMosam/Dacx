import 'dart:math';

import 'package:flutter/material.dart';

import '../link.dart';
import '../pacing.dart';
import '../spotify.dart';
import '../theme.dart';
import '../widgets/deck_key.dart';
import '../widgets/side_rail.dart';
import 'media_screen.dart';
import 'spotify_screen.dart';

/// The home screen: keys edge to edge, like a Stream Deck. The grid fills
/// everything right of the rail and picks its rows and columns so keys stay
/// close to square: 6 × 3 on a phone on its side, 3 × 7 or so upright.
/// Unused slots stay dark, ready for the next keys.
class DeckScreen extends StatefulWidget {
  const DeckScreen({super.key});

  @override
  State<DeckScreen> createState() => _DeckScreenState();
}

/// Rows and columns for a grid of near-square keys filling [size].
({int cols, int rows}) deckGrid(Size size, {double gap = 10}) {
  final wide = size.width >= size.height;
  final short = wide ? size.height : size.width;
  final long = wide ? size.width : size.height;
  // At least 3 across the short side; tablets get more, around 150 dp a key.
  final across = max(3, (short / 150).round());
  final key = (short - gap * (across - 1)) / across;
  final along = max(1, ((long + gap) / (key + gap)).round());
  return wide ? (cols: along, rows: across) : (cols: across, rows: along);
}

class _DeckScreenState extends State<DeckScreen> with SingleTickerProviderStateMixin {
  late final DeckLink _link = LinkScope.read(context);
  late final _boot = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..forward();
  // Keys show live state: Media's light, Spotify's album art.
  late final _poll = Poller(const Duration(seconds: 4), _fetch);

  bool _mediaPlaying = false;
  SpStatus? _sp;

  static const _gap = 10.0;

  @override
  void initState() {
    super.initState();
    _poll.start();
  }

  @override
  void dispose() {
    _poll.stop();
    _boot.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    if (!_link.online) return;
    final m = await _link.send('media', {'action': 'state'});
    final s = await _link.send('spotify', {'action': 'status'});
    if (!mounted) return;
    final raw = s['spotify'] as Map<String, dynamic>?;
    setState(() {
      _mediaPlaying = (m['session'] as Map?)?['playing'] == true;
      _sp = raw == null ? null : SpStatus.fromJson(raw);
    });
  }

  Future<void> _go(Widget page) async {
    _poll.stop();
    await Navigator.of(context).push(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 340),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, a, _, child) {
        final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: c,
          child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(c), child: child),
        );
      },
    ));
    if (mounted) _poll.start();
  }

  List<Widget> _keys() => [
        DeckKey(
          face: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.7, -0.8),
              radius: 1.5,
              colors: [Color(0xFF8B5CF6), Color(0xFF5B21B6), Color(0xFF2A0E5C)],
              stops: [0, 0.5, 1],
            ),
          ),
          led: _mediaPlaying ? Deck.ok : null,
          onTap: () => _go(const MediaScreen()),
          child: const KeyFace(icon: _MediaGlyph(), label: 'MEDIA'),
        ),
        _SpotifyKey(status: _sp, onTap: () => _go(const SpotifyScreen())),
      ];

  @override
  Widget build(BuildContext context) {
    final online = LinkScope.of(context).online;
    return Scaffold(
      body: SafeArea(
        child: Row(children: [
          const SideRail(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
              child: AnimatedOpacity(
                // Keys dim while the PC is out of reach.
                opacity: online ? 1 : 0.4,
                duration: const Duration(milliseconds: 300),
                child: LayoutBuilder(builder: (context, box) => _grid(box.biggest)),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _grid(Size size) {
    final (:cols, :rows) = deckGrid(size, gap: _gap);
    final keys = _keys();
    return Column(children: [
      for (var r = 0; r < rows; r++) ...[
        if (r > 0) const SizedBox(height: _gap),
        Expanded(
          child: Row(children: [
            for (var c = 0; c < cols; c++) ...[
              if (c > 0) const SizedBox(width: _gap),
              Expanded(
                child: _bootIn(
                  r * cols + c,
                  r * cols + c < keys.length ? keys[r * cols + c] : const DeckKey(),
                ),
              ),
            ],
          ]),
        ),
      ],
    ]);
  }

  /// Keys light up one after another when the deck first appears.
  Widget _bootIn(int i, Widget child) {
    final start = (i * 0.03).clamp(0.0, 0.55);
    final a = CurvedAnimation(parent: _boot, curve: Interval(start, start + 0.45, curve: Curves.easeOutCubic));
    return AnimatedBuilder(
      animation: a,
      builder: (context, c) => Opacity(
        opacity: a.value,
        child: Transform.scale(scale: 0.9 + 0.1 * a.value, child: c),
      ),
      child: child,
    );
  }
}

/// ▶❚❚ drawn to sit on a key.
class _MediaGlyph extends StatelessWidget {
  const _MediaGlyph();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final s = box.biggest.shortestSide * 0.5;
          return CustomPaint(size: Size(s, s * 0.6), painter: _MediaGlyphPainter());
        },
      );
}

class _MediaGlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final shape = Path()
      ..moveTo(w * 0.04, h * 0.08)
      ..lineTo(w * 0.46, h * 0.5)
      ..lineTo(w * 0.04, h * 0.92)
      ..close()
      ..addRRect(RRect.fromLTRBR(w * 0.58, h * 0.1, w * 0.7, h * 0.9, Radius.circular(w * 0.03)))
      ..addRRect(RRect.fromLTRBR(w * 0.82, h * 0.1, w * 0.94, h * 0.9, Radius.circular(w * 0.03)));
    canvas.drawShadow(shape, Colors.black, 4, false);
    canvas.drawPath(shape, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_MediaGlyphPainter old) => false;
}

/// Shows the album art of whatever Spotify is playing, like the Spotify
/// plugin on a real Stream Deck. Falls back to a green face with the mark.
class _SpotifyKey extends StatelessWidget {
  const _SpotifyKey({required this.status, required this.onTap});
  final SpStatus? status;
  final VoidCallback onTap;

  static const _green = BoxDecoration(
    gradient: RadialGradient(
      center: Alignment(-0.7, -0.8),
      radius: 1.5,
      colors: [Color(0xFF1ED760), Color(0xFF12803B), Color(0xFF06311A)],
      stops: [0, 0.5, 1],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final art = status?.art;
    return DeckKey(
      face: _green,
      led: status?.playing == true ? Deck.ok : null,
      onTap: onTap,
      child: LayoutBuilder(builder: (context, box) {
        final s = box.biggest.shortestSide;
        if (art == null) {
          return KeyFace(
            icon: SpotifyGlyph(size: s * 0.36, color: Colors.black, ink: Sp.green),
            label: 'SPOTIFY',
          );
        }
        return Stack(fit: StackFit.expand, children: [
          Image.network(art, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => const SizedBox()),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment(0, 0.1),
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0xD9000000)],
              ),
            ),
          ),
          Positioned(
            top: (s * 0.09).clamp(6.0, 12.0),
            left: (s * 0.09).clamp(6.0, 12.0),
            child: SpotifyGlyph(size: (s * 0.18).clamp(14.0, 26.0)),
          ),
          Positioned(
            left: 4,
            right: 4,
            bottom: (s * 0.1).clamp(8.0, 16.0),
            child: Text(
              'SPOTIFY',
              textAlign: TextAlign.center,
              style: capsLabel(color: Colors.white, size: (s * 0.11).clamp(9.0, 12.0)),
            ),
          ),
        ]);
      }),
    );
  }
}
