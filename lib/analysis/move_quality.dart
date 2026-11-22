import 'package:flutter/material.dart';

/// Label kualitas langkah. Tiap label punya warna dan simbol untuk badge di papan.
enum MoveQuality {
  brilliant('Brilliant', Color(0xFF1BACA6), Colors.white, glyph: '!!'),
  best('Best', Color(0xFF2E9E4F), Colors.white, icon: Icons.star_rounded),
  excellent('Excellent', Color(0xFF8BC34A), Colors.black, icon: Icons.thumb_up),
  good('Good', Color(0xFF3D8FE0), Colors.white, icon: Icons.check),
  book('Book', Color(0xFF8E9AAF), Colors.white, icon: Icons.menu_book),
  inaccuracy('Inaccuracy', Color(0xFFF2C500), Colors.black, glyph: '?!'),
  mistake('Mistake', Color(0xFFF08A24), Colors.black, glyph: '?'),
  miss('Miss', Color(0xFF9C5CD6), Colors.white, icon: Icons.close),
  blunder('Blunder', Color(0xFFD7302F), Colors.white, glyph: '??');

  const MoveQuality(
    this.label,
    this.color,
    this.onColor, {
    this.icon,
    this.glyph,
  });

  final String label;
  final Color color;
  final Color onColor;
  final IconData? icon;
  final String? glyph;

  /// Label dasar dari CPL saja (tanpa Book, Brilliant, Miss).
  /// 0-10 Best, 11-30 Excellent, 31-70 Good, 71-150 Inaccuracy,
  /// 151-300 Mistake, >300 Blunder.
  static MoveQuality fromCpl(int cpl) {
    if (cpl <= 10) return MoveQuality.best;
    if (cpl <= 30) return MoveQuality.excellent;
    if (cpl <= 70) return MoveQuality.good;
    if (cpl <= 150) return MoveQuality.inaccuracy;
    if (cpl <= 300) return MoveQuality.mistake;
    return MoveQuality.blunder;
  }
}
