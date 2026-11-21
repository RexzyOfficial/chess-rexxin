import 'dart:math' as math;

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'analysis/game_line.dart';
import 'game_notifier.dart';
import 'screens/pgn_screen.dart';
import 'screens/review_screen.dart';
import 'ui_colors.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final GameNotifier _game;
  bool _resultShown = false;

  @override
  void initState() {
    super.initState();
    _game = context.read<GameNotifier>();
    _game.addListener(_onGameChanged);
  }

  @override
  void dispose() {
    _game.removeListener(_onGameChanged);
    super.dispose();
  }

  void _onGameChanged() {
    if (_game.isGameOver && !_resultShown) {
      _resultShown = true;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && _game.isGameOver) _showResultDialog();
      });
    } else if (!_game.isGameOver) {
      _resultShown = false;
    }
  }

  // Game Review hanya tersedia setelah permainan selesai.
  void _openGameReview() {
    final GameLine line;
    try {
      line = lineFromMoves(_game.playedMoves);
    } on GameLineException catch (e) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReviewScreen(
          line: line,
          title: 'Game Review',
          showArrows: false,
          autoStart: true,
          onNewGame: _game.newGame,
        ),
      ),
    );
  }

  void _openPgn() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const PgnScreen()),
    );
  }

  Future<void> _showResultDialog() {
    final String title = _game.resultTitle;
    final String reason = _game.resultReason;
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kPanel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        content: Text(
          reason,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, color: Colors.white70),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
          OutlinedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _openGameReview();
            },
            child: const Text('Game Review'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kAccent),
            onPressed: () {
              Navigator.of(ctx).pop();
              _game.newGame();
            },
            child: const Text('New Game'),
          ),
        ],
      ),
    );
  }

  // Bulatkan ke kelipatan 8 supaya kotak tajam.
  double _fit(double value) {
    final double v = (value / 8).floorToDouble() * 8;
    return math.max(v, 80);
  }

  Widget _buildBoard(GameNotifier game, double size) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Chessboard(
        size: size,
        controller: game.boardController,
        orientation: game.orientation,
        onMove: game.onMove,
        settings: const ChessboardSettings(
          colorScheme: ChessboardColorScheme.brown,
          pieceAssets: PieceSet.cburnettAssets,
          enableCoordinates: true,
          showValidMoves: true,
          enablePremoves: false,
          animationDuration: Duration(milliseconds: 200),
        ),
      ),
    );
  }

  List<Widget> _buildButtons(GameNotifier game) {
    return [
      FilledButton.icon(
        onPressed: game.newGame,
        icon: const Icon(Icons.add, size: 18),
        label: const Text('New Game'),
        style: _buttonStyle(filled: true),
      ),
      OutlinedButton.icon(
        onPressed: game.canUndo ? game.undo : null,
        icon: const Icon(Icons.undo, size: 18),
        label: const Text('Undo'),
        style: _buttonStyle(filled: false),
      ),
      OutlinedButton.icon(
        onPressed: game.flipBoard,
        icon: const Icon(Icons.swap_vert, size: 18),
        label: const Text('Flip Board'),
        style: _buttonStyle(filled: false),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final GameNotifier game = context.watch<GameNotifier>();

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 44,
        title: _StatusTitle(game: game),
        actions: [
          if (game.isGameOver)
            IconButton(
              tooltip: 'Game Review',
              icon: const Icon(Icons.insights),
              onPressed: _openGameReview,
            ),
          PopupMenuButton<String>(
            tooltip: 'Menu',
            onSelected: (value) {
              if (value == 'pgn') _openPgn();
            },
            itemBuilder: (_) => const [
              PopupMenuItem<String>(value: 'pgn', child: Text('Analyze PGN')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) {
            const double pad = 8;
            final bool wide = c.maxWidth > c.maxHeight * 1.15;
            final buttons = _buildButtons(game);

            if (wide) {
              // Landscape / split kiri-kanan: papan kiri, tombol kanan.
              const double panelW = 140;
              final double size = _fit(
                math.min(c.maxHeight - pad * 2, c.maxWidth - pad * 3 - panelW),
              );
              return Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildBoard(game, size),
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

            // Portrait / split atas-bawah: papan lalu tombol.
            const double buttonsH = 44;
            final double size = _fit(
              math.min(
                c.maxWidth - pad * 2,
                c.maxHeight - buttonsH - pad * 3,
              ),
            );
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBoard(game, size),
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
    const padding = EdgeInsets.symmetric(horizontal: 6, vertical: 10);
    const textStyle = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600);
    if (filled) {
      return FilledButton.styleFrom(
        backgroundColor: kAccent,
        foregroundColor: Colors.white,
        shape: shape,
        padding: padding,
        textStyle: textStyle,
      );
    }
    return OutlinedButton.styleFrom(
      foregroundColor: Colors.white70,
      side: const BorderSide(color: kPanelBorder),
      backgroundColor: kPanel,
      shape: shape,
      padding: padding,
      textStyle: textStyle,
    );
  }
}

/// Status di judul AppBar: giliran aktif, badge Check, atau hasil akhir.
class _StatusTitle extends StatelessWidget {
  const _StatusTitle({required this.game});

  final GameNotifier game;

  @override
  Widget build(BuildContext context) {
    final bool over = game.isGameOver;
    final bool whiteTurn = game.turn == Side.white;

    final List<Widget> children;
    if (over) {
      final String reason = game.resultReason;
      children = [
        const Icon(Icons.emoji_events_outlined, size: 18, color: Colors.amber),
        const SizedBox(width: 8),
        Text(
          game.resultTitle,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        if (reason.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text(
            '· $reason',
            style: const TextStyle(fontSize: 13, color: Colors.white60),
          ),
        ],
      ];
    } else {
      children = [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: whiteTurn ? const Color(0xFFF2F2F2) : const Color(0xFF1B1B1B),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white38),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          whiteTurn ? 'White to move' : 'Black to move',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        if (game.isCheck) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: kCheckRed,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Check',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ];
    }

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}
