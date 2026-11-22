import 'package:dartchess/dartchess.dart';

class GameLineException implements Exception {
  const GameLineException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Satu permainan: positions[0] = posisi awal, positions[k] = setelah langkah k.
class GameLine {
  const GameLine({
    required this.positions,
    required this.moves,
    required this.sans,
  });

  final List<Position> positions;
  final List<Move> moves;
  final List<String> sans;

  int get length => moves.length;

  /// Label langkah ke-[ply] (1-based), misalnya "12. Nf3" atau "12… Nc6".
  String moveLabel(int ply) {
    final Position start = positions.first;
    final int offset = start.turn == Side.black ? ply : ply - 1;
    final int number = start.fullmoves + offset ~/ 2;
    final bool white = positions[ply - 1].turn == Side.white;
    return white ? '$number. ${sans[ply - 1]}' : '$number… ${sans[ply - 1]}';
  }

  /// Kotak tempat badge kualitas ditampilkan untuk langkah ke-[ply] (1-based):
  /// kotak tujuan bidak yang bergerak. Castling -> raja (g/c-file),
  /// promosi -> kotak bidak baru.
  Square badgeSquare(int ply) {
    final String san = sans[ply - 1];
    if (san.startsWith('O-O')) {
      final bool white = positions[ply - 1].turn == Side.white;
      final bool queenSide = san.startsWith('O-O-O');
      return Square.values[(white ? 0 : 56) + (queenSide ? 2 : 6)];
    }
    final Move m = moves[ply - 1];
    if (m is NormalMove) return m.to;
    return Square.values[0];
  }
}

/// Membangun GameLine dari daftar langkah permainan lokal (dari posisi awal).
GameLine lineFromMoves(List<Move> rawMoves) {
  Position pos = Chess.initial;
  final List<Position> positions = <Position>[pos];
  final List<Move> moves = <Move>[];
  final List<String> sans = <String>[];

  try {
    for (final Move raw in rawMoves) {
      final Move move = raw is NormalMove ? pos.normalizeMove(raw) : raw;
      final (next, san) = pos.makeSan(move);
      pos = next;
      positions.add(pos);
      moves.add(move);
      sans.add(san);
    }
  } catch (_) {
    throw const GameLineException('Riwayat langkah tidak dapat diproses.');
  }

  return GameLine(positions: positions, moves: moves, sans: sans);
}

PgnGame<PgnNodeData> _parse(String text) {
  try {
    return PgnGame.parsePgn(text);
  } catch (_) {
    throw const GameLineException('Format PGN tidak dapat dibaca.');
  }
}

Position _startingPosition(PgnGame<PgnNodeData> game) {
  try {
    return PgnGame.startingPosition(game.headers);
  } catch (_) {
    throw const GameLineException('Posisi awal (FEN) pada PGN tidak valid.');
  }
}

/// Membangun GameLine dari teks PGN (mainline game pertama).
/// Melempar [GameLineException] dengan pesan jelas bila PGN tidak valid.
GameLine lineFromPgn(String text) {
  final String trimmed = text.trim();
  if (trimmed.isEmpty) {
    throw const GameLineException(
      'PGN masih kosong. Tempel teks PGN atau upload file.',
    );
  }

  final PgnGame<PgnNodeData> game = _parse(trimmed);
  Position pos = _startingPosition(game);

  final List<Position> positions = <Position>[pos];
  final List<Move> moves = <Move>[];
  final List<String> sans = <String>[];

  int ply = 0;
  for (final PgnNodeData node in game.moves.mainline()) {
    ply++;
    final Move? move = pos.parseSan(node.san);
    if (move == null) {
      throw GameLineException(
        'Langkah ke-$ply ("${node.san}") tidak valid atau ilegal pada posisinya.',
      );
    }
    final (next, san) = pos.makeSan(move);
    pos = next;
    positions.add(pos);
    moves.add(move);
    sans.add(san);
  }

  if (moves.isEmpty) {
    throw const GameLineException('PGN tidak berisi langkah.');
  }

  return GameLine(positions: positions, moves: moves, sans: sans);
}
