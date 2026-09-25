import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/io.dart';

/// unpaired: no PC saved, the pair screen shows.
/// connecting: first handshake with a PC the user just picked.
/// online: paired and talking.
/// reconnecting: paired, but the socket dropped; retrying in the background.
enum LinkState { unpaired, connecting, online, reconnecting }

class DeckError implements Exception {
  DeckError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Where a PC lives. Comes from the desktop's QR code or is typed in.
class PcAddress {
  const PcAddress(this.host, this.port, this.code);
  final String host;
  final int port;
  final String code;

  static const defaultPort = 9876;
  static final _code = RegExp(r'^\d{6}$');

  /// The desktop's QR: dacx://192.168.1.11:9876?code=372231
  static PcAddress? fromQr(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != 'dacx' || uri.host.isEmpty) return null;
    final code = uri.queryParameters['code'] ?? '';
    if (!_code.hasMatch(code)) return null;
    return PcAddress(uri.host, uri.hasPort ? uri.port : defaultPort, code);
  }

  /// "192.168.1.11" or "192.168.1.11:9876", plus the 6-digit code.
  static PcAddress? fromInput(String address, String code) {
    final a = address.trim();
    final c = code.replaceAll(' ', '');
    if (a.isEmpty || !_code.hasMatch(c)) return null;
    final colon = a.lastIndexOf(':');
    if (colon == -1) return PcAddress(a, defaultPort, c);
    final port = int.tryParse(a.substring(colon + 1));
    if (port == null || port <= 0 || port > 65535) return null;
    return PcAddress(a.substring(0, colon), port, c);
  }

  String get label => port == defaultPort ? host : '$host:$port';
}

enum _Open { ok, wrongCode, unreachable, cancelled }

/// The one WebSocket to the Dacx desktop app: pairing, request/reply, and
/// reconnecting quietly when the WiFi blinks.
class DeckLink extends ChangeNotifier {
  LinkState _state = LinkState.unpaired;
  LinkState get state => _state;
  bool get online => state == LinkState.online;

  PcAddress? _pc;
  PcAddress? get pc => _pc;

  /// The PC's hostname, sent back when pairing succeeds.
  String? pcName;

  /// Last address typed or scanned, to prefill the pair screen.
  String? lastAddress;

  /// Shown on the pair screen after the saved code stopped working.
  String? notice;

  IOWebSocketChannel? _ch;
  StreamSubscription? _sub;
  Completer<String?>? _auth;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  int _nextId = 1;
  int _session = 0;
  int _attempt = 0;
  bool _dialing = false;
  Timer? _retry;

  void _set(LinkState s) {
    if (_state == s) return;
    _state = s;
    notifyListeners();
  }

  // ── Saved PC ──────────────────────────────────────────────────────────────

  Future<void> restore() async {
    final p = await SharedPreferences.getInstance();
    lastAddress = p.getString('pc.last');
    final host = p.getString('pc.host');
    final code = p.getString('pc.code');
    if (host == null || code == null) return;
    _pc = PcAddress(host, p.getInt('pc.port') ?? PcAddress.defaultPort, code);
    pcName = p.getString('pc.name');
    _set(LinkState.reconnecting);
    unawaited(_dial());
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    final pc = _pc!;
    await p.setString('pc.host', pc.host);
    await p.setInt('pc.port', pc.port);
    await p.setString('pc.code', pc.code);
    await p.setString('pc.name', pcName ?? pc.host);
    await p.setString('pc.last', pc.label);
  }

  Future<void> _clearSaved() async {
    final p = await SharedPreferences.getInstance();
    for (final k in ['pc.host', 'pc.port', 'pc.code', 'pc.name']) {
      await p.remove(k);
    }
  }

  // ── Pairing ───────────────────────────────────────────────────────────────

  /// Pairs with [pc]. Returns null on success, or a message to show.
  Future<String?> pair(PcAddress pc) async {
    _teardown();
    _pc = pc;
    lastAddress = pc.label;
    notice = null;
    _set(LinkState.connecting);
    final r = await _open();
    if (r == _Open.ok) {
      await _save();
      return null;
    }
    _pc = null;
    _set(LinkState.unpaired);
    return switch (r) {
      _Open.wrongCode => "That code didn't match. Check the code on your PC.",
      _ => "Couldn't reach ${pc.label}. Is Dacx open on your PC, "
          'and are both on the same WiFi?',
    };
  }

  Future<void> unpair() async {
    _teardown();
    _pc = null;
    pcName = null;
    await _clearSaved();
    _set(LinkState.unpaired);
  }

  /// Called when the app comes back to the foreground.
  void wake() {
    if (_state == LinkState.reconnecting) {
      _attempt = 0;
      unawaited(_dial());
    }
  }

  // ── Socket ────────────────────────────────────────────────────────────────

