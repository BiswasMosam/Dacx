import 'dart:async';

import 'package:flutter/material.dart';

import 'theme.dart';

/// Runs [tick] every [every] while the app is in the foreground. Ticks never
/// overlap: asking for one while another runs queues exactly one more.
class Poller {
  Poller(this.every, this.tick);

  final Duration every;
  final Future<void> Function() tick;

  Timer? _timer;
  Timer? _soon;
  bool _busy = false;
  bool _again = false;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(every, (_) => now());
    now();
  }

  void stop() {
    _timer?.cancel();
    _soon?.cancel();
  }

  /// Polls once after [delay], for when the PC needs a moment to catch up.
  void after(Duration delay) {
    _soon?.cancel();
    _soon = Timer(delay, now);
  }

  Future<void> now() async {
    final life = WidgetsBinding.instance.lifecycleState;
    if (life != null && life != AppLifecycleState.resumed) return;
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      await tick();
    } catch (_) {
      // A missed poll is harmless; the next one catches up.
    } finally {
      _busy = false;
    }
    if (_again) {
      _again = false;
      unawaited(now());
    }
  }
}

/// Sends only the newest value, one request at a time. While a send is in
/// flight, newer values overwrite each other and only the last goes out, so
/// a fast knob turn never builds a backlog on the PC.
class LatestSender<T> {
  LatestSender(this._send);

  final Future<void> Function(T value) _send;
  T? _next;
  bool _has = false;
  bool _busy = false;

  void push(T value) {
    _next = value;
    _has = true;
    if (!_busy) _pump();
  }

  Future<void> _pump() async {
    _busy = true;
    while (_has) {
      final v = _next as T;
      _has = false;
      try {
        await _send(v);
      } catch (_) {}
    }
    _busy = false;
  }
}

void toast(BuildContext context, String message, {Color background = const Color(0xFF1C1C22)}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    content: Text(message, style: const TextStyle(color: Deck.text)),
    behavior: SnackBarBehavior.floating,
    backgroundColor: background,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    duration: const Duration(seconds: 3),
  ));
}
