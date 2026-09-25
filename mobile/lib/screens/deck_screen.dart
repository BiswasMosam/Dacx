import 'dart:math';

import 'package:flutter/material.dart';

import '../link.dart';
import '../pacing.dart';
import '../spotify.dart';
import '../theme.dart';
import '../widgets/deck_key.dart';
import 'media_screen.dart';
import 'spotify_screen.dart';

/// The home screen: a grid of keys like a Stream Deck. 3 × 5 upright,
/// 5 × 3 on its side, so the deck turns with the phone. Unused slots stay
/// dark, ready for the next keys.
class DeckScreen extends StatefulWidget {
  const DeckScreen({super.key});

  @override
  State<DeckScreen> createState() => _DeckScreenState();
}

class _DeckScreenState extends State<DeckScreen> with SingleTickerProviderStateMixin {
  late final DeckLink _link = LinkScope.read(context);
  late final _boot = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..forward();
  // Keys show live state: Media's LED, Spotify's album art.
  late final _poll = Poller(const Duration(seconds: 4), _fetch);

  bool _mediaPlaying = false;
  SpStatus? _sp;

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
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, a, _, child) {
        final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: c,
          child: ScaleTransition(scale: Tween(begin: 0.95, end: 1.0).animate(c), child: child),
        );
      },
    ));
    if (mounted) _poll.start();
  }

  List<Widget> _keys() => [
        DeckKey(
          glow: Deck.accent,
          lit: _mediaPlaying,
          lcd: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.2),
              radius: 0.9,
              colors: [Color(0x406D28D9), Deck.lcd],
            ),
          ),
          onTap: () => _go(const MediaScreen()),
          child: KeyFace(
            icon: const _MediaGlyph(),
            label: 'MEDIA',
            led: _mediaPlaying ? Deck.ok : null,
          ),
        ),
        _SpotifyKey(status: _sp, onTap: () => _go(const SpotifyScreen())),
      ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          child: Column(children: [
            const _TopBar(),
            const SizedBox(height: 16),
            Expanded(child: LayoutBuilder(builder: _grid)),
          ]),
        ),
      ),
    );
  }

  Widget _grid(BuildContext context, BoxConstraints box) {
    final wide = box.maxWidth > box.maxHeight;
    final cols = wide ? 5 : 3, rows = wide ? 3 : 5;
    const pad = 16.0;
    const inset = pad + 1; // padding plus the body's 1px border
    final gap = (min(box.maxWidth, box.maxHeight) * 0.035).clamp(10.0, 18.0);
    final side = min(
      (box.maxWidth - inset * 2 - gap * (cols - 1)) / cols,
      (box.maxHeight - inset * 2 - gap * (rows - 1)) / rows,
    ).floorToDouble();
    final keys = _keys();

    return Center(
      child: Container(
        padding: const EdgeInsets.all(pad),
        decoration: BoxDecoration(
          color: Deck.body,
          borderRadius: BorderRadius.circular(side * 0.3),
          border: Border.all(color: const Color(0xFF1C1C23)),
          boxShadow: const [BoxShadow(color: Colors.black, blurRadius: 40, offset: Offset(0, 16))],
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var r = 0; r < rows; r++) ...[
            if (r > 0) SizedBox(height: gap),
            Row(mainAxisSize: MainAxisSize.min, children: [
              for (var c = 0; c < cols; c++) ...[
                if (c > 0) SizedBox(width: gap),
                SizedBox.square(
                  dimension: side,
                  child: _bootIn(
                    r * cols + c,
                    r * cols + c < keys.length ? keys[r * cols + c] : const DeckKey(),
                  ),
                ),
              ],
            ]),
          ],
        ]),
      ),
    );
  }

  /// Keys light up one after another when the deck first appears.
  Widget _bootIn(int i, Widget child) {
    final start = (i * 0.045).clamp(0.0, 0.6);
    final a = CurvedAnimation(parent: _boot, curve: Interval(start, start + 0.4, curve: Curves.easeOutBack));
    return AnimatedBuilder(
      animation: a,
      builder: (context, c) => Opacity(
        opacity: a.value.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.8 + 0.2 * a.value, child: c),
      ),
      child: child,
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    final link = LinkScope.of(context);
    final online = link.online;
    return Row(children: [
      Text('DACX', style: capsLabel(color: Deck.text, size: 17).copyWith(letterSpacing: 6)),
      Container(
        width: 6,
        height: 6,
        margin: const EdgeInsets.only(left: 2, bottom: 10),
        decoration: const BoxDecoration(color: Deck.accent, shape: BoxShape.circle),
      ),
      const Spacer(),
      GestureDetector(
        onTap: () => _showPc(context, link),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFF101014),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF1F1F27)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: online ? Deck.ok : Deck.warn,
                boxShadow: [BoxShadow(color: (online ? Deck.ok : Deck.warn).withValues(alpha: 0.7), blurRadius: 6)],
              ),
            ),
            const SizedBox(width: 9),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                online ? (link.pcName ?? 'Connected') : 'Reconnecting…',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
      ),
    ]);
  }

  void _showPc(BuildContext context, DeckLink link) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF0E0E12),
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('PAIRED PC', style: capsLabel()),
            const SizedBox(height: 10),
            Text(link.pcName ?? link.pc?.host ?? 'Unknown',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(link.pc?.label ?? '', style: const TextStyle(color: Deck.muted)),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(sheet).pop();
                  link.unpair();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Deck.danger,
                  side: BorderSide(color: Deck.danger.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Unpair this PC'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// ▶❚❚ drawn to sit on a key's LCD.
class _MediaGlyph extends StatelessWidget {
  const _MediaGlyph();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          final s = box.biggest.shortestSide * 0.62;
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
    canvas.drawPath(
      shape,
      Paint()
        ..color = Deck.accent.withValues(alpha: 0.8)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.06),
    );
    canvas.drawPath(
      shape,
      Paint()
        ..color = Deck.text
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_MediaGlyphPainter old) => false;
}

/// Shows the album art of whatever Spotify is playing, like the Spotify
/// plugin on a real Stream Deck. Falls back to the green mark.
class _SpotifyKey extends StatelessWidget {
  const _SpotifyKey({required this.status, required this.onTap});
  final SpStatus? status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final art = status?.art;
    return DeckKey(
      glow: Sp.green,
      lit: status?.playing == true,
      lcd: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.2),
          radius: 0.9,
          colors: [Color(0x2E1ED760), Deck.lcd],
        ),
      ),
      onTap: onTap,
      child: LayoutBuilder(builder: (context, box) {
        final s = box.biggest.shortestSide;
        if (art == null) {
          return KeyFace(icon: SpotifyGlyph(size: s * 0.4), label: 'SPOTIFY');
        }
        return Stack(fit: StackFit.expand, children: [
          Image.network(art, fit: BoxFit.cover, gaplessPlayback: true,
              errorBuilder: (_, _, _) => const SizedBox()),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.center,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0xCC000000)],
              ),
            ),
          ),
          Positioned(top: s * 0.08, right: s * 0.08, child: SpotifyGlyph(size: s * 0.2)),
          Positioned(
            left: 0,
            right: 0,
            bottom: s * 0.1,
            child: Text(
              'SPOTIFY',
              textAlign: TextAlign.center,
              style: capsLabel(color: Colors.white, size: (s * 0.13).clamp(8.0, 12.0)),
            ),
          ),
        ]);
      }),
    );
  }
}
