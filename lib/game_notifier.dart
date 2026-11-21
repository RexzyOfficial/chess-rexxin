import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

/// State permainan 2 pemain lokal. Semua aturan catur dari dartchess.
class GameNotifier extends ChangeNotifier {
  GameNotifier() {
    boardController = ChessboardController(game: _buildGame());
  }

  late final ChessboardController boardController;

  // _positions[0] = posisi awal; _positions.last = posisi sekarang.
  // _moves[i] = langkah yang membawa _positions[i] ke _positions[i + 1].
  final List<Position> _positions = <Position>[Chess.initial];
  final List<Move> _moves = <Move>[];

  Side _orientation = Side.white;

  Position get position => _positions.last;
  Side get turn => position.turn;
  Side get orientation => _orientation;
  Move? get lastMove => _moves.isEmpty ? null : _moves.last;
  bool get canUndo => _moves.isNotEmpty;
  bool get isCheck => position.isCheck;
  bool get isGameOver => position.isGameOver;

  /// Salinan riwayat langkah (untuk Game Review setelah game selesai).
  List<Move> get playedMoves => List<Move>.unmodifiable(_moves);

  String get resultTitle {
    final Side? winner = position.outcome?.winner;
    if (winner == Side.white) return 'White wins';
    if (winner == Side.black) return 'Black wins';
    return 'Draw';
  }

  String get resultReason {
    final Position p = position;
    if (p.isCheckmate) return 'Checkmate';
    if (p.isStalemate) return 'Stalemate';
    if (p.isInsufficientMaterial) return 'Insufficient material';
    return '';
  }

  GameData _buildGame() {
    final Position pos = position;
    return GameData(
      fen: pos.fen,
      playerSide: pos.turn == Side.white ? PlayerSide.white : PlayerSide.black,
      sideToMove: pos.turn,
      // Game selesai -> tidak ada langkah valid, papan terkunci.
      validMoves: pos.isGameOver ? const {} : makeLegalMoves(pos),
      lastMove: lastMove,
      kingSquareInCheck: pos.isCheck ? pos.board.kingOf(pos.turn) : null,
    );
  }

  void _sync({bool animate = true}) {
    boardController.updatePosition(_buildGame(), animate: animate);
    notifyListeners();
  }

  /// Dipanggil papan setelah pemain menyelesaikan langkah
  /// (promosi sudah dipilih lewat selector bawaan papan).
  void onMove(Move move, {bool? viaDragAndDrop}) {
    final Position pos = position;
    if (pos.isGameOver) {
      _sync();
      return;
    }

    final Move normalized = move is NormalMove ? pos.normalizeMove(move) : move;
    if (!pos.isLegal(normalized)) {
      // Langkah ilegal: kembalikan bidak ke posisi awal.
      _sync();
      return;
    }

    _positions.add(pos.play(normalized));
    _moves.add(move);
    _sync();
  }

  void newGame() {
    _positions
      ..clear()
      ..add(Chess.initial);
    _moves.clear();
    _sync(animate: false);
  }

  void undo() {
    if (!canUndo) return;
    _positions.removeLast();
    _moves.removeLast();
    _sync();
  }

  void flipBoard() {
    _orientation = _orientation.opposite;
    notifyListeners();
  }

  @override
  void dispose() {
    boardController.dispose();
    super.dispose();
  }
}
