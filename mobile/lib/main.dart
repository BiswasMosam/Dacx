import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'link.dart';
import 'screens/deck_screen.dart';
import 'screens/pair_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A deck is all keys: hide the status and navigation bars.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  final link = DeckLink();
  await link.restore();
  runApp(DacxApp(link: link));
}

class DacxApp extends StatefulWidget {
  const DacxApp({super.key, required this.link});
  final DeckLink link;

  @override
  State<DacxApp> createState() => _DacxAppState();
}

class _DacxAppState extends State<DacxApp> with WidgetsBindingObserver {
  final _nav = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.link.addListener(_onLink);
  }

  @override
  void dispose() {
    widget.link.removeListener(_onLink);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      widget.link.wake();
    }
  }

  /// Unpairing drops back to the pair screen, whatever page is open.
  void _onLink() {
    if (widget.link.state == LinkState.unpaired) {
      _nav.currentState?.popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LinkScope(
      link: widget.link,
      child: MaterialApp(
        title: 'Dacx',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        navigatorKey: _nav,
        builder: (context, child) => _ReconnectBanner(child: child!),
        home: const _Home(),
      ),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home();

  @override
  Widget build(BuildContext context) {
    final state = LinkScope.of(context).state;
    final pairing = state == LinkState.unpaired || state == LinkState.connecting;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      child: pairing
          ? const PairScreen(key: ValueKey('pair'))
          : const DeckScreen(key: ValueKey('deck')),
    );
  }
}

/// A small pill over every page while the link is down.
class _ReconnectBanner extends StatelessWidget {
  const _ReconnectBanner({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final link = LinkScope.of(context);
    final show = link.state == LinkState.reconnecting;
    return Stack(children: [
      child,
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(
          child: IgnorePointer(
            child: AnimatedSlide(
              offset: show ? Offset.zero : const Offset(0, -2),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              child: Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1508),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Deck.warn.withValues(alpha: 0.35)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const SizedBox.square(
                      dimension: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.6, color: Deck.warn),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Reconnecting to ${link.pcName ?? 'your PC'}…',
                      style: const TextStyle(color: Deck.warn, fontSize: 12.5, fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
