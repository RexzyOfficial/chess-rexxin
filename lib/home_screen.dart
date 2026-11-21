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

  // Bulatkan ke kelipatan 8 supaya kotak tajam.
  double _fit(double value) {
    final double v = (value / 8).floorToDouble() * 8;
    return math.max(v, 80);
  }

  Widget _buildBoard(double size) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Chessboard(
        size: size,
        controller: _controller,
        orientation: _orientation,
        onMove: _onMove,
        settings: const ChessboardSettings(
          colorScheme: ChessboardColorScheme.brown,
          pieceAssets: PieceSet.cburnettAssets,
          enableCoordinates: true,
          showValidMoves: false,
          enablePremoves: false,
          autoQueenPromotion: true,
          animationDuration: Duration(milliseconds: 200),
        ),
      ),
    );
  }

  List<Widget> _buildButtons() {
    return [
      FilledButton.icon(
        onPressed: _newGame,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('New Game'),
        style: _buttonStyle(filled: true),
      ),
      OutlinedButton.icon(
        onPressed: _undo,
        icon: const Icon(Icons.undo, size: 18),
        label: const Text('Undo'),
        style: _buttonStyle(filled: false),
      ),
      OutlinedButton.icon(
        onPressed: _flipBoard,
        icon: const Icon(Icons.swap_vert, size: 18),
        label: const Text('Flip Board'),
        style: _buttonStyle(filled: false),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
        title: const Text(
          'Chess Rexxin',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            const double pad = 12;
            final bool wide = c.maxWidth > c.maxHeight * 1.15;

            if (wide) {
              // Landscape / split kiri-kanan: papan di kiri, tombol di kanan.
              const double panelW = 140;
              final double size = _fit(
                math.min(c.maxHeight - pad * 2, c.maxWidth - pad * 3 - panelW),
              );
              final buttons = _buildButtons();
              return Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildBoard(size),
                    const SizedBox(width: pad),
                    SizedBox(
                      width: panelW,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (int i = 0; i < buttons.length; i++) ...[
                            if (i > 0) const SizedBox(height: 8),
                            buttons[i],
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            // Portrait / split atas-bawah: papan di atas, tombol di bawah.
            const double buttonsH = 46;
            final double size = _fit(
              math.min(c.maxWidth - pad * 2, c.maxHeight - buttonsH - pad * 3),
            );
            final buttons = _buildButtons();
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBoard(size),
                  const SizedBox(height: pad),
                  SizedBox(
                    width: size,
                    height: buttonsH,
                    child: Row(
                      children: [
                        for (int i = 0; i < buttons.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(child: buttons[i]),
                        ],
                      ],
                    ),
                  ),
                ],
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
    const padding = EdgeInsets.symmetric(horizontal: 6, vertical: 12);
    const textStyle = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600);
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
