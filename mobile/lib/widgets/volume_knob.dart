import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// A rotary volume knob that stays clean until you touch it.
///
/// At rest it is just the knob: no ring, no number, no − or +. Press and
/// hold, and it grows a little while the level ring and the number fade in;
/// turn clockwise for louder, anticlockwise for quieter. Let go and it
/// settles back. A quick tap mutes; while muted the pointer turns amber.
class VolumeKnob extends StatefulWidget {
  const VolumeKnob({
    super.key,
    required this.value,
    required this.muted,
    required this.onChanged,
    required this.onMute,
    this.color = Deck.accent,
  });

  final int value; // 0..100
  final bool muted;
  final ValueChanged<int> onChanged;
  final VoidCallback onMute;
  final Color color;

  @override
  State<VolumeKnob> createState() => _VolumeKnobState();
}

// The knob turns through 270°, from bottom-left (0) over the top to
// bottom-right (100). Angles are canvas angles: 0 = right, clockwise.
const _start = 0.75 * pi;
const _sweep = 1.5 * pi;

// A touch shorter than this that barely moves is a tap (mute), not a hold.
const _tapTime = Duration(milliseconds: 250);
const _revealDelay = Duration(milliseconds: 140);
const _slop = 8.0;

class _VolumeKnobState extends State<VolumeKnob> with SingleTickerProviderStateMixin {
  late final _hold = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    reverseDuration: const Duration(milliseconds: 320),
  );

  double? _drag; // value while turning
  double _lastAngle = 0;
  Offset _downAt = Offset.zero;
  DateTime _downTime = DateTime(0);
  bool _turning = false;
  int? _pointer;
  Timer? _reveal;

  double get _shown => _drag ?? widget.value.toDouble();

  @override
  void dispose() {
    _reveal?.cancel();
    _hold.dispose();
    super.dispose();
  }

  void _show() {
    _reveal?.cancel();
    if (_hold.status == AnimationStatus.forward || _hold.isCompleted) return;
    HapticFeedback.lightImpact();
    _hold.forward();
  }

  double _angle(Offset p, Size s) => atan2(p.dy - s.height / 2, p.dx - s.width / 2);

  void _down(PointerDownEvent e, Size size) {
    if (_pointer != null) return;
    final r = size.shortestSide / 2;
    if ((e.localPosition - size.center(Offset.zero)).distance > r) return;
    _pointer = e.pointer;
    _downAt = e.localPosition;
    _downTime = DateTime.now();
    _turning = false;
    _lastAngle = _angle(e.localPosition, size);
    _reveal = Timer(_revealDelay, _show);
  }

  void _move(PointerMoveEvent e, Size size) {
    if (e.pointer != _pointer) return;
    if (!_turning) {
      if ((e.localPosition - _downAt).distance < _slop) return;
      _turning = true;
      _show();
      setState(() => _drag = widget.value.toDouble());
    }
    // Near the centre a tiny move swings the angle wildly, so ignore it.
    if ((e.localPosition - size.center(Offset.zero)).distance < size.shortestSide * 0.08) return;
    final a = _angle(e.localPosition, size);
    var delta = a - _lastAngle;
    if (delta > pi) delta -= 2 * pi;
    if (delta < -pi) delta += 2 * pi;
    _lastAngle = a;

    final before = _drag!.round();
    final next = (_drag! + delta / _sweep * 100).clamp(0.0, 100.0);
    setState(() => _drag = next);
    final after = next.round();
    if (after != before) {
      if (after ~/ 2 != before ~/ 2) HapticFeedback.selectionClick();
      widget.onChanged(after);
    }
  }

  void _up(PointerEvent e, {bool cancelled = false}) {
    if (e.pointer != _pointer) return;
    _pointer = null;
    _reveal?.cancel();
    final quick = DateTime.now().difference(_downTime) < _tapTime;
    if (!cancelled && !_turning && quick) {
      HapticFeedback.mediumImpact();
      widget.onMute();
    }
    if (_drag != null) {
      final v = _drag!.round();
      if (v != widget.value) widget.onChanged(v);
      setState(() => _drag = null);
    }
    _turning = false;
    _hold.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      // Leave room around the knob for the ring and for it to grow.
      final size = Size.square(box.biggest.shortestSide);
      final r = size.width / 2;

      return Center(
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) => _down(e, size),
          onPointerMove: (e) => _move(e, size),
          onPointerUp: _up,
          onPointerCancel: (e) => _up(e, cancelled: true),
          child: SizedBox.fromSize(
            size: size,
            child: AnimatedBuilder(
              animation: _hold,
              builder: (context, _) {
                final t = Curves.easeOutCubic.transform(_hold.value);
                return Stack(clipBehavior: Clip.none, children: [
                  // Level ring and − / +, only while held.
                  if (t > 0)
                    Positioned.fill(
                      child: Opacity(
                        opacity: t,
                        child: CustomPaint(
                          painter: _RingPainter(value: _shown, muted: widget.muted, color: widget.color),
                        ),
                      ),
                    ),
                  if (t > 0) ...[
                    _endLabel('−', size, _start - 0.22, t),
                    _endLabel('+', size, _start + _sweep + 0.22, t),
                  ],
                  // The knob itself, a touch bigger while held.
                  Positioned.fill(
                    child: Transform.scale(
                      scale: 1 + 0.15 * t,
                      child: CustomPaint(
                        painter: _KnobPainter(value: _shown, muted: widget.muted),
                      ),
                    ),
                  ),
                  if (t > 0)
                    Center(
                      child: Opacity(
                        opacity: t,
                        child: Transform.scale(
                          scale: 0.9 + 0.17 * t,
                          child: Text(
                            widget.muted && _drag == null ? 'MUTED' : '${_shown.round()}',
                            style: widget.muted && _drag == null
                                ? capsLabel(color: Deck.warn, size: (r * 0.09).clamp(10.0, 14.0))
                                : TextStyle(
                                    color: Deck.text,
                                    fontSize: r * 0.26,
                                    fontWeight: FontWeight.w300,
                                    height: 1,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                          ),
                        ),
                      ),
                    ),
                ]);
              },
            ),
          ),
        ),
      );
    });
  }

  Widget _endLabel(String text, Size size, double angle, double t) {
    final at = size.center(Offset(cos(angle), sin(angle)) * (size.width / 2 * 0.9));
    return Positioned(
      left: at.dx - 12,
      top: at.dy - 14,
      child: Opacity(
        opacity: t,
        child: SizedBox(
          width: 24,
          height: 28,
          child: Center(
            child: Text(text, style: const TextStyle(color: Deck.muted, fontSize: 20, fontWeight: FontWeight.w300)),
          ),
        ),
      ),
    );
  }
}

