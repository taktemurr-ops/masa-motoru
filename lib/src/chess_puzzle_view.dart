import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/strings.dart';

import 'board_view.dart';
import 'chess.dart';
import 'chess_puzzle.dart';
import 'chess_puzzle_texts.dart';
import 'grid_state.dart';
import 'skins2.dart';
import 'studio_chrome.dart';

Uint8List _buildKpk(int _) => Kpk.build();

/// Bulmacanın tema adı (33 dil).
String puzzleKindLabel(PuzzleKind k, String lang) => switch (k) {
      PuzzleKind.mate1 || PuzzleKind.mate2 || PuzzleKind.mate3 => Strings.pick(tpMateIn, lang).replaceAll('{n}', '${k.mateIn}'),
      PuzzleKind.fork => Strings.pick(tpFork, lang),
      PuzzleKind.pin => Strings.pick(tpPin, lang),
      PuzzleKind.skewer => Strings.pick(tpSkewer, lang),
      PuzzleKind.discovered => Strings.pick(tpDiscovered, lang),
      PuzzleKind.pawnWin => Strings.pick(tpPawnWin, lang),
      PuzzleKind.pawnDraw => Strings.pick(tpPawnDraw, lang),
    };

/// Bulmacanın hedefi (33 dil).
String puzzleGoal(PuzzleKind k, String lang) => switch (k) {
      PuzzleKind.mate1 || PuzzleKind.mate2 || PuzzleKind.mate3 => Strings.pick(tpGoalMate, lang).replaceAll('{n}', '${k.mateIn}'),
      PuzzleKind.pawnWin => Strings.pick(tpGoalPawnWin, lang),
      PuzzleKind.pawnDraw => Strings.pick(tpGoalPawnDraw, lang),
      _ => Strings.pick(tpGoalTactic, lang),
    };

/// Satranç bulmacası ekranı: tahta, tema etiketi, sıra, ipucu.
class ChessPuzzleView extends StatefulWidget {
  final PlayContext ctx;
  const ChessPuzzleView({super.key, required this.ctx});

  @override
  State<ChessPuzzleView> createState() => _ChessPuzzleViewState();
}

class _ChessPuzzleViewState extends State<ChessPuzzleView> {
  late ChessPuzzle pz;
  late PuzzleJudge judge;
  int? _selected, _hintFrom, _hintTo, _last;
  bool _busy = false, _ended = false, _ready = true;
  int _seconds = 0, _hints = 0, _mistakes = 0;
  Timer? _timer;
  String? _flash;
  bool _flashGood = false;

  PlayContext get ctx => widget.ctx;
  String _t(List<String> l) => Strings.pick(l, ctx.lang);

