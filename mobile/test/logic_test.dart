import 'dart:async';

import 'package:dacx/link.dart';
import 'package:dacx/pacing.dart';
import 'package:dacx/screens/media_screen.dart';
import 'package:dacx/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PcAddress.fromQr', () {
    test('reads the desktop QR', () {
      final pc = PcAddress.fromQr('dacx://192.168.1.11:9876?code=372231')!;
      expect(pc.host, '192.168.1.11');
      expect(pc.port, 9876);
      expect(pc.code, '372231');
    });

    test('defaults the port', () {
      expect(PcAddress.fromQr('dacx://10.0.0.5?code=123456')!.port, PcAddress.defaultPort);
    });

    test('rejects other QR codes', () {
      expect(PcAddress.fromQr('https://example.com'), isNull);
      expect(PcAddress.fromQr('dacx://10.0.0.5:9876?code=12'), isNull);
      expect(PcAddress.fromQr('dacx://10.0.0.5:9876'), isNull);
      expect(PcAddress.fromQr('not a url at all'), isNull);
    });
  });

  group('PcAddress.fromInput', () {
    test('plain address uses the default port', () {
      final pc = PcAddress.fromInput(' 192.168.1.11 ', '372 231')!;
      expect(pc.host, '192.168.1.11');
      expect(pc.port, 9876);
      expect(pc.code, '372231');
      expect(pc.label, '192.168.1.11');
    });

    test('address with a port', () {
      final pc = PcAddress.fromInput('192.168.1.11:9000', '372231')!;
      expect(pc.port, 9000);
      expect(pc.label, '192.168.1.11:9000');
    });

    test('bad input', () {
      expect(PcAddress.fromInput('', '372231'), isNull);
      expect(PcAddress.fromInput('192.168.1.11', '3722'), isNull);
      expect(PcAddress.fromInput('192.168.1.11:99999', '372231'), isNull);
      expect(PcAddress.fromInput('192.168.1.11:abc', '372231'), isNull);
    });
  });

  test('mediaAppName', () {
    expect(mediaAppName('Spotify.exe'), 'Spotify');
    expect(mediaAppName('Comet.KVLEPZXF4RUS5KNSB43WD467EI'), 'Comet');
    expect(mediaAppName('SpotifyAB.SpotifyMusic_zpdnekdrzrea0!Spotify'), 'SpotifyMusic');
    expect(mediaAppName('Microsoft.ZuneMusic_8wekyb3d8bbwe!Microsoft.ZuneMusic'), 'ZuneMusic');
    expect(mediaAppName(r'C:\Program Files\VideoLAN\VLC\vlc.exe'), 'vlc');
    expect(mediaAppName('Chrome'), 'Chrome');
    expect(mediaAppName('308046B0AF4A39CB'), isNull);
    expect(mediaAppName(''), isNull);
    expect(mediaAppName(null), isNull);
  });

  test('fmtTime', () {
    expect(fmtTime(0), '0:00');
    expect(fmtTime(23000), '0:23');
    expect(fmtTime(71999), '1:11');
    expect(fmtTime(3600000), '60:00');
    expect(fmtTime(-5), '0:00');
  });

  test('LatestSender sends the first and the newest value, nothing in between', () async {
    final sent = <int>[];
    final gates = <Completer<void>>[];
    final s = LatestSender<int>((v) {
      sent.add(v);
      final c = Completer<void>();
      gates.add(c);
      return c.future;
    });

    s.push(1); // goes out at once
    s.push(2);
    s.push(3);
    s.push(4); // only this one waits
    await Future<void>.delayed(Duration.zero);
    expect(sent, [1]);

    gates.last.complete();
    await Future<void>.delayed(Duration.zero);
    expect(sent, [1, 4]);

    gates.last.complete();
    await Future<void>.delayed(Duration.zero);
    expect(sent, [1, 4]);
  });

  test('LatestSender keeps going after a failed send', () async {
    final sent = <int>[];
    final s = LatestSender<int>((v) async {
      sent.add(v);
      if (v == 1) throw DeckError('boom');
    });
    s.push(1);
    s.push(2);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(sent, [1, 2]);
  });
}
