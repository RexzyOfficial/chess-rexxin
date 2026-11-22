import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Kunci posisi: penempatan bidak + giliran + hak castling.
/// En passant sengaja diabaikan supaya cocok antar sumber.
String bookKey(Position pos) {
  final List<String> f = pos.fen.split(' ');
  return '${f[0]} ${f[1]} ${f[2]}';
}

/// Dijalankan di isolate terpisah: memainkan semua baris opening (UCI)
/// dan mengumpulkan kunci setiap posisi yang dilalui.
Set<String> _buildBookKeys(List<String> lines) {
  final Set<String> keys = <String>{};
  final Map<String, Position> cache = <String, Position>{
    '': Chess.initial,
  };

  for (final String line in lines) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty) continue;

    Position pos = Chess.initial;
    String prefix = '';

    for (final String uci in trimmed.split(' ')) {
      final String next = prefix.isEmpty ? uci : '$prefix $uci';
      final Position? cached = cache[next];
      if (cached != null) {
        pos = cached;
        prefix = next;
        continue;
      }
      try {
        final Move move = pos.normalizeMove(NormalMove.fromUci(uci));
        if (!pos.isLegal(move)) break;
        pos = pos.play(move);
      } catch (_) {
        break;
      }
      prefix = next;
      cache[next] = pos;
      keys.add(bookKey(pos));
    }
  }
  return keys;
}

/// Buku opening lokal dari assets/openings.txt (satu baris UCI per opening).
/// Bila asset hilang atau gagal dibaca, buku kosong dan label Book tidak muncul.
class OpeningBook {
  OpeningBook._();

  static final OpeningBook instance = OpeningBook._();

  static final String _startKey = bookKey(Chess.initial);

  Set<String> _keys = const <String>{};
  Future<void>? _loading;

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final String raw = await rootBundle.loadString('assets/openings.txt');
      _keys = await compute(_buildBookKeys, raw.split('\n'));
    } catch (_) {
      _keys = const <String>{};
    }
  }

  /// True bila posisi ini ada di salah satu baris opening (dasar label Book).
  bool contains(Position pos) =>
      _keys.isNotEmpty && _keys.contains(bookKey(pos));

  /// Seperti [contains], tetapi posisi awal standar juga dianggap buku.
  /// Dipakai untuk memilih depth analisis yang lebih rendah.
  bool isBookPosition(Position pos) {
    if (_keys.isEmpty) return false;
    final String key = bookKey(pos);
    return key == _startKey || _keys.contains(key);
  }
}