  @override
  void initState() {
    super.initState();
    pz = (ctx.generated as GeneratedLevel<ChessPuzzle>).puzzle;
    judge = PuzzleJudge(pz);
    _seconds = (ctx.resume['secs'] as num?)?.toInt() ?? 0;
    _hints = (ctx.resume['hints'] as num?)?.toInt() ?? 0;
    _mistakes = (ctx.resume['miss'] as num?)?.toInt() ?? 0;
    final moves = ctx.resume['moves'];
    if (moves is List) {
      // Kaldığı yerden: oyuncu ve rakip hamleleri sırayla yeniden oynanır.
      for (final m in moves) {
        final v = (m as num).toInt();
        if (judge.playerToMove) {
          judge.play(v);
        } else {
          judge.applyReply(v);
        }
        _history.add(v);
        _last = pTo(v);
      }
    }
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_ended && mounted) setState(() => _seconds++);
    });
    if (pz.kind.isEndgame && !Kpk.ready) {
      _ready = false;
      compute(_buildKpk, 0).then((data) {
        Kpk.fromData(data);
        if (mounted) setState(() => _ready = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  final List<int> _history = [];

  void _persist() => ctx.saveResume({'moves': _history, 'secs': _seconds, 'hints': _hints, 'miss': _mistakes});

  List<int> get _legal => _ready && !_busy && !_ended && judge.playerToMove ? judge.s.legal() : const [];

  void _tap(int cell) {
    if (cell < 0) return;
    final legal = _legal;
    if (legal.isEmpty) return;
    if (_selected != null) {
      final picks = [for (final m in legal) if (pFrom(m) == _selected && pTo(m) == cell) m];
      if (picks.isNotEmpty) {
        if (picks.length > 1) {
          _choosePromotion(picks);
        } else {
          _try(picks.first);
        }
        return;
      }
    }
    if (legal.any((m) => pFrom(m) == cell)) {
      ctx.sfx(Sfx.tap);
      setState(() => _selected = _selected == cell ? null : cell);
      return;
    }
    setState(() => _selected = null);
  }

  Future<void> _choosePromotion(List<int> picks) async {
    final side = judge.s.stm;
    final m = await showModalBottomSheet<int>(
      context: context,
      builder: (c) => StudioChrome(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_t(tpPromoteTo), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                for (final p in picks)
                  InkWell(
                    onTap: () => Navigator.pop(c, p),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: CustomPaint(painter: _PieceP(side * 8 + pPromo(p))),
                    ),
                  ),
              ]),
            ]),
          ),
        ),
      ),
    );
    if (m != null && mounted) _try(m);
  }

  Future<void> _try(int m) async {
    if (!judge.accepts(m)) {
      ctx.sfx(Sfx.error);
      setState(() {
        _mistakes++;
        _selected = null;
        _flash = _t(tpWrong);
        _flashGood = false;
      });
      _persist();
      return;
    }
    ctx.sfx(Sfx.place);
    final done = judge.play(m);
    _history.add(m);
    setState(() {
      _selected = null;
      _hintFrom = _hintTo = null;
      _last = pTo(m);
      _flash = _t(tpCorrect);
      _flashGood = true;
    });
    if (done) {
      _finish(true);
      return;
    }
    if (pz.kind == PuzzleKind.pawnWin && judge.done >= pz.target) {
      setState(() => _flash = _t(tpTooSlow));
      _finish(false);
      return;
    }
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    final r = judge.reply();
    if (r < 0) {
      _finish(judge.solved);
      return;
    }
    judge.applyReply(r);
    _history.add(r);
    ctx.sfx(Sfx.place);
    setState(() {
      _busy = false;
      _last = pTo(r);
    });
    _persist();
    if (judge.solved) _finish(true);
  }

  Future<void> _hint() async {
    if (!_ready || _busy || _ended || !judge.playerToMove || !await ctx.requestHint()) return;
    final m = judge.hint();
    if (m < 0 || !mounted) return;
    _hints++;
    setState(() {
      // İlk ipucu taşı, ikincisi hedef kareyi de gösterir.
      if (_hintFrom == pFrom(m)) {
        _hintTo = pTo(m);
      } else {
        _hintFrom = pFrom(m);
        _hintTo = null;
      }
      _selected = pFrom(m);
    });
    _persist();
  }

  void _finish(bool won) {
    if (_ended) return;
    _ended = true;
    _timer?.cancel();
    ctx.sfx(won ? Sfx.win : Sfx.lose);
    final stars = won ? ChessPuzzleRules.stars(mistakes: _mistakes, hints: _hints) : 0;
    Future<void>.delayed(const Duration(milliseconds: 650), () {
      ctx.finish(RoundResult(
        won: won,
        score: won ? math.max(50, 300 + pz.difficulty * 50 - _mistakes * 40 - _hints * 60) : 10,
        stars: stars,
        seconds: _seconds,
        moves: judge.done,
        hintsUsed: _hints,
        headline: won ? _t(tpSolved) : null,
        gameStats: {
          'puzzles_solved': won ? 1 : 0,
          'mates_found': won && pz.kind.isMate ? 1 : 0,
          'tactics_won': won && pz.kind.isTactic ? 1 : 0,
        },
      ));
    });
  }

  @override
  Widget build(BuildContext context) => StudioChrome(child: Builder(builder: _build));

  Widget _build(BuildContext context) {
    final look = StudioLook.of(context);
    final legal = _legal;
    final grid = GridState(8, 8, [for (final v in judge.s.b) v])..last = _last ?? -1;
    final info = BoardPaintInfo(
      selected: _selected,
      targets: {for (final m in legal) if (_selected != null && pFrom(m) == _selected) pTo(m)},
      hintFrom: _hintFrom,
      hintTo: _hintTo,
      human: pz.side,
      colors: ctx.pieceColors,
      colorBlind: ctx.colorBlind,
      canAct: legal.isNotEmpty,
    );
    final needed = judge.playerMovesNeeded;
    final progress = _t(tpProgress)
        .replaceAll('{a}', '${math.min(judge.done + (judge.solved ? 0 : 1), needed)}')
        .replaceAll('{b}', '$needed');
    return LayoutBuilder(builder: (context, cons) {
      final side = math.min(cons.maxWidth - 16, cons.maxHeight - 170).clamp(160.0, 900.0);
      final size = Size(side, side);
      return Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
          child: Row(children: [
            StudioTag(icon: pz.kind.isMate ? Icons.flag_rounded : (pz.kind.isEndgame ? Icons.hourglass_bottom_rounded : Icons.bolt_rounded), text: puzzleKindLabel(pz.kind, ctx.lang)),
            const Spacer(),
            StudioTag(icon: Icons.timer_outlined, text: '${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}'),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Text(puzzleGoal(pz.kind, ctx.lang),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: kStudioText, fontWeight: FontWeight.w700, fontSize: 14)),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(colors: [look.accent.withValues(alpha: 0.85), look.play.withValues(alpha: 0.85)]),
            border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.4),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 20, height: 20, child: CustomPaint(painter: _PieceP(pz.side * 8 + cK))),
            const SizedBox(width: 8),
            Flexible(
              child: Text('${_t(pz.side == 0 ? tpWhiteToMove : tpBlackToMove)}  ·  $progress',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: look.onAccent)),
            ),
          ]),
        ),
        SizedBox(
          height: 26,
          child: _flash == null
              ? null
              : Center(
                  child: Text(_flash!,
                      key: ValueKey('flash-$_flash'),
                      style: TextStyle(color: _flashGood ? const Color(0xFF8BE28B) : const Color(0xFFFFA4A4), fontWeight: FontWeight.w800))),
        ),
        Expanded(
          child: Center(
            child: !_ready
                ? Column(mainAxisSize: MainAxisSize.min, children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(_t(tpPreparing), style: const TextStyle(color: kStudioTextDim)),
                  ])
                : GestureDetector(
                    onTapUp: (d) => _tap(const ChessSkin().hit(d.localPosition, size, grid, info)),
                    child: Semantics(
                      label: 'board',
                      child: SizedBox(width: side, height: side, child: CustomPaint(painter: _BoardP(grid, info))),
                    ),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            StudioRoundAction(
                onPressed: _ended || _busy || !_ready || !judge.playerToMove ? null : _hint, icon: Icons.lightbulb, tooltip: ctx.t('hint')),
          ]),
        ),
      ]);
    });
  }
}

class _BoardP extends CustomPainter {
  final GridState s;
  final BoardPaintInfo info;
  _BoardP(this.s, this.info);
  @override
  void paint(Canvas canvas, Size size) => const ChessSkin().paint(canvas, size, s, info);
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _PieceP extends CustomPainter {
  final int v;
  _PieceP(this.v);
  @override
  void paint(Canvas canvas, Size size) => ChessSkin.drawPiece(canvas, Offset.zero & size, v);
  @override
  bool shouldRepaint(covariant _PieceP o) => o.v != v;
}