/// The LED ring around the knob, shown while it's held.
class _RingPainter extends CustomPainter {
  _RingPainter({required this.value, required this.muted, required this.color});

  final double value;
  final bool muted;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final t = value / 100;
    final lit = muted ? Deck.muted : color;
    const ticks = 41;
    final tickIn = r * 0.86, tickOut = r * 0.95;
    for (var i = 0; i < ticks; i++) {
      final f = i / (ticks - 1);
      final a = _start + _sweep * f;
      final on = t > 0 && f <= t + 1e-6;
      final dir = Offset(cos(a), sin(a));
      if (on && !muted) {
        canvas.drawLine(
          c + dir * tickIn,
          c + dir * tickOut,
          Paint()
            ..strokeWidth = r * 0.05
            ..strokeCap = StrokeCap.round
            ..color = lit.withValues(alpha: 0.2 * f)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
      canvas.drawLine(
        c + dir * tickIn,
        c + dir * tickOut,
        Paint()
          ..strokeWidth = r * 0.022
          ..strokeCap = StrokeCap.round
          ..color = on ? lit.withValues(alpha: 0.4 + 0.6 * f) : Deck.faint.withValues(alpha: 0.5),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.muted != muted || old.color != color;
}

/// The knob: one flat dark disc with a small pointer dot that turns with
/// the value. Nothing else, so it reads as a single clean circle.
class _KnobPainter extends CustomPainter {
  _KnobPainter({required this.value, required this.muted});

  final double value;
  final bool muted;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final bodyR = r * 0.7; // held: 0.7 × 1.15, just inside the ring

    // One flat disc with a hairline edge. No shading: dark gradients band.
    canvas.drawCircle(c, bodyR, Paint()..color = Deck.knob);
    canvas.drawCircle(
      c,
      bodyR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.08),
    );

    // Pointer: a small dot near the edge. Amber while muted.
    final turn = _start + _sweep * (value / 100);
    final at = c + Offset(cos(turn), sin(turn)) * (bodyR * 0.82);
    final dot = muted ? Deck.warn : Colors.white;
    canvas.drawCircle(
      at,
      r * 0.03,
      Paint()
        ..color = dot.withValues(alpha: 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.02),
    );
    canvas.drawCircle(at, r * 0.022, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(_KnobPainter old) => old.value != value || old.muted != muted;
}
