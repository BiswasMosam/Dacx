import 'package:dacx/link.dart';
import 'package:dacx/screens/deck_screen.dart';
import 'package:dacx/screens/media_screen.dart';
import 'package:dacx/screens/pair_screen.dart';
import 'package:dacx/screens/spotify_screen.dart';
import 'package:dacx/theme.dart';
import 'package:dacx/widgets/deck_key.dart';
import 'package:dacx/widgets/volume_knob.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers like the desktop app would, without a socket.
class FakeLink extends DeckLink {
  FakeLink({this.authorized = true, this.playing = true}) {
    pcName = 'Dexter';
  }

  final bool authorized;
  final bool playing;
  final calls = <String>[];

  @override
  LinkState get state => LinkState.online;

  @override
  Future<Map<String, dynamic>> send(String type, [Map<String, dynamic> args = const {}]) async {
    calls.add('$type.${args['action']}');
    return switch ((type, args['action'])) {
      ('media', 'state') => {
          'volume': 56,
          'muted': false,
          'session': {'app': 'Spotify.exe', 'title': 'Midnight City', 'artist': 'M83', 'playing': true},
        },
      ('spotify', 'status') => {
          'authorized': authorized,
          'spotify': playing
              ? {
                  'connected': true,
                  'playing': true,
                  'trackId': 't1',
                  'track': 'A Really Quite Long Song Title That Has To Wrap Or Clip Somewhere',
                  'artist': 'Some Artist, Another Artist',
                  'album': 'Album',
                  'albumArt': null,
                  'progress': 23000,
                  'duration': 71000,
                  'shuffle': true,
                  'repeat': 'context',
                  'volume': 64,
                  'supportsVolume': true,
                  'deviceId': 'd1',
                  'deviceName': 'DEXTER',
                  'deviceType': 'Computer',
                }
              : {'connected': true, 'playing': false},
        },
      ('spotify', 'queue') => {
          'current': {'name': 'Now', 'artist': 'A', 'image': null},
          'queue': [
            for (var i = 0; i < 12; i++) {'name': 'Queued song $i', 'artist': 'Artist $i', 'image': null},
          ],
        },
      ('spotify', 'devices') => {
          'devices': [
            {'id': 'd1', 'name': 'DEXTER', 'type': 'Computer', 'active': true},
            {'id': 'd2', 'name': 'Pixel 8', 'type': 'Smartphone', 'active': false},
          ],
        },
      _ => <String, dynamic>{},
    };
  }
}

const sizes = {
  'phone portrait': Size(392, 850),
  'phone landscape': Size(850, 392),
  'small portrait': Size(360, 640),
  'small landscape': Size(640, 360),
  'tablet portrait': Size(800, 1280),
  'tablet landscape': Size(1280, 800),
};

Future<void> _show(WidgetTester tester, Size size, DeckLink link, Widget page) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(LinkScope(
    link: link,
    child: MaterialApp(theme: buildTheme(), home: page),
  ));
  await tester.pump(const Duration(milliseconds: 50));
  await tester.pump(const Duration(milliseconds: 1200));
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  for (final MapEntry(key: name, value: size) in sizes.entries) {
    group(name, () {
      testWidgets('deck shows 15 keys, 2 of them live', (tester) async {
        await _show(tester, size, FakeLink(), const DeckScreen());
        expect(find.byType(DeckKey), findsNWidgets(15));
        // Right number of columns, and every key on screen.
        final cols = size.width > size.height ? 5 : 3;
        final keys = find.byType(DeckKey);
        final top = tester.getTopLeft(keys.at(0)).dy;
        expect(tester.getTopLeft(keys.at(cols - 1)).dy, top);
        expect(tester.getTopLeft(keys.at(cols)).dy, greaterThan(top));
        final screen = Offset.zero & size;
        for (var i = 0; i < 15; i++) {
          final r = tester.getRect(keys.at(i));
          expect(screen.contains(r.topLeft) && screen.contains(r.bottomRight - const Offset(1, 1)), isTrue,
              reason: 'key $i at $r is off screen');
        }
        expect(find.text('MEDIA'), findsOneWidget);
        expect(find.text('SPOTIFY'), findsOneWidget);
        expect(find.text('Dexter'), findsOneWidget);
        await _close(tester);
      });

      testWidgets('media page', (tester) async {
        final link = FakeLink();
        await _show(tester, size, link, const MediaScreen());
        expect(find.byType(VolumeKnob), findsOneWidget);
        expect(find.text('56'), findsOneWidget);
        expect(find.text('Midnight City'), findsNothing); // part of a rich text span
        expect(find.textContaining('Midnight City', findRichText: true), findsOneWidget);
        await tester.tap(find.text('PAUSE'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(link.calls, contains('media.pause'));
        await _close(tester);
      });

      testWidgets('spotify page: player, queue, devices', (tester) async {
        final link = FakeLink();
        await _show(tester, size, link, const SpotifyScreen());
        expect(find.text('0:23'), findsOneWidget);
        expect(find.text('1:11'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.queue_music_rounded));
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('Queue'), findsOneWidget);
        expect(find.text('Queued song 0'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.arrow_back_rounded).last);
        await tester.pump(const Duration(milliseconds: 600));
        await tester.tap(find.byIcon(Icons.devices_rounded));
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('Pixel 8'), findsOneWidget);
        expect(find.text('Listening on'), findsOneWidget);
        await _close(tester);
      });

      testWidgets('spotify page: nothing playing', (tester) async {
        await _show(tester, size, FakeLink(playing: false), const SpotifyScreen());
        expect(find.text('Nothing playing'), findsOneWidget);
        await _close(tester);
      });

      testWidgets('spotify page: not linked on the PC', (tester) async {
        await _show(tester, size, FakeLink(authorized: false), const SpotifyScreen());
        expect(find.text('Link Spotify on your PC'), findsOneWidget);
        await _close(tester);
      });

      testWidgets('pair screen', (tester) async {
        await _show(tester, size, DeckLink(), const PairScreen());
        expect(find.text('SCAN QR'), findsOneWidget);
        expect(find.text('Connect'), findsOneWidget);
        await _close(tester);
      });
    });
  }
}
