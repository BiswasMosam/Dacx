import 'package:flutter/material.dart';

/// Colours for the deck itself. The desktop app uses the same violet.
class Deck {
  static const bg = Color(0xFF060608);
  static const body = Color(0xFF0D0D11);
  static const bezelTop = Color(0xFF1C1C23);
  static const bezelBottom = Color(0xFF0B0B0E);
  static const edge = Color(0xFF2A2A33);
  static const lcd = Color(0xFF040405);
  static const text = Color(0xFFECECF1);
  static const muted = Color(0xFF7A7A86);
  static const faint = Color(0xFF3A3A44);
  static const accent = Color(0xFF8B5CF6);
  static const accentDeep = Color(0xFF6D28D9);
  static const ok = Color(0xFF34D399);
  static const warn = Color(0xFFF5A524);
  static const danger = Color(0xFFF43F5E);
}

/// Black and green, for everything Spotify.
class Sp {
  static const bg = Color(0xFF000000);
  static const surface = Color(0xFF121212);
  static const raised = Color(0xFF1F1F1F);
  static const green = Color(0xFF1ED760);
  static const greenDeep = Color(0xFF169C46);
  static const text = Color(0xFFFFFFFF);
  static const sub = Color(0xFFB3B3B3);
  static const dim = Color(0xFF535353);
}

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Deck.accent,
      brightness: Brightness.dark,
      surface: Deck.bg,
    ),
    scaffoldBackgroundColor: Deck.bg,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: Deck.text,
      displayColor: Deck.text,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: Deck.accent,
      selectionHandleColor: Deck.accent,
    ),
  );
}

/// Small caps label used across the deck: "MEDIA", "VOLUME".
TextStyle capsLabel({Color color = Deck.muted, double size = 11}) => TextStyle(
      color: color,
      fontSize: size,
      fontWeight: FontWeight.w700,
      letterSpacing: size * 0.16,
    );

String fmtTime(int ms) {
  final s = (ms / 1000).floor().clamp(0, 359999);
  final m = s ~/ 60;
  return '$m:${(s % 60).toString().padLeft(2, '0')}';
}
