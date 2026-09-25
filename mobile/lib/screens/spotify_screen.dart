import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../link.dart';
import '../pacing.dart';
import '../spotify.dart';
import '../theme.dart';
import '../widgets/deck_key.dart';

enum _Panel { now, queue, devices }

/// Dacx x Spotify, in black and green. Album art on one side, the player on
/// the other; the player side swaps to the queue or the device list.
class SpotifyScreen extends StatefulWidget {
  const SpotifyScreen({super.key});

  @override
  State<SpotifyScreen> createState() => _SpotifyScreenState();
}

class _SpotifyScreenState extends State<SpotifyScreen> {
  late final DeckLink _link = LinkScope.read(context);
  late final _poll = Poller(const Duration(seconds: 2), _fetch);
  late final _volume = LatestSender<int>(
    (v) => _link.send('spotify', {'action': 'volume', 'value': v}),
  );

  bool? _authorized; // null until the PC first answers
  SpStatus? _st;
  String? _art; // shown art; swapped only once the new image has loaded
  int _misses = 0;
  _Panel _panel = _Panel.now;

  // Replies to polls that started before a tap are stale; drop them.
  int _epoch = 0;
  DateTime _holdVolume = DateTime(0);

  // Playback position between polls is estimated locally.
  int _pos = 0;
  DateTime _posAt = DateTime.now();
  final _now = ValueNotifier<int>(0);
  Timer? _ticker;
  double? _scrub;
  double? _volDrag;

  SpTrack? _current;
  List<SpTrack>? _queue;
  List<SpDevice>? _devices;
  String? _moving; // device id a transfer is in flight to

