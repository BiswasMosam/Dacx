import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// A rotary volume knob. Turn it with a finger in a circle; the LED ring
/// fills from − to +. Tap the centre cap to mute.
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

class _VolumeKnobState extends State<VolumeKnob> {
  double? _drag; // value while a finger is on the knob
  double _lastAngle = 0;

  double get _shown => _drag ?? widget.value.toDouble();

  double _angleOf(Offset p, Size size) =>
      atan2(p.dy - size.height / 2, p.dx - size.width / 2);

  void _panStart(DragStartDetails d, Size size) {
    _lastAngle = _angleOf(d.localPosition, size);
    setState(() => _drag = widget.value.toDouble());
  }

  void _panUpdate(DragUpdateDetails d, Size size) {
    final c = size.center(Offset.zero);
    // Near the centre a tiny move swings the angle wildly, so ignore it.
    if ((d.localPosition - c).distance < size.shortestSide * 0.1) return;
    final a = _angleOf(d.localPosition, size);
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

  void _panEnd() {
    if (_drag == null) return;
    final v = _drag!.round();
    setState(() => _drag = null);
    if (v != widget.value) widget.onChanged(v);
  }

  void _step(int by) {
    final v = (widget.value + by).clamp(0, 100);
    if (v == widget.value) return;
    HapticFeedback.selectionClick();
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = Size.square(box.biggest.shortestSide);
      final capR = size.width * 0.2;
      // − and + sit just inside the gap at the bottom, at the ends of the ring.
      final ends = size.width * 0.5 * 0.84;
      Offset endAt(double angle) =>
          size.center(Offset(cos(angle), sin(angle)) * ends);

      return Center(
        child: SizedBox.fromSize(
          size: size,
          child: Stack(children: [
            Positioned.fill(
              child: GestureDetector(
                onPanStart: (d) => _panStart(d, size),
                onPanUpdate: (d) => _panUpdate(d, size),
                onPanEnd: (_) => _panEnd(),
                onPanCancel: _panEnd,
                child: CustomPaint(
                  painter: _KnobPainter(
                    value: _shown,
                    muted: widget.muted,
                    color: widget.color,
                  ),
                ),
              ),
            ),
            // Centre cap: the reading, and tap to mute.
            Center(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.mediumImpact();
                  widget.onMute();
                },
                child: SizedBox.square(
                  dimension: capR * 2,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(
                      widget.muted ? '—' : '${_shown.round()}',
                      style: TextStyle(
                        color: widget.muted ? Deck.muted : Deck.text,
                        fontSize: capR * 0.62,
                        fontWeight: FontWeight.w300,
                        height: 1,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    SizedBox(height: capR * 0.1),
                    Text(
                      widget.muted ? 'MUTED' : 'VOLUME',
                      style: capsLabel(
                        color: widget.muted ? Deck.warn : Deck.muted,
                        size: (capR * 0.15).clamp(8.0, 12.0),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
            _endLabel('−', endAt(_start - 0.2), () => _step(-2)),
            _endLabel('+', endAt(_start + _sweep + 0.2), () => _step(2)),
          ]),
        ),
      );
    });
  }

  Widget _endLabel(String text, Offset at, VoidCallback onTap) {
    return Positioned(
      left: at.dx - 22,
      top: at.dy - 22,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: Text(text,
                style: const TextStyle(color: Deck.muted, fontSize: 22, fontWeight: FontWeight.w300)),
          ),
        ),
      ),
    );
  }
}

class _KnobPainter extends CustomPainter {
  _KnobPainter({required this.value, required this.muted, required this.color});

  final double value;
  final bool muted;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final t = value / 100;
    final lit = muted ? Deck.muted : color;

    // LED ring: 41 ticks, lit up to the value.
    const ticks = 41;
    final tickIn = r * 0.80, tickOut = r * 0.88;
    for (var i = 0; i < ticks; i++) {
      final f = i / (ticks - 1);
      final a = _start + _sweep * f;
      final on = f <= t + 1e-6 && t > 0;
      final dir = Offset(cos(a), sin(a));
      final paint = Paint()
        ..strokeWidth = r * 0.022
        ..strokeCap = StrokeCap.round
        ..color = on ? lit.withValues(alpha: 0.35 + 0.65 * f) : Deck.faint.withValues(alpha: 0.55);
      if (on && !muted) {
        canvas.drawLine(
          c + dir * tickIn,
          c + dir * tickOut,
          Paint()
            ..strokeWidth = r * 0.05
            ..strokeCap = StrokeCap.round
            ..color = lit.withValues(alpha: 0.18 * f)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
      }
      canvas.drawLine(c + dir * tickIn, c + dir * tickOut, paint);
    }

    // Knob body with a soft drop shadow.
    final bodyR = r * 0.70;
    canvas.drawCircle(
      c + Offset(0, r * 0.04),
      bodyR,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.8)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.06),
    );
    canvas.drawCircle(
      c,
      bodyR,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 1.1,
          colors: const [Color(0xFF34343E), Color(0xFF17171C), Color(0xFF0B0B0E)],
          stops: const [0, 0.55, 1],
        ).createShader(Rect.fromCircle(center: c, radius: bodyR)),
    );
    canvas.drawCircle(
      c,
      bodyR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: 0.07),
    );

    // Knurled grip. It turns with the value, so the knob looks like it rotates.
    final turn = _start + _sweep * t;
    final grip = Paint()
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.06);
    for (var i = 0; i < 72; i++) {
      final a = turn + i * 2 * pi / 72;
      final d = Offset(cos(a), sin(a));
      canvas.drawLine(c + d * (bodyR * 0.9), c + d * (bodyR * 0.985), grip);
    }

    // Pointer notch.
    final pd = Offset(cos(turn), sin(turn));
    canvas.drawLine(
      c + pd * (bodyR * 0.62),
      c + pd * (bodyR * 0.84),
      Paint()
        ..strokeWidth = r * 0.03
        ..strokeCap = StrokeCap.round
        ..color = muted ? Deck.muted : Colors.white,
    );

    // Centre cap (the inner circle in the sketch), recessed.
    final capR = r * 0.40;
    canvas.drawCircle(
      c,
      capR,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF070709), Color(0xFF15151A)],
        ).createShader(Rect.fromCircle(center: c, radius: capR)),
    );
    canvas.drawCircle(
      c,
      capR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_KnobPainter old) =>
      old.value != value || old.muted != muted || old.color != color;
}