  Future<_Open> _open() async {
    final session = ++_session;
    final pc = _pc!;
    try {
      final ch = IOWebSocketChannel.connect(
        Uri(scheme: 'ws', host: pc.host, port: pc.port),
        connectTimeout: const Duration(seconds: 5),
        // A dead WiFi link otherwise goes unnoticed until the next tap. Not
        // shorter: busy WiFi can hold a pong back for a few seconds.
        pingInterval: const Duration(seconds: 10),
      );
      await ch.ready;
      if (session != _session) {
        unawaited(ch.sink.close());
        return _Open.cancelled;
      }
      _ch = ch;
      final auth = _auth = Completer<String?>();
      _sub = ch.stream.listen(
        (d) => _onData(session, d),
        onDone: () => _onClosed(session),
        onError: (_) => _onClosed(session),
      );
      ch.sink.add(jsonEncode({'type': 'auth', 'code': pc.code, 'name': 'Dacx Mobile'}));

      final host = await auth.future.timeout(const Duration(seconds: 5));
      if (session != _session) return _Open.cancelled;
      if (host == null) {
        _closeSocket();
        return _Open.wrongCode;
      }
      pcName = host.isEmpty ? pc.host : host;
      _attempt = 0;
      _set(LinkState.online);
      return _Open.ok;
    } catch (_) {
      if (session != _session) return _Open.cancelled;
      _closeSocket();
      return _Open.unreachable;
    }
  }

  Future<void> _dial() async {
    _retry?.cancel();
    if (_pc == null || _dialing) return;
    _dialing = true;
    final _Open r;
    try {
      r = await _open();
    } finally {
      _dialing = false;
    }
    if (r == _Open.ok || r == _Open.cancelled) return;
    if (r == _Open.wrongCode) {
      // The desktop makes a fresh code each time it starts.
      notice = '${pcName ?? 'Your PC'} has a new pairing code. Scan it again.';
      final keep = _pc!.label;
      await unpair();
      lastAddress = keep;
      notifyListeners();
      return;
    }
    final wait = Duration(seconds: min(8, 1 << min(_attempt++, 3)));
    _retry = Timer(wait, _dial);
  }

  void _onData(int session, dynamic raw) {
    if (session != _session || raw is! String) return;
    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (msg['type']) {
      case 'auth_ok':
        _auth?.complete(msg['host'] as String? ?? '');
      case 'auth_fail':
        _auth?.complete(null);
      case 'result':
        _pending.remove(msg['id'])?.complete(msg);
      case 'error':
        _pending.remove(msg['id'])?.completeError(
            DeckError(msg['message'] as String? ?? 'Something went wrong on your PC'));
    }
  }

  void _onClosed(int session) {
    if (session != _session) return;
    final auth = _auth;
    if (auth != null && !auth.isCompleted) auth.completeError(DeckError('closed'));
    _failPending('Lost the connection to your PC');
    _closeSocket();
    if (_state == LinkState.online) {
      _set(LinkState.reconnecting);
      _retry = Timer(const Duration(milliseconds: 600), _dial);
    }
  }

  void _failPending(String why) {
    final all = _pending.values.toList();
    _pending.clear();
    for (final c in all) {
      c.completeError(DeckError(why));
    }
  }

  void _closeSocket() {
    _sub?.cancel();
    _sub = null;
    _ch?.sink.close();
    _ch = null;
  }

  void _teardown() {
    _session++;
    _retry?.cancel();
    _failPending('Disconnected');
    _closeSocket();
  }

  // ── Requests ──────────────────────────────────────────────────────────────

  /// Sends one command and waits for its reply. During a short reconnect it
  /// waits a moment for the link to come back instead of failing the tap.
  Future<Map<String, dynamic>> send(String type, [Map<String, dynamic> args = const {}]) async {
    if (!online && _state == LinkState.reconnecting) {
      wake();
      await _backOnline(const Duration(seconds: 4));
    }
    final ch = _ch;
    if (!online || ch == null) throw DeckError('Not connected to your PC');
    final id = _nextId++;
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    ch.sink.add(jsonEncode({'type': type, ...args, 'id': id}));
    return c.future.timeout(const Duration(seconds: 8), onTimeout: () {
      _pending.remove(id);
      throw DeckError('Your PC took too long to answer');
    });
  }

  Future<void> _backOnline(Duration within) async {
    if (online) return;
    final back = Completer<void>();
    void check() {
      if (online && !back.isCompleted) back.complete();
    }

    addListener(check);
    try {
      await back.future.timeout(within);
    } on TimeoutException {
      // send() reports it.
    } finally {
      removeListener(check);
    }
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }
}

/// Gives every screen the link and rebuilds them when its state changes.
class LinkScope extends InheritedNotifier<DeckLink> {
  const LinkScope({super.key, required DeckLink link, required super.child})
      : super(notifier: link);

  static DeckLink of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LinkScope>()!.notifier!;

  /// Reads the link without subscribing to its changes.
  static DeckLink read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<LinkScope>()!.notifier!;
}