  @override
  void initState() {
    super.initState();
    _poll.start();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _now.value = _position());
  }

  @override
  void dispose() {
    _poll.stop();
    _ticker?.cancel();
    _now.dispose();
    super.dispose();
  }

  int _position() {
    final st = _st;
    if (st == null) return 0;
    if (!st.playing) return _pos;
    return min(st.duration, _pos + DateTime.now().difference(_posAt).inMilliseconds);
  }

  void _setPos(int ms) {
    _pos = ms;
    _posAt = DateTime.now();
    _now.value = _position();
  }

  // ── Talking to the PC ─────────────────────────────────────────────────────

  Future<void> _fetch() async {
    if (!_link.online) return;
    final e = _epoch;
    final r = await _link.send('spotify', {'action': 'status'});
    if (!mounted || e != _epoch) return;

    final raw = r['spotify'] as Map<String, dynamic>?;
    var next = raw == null ? null : SpStatus.fromJson(raw);
    // One empty reply is usually a Spotify API hiccup, not a stop.
    if (next == null && _st != null && ++_misses < 2) return;
    _misses = 0;
    if (next != null && _st != null && DateTime.now().isBefore(_holdVolume)) {
      next = next.copyWith(volume: _st!.volume);
    }
    setState(() {
      _authorized = r['authorized'] as bool? ?? false;
      _st = next;
    });
    if (next != null) _setPos(next.progress);
    _loadArt(next?.art);
  }

  void _loadArt(String? url) {
    if (url == _art) return;
    if (url == null) {
      setState(() => _art = null);
      return;
    }
    precacheImage(NetworkImage(url), context).whenComplete(() {
      if (mounted && _st?.art == url) setState(() => _art = url);
    });
  }

  Future<void> _cmd(String action, [Map<String, dynamic> args = const {}]) async {
    _epoch++;
    try {
      await _link.send('spotify', {'action': action, ...args});
    } on DeckError catch (e) {
      if (mounted) toast(context, e.message, background: Sp.raised);
    }
    // Spotify takes a moment to report the change.
    _poll.after(const Duration(milliseconds: 700));
  }

  void _playPause() {
    final st = _st;
    if (st == null) return;
    _setPos(_position());
    setState(() => _st = st.copyWith(playing: !st.playing));
    _cmd(st.playing ? 'pause' : 'play');
  }

  void _shuffle() {
    final st = _st!;
    setState(() => _st = st.copyWith(shuffle: !st.shuffle));
    _cmd('shuffle', {'value': !st.shuffle});
  }

  void _repeat() {
    final st = _st!;
    final next = switch (st.repeat) { 'off' => 'context', 'context' => 'track', _ => 'off' };
    setState(() => _st = st.copyWith(repeat: next));
    _cmd('repeat', {'value': next});
  }

  void _seek(int ms) {
    _setPos(ms);
    _cmd('seek', {'position': ms});
  }

  void _setVolume(int v) {
    _epoch++;
    _holdVolume = DateTime.now().add(const Duration(seconds: 2));
    setState(() => _st = _st?.copyWith(volume: v));
    _volume.push(v);
  }

  Future<void> _open(_Panel p) async {
    HapticFeedback.selectionClick();
    setState(() => _panel = p);
    if (p == _Panel.queue) await _loadQueue();
    if (p == _Panel.devices) await _loadDevices();
  }

  Future<void> _loadQueue() async {
    try {
      final r = await _link.send('spotify', {'action': 'queue'});
      if (!mounted) return;
      final cur = r['current'] as Map<String, dynamic>?;
      setState(() {
        _current = cur == null ? null : SpTrack.fromJson(cur);
        _queue = [for (final t in (r['queue'] as List? ?? const [])) SpTrack.fromJson(t as Map<String, dynamic>)];
      });
    } on DeckError catch (e) {
      if (mounted) {
        toast(context, e.message, background: Sp.raised);
        setState(() => _queue ??= const []);
      }
    }
  }

  Future<void> _loadDevices() async {
    try {
      final r = await _link.send('spotify', {'action': 'devices'});
      if (!mounted) return;
      setState(() => _devices = [
            for (final d in (r['devices'] as List? ?? const [])) SpDevice.fromJson(d as Map<String, dynamic>)
          ]);
    } on DeckError catch (e) {
      if (mounted) {
        toast(context, e.message, background: Sp.raised);
        setState(() => _devices ??= const []);
      }
    }
  }

  Future<void> _transfer(SpDevice d) async {
    setState(() => _moving = d.id);
    _epoch++;
    try {
      await _link.send('spotify', {'action': 'transfer', 'deviceId': d.id});
      await Future.delayed(const Duration(milliseconds: 600));
      await _loadDevices();
    } on DeckError catch (e) {
      if (mounted) toast(context, e.message, background: Sp.raised);
    }
    if (mounted) setState(() => _moving = null);
    _poll.after(const Duration(milliseconds: 300));
  }

  // ── Layout ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        sliderTheme: const SliderThemeData(
          trackHeight: 4,
          activeTrackColor: Sp.green,
          inactiveTrackColor: Color(0xFF3E3E3E),
          disabledActiveTrackColor: Sp.dim,
          disabledInactiveTrackColor: Color(0xFF2A2A2A),
          thumbColor: Colors.white,
          disabledThumbColor: Sp.dim,
          overlayColor: Color(0x221ED760),
          trackShape: RoundedRectSliderTrackShape(),
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6, elevation: 0, pressedElevation: 0),
          overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(color: Sp.green),
      ),
      child: Scaffold(
        backgroundColor: Sp.bg,
        body: Stack(children: [
          const Positioned.fill(child: _Glow()),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: LayoutBuilder(builder: (context, box) {
                final wide = box.maxWidth > box.maxHeight;
                return Column(children: [
                  _header(),
                  SizedBox(height: wide ? 14 : 22),
                  Expanded(child: _body(wide)),
                ]);
              }),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _header() {
    final device = _st?.deviceName;
    return Row(children: [
      const BackKey(),
      const SizedBox(width: 14),
      const SpotifyGlyph(size: 22),
      const SizedBox(width: 10),
      Text('SPOTIFY', style: capsLabel(color: Sp.text, size: 14)),
      const SizedBox(width: 16),
      Expanded(
        child: device == null
            ? const SizedBox()
            : Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            const Icon(Icons.volume_up_rounded, size: 14, color: Sp.green),
            const SizedBox(width: 6),
            Flexible(
              child: Text(device,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Sp.green, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ]),
      ),
    ]);
  }

  Widget _body(bool wide) {
    if (_authorized == null) {
      return const Center(child: SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (_authorized == false) return _NotLinked(pcName: _link.pcName);

    return LayoutBuilder(builder: (context, box) {
      if (wide) {
        final side = min(box.maxHeight, box.maxWidth * 0.42);
        return Row(children: [
          _Art(url: _art, size: side),
          SizedBox(width: max(20.0, box.maxWidth * 0.035)),
          Expanded(child: _panelView(compact: true)),
        ]);
      }
      final full = min(box.maxWidth, box.maxHeight - 300).clamp(96.0, 520.0);
      final side = _panel == _Panel.now ? full : min(full, box.maxHeight * 0.24);
      // Small phones get the one-line title and tighter spacing.
      final tight = box.maxHeight - full - 24 < 300;
      return Column(children: [
        TweenAnimationBuilder<double>(
          tween: Tween(end: side),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          builder: (_, s, _) => _Art(url: _art, size: s),
        ),
        const SizedBox(height: 24),
        Expanded(child: _panelView(compact: tight)),
      ]);
    });
  }

  Widget _panelView({required bool compact}) {
    final child = switch (_panel) {
      _Panel.now => KeyedSubtree(key: const ValueKey('now'), child: _nowPanel(compact)),
      _Panel.queue => KeyedSubtree(key: const ValueKey('queue'), child: _queuePanel()),
      _Panel.devices => KeyedSubtree(key: const ValueKey('devices'), child: _devicesPanel()),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(anim),
          child: child,
        ),
      ),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [...previous, ?current],
      ),
      child: child,
    );
  }

  // ── Now playing ───────────────────────────────────────────────────────────

  Widget _nowPanel(bool compact) {
    final st = _st;
    if (st == null || !st.hasTrack) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: compact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          const Text('Nothing playing', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            'Start Spotify on any device, or pick one here.',
            textAlign: compact ? TextAlign.start : TextAlign.center,
            style: const TextStyle(color: Sp.sub, fontSize: 14),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => _open(_Panel.devices),
            icon: const Icon(Icons.devices_rounded, size: 18),
            label: const Text('Devices'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Sp.green,
              side: const BorderSide(color: Sp.green),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.centerLeft,
            children: [...previous, ?current],
          ),
          child: Column(
            key: ValueKey(st.trackId ?? st.track),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                st.track,
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: compact ? 22 : 24, fontWeight: FontWeight.w800, height: 1.15),
              ),
              const SizedBox(height: 4),
              Text(st.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Sp.sub, fontSize: 15)),
            ],
          ),
        ),
        SizedBox(height: compact ? 10 : 18),
        _timeline(st),
        SizedBox(height: compact ? 4 : 12),
        _controls(st),
        SizedBox(height: compact ? 8 : 18),
        _bottomRow(st),
      ],
    );
  }

  Widget _timeline(SpStatus st) {
    return ValueListenableBuilder<int>(
      valueListenable: _now,
      builder: (context, pos, _) {
        final dur = max(st.duration, 1).toDouble();
        final v = (_scrub ?? pos.toDouble()).clamp(0.0, dur);
        return Column(children: [
          SizedBox(
            height: 28,
            child: Slider(
              value: v,
              max: dur,
              padding: EdgeInsets.zero,
              onChangeStart: (x) => setState(() => _scrub = x),
              onChanged: (x) => setState(() => _scrub = x),
              onChangeEnd: (x) {
                setState(() => _scrub = null);
                _seek(x.round());
              },
            ),
          ),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(fmtTime(v.round()), style: _timeStyle),
            Text(fmtTime(st.duration), style: _timeStyle),
          ]),
        ]);
      },
    );
  }

  static const _timeStyle = TextStyle(
    color: Sp.sub,
    fontSize: 11,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  Widget _controls(SpStatus st) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      _Toggle(icon: Icons.shuffle_rounded, on: st.shuffle, onTap: _shuffle),
      _Tap(icon: Icons.skip_previous_rounded, size: 38, onTap: () => _cmd('previous')),
      _PlayButton(playing: st.playing, onTap: _playPause),
      _Tap(icon: Icons.skip_next_rounded, size: 38, onTap: () => _cmd('next')),
      _Toggle(
        icon: st.repeat == 'track' ? Icons.repeat_one_rounded : Icons.repeat_rounded,
        on: st.repeat != 'off',
        onTap: _repeat,
      ),
    ]);
  }

  Widget _bottomRow(SpStatus st) {
    final canVolume = st.supportsVolume && st.volume != null;
    final vol = _volDrag ?? (st.volume ?? 0).toDouble();
    return Row(children: [
      _Tap(icon: Icons.devices_rounded, size: 22, color: Sp.sub, onTap: () => _open(_Panel.devices)),
      const SizedBox(width: 6),
      _Tap(
        icon: Icons.remove_rounded,
        size: 18,
        color: Sp.sub,
        onTap: canVolume ? () => _setVolume(max(0, (st.volume ?? 0) - 5)) : null,
      ),
      Expanded(
        child: SizedBox(
          height: 28,
          child: Slider(
            value: vol.clamp(0, 100),
            max: 100,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            onChanged: canVolume
                ? (x) {
                    setState(() => _volDrag = x);
                    _setVolume(x.round());
                  }
                : null,
            onChangeEnd: canVolume ? (_) => setState(() => _volDrag = null) : null,
          ),
        ),
      ),
      _Tap(
        icon: Icons.add_rounded,
        size: 18,
        color: Sp.sub,
        onTap: canVolume ? () => _setVolume(min(100, (st.volume ?? 0) + 5)) : null,
      ),
      const SizedBox(width: 6),
      _Tap(icon: Icons.queue_music_rounded, size: 22, color: Sp.sub, onTap: () => _open(_Panel.queue)),
    ]);
  }

  // ── Queue / Devices ───────────────────────────────────────────────────────

  Widget _queuePanel() {
    final q = _queue;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _PanelHeader(title: 'Queue', onBack: () => setState(() => _panel = _Panel.now), onRefresh: _loadQueue),
      const SizedBox(height: 8),
      Expanded(
        child: q == null
            ? const _Loading()
            : ListView(padding: EdgeInsets.zero, children: [
                if (_current != null) ...[
                  const _Caption('Now playing'),
                  _TrackRow(track: _current!, now: true),
                  const SizedBox(height: 10),
                ],
                const _Caption('Next up'),
                if (q.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Nothing queued.', style: TextStyle(color: Sp.sub)),
                  ),
                for (final t in q) _TrackRow(track: t),
              ]),
      ),
    ]);
  }

  Widget _devicesPanel() {
    final ds = _devices;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _PanelHeader(title: 'Devices', onBack: () => setState(() => _panel = _Panel.now), onRefresh: _loadDevices),
      const SizedBox(height: 8),
      Expanded(
        child: ds == null
            ? const _Loading()
            : ds.isEmpty
                ? const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'No devices found. Open Spotify on a phone, a PC or a speaker, then refresh.',
                      style: TextStyle(color: Sp.sub, height: 1.4),
                    ),
                  )
                : ListView(padding: EdgeInsets.zero, children: [
                    for (final d in ds)
                      _DeviceRow(
                        device: d,
                        busy: _moving == d.id,
                        onTap: d.active || _moving != null ? null : () => _transfer(d),
                      ),
                  ]),
      ),
    ]);
  }
}

