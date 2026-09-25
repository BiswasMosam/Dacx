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
