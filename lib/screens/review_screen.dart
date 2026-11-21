import 'dart:math' as math;

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../analysis/analysis_controller.dart';
import '../analysis/game_line.dart';
import '../analysis/move_quality.dart';
import '../engine/uci.dart';
import '../ui_colors.dart';

const double _rowHeight = 48;

/// Layar review bersama.
/// - Game Review: autoStart = true, showArrows = false.
/// - Analyze PGN: autoStart = false (tombol "Analyze Game"), showArrows = true.
class ReviewScreen extends StatelessWidget {
  const ReviewScreen({
    super.key,
    required this.line,
    required this.title,
    required this.showArrows,
    required this.autoStart,
    this.onNewGame,
  });

  final GameLine line;
  final String title;
  final bool showArrows;
  final bool autoStart;
  final VoidCallback? onNewGame;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AnalysisController>(
      create: (_) {
        final AnalysisController controller = AnalysisController(line);
        if (autoStart) Future<void>.microtask(controller.run);
        return controller;
      },
      child: _ReviewBody(
        title: title,
        showArrows: showArrows,
        onNewGame: onNewGame,
      ),
    );
  }
}

class _ReviewBody extends StatefulWidget {
  const _ReviewBody({
    required this.title,
    required this.showArrows,
    required this.onNewGame,
  });

  final String title;
  final bool showArrows;
  final VoidCallback? onNewGame;

  @override
  State<_ReviewBody> createState() => _ReviewBodyState();
}

class _ReviewBodyState extends State<_ReviewBody> {
  late final AnalysisController _ctrl;
  late final ChessboardController _board;
  final ScrollController _scroll = ScrollController();

  int _shownIndex = 0;
  bool _flipped = false;

  @override
  void initState() {
    super.initState();
    _ctrl = context.read<AnalysisController>();
    _shownIndex = _ctrl.selectedIndex;
    _board = ChessboardController(game: _gameFor(_shownIndex));
    _ctrl.addListener(_onCtrl);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onCtrl);
    _board.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // Papan hanya untuk dilihat: tidak ada langkah valid.
  GameData _gameFor(int index) {
    final Position pos = _ctrl.line.positions[index];
    return GameData(
      fen: pos.fen,
      playerSide: PlayerSide.white,
      sideToMove: pos.turn,
      validMoves: const {},
      lastMove: index == 0 ? null : _ctrl.line.moves[index - 1],
      kingSquareInCheck: pos.isCheck ? pos.board.kingOf(pos.turn) : null,
    );
  }

  void _onCtrl() {
    final int idx = _ctrl.selectedIndex;
    if (idx == _shownIndex) return;
    _shownIndex = idx;
    _board.updatePosition(_gameFor(idx));
    _scrollTo(idx);
  }

  void _scrollTo(int index) {
    if (!_scroll.hasClients) return;
    final double target = index * _rowHeight -
        _scroll.position.viewportDimension / 2 +
        _rowHeight / 2;
    _scroll.animateTo(
      math.max(0.0, math.min(_scroll.position.maxScrollExtent, target)),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  /// Panah best move: hanya di layar analisis PGN, mengikuti posisi terpilih.
  Set<Shape> _shapes(AnalysisController c) {
    if (!widget.showArrows) return const {};
    final String? uci = c.bestMoveAt(c.selectedIndex);
    if (uci == null) return const {};
    try {
      final NormalMove move = NormalMove.fromUci(uci);
      return {
        Arrow(
          color: const Color(0xAA15781B),
          orig: move.from,
          dest: move.to,
        ),
      };
    } catch (_) {
      return const {};
    }
  }

  double _fit(double value) {
    final double v = (value / 8).floorToDouble() * 8;
    return math.max(v, 80);
  }

  Widget _buildBoard(AnalysisController c, double size) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Chessboard(
        size: size,
        controller: _board,
        orientation: _flipped ? Side.black : Side.white,
        shapes: _shapes(c),
        settings: const ChessboardSettings(
          colorScheme: ChessboardColorScheme.brown,
          pieceAssets: PieceSet.cburnettAssets,
          enableCoordinates: true,
          showValidMoves: false,
          enablePremoves: false,
          animationDuration: Duration(milliseconds: 200),
        ),
      ),
    );
  }

  void _newGame() {
    Navigator.of(context).pop();
    widget.onNewGame?.call();
  }

  @override
  Widget build(BuildContext context) {
    final AnalysisController c = context.watch<AnalysisController>();

    final Widget lower = Column(
      children: [
        _AnalysisBar(
          ctrl: c,
          onNewGame: widget.onNewGame == null ? null : _newGame,
        ),
        _SelectionInfo(ctrl: c),
        const Divider(height: 1, color: kPanelBorder),
        Expanded(child: _MoveList(ctrl: c, scroll: _scroll)),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 44,
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'Flip Board',
            icon: const Icon(Icons.swap_vert),
            onPressed: () => setState(() => _flipped = !_flipped),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, cons) {
            final bool wide = cons.maxWidth > cons.maxHeight * 1.15;

            if (wide) {
              final double size = _fit(
                math.min(cons.maxHeight - 16, cons.maxWidth * 0.55),
              );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: _buildBoard(c, size),
                  ),
                  Expanded(child: lower),
                ],
              );
            }