// ── Pieces ────────────────────────────────────────────────────────────────────

/// A faint green light in the corner, so the black has some depth.
class _Glow extends StatelessWidget {
  const _Glow();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-1.1, -1.2),
            radius: 1.4,
            colors: [Color(0x221ED760), Color(0x00000000)],
          ),
        ),
      );
}

class _Art extends StatelessWidget {
  const _Art({required this.url, required this.size});
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.05 + 4);
    Widget blank() => ColoredBox(
          key: const ValueKey('none'),
          color: Sp.raised,
          child: Center(child: Icon(Icons.music_note_rounded, color: Sp.dim, size: size * 0.3)),
        );
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: const [BoxShadow(color: Color(0xCC000000), blurRadius: 40, offset: Offset(0, 16))],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 450),
            child: url == null
                ? blank()
                : Image.network(
                    url!,
                    key: ValueKey(url),
                    fit: BoxFit.cover,
                    width: size,
                    height: size,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => blank(),
                  ),
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatefulWidget {
  const _PlayButton({required this.playing, required this.onTap});
  final bool playing;
  final VoidCallback onTap;

  @override
  State<_PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<_PlayButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        HapticFeedback.lightImpact();
        setState(() => _down = true);
      },
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.9 : 1,
        duration: const Duration(milliseconds: 100),
        child: Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Sp.green,
            boxShadow: [BoxShadow(color: Sp.green.withValues(alpha: 0.3), blurRadius: 22)],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: Icon(
              widget.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              key: ValueKey(widget.playing),
              color: Colors.black,
              size: 34,
            ),
          ),
        ),
      ),
    );
  }
}

