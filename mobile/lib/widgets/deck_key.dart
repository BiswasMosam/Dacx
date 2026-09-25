import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// One key. Live keys are raised dark tiles (or carry their own [face]);
/// a key with no [onTap] is an empty slot and stays quiet. The key fills
/// whatever box its parent gives it: square on the deck, a tall bar on Media.
class DeckKey extends StatefulWidget {
  const DeckKey({super.key, this.child, this.onTap, this.face, this.led});

  final Widget? child;
  final VoidCallback? onTap;

  /// Background of the key, e.g. a colour gradient or album art. Defaults to
  /// the dark tile.
  final Decoration? face;

  /// A small status light in the top-right corner, or null for none.
  final Color? led;

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

  static const _tile = BoxDecoration(color: Deck.key);
  static const _slot = BoxDecoration(color: Deck.slot);

  @override
  Widget build(BuildContext context) {
    final live = widget.onTap != null;
    return LayoutBuilder(builder: (context, box) {
      final s = box.biggest.shortestSide;
      final radius = BorderRadius.circular((s * 0.16).clamp(10.0, 20.0));
      final led = widget.led;

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _press(true),
        onTapUp: (_) => _press(false),
        onTapCancel: () => _press(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.95 : 1,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          child: ClipRRect(
            borderRadius: radius,
            child: DecoratedBox(
              decoration: widget.face ?? (live ? _tile : _slot),
              child: Stack(fit: StackFit.expand, children: [
                ?widget.child,
                if (led != null)
                  Positioned(
                    top: (s * 0.09).clamp(6.0, 12.0),
                    right: (s * 0.09).clamp(6.0, 12.0),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: led,
                        boxShadow: [BoxShadow(color: led.withValues(alpha: 0.7), blurRadius: 6)],
                      ),
                    ),
                  ),
                IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _down ? 1 : 0,
                    duration: const Duration(milliseconds: 90),
                    child: const ColoredBox(color: Color(0x1AFFFFFF)),
                  ),
                ),
                // Hairline edge, drawn over any art so every key reads as a key.
                IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      border: Border.all(color: live ? const Color(0x14FFFFFF) : const Color(0x0AFFFFFF)),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
    });
  }
}

/// Icon over a caps label, the standard face for a key.
class KeyFace extends StatelessWidget {
  const KeyFace({super.key, required this.icon, required this.label, this.color = Deck.text});

  final Widget icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final s = box.biggest.shortestSide;
      final labelSize = (s * 0.11).clamp(9.0, 12.0);
      return Stack(children: [
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.only(bottom: labelSize * 1.8),
            child: Center(child: icon),
          ),
        ),
        Positioned(
          left: 4,
          right: 4,
          bottom: (s * 0.1).clamp(8.0, 16.0),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: capsLabel(color: color.withValues(alpha: 0.88), size: labelSize),
          ),
        ),
      ]);
    });
  }
}

/// A small square key used as the back button at the top of the rail.
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
