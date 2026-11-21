import 'dart:math' as math;

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';

const String _startFen = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR';

const Color _accent = Color(0xFF769656);
const Color _panel = Color(0xFF262421);
const Color _panelBorder = Color(0xFF34312D);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final ChessboardController _controller;

  Pieces _pieces = Map.of(readFen(_startFen));
  Side _sideToMove = Side.white;
  Move? _lastMove;
  Side _orientation = Side.white;

  @override
  void initState() {
    super.initState();
    _controller = ChessboardController(game: _buildGame());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Tahap UI: semua bidak boleh pindah ke kotak mana pun (tanpa validasi).
  GameData _buildGame() {
    final ValidMoves free = {
      for (final entry in _pieces.entries)
        entry.key: {
          for (final target in Square.values)
            if (target != entry.key) target,
        },
    };
    return GameData(
      fen: writeFen(_pieces),
      playerSide: PlayerSide.both,
      sideToMove: _sideToMove,
      validMoves: free,
      lastMove: _lastMove,
    );
  }

  void _onMove(Move move, {bool? viaDragAndDrop}) {
    if (move is! NormalMove) return;
    final piece = _pieces[move.from];
    if (piece == null) return;

    final next = Map.of(_pieces)..remove(move.from);
    next[move.to] = move.promotion == null
        ? piece
        : Piece(color: piece.color, role: move.promotion!);

    setState(() {
      _pieces = next;
      _lastMove = move;
      _sideToMove = piece.color == Side.white ? Side.black : Side.white;
    });
    _controller.updatePosition(_buildGame());
  }

  void _newGame() {
    setState(() {
      _pieces = Map.of(readFen(_startFen));
      _sideToMove = Side.white;
      _lastMove = null;
    });
    _controller.updatePosition(_buildGame(), animate: false);
  }

  void _flipBoard() {
    setState(() {
      _orientation = _orientation == Side.white ? Side.black : Side.white;
    });
  }

  void _undo() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Undo belum tersedia di tahap ini'),
          duration: Duration(seconds: 1),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final bool whiteBottom = _orientation == Side.white;

    final topPill = _TurnPill(
      label: whiteBottom ? 'Hitam' : 'Putih',
      dotColor: whiteBottom ? const Color(0xFF1B1B1B) : const Color(0xFFF2F2F2),
      active: _sideToMove == (whiteBottom ? Side.black : Side.white),
    );
    final bottomPill = _TurnPill(
      label: whiteBottom ? 'Putih' : 'Hitam',
      dotColor: whiteBottom ? const Color(0xFFF2F2F2) : const Color(0xFF1B1B1B),
      active: _sideToMove == (whiteBottom ? Side.white : Side.black),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Chess Rexxin',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const double hPad = 16;
            const double rankLabelWidth = 18;
            const double reservedHeight = 230;

            final double maxByWidth =
                constraints.maxWidth - (hPad * 2) - rankLabelWidth;
            final double maxByHeight = constraints.maxHeight - reservedHeight;
            final double boardSize = (math.min(maxByWidth, maxByHeight) / 8)
                    .floorToDouble() *
                8;
            final double size = math.max(boardSize, 160);

            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: hPad),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: size + rankLabelWidth,
                          child: Row(
                            children: [
                              Expanded(child: topPill),
                              const SizedBox(width: 10),
                              Expanded(child: bottomPill),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        _BoardWithCoordinates(
                          size: size,
                          rankLabelWidth: rankLabelWidth,
                          orientation: _orientation,
                          board: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Chessboard(
                              size: size,
                              controller: _controller,
                              orientation: _orientation,
                              onMove: _onMove,
                              settings: const ChessboardSettings(
                                colorScheme: ChessboardColorScheme.brown,
                                pieceAssets: PieceSet.cburnettAssets,
                                enableCoordinates: false,
                                enablePremoves: false,
                                autoQueenPromotion: true,
                                animationDuration: Duration(milliseconds: 200),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: size + rankLabelWidth,
                          child: Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _newGame,
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('New Game'),
                                  style: _buttonStyle(filled: true),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _undo,
                                  icon: const Icon(Icons.undo, size: 18),
                                  label: const Text('Undo'),
                                  style: _buttonStyle(filled: false),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _flipBoard,
                                  icon: const Icon(Icons.swap_vert, size: 18),
                                  label: const Text('Flip'),
                                  style: _buttonStyle(filled: false),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  ButtonStyle _buttonStyle({required bool filled}) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    const padding = EdgeInsets.symmetric(horizontal: 6, vertical: 14);
    const textStyle = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
    if (filled) {
      return FilledButton.styleFrom(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        shape: shape,
        padding: padding,
        textStyle: textStyle,
      );
    }
    return OutlinedButton.styleFrom(
      foregroundColor: Colors.white70,
      side: const BorderSide(color: _panelBorder),
      backgroundColor: _panel,
      shape: shape,
      padding: padding,
      textStyle: textStyle,
    );
  }
}

class _BoardWithCoordinates extends StatelessWidget {
  const _BoardWithCoordinates({
    required this.size,
    required this.rankLabelWidth,
    required this.orientation,
    required this.board,
  });

  final double size;
  final double rankLabelWidth;
  final Side orientation;
  final Widget board;

  @override
  Widget build(BuildContext context) {
    final bool white = orientation == Side.white;
    final ranks = white
        ? const ['8', '7', '6', '5', '4', '3', '2', '1']
        : const ['1', '2', '3', '4', '5', '6', '7', '8'];
    final files = white
        ? const ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h']
        : const ['h', 'g', 'f', 'e', 'd', 'c', 'b', 'a'];

    final double fontSize = (size / 8 * 0.26).clamp(9.0, 12.0);
    final style = TextStyle(
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      color: Colors.white38,
      letterSpacing: 0.2,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: rankLabelWidth,
              height: size,
              child: Column(
                children: [
                  for (final r in ranks)
                    Expanded(
                      child: Center(child: Text(r, style: style)),
                    ),
                ],
              ),
            ),
            SizedBox(width: size, height: size, child: board),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            SizedBox(width: rankLabelWidth),
            SizedBox(
              width: size,
              child: Row(
                children: [
                  for (final f in files)
                    Expanded(child: Center(child: Text(f, style: style))),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _TurnPill extends StatelessWidget {
  const _TurnPill({
    required this.label,
    required this.dotColor,
    required this.active,
  });

  final String label;
  final Color dotColor;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: active ? const Color(0xFF3A3733) : _panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: active ? _accent : _panelBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              letterSpacing: 0.3,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              color: active ? Colors.white : Colors.white54,
            ),
          ),
        ],
      ),
    );
  }
}