/// A bare icon with a generous hit area.
class _Tap extends StatelessWidget {
  const _Tap({required this.icon, required this.onTap, this.size = 26, this.color = Sp.text});
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      child: SizedBox(
        width: max(40, size + 12),
        height: max(40, size + 12),
        child: Icon(icon, size: size, color: onTap == null ? Sp.dim : color),
      ),
    );
  }
}

/// Shuffle and repeat: green with a dot underneath when on.
class _Toggle extends StatelessWidget {
  const _Toggle({required this.icon, required this.on, required this.onTap});
  final IconData icon;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: SizedBox(
        width: 44,
        height: 48,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 24, color: on ? Sp.green : Sp.sub),
          const SizedBox(height: 4),
          AnimatedOpacity(
            opacity: on ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: Container(
              width: 4,
              height: 4,
              decoration: const BoxDecoration(color: Sp.green, shape: BoxShape.circle),
            ),
          ),
        ]),
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.title, required this.onBack, required this.onRefresh});
  final String title;
  final VoidCallback onBack;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _Tap(icon: Icons.arrow_back_rounded, size: 22, onTap: onBack),
      const SizedBox(width: 4),
      Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      const Spacer(),
      _Tap(icon: Icons.refresh_rounded, size: 20, color: Sp.sub, onTap: onRefresh),
    ]);
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 8),
        child: Text(text.toUpperCase(), style: capsLabel(color: Sp.sub, size: 10)),
      );
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Align(
        alignment: Alignment(0, -0.6),
        child: SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      );
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.track, this.now = false});
  final SpTrack track;
  final bool now;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox.square(
            dimension: 44,
            child: track.image == null
                ? const ColoredBox(color: Sp.raised, child: Icon(Icons.music_note_rounded, color: Sp.dim, size: 18))
                : Image.network(track.image!, fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const ColoredBox(color: Sp.raised)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(track.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: now ? Sp.green : Sp.text, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(track.artist,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Sp.sub, fontSize: 13)),
          ]),
        ),
        if (now) ...[
          const SizedBox(width: 8),
          const Icon(Icons.graphic_eq_rounded, color: Sp.green, size: 18),
        ],
      ]),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device, required this.busy, required this.onTap});
  final SpDevice device;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final on = device.active;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: on ? Sp.green.withValues(alpha: 0.14) : Sp.raised,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(device.icon, color: on ? Sp.green : Sp.sub, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: on ? Sp.green : Sp.text, fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(on ? 'Listening on' : device.type,
                  style: TextStyle(color: on ? Sp.green.withValues(alpha: 0.8) : Sp.sub, fontSize: 12)),
            ]),
          ),
          if (busy)
            const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
          else if (on)
            const Icon(Icons.graphic_eq_rounded, color: Sp.green, size: 20),
        ]),
      ),
    );
  }
}

class _NotLinked extends StatelessWidget {
  const _NotLinked({required this.pcName});
  final String? pcName;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SpotifyGlyph(size: 56),
          const SizedBox(height: 20),
          const Text('Link Spotify on your PC',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text(
            'Open Dacx on ${pcName ?? 'your PC'}, press Connect on the Spotify card '
            'and sign in. This page picks it up on its own.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Sp.sub, height: 1.45),
          ),
        ]),
      ),
    );
  }
}
