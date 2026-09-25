import 'dart:convert';
import 'dart:io';

import 'package:dacx/link.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A stand-in for the desktop's WebSocket server, speaking the same protocol.
class FakePc {
  HttpServer? _http;
  String code = '123456';
  final sockets = <WebSocket>[];
  final seen = <Map<String, dynamic>>[];

  int get port => _http!.port;

  Future<void> start({int port = 0}) async {
    _http = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    _http!.listen((req) async {
      final ws = await WebSocketTransformer.upgrade(req);
      sockets.add(ws);
      var authed = false;
      ws.listen((raw) {
        final m = jsonDecode(raw as String) as Map<String, dynamic>;
        if (!authed) {
          if (m['type'] == 'auth' && m['code'] == code) {
            authed = true;
            ws.add(jsonEncode({'type': 'auth_ok', 'clientId': 'c1', 'host': 'TestPC'}));
          } else {
            ws.add(jsonEncode({'type': 'auth_fail', 'reason': 'wrong_code'}));
            ws.close();
          }
          return;
        }
        seen.add(m);
        if (m['type'] == 'boom') {
          ws.add(jsonEncode({'type': 'error', 'message': 'Spotify is sulking', 'id': m['id']}));
        } else if (m['type'] == 'slow') {
          // Reply to the fast one first, so ids have to sort it out.
          Future.delayed(const Duration(milliseconds: 150),
              () => ws.add(jsonEncode({'type': 'result', 'echo': 'slow', 'id': m['id']})));
        } else {
          ws.add(jsonEncode({'type': 'result', 'echo': m['type'], 'id': m['id']}));
        }
      });
    });
  }

  /// Drops every socket, like a WiFi blip.
  Future<void> dropAll() async {
    for (final s in sockets) {
      await s.close();
    }
    sockets.clear();
  }

  Future<void> stop() async => _http?.close(force: true);
}

Future<void> until(bool Function() ok, {Duration within = const Duration(seconds: 6)}) async {
  final end = DateTime.now().add(within);
  while (!ok()) {
    if (DateTime.now().isAfter(end)) fail('timed out waiting');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  late FakePc pc;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    pc = FakePc();
    await pc.start();
  });

  tearDown(() => pc.stop());

  PcAddress addr([String? code]) => PcAddress('127.0.0.1', pc.port, code ?? pc.code);

  test('wrong code is refused and nothing is saved', () async {
    final link = DeckLink();
    final err = await link.pair(addr('000000'));
    expect(err, contains("didn't match"));
    expect(link.state, LinkState.unpaired);
    expect((await SharedPreferences.getInstance()).getString('pc.host'), isNull);
    link.dispose();
  });

  test('nobody listening gives a reachability message', () async {
    final link = DeckLink();
    final err = await link.pair(const PcAddress('127.0.0.1', 1, '123456'));
    expect(err, contains("Couldn't reach"));
    expect(link.state, LinkState.unpaired);
    link.dispose();
  });

  test('pairs, saves the PC, and matches replies to requests by id', () async {
    final link = DeckLink();
    expect(await link.pair(addr()), isNull);
    expect(link.state, LinkState.online);
    expect(link.pcName, 'TestPC');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('pc.host'), '127.0.0.1');
    expect(prefs.getString('pc.code'), '123456');

    final slow = link.send('slow');
    final fast = link.send('media', {'action': 'state'});
    expect((await fast)['echo'], 'media');
    expect((await slow)['echo'], 'slow');
    expect(pc.seen.last['action'], 'state');

    await expectLater(link.send('boom'), throwsA(isA<DeckError>().having((e) => e.message, 'message', 'Spotify is sulking')));
    link.dispose();
  });

  test('reconnects on its own after the socket drops', () async {
    final link = DeckLink();
    await link.pair(addr());
    await pc.dropAll();
    await until(() => link.state == LinkState.reconnecting);
    await until(() => link.online);
    expect((await link.send('media'))['echo'], 'media');
    link.dispose();
  });

  test('a tap during a reconnect waits for the link instead of failing', () async {
    final link = DeckLink();
    await link.pair(addr());
    final port = pc.port;
    await pc.stop();
    await pc.dropAll();
    await until(() => link.state == LinkState.reconnecting);

    // The PC comes back a moment after the tap.
    final tap = link.send('media', {'action': 'play'});
    await Future<void>.delayed(const Duration(milliseconds: 300));
    pc = FakePc();
    await pc.start(port: port);
    expect((await tap)['echo'], 'media');
    link.dispose();
  });

  test('restore() reconnects to the saved PC', () async {
    final first = DeckLink();
    await first.pair(addr());
    first.dispose();

    final link = DeckLink();
    await link.restore();
    expect(link.state, isNot(LinkState.unpaired));
    await until(() => link.online);
    expect(link.pcName, 'TestPC');
    link.dispose();
  });

  test('a PC with a new code sends the phone back to pairing, address kept', () async {
    final first = DeckLink();
    await first.pair(addr());
    first.dispose();

    pc.code = '654321'; // the desktop restarted
    final link = DeckLink();
    await link.restore();
    await until(() => link.state == LinkState.unpaired);
    expect(link.notice, contains('new pairing code'));
    expect(link.lastAddress, '127.0.0.1:${pc.port}');
    expect((await SharedPreferences.getInstance()).getString('pc.code'), isNull);
    link.dispose();
  });
}
