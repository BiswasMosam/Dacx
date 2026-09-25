import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// One physical key: a bevelled cap with a small LCD inset, like a
/// Stream Deck button. It fills whatever box its parent gives it, so the
/// same key works as a square on the deck and as a tall bar on Media.
class DeckKey extends StatefulWidget {
  const DeckKey({
    super.key,
    this.child,
    this.onTap,
    this.glow,
    this.lit = false,
    this.lcd,
  });

  /// What's drawn on the LCD.
  final Widget? child;
  final VoidCallback? onTap;

  /// Backlight colour. The key glows softly with it, and brighter when [lit].
  final Color? glow;
  final bool lit;

  /// LCD background; defaults to near black.
  final Decoration? lcd;

  @override
  State<DeckKey> createState() => _DeckKeyState();
}

class _DeckKeyState extends State<DeckKey> {
  bool _down = false;

  void _press(bool down) {
    if (widget.onTap == null || _down == down) return;
    if (down) HapticFeedback.lightImpact();
    setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final glow = widget.glow;
    final active = widget.onTap != null;
    return LayoutBuilder(builder: (context, box) {
      final side = box.biggest.shortestSide;
      final radius = (side * 0.16).clamp(8.0, 22.0);
      final inset = (side * 0.065).clamp(4.0, 9.0);
      final glowAlpha = glow == null ? 0.0 : (_down ? 0.55 : widget.lit ? 0.4 : 0.14);

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _press(true),
        onTapUp: (_) => _press(false),
        onTapCancel: () => _press(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.93 : 1,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.all(inset),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: active
                    ? const [Deck.bezelTop, Deck.bezelBottom]
                    : const [Color(0xFF131317), Color(0xFF09090B)],
              ),
              border: Border.all(
                color: active ? Deck.edge : const Color(0xFF1A1A20),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.7),
                  blurRadius: _down ? 4 : 14,
                  offset: Offset(0, _down ? 2 : 7),
                ),
                if (glowAlpha > 0)
                  BoxShadow(
                    color: glow!.withValues(alpha: glowAlpha),
                    blurRadius: _down ? 28 : 22,
                    spreadRadius: _down ? 1 : -2,
                  ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius * 0.62),
              child: DecoratedBox(
                decoration: widget.lcd ?? const BoxDecoration(color: Deck.lcd),
                position: DecorationPosition.background,
                child: Stack(fit: StackFit.expand, children: [
                  if (widget.child != null) widget.child!,
                  // The pressed LCD brightens a touch, like a backlight flare.
                  IgnorePointer(
                    child: AnimatedOpacity(
                      opacity: _down ? 1 : 0,
                      duration: const Duration(milliseconds: 90),
                      child: ColoredBox(
                        color: (glow ?? Colors.white).withValues(alpha: 0.12),
                      ),
                    ),
                  ),
                  // Glass sheen across the top of the LCD.
                  const IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.center,
                          colors: [Color(0x14FFFFFF), Color(0x00FFFFFF)],
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
    });
  }
}

/// Icon over a caps label, the standard face for a key's LCD.
class KeyFace extends StatelessWidget {
  const KeyFace({super.key, required this.icon, required this.label, this.color = Deck.text, this.led});

  final Widget icon;
  final String label;
  final Color color;

  /// A small status light in the top corner, or null for none.
  final Color? led;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final s = box.biggest.shortestSide;
      final labelSize = (s * 0.13).clamp(8.0, 12.0);
      return Stack(children: [
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.only(bottom: labelSize * 1.6),
            child: Center(child: icon),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: s * 0.1,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: capsLabel(color: color.withValues(alpha: 0.72), size: labelSize),
          ),
        ),
        if (led != null)
          Positioned(
            top: s * 0.1,
            right: s * 0.1,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: led,
                boxShadow: [BoxShadow(color: led!.withValues(alpha: 0.8), blurRadius: 6)],
              ),
            ),
          ),
      ]);
    });
  }
}

/// A small square key used as a back button in page headers.
class BackKey extends StatelessWidget {
  const BackKey({super.key, this.color = Deck.text});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 44,
      child: DeckKey(
        onTap: () => Navigator.of(context).maybePop(),
        child: Icon(Icons.arrow_back_rounded, color: color, size: 20),
      ),
    );
  }
}
