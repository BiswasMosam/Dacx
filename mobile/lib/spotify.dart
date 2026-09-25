import 'dart:math';

import 'package:flutter/material.dart';

import 'theme.dart';

/// What Spotify is doing right now, as the desktop reports it.
class SpStatus {
  SpStatus.fromJson(Map<String, dynamic> j)
      : playing = j['playing'] == true,
        trackId = j['trackId'] as String?,
        track = j['track'] as String? ?? '',
        artist = j['artist'] as String? ?? '',
        album = j['album'] as String? ?? '',
        art = j['albumArt'] as String?,
        progress = (j['progress'] as num?)?.toInt() ?? 0,
        duration = (j['duration'] as num?)?.toInt() ?? 0,
        shuffle = j['shuffle'] == true,
        repeat = j['repeat'] as String? ?? 'off',
        volume = (j['volume'] as num?)?.toInt(),
        supportsVolume = j['supportsVolume'] != false,
        deviceId = j['deviceId'] as String?,
        deviceName = j['deviceName'] as String?,
        deviceType = j['deviceType'] as String?;

  const SpStatus._(this.playing, this.trackId, this.track, this.artist, this.album, this.art,
      this.progress, this.duration, this.shuffle, this.repeat, this.volume, this.supportsVolume,
      this.deviceId, this.deviceName, this.deviceType);

  final bool playing;
  final String? trackId;
  final String track;
  final String artist;
  final String album;
  final String? art;
  final int progress;
  final int duration;
  final bool shuffle;
  final String repeat; // off | context | track
  final int? volume;
  final bool supportsVolume;
  final String? deviceId;
  final String? deviceName;
  final String? deviceType;

  bool get hasTrack => track.isNotEmpty;

  SpStatus copyWith({bool? playing, bool? shuffle, String? repeat, int? volume, int? progress}) =>
      SpStatus._(playing ?? this.playing, trackId, track, artist, album, art, progress ?? this.progress,
          duration, shuffle ?? this.shuffle, repeat ?? this.repeat, volume ?? this.volume,
          supportsVolume, deviceId, deviceName, deviceType);
}

class SpTrack {
  SpTrack.fromJson(Map<String, dynamic> j)
      : name = j['name'] as String? ?? '',
        artist = j['artist'] as String? ?? '',
        image = j['image'] as String?;

  final String name;
  final String artist;
  final String? image;
}

class SpDevice {
  SpDevice.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String? ?? '',
        name = j['name'] as String? ?? 'Unknown device',
        type = j['type'] as String? ?? '',
        active = j['active'] == true;

  final String id;
  final String name;
  final String type;
  final bool active;

  IconData get icon => switch (type.toLowerCase()) {
        'computer' => Icons.computer_rounded,
        'smartphone' => Icons.smartphone_rounded,
        'tablet' => Icons.tablet_android_rounded,
        'speaker' => Icons.speaker_rounded,
        'tv' => Icons.tv_rounded,
        'castvideo' || 'castaudio' => Icons.cast_rounded,
        'gameconsole' => Icons.sports_esports_rounded,
        'automobile' => Icons.directions_car_rounded,
        _ => Icons.devices_other_rounded,
      };
}

/// The three-wave Spotify mark, drawn rather than shipped as an image.
class SpotifyGlyph extends StatelessWidget {
  const SpotifyGlyph({super.key, this.size = 24, this.color = Sp.green, this.ink = Colors.black});
  final double size;
  final Color color;
  final Color ink;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _GlyphPainter(color, ink));
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.color, this.ink);
  final Color color;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final r = min(size.width, size.height) / 2;
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, r, Paint()..color = color);
    final waves = [(-0.26, 0.62, 0.14), (0.02, 0.52, 0.115), (0.27, 0.42, 0.09)];
    for (final (y, half, w) in waves) {
      final p = Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = r * w;
      final left = c + Offset(-half * r, (y + 0.02) * r);
      final right = c + Offset(half * r * 0.94, (y + 0.1) * r);
      final ctrl = c + Offset(-0.06 * r, (y - 0.2) * r);
      canvas.drawPath(
        Path()
          ..moveTo(left.dx, left.dy)
          ..quadraticBezierTo(ctrl.dx, ctrl.dy, right.dx, right.dy),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.color != color || old.ink != ink;
}