            final double size = _fit(
              math.min(cons.maxWidth - 16, cons.maxHeight * 0.45),
            );
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: _buildBoard(c, size),
                ),
                Expanded(child: lower),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Status analisis: tombol Analyze, progress, cancel, error, New Game.
class _AnalysisBar extends StatelessWidget {
  const _AnalysisBar({required this.ctrl, required this.onNewGame});

  final AnalysisController ctrl;
  final VoidCallback? onNewGame;

  @override
  Widget build(BuildContext context) {
    final bool running = ctrl.status == AnalysisStatus.running;

    final Widget content = switch (ctrl.status) {
      AnalysisStatus.idle => FilledButton.icon(
          onPressed: ctrl.run,
          icon: const Icon(Icons.analytics_outlined, size: 18),
          label: const Text('Analyze Game'),
          style: FilledButton.styleFrom(backgroundColor: kAccent),
        ),
      AnalysisStatus.running => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Analyzing move ${ctrl.progressMove}/${ctrl.line.length}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                OutlinedButton(
                  onPressed: ctrl.cancel,
                  child: const Text('Cancel'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ctrl.progress,
                minHeight: 6,
                color: kAccent,
                backgroundColor: kPanelBorder,
              ),
            ),
          ],
        ),
      AnalysisStatus.done => const Row(
          children: [
            Icon(Icons.check_circle, size: 18, color: kAccent),
            SizedBox(width: 8),
            Text(
              'Analysis complete',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      AnalysisStatus.cancelled => Row(
          children: [
            const Expanded(
              child: Text(
                'Analysis cancelled',
                style: TextStyle(fontSize: 14, color: Colors.white70),
              ),
            ),
            FilledButton(
              onPressed: ctrl.run,
              style: FilledButton.styleFrom(backgroundColor: kAccent),
              child: const Text('Analyze again'),
            ),
          ],
        ),
      AnalysisStatus.error => Row(
          children: [
            Expanded(
              child: Text(
                ctrl.errorMessage ?? 'Terjadi kesalahan.',
                style: const TextStyle(fontSize: 13, color: Color(0xFFFF8A80)),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: ctrl.run,
              style: FilledButton.styleFrom(backgroundColor: kAccent),
              child: const Text('Retry'),
            ),
          ],
        ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          content,
          if (onNewGame != null && !running) ...[
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: onNewGame,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New Game'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Langkah terpilih: label kualitas + evaluasi singkat, dengan tombol prev/next.
class _SelectionInfo extends StatelessWidget {
  const _SelectionInfo({required this.ctrl});

  final AnalysisController ctrl;

  @override
  Widget build(BuildContext context) {
    final int i = ctrl.selectedIndex;
    final GameLine line = ctrl.line;
    final PositionAnalysis? a = ctrl.analysisAt(i);
    final String? evalText =
        a == null ? null : formatEval(a.score, line.positions[i].turn);
    final MoveReview? review = ctrl.reviewOfPly(i);
    final String title = i == 0 ? 'Start position' : line.moveLabel(i);

    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: i > 0 ? () => ctrl.select(i - 1) : null,
        ),
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 2,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (review != null) _QualityBadge(quality: review.quality),
              if (evalText != null) _EvalChip(text: evalText),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: i < line.length ? () => ctrl.select(i + 1) : null,
        ),
      ],
    );
  }
}

class _MoveList extends StatelessWidget {
  const _MoveList({required this.ctrl, required this.scroll});

  final AnalysisController ctrl;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    final GameLine line = ctrl.line;

    return ListView.builder(
      controller: scroll,
      itemExtent: _rowHeight,
      itemCount: line.length + 1,
      itemBuilder: (context, index) {
        final PositionAnalysis? a = ctrl.analysisAt(index);
        final String? evalText =
            a == null ? null : formatEval(a.score, line.positions[index].turn);

        return _MoveRow(
          label: index == 0 ? 'Start position' : line.moveLabel(index),
          quality: ctrl.reviewOfPly(index)?.quality,
          evalText: evalText,
          selected: index == ctrl.selectedIndex,
          onTap: () => ctrl.select(index),
        );
      },
    );
  }
}

class _MoveRow extends StatelessWidget {
  const _MoveRow({
    required this.label,
    required this.quality,
    required this.evalText,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final MoveQuality? quality;
  final String? evalText;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? kPanelBorder : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              if (quality != null) _QualityBadge(quality: quality!),
              const SizedBox(width: 10),
              SizedBox(
                width: 54,
                child: Text(
                  evalText ?? '',
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QualityBadge extends StatelessWidget {
  const _QualityBadge({required this.quality});

  final MoveQuality quality;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: quality.color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        quality.label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: quality.onColor,
        ),
      ),
    );
  }
}

class _EvalChip extends StatelessWidget {
  const _EvalChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: kPanelBorder),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}
