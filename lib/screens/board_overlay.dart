import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';

import '../analysis/move_quality.dart';

// Warna kotak skema "brown": koordinat memakai warna kotak lawannya.
const Color _lightSquare = Color(0xFFF0D9B5);
const Color _darkSquare = Color(0xFFB58863);

/// Badge kualitas langkah (bulat, kecil) untuk ditaruh di pojok bidak.
class MoveBadge extends StatelessWidget {
  const MoveBadge({super.key, required this.quality, required this.diameter});

  final MoveQuality quality;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final String? glyph = quality.glyph;
    final Widget symbol = glyph != null
        ? Text(
            glyph,
            style: TextStyle(
              fontSize: diameter * 0.5,
              fontWeight: FontWeight.w900,
              color: quality.onColor,
              height: 1,
            ),
          )
        : Icon(quality.icon, size: diameter * 0.64, color: quality.onColor);

    return Container(
      width: diameter,
      height: diameter,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: quality.color,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0x66000000), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: symbol,
    );
  }
}

/// Lapisan di atas papan: koordinat (rank kiri-atas, file kanan-bawah) dan
/// badge kualitas di pojok kanan-atas kotak tujuan bidak yang baru bergerak.
/// Posisi koordinat dipilih agar tidak pernah bertabrakan dengan badge.
class BoardOverlay extends StatelessWidget {
  const BoardOverlay({
    super.key,
    required this.size,
    required this.orientation,
    required this.badgeKey,
    this.badgeSquare,
    this.quality,
  });

  final double size;
  final Side orientation;

  /// Berubah setiap langkah terpilih berganti, agar animasi badge diulang.
  final int badgeKey;
  final Square? badgeSquare;
  final MoveQuality? quality;

  @override
  Widget build(BuildContext context) {
    final double sq = size / 8;
    final bool white = orientation == Side.white;
    final double fontSize = math.max(8.0, math.min(11.0, sq * 0.22));

    TextStyle coordStyle(int file, int rank) => TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          height: 1,
          // a1 = kotak gelap -> (file + rank) genap = gelap.
          color: (file + rank).isEven ? _lightSquare : _darkSquare,
        );

    final List<Widget> children = <Widget>[];

    // Angka rank: pojok kiri-atas kotak pada kolom paling kiri.
    for (int row = 0; row < 8; row++) {
      final int file = white ? 0 : 7;
      final int rank = white ? 7 - row : row;
      children.add(
        Positioned(
          left: 3,
          top: row * sq + 2,
          child: Text('${rank + 1}', style: coordStyle(file, rank)),
        ),
      );
    }

    // Huruf file: pojok kanan-bawah kotak pada baris paling bawah.
    for (int col = 0; col < 8; col++) {
      final int file = white ? col : 7 - col;
      final int rank = white ? 0 : 7;
      children.add(
        Positioned(
          left: col * sq,
          top: 7 * sq,
          width: sq,
          height: sq,
          child: Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 3, bottom: 2),
              child: Text(
                String.fromCharCode(97 + file),
                style: coordStyle(file, rank),
              ),
            ),
          ),
        ),
      );
    }

    final Square? square = badgeSquare;
    final MoveQuality? q = quality;
    if (square != null && q != null) {
      final int idx = Square.values.indexOf(square);
      if (idx >= 0) {
        final int file = idx % 8;
        final int rank = idx ~/ 8;
        final int col = white ? file : 7 - file;
        final int row = white ? 7 - rank : rank;

        final double d = math.max(16.0, math.min(26.0, sq * 0.46));
        double cx = (col + 1) * sq - d * 0.28;
        double cy = row * sq + d * 0.28;
        // Selalu di dalam papan (kotak di tepi atas/kanan).
        cx = math.max(d / 2, math.min(size - d / 2, cx));
        cy = math.max(d / 2, math.min(size - d / 2, cy));

        children.add(
          Positioned(
            left: cx - d / 2,
            top: cy - d / 2,
            child: TweenAnimationBuilder<double>(
              key: ValueKey<int>(badgeKey),
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 420),
              // Muncul setelah bidak selesai berpindah.
              curve: const Interval(0.4, 1.0, curve: Curves.easeOutBack),
              builder: (context, t, child) => Opacity(
                opacity: math.max(0.0, math.min(1.0, t)),
                child: Transform.scale(scale: 0.5 + 0.5 * t, child: child),
              ),
              child: MoveBadge(quality: q, diameter: d),
            ),
          ),
        );
      }
    }

    return Stack(children: children);
  }
}
