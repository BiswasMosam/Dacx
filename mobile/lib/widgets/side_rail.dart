import 'package:flutter/material.dart';

import '../link.dart';
import '../theme.dart';
import 'deck_key.dart';

/// The slim column down the left edge. Everything that isn't a key lives
/// here (the logo or a back button, the page name, the link to the PC) so
/// the rest of the screen is all keys.
class SideRail extends StatelessWidget {
  const SideRail({super.key, this.title, this.back = false, this.mark});

  /// Page name, written up the rail. Null on the deck itself.
  final String? title;

  /// Show a back button instead of the logo.
  final bool back;

  /// A small brand mark under the back button, like the Spotify glyph.
  final Widget? mark;

  static const width = 64.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(children: [
          if (back) const BackKey() else const _Logo(),
          if (mark != null) ...[const SizedBox(height: 16), mark!],
          Expanded(
            child: title == null
                ? const SizedBox()
                : Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: Text(
                          title!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: capsLabel(color: Deck.text, size: 12).copyWith(letterSpacing: 5),
                        ),
                      ),
                    ),
                  ),
          ),
          const _LinkStatus(),
        ]),
      ),
    );
  }
}

/// The app mark: a tiny 2 × 2 deck, the same as the launcher icon.
class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    Widget cell(Color c) => Container(
          width: 15,
          height: 15,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
        );
    return SizedBox(
      height: 44,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            cell(Deck.accent),
            const SizedBox(width: 4),
            cell(const Color(0xFF1E1E25)),
          ]),
          const SizedBox(height: 4),
          Row(mainAxisSize: MainAxisSize.min, children: [
            cell(const Color(0xFF1E1E25)),
            const SizedBox(width: 4),
            cell(Sp.green),
          ]),
        ]),
      ),
    );
  }
}

/// The PC's name written up the rail over a status light. Green when
/// connected, amber while reconnecting. Tap for the PC sheet.
class _LinkStatus extends StatelessWidget {
  const _LinkStatus();

  @override
  Widget build(BuildContext context) {
    final link = LinkScope.of(context);
    final online = link.online;
    final color = online ? Deck.ok : Deck.warn;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showPcSheet(context, link),
      child: SizedBox(
        width: SideRail.width,
        child: Column(children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 150),
            child: RotatedBox(
              quarterTurns: 3,
              child: Text(
                online ? (link.pcName ?? 'Connected').toUpperCase() : 'RECONNECTING',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: capsLabel(color: online ? Deck.muted : Deck.warn, size: 10).copyWith(letterSpacing: 3),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox.square(
            dimension: 36,
            child: Stack(alignment: Alignment.center, children: [
              if (!online)
                const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Deck.warn),
                ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.7), blurRadius: 8)],
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

void showPcSheet(BuildContext context, DeckLink link) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF0E0E12),
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(link.online ? 'PAIRED PC' : 'RECONNECTING TO', style: capsLabel()),
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
