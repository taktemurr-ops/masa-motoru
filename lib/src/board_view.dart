import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/services/audio.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/strings.dart';

import 'board_ai.dart';
import 'board_game.dart';
import 'board_levels.dart';

/// Çizimde kullanılan anlık bilgiler.
class BoardPaintInfo {
  final int? selected;
  final Set<int> targets;
  final int? hintFrom, hintTo;
  final int human;
  final List<Color> colors;
  final bool colorBlind;
  final bool canAct;
  const BoardPaintInfo({
    this.selected,
    this.targets = const {},
    this.hintFrom,
    this.hintTo,
    required this.human,
    required this.colors,
    required this.colorBlind,
    required this.canAct,
  });
}

/// Bir oyunun tahta çizimi ve dokunma eşlemesi.
abstract class BoardSkin {
  const BoardSkin();

  /// Tahtanın en/boy oranı.
  double aspect(BoardState s) => 1;
  void paint(Canvas c, Size size, BoardState s, BoardPaintInfo info);

  /// Dokunulan nokta → kare/hücre (yoksa -1).
  int hit(Offset p, Size size, BoardState s, [BoardPaintInfo? info]);

  /// Koltuğun taşını küçük bir kutuya çiz (üstteki "Sen" göstergesi).
  void paintSeat(Canvas c, Rect r, int seat, BoardPaintInfo info);
}

class _AiJob {
  final BoardRules rules;
  final String state;
  final int depth, budget, seed;
  final double noise;
  const _AiJob(this.rules, this.state, this.depth, this.budget, this.noise, this.seed);
}

int _runAi(_AiJob j) {
  final s = j.rules.parse(j.state);
  return BoardAI(j.rules, depth: j.depth, nodeBudget: j.budget, noise: j.noise, r: SeededRandom(j.seed)).choose(s);
}

/// Bütün masa oyunlarının ortak oyun ekranı.
class BoardView extends StatefulWidget {
  final PlayContext ctx;
  final BoardSkin skin;
  const BoardView({super.key, required this.ctx, required this.skin});

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> {
  late BoardLevel level;
  late BoardState s;
  late SeededRandom r;
  final List<String> _undo = [];
  int? _selected;
  int? _hintFrom, _hintTo;
  bool _busy = false, _ended = false;
  int _seconds = 0, _hints = 0, _undos = 0, _moves = 0;
  Timer? _timer;
  String? _flash;

  PlayContext get ctx => widget.ctx;
  BoardRules get rules => level.rules;
  bool get _over => rules.isOver(s) || s.ply >= rules.maxPly;

  @override
  void initState() {
    super.initState();
    level = (ctx.generated as GeneratedLevel<BoardLevel>).puzzle;
    final snap = ctx.resume['snap'];
    s = snap is String ? rules.parse(snap) : level.start.copy();
    _seconds = (ctx.resume['secs'] as num?)?.toInt() ?? 0;
    _hints = (ctx.resume['hints'] as num?)?.toInt() ?? 0;
    r = SeededRandom(mixSeed([level.seed, 31, _seconds]));
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_ended && mounted) setState(() => _seconds++);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _advance());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _persist() => ctx.saveResume({'snap': s.serialize(), 'secs': _seconds, 'hints': _hints});

  List<int> get _legal => !_over && s.turn == level.human && !rules.needsChance(s) ? rules.moves(s) : const [];

  /// Sıra rakipteyse ya da şans olayı bekliyorsa oyunu ilerlet.
  Future<void> _advance() async {
    while (mounted && !_ended) {
      if (_over) {
        _end();
        return;
      }
      if (rules.needsChance(s)) {
        setState(() => _busy = true);
        await Future<void>.delayed(const Duration(milliseconds: 450));
        if (!mounted) return;
        setState(() => rules.applyChance(s, r));
        ctx.sfx(Sfx.tap);
        continue;
      }
      if (s.turn == level.human) {
        final legal = rules.moves(s);
        if (legal.length == 1 && legal.first == kPass) {
          setState(() => _flash = _t(_tPass));
          await Future<void>.delayed(const Duration(milliseconds: 700));
          if (!mounted) return;
          setState(() {
            rules.apply(s, kPass);
            _flash = null;
          });
          continue;
        }
        setState(() => _busy = false);
        _persist();
        return;
      }
      setState(() => _busy = true);
      final started = DateTime.now();
      final m = await compute(_runAi, _AiJob(rules, s.serialize(), level.opp.depth, level.opp.budget, level.opp.noise, r.nextInt(1 << 30)));
      final spent = DateTime.now().difference(started).inMilliseconds;
      if (spent < 420) await Future<void>.delayed(Duration(milliseconds: 420 - spent));
      if (!mounted || _ended) return;
      setState(() => rules.apply(s, m));
      ctx.sfx(m == kPass ? Sfx.tap : Sfx.place);
    }
  }

  void _tap(int cell) {
    if (_busy || _ended || cell < 0) return;
    final legal = _legal;
    if (legal.isEmpty) return;
    int? pick;
    if (_selected != null) {
      for (final m in legal) {
        if (mvFrom(m) == _selected && mvTo(m) == cell) {
          pick = m;
          break;
        }
      }
    }
    if (pick == null) {
      for (final m in legal) {
        if (mvFrom(m) == -1 && mvTo(m) == cell) {
          pick = m;
          break;
        }
      }
    }
    if (pick != null) {
      _play(pick);
      return;
    }
    if (legal.any((m) => mvFrom(m) == cell)) {
      ctx.sfx(Sfx.tap);
      setState(() => _selected = _selected == cell ? null : cell);
      return;
    }
    ctx.sfx(Sfx.error);
    setState(() => _selected = null);
  }

  void _play(int m) {
    _undo.add(s.serialize());
    setState(() {
      rules.apply(s, m);
      _selected = null;
      _hintFrom = _hintTo = null;
      _moves++;
    });
    ctx.sfx(Sfx.place);
    _advance();
  }

  void _doUndo() {
    if (_undo.isEmpty || _busy || _ended) return;
    setState(() {
      s = rules.parse(_undo.removeLast());
      _undos++;
      _selected = null;
      _hintFrom = _hintTo = null;
    });
    _persist();
  }

  Future<void> _hint() async {
    if (_busy || _ended || _legal.isEmpty || !await ctx.requestHint()) return;
    setState(() => _busy = true);
    final m = await compute(_runAi, _AiJob(rules, s.serialize(), math.max(3, level.opp.depth + 1), 30000, 0, 5));
    if (!mounted) return;
    _hints++;
    setState(() {
      _busy = false;
      _hintFrom = mvFrom(m) >= 0 ? mvFrom(m) : null;
      _hintTo = mvTo(m);
      _selected = _hintFrom;
    });
    _persist();
  }

  void _end() {
    if (_ended) return;
    _ended = true;
    _timer?.cancel();
    final won = level.goalMet(s);
    ctx.sfx(won ? Sfx.win : Sfx.lose);
    final o = outcomeFor(rules, s, level.human);
    ctx.finish(RoundResult(
      won: won,
      score: won ? math.max(50, 400 + level.difficulty * 60 - _moves * 2 - _hints * 40) : (o == Outcome.draw ? 60 : 10),
      stars: BoardGameRules.stars(won: won, hints: _hints, undos: _undos),
      seconds: _seconds,
      moves: _moves,
      hintsUsed: _hints,
      undosUsed: _undos,
      gameStats: {'games_won': o == Outcome.win ? 1 : 0, 'moves_made': _moves},
    ));
  }

  String _t(List<String> l) => Strings.pick(l, ctx.lang);

  BoardPaintInfo get _info {
    final legal = _legal;
    final targets = <int>{
      for (final m in legal)
        if (_selected != null && mvFrom(m) == _selected) mvTo(m)
    };
    return BoardPaintInfo(
      selected: _selected,
      targets: targets,
      hintFrom: _hintFrom,
      hintTo: _hintTo,
      human: level.human,
      colors: ctx.pieceColors,
      colorBlind: ctx.colorBlind,
      canAct: legal.isNotEmpty && !_busy,
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = rules.status(s, ctx.lang);
    final myTurn = s.turn == level.human && !_over;
    final turnText = _flash ?? (myTurn ? _t(_tYourTurn) : _t(_tThinking));
    final info = _info;
    return LayoutBuilder(builder: (context, cons) {
      final aspect = widget.skin.aspect(s);
      final maxW = cons.maxWidth - 16, maxH = cons.maxHeight - 120;
      var bw = maxW, bh = bw / aspect;
      if (bh > maxH) {
        bh = maxH;
        bw = bh * aspect;
      }
      final size = Size(bw, bh);
      return Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            Expanded(
              child: Text(_t(level.goal == BoardGoal.win ? _tGoalWin : _tGoalNotLose),
                  style: Theme.of(context).textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            const Icon(Icons.timer_outlined, size: 18),
            Text(' ${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}'),
          ]),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('${_t(_tYou)}: '),
          SizedBox(width: 20, height: 20, child: CustomPaint(painter: _SeatP(widget.skin, level.human, info))),
          const SizedBox(width: 12),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: myTurn ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant),
            child: Text(turnText),
          ),
        ]),
        if (status.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 2), child: Text(status, style: Theme.of(context).textTheme.bodySmall)),
        Expanded(
          child: Center(
            child: GestureDetector(
              onTapUp: (d) => _tap(widget.skin.hit(d.localPosition, size, s, info)),
              child: Semantics(
                label: 'board',
                child: SizedBox(width: bw, height: bh, child: CustomPaint(painter: _BoardP(widget.skin, s, info, s.ply, _selected, _hintTo))),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            IconButton.filledTonal(
                onPressed: _ended || _busy || !myTurn ? null : _hint, icon: const Icon(Icons.lightbulb), tooltip: ctx.t('hint')),
            IconButton.filledTonal(
                onPressed: _undo.isNotEmpty && !_busy && !_ended ? _doUndo : null, icon: const Icon(Icons.undo), tooltip: ctx.t('undo')),
            if (_legal.length > 1 && _legal.contains(kPass))
              FilledButton.tonal(onPressed: _busy || _ended ? null : () => _play(kPass), child: Text(_t(_tPass))),
          ]),
        ),
      ]);
    });
  }
}

class _BoardP extends CustomPainter {
  final BoardSkin skin;
  final BoardState s;
  final BoardPaintInfo info;
  final int ply;
  final int? sel, hint;
  _BoardP(this.skin, this.s, this.info, this.ply, this.sel, this.hint);
  @override
  void paint(Canvas canvas, Size size) => skin.paint(canvas, size, s, info);
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _SeatP extends CustomPainter {
  final BoardSkin skin;
  final int seat;
  final BoardPaintInfo info;
  _SeatP(this.skin, this.seat, this.info);
  @override
  void paint(Canvas canvas, Size size) => skin.paintSeat(canvas, Offset.zero & size, seat, info);
  @override
  bool shouldRepaint(covariant _SeatP o) => o.seat != seat;
}

// tr en de es fr ar fa he ur ru uk pl cs ro hu el it pt nl sv da nb fi ja ko zh hi bn id ms th vi fil
const _tYourTurn = ['Sıra sende', 'Your turn', 'Du bist dran', 'Tu turno', 'À vous', 'دورك', 'نوبت توست', 'תורך', 'آپ کی باری', 'Ваш ход', 'Ваш хід', 'Twój ruch', 'Jsi na tahu', 'Rândul tău', 'Te jössz', 'Σειρά σου', 'Tocca a te', 'Sua vez', 'Jouw beurt', 'Din tur', 'Din tur', 'Din tur', 'Sinun vuorosi', 'あなたの番', '당신 차례', '轮到你了', 'आपकी बारी', 'আপনার পালা', 'Giliranmu', 'Giliran anda', 'ตาของคุณ', 'Đến lượt bạn', 'Ikaw na'];
const _tThinking = ['Rakip düşünüyor…', 'Opponent is thinking…', 'Gegner überlegt…', 'El rival piensa…', "L'adversaire réfléchit…", 'الخصم يفكر…', 'حریف فکر می‌کند…', 'היריב חושב…', 'مخالف سوچ رہا ہے…', 'Соперник думает…', 'Суперник думає…', 'Rywal myśli…', 'Soupeř přemýšlí…', 'Adversarul se gândește…', 'Az ellenfél gondolkodik…', 'Ο αντίπαλος σκέφτεται…', "L'avversario pensa…", 'O rival está pensando…', 'Tegenstander denkt na…', 'Motståndaren tänker…', 'Modstanderen tænker…', 'Motstanderen tenker…', 'Vastustaja miettii…', '相手が考え中…', '상대가 생각 중…', '对手思考中…', 'विरोधी सोच रहा है…', 'প্রতিপক্ষ ভাবছে…', 'Lawan sedang berpikir…', 'Lawan sedang berfikir…', 'คู่แข่งกำลังคิด…', 'Đối thủ đang nghĩ…', 'Nag-iisip ang kalaban…'];
const _tPass = ['Pas', 'Pass', 'Passen', 'Pasar', 'Passer', 'تمرير', 'پاس', 'פס', 'پاس', 'Пас', 'Пас', 'Pas', 'Pas', 'Pas', 'Passz', 'Πάσο', 'Passo', 'Passar', 'Passen', 'Pass', 'Pas', 'Pass', 'Ohi', 'パス', '패스', '过', 'पास', 'পাস', 'Lewati', 'Langkau', 'ผ่าน', 'Bỏ lượt', 'Pasa'];
const _tGoalWin = ['Oyunu kazan', 'Win the game', 'Gewinne die Partie', 'Gana la partida', 'Gagnez la partie', 'اربح المباراة', 'بازی را ببر', 'נצחו במשחק', 'کھیل جیتیں', 'Выиграйте партию', 'Виграйте партію', 'Wygraj partię', 'Vyhraj partii', 'Câștigă partida', 'Nyerd meg a játszmát', 'Κέρδισε την παρτίδα', 'Vinci la partita', 'Vença a partida', 'Win de partij', 'Vinn partiet', 'Vind spillet', 'Vinn partiet', 'Voita peli', '対局に勝とう', '게임에서 이기세요', '赢得对局', 'खेल जीतें', 'খেলায় জিতুন', 'Menangkan permainan', 'Menangi permainan', 'ชนะเกมนี้', 'Thắng ván đấu', 'Manalo sa laro'];
const _tGoalNotLose = ['Kaybetme (berabere de olur)', "Don't lose (a draw counts)", 'Verliere nicht (Remis zählt)', 'No pierdas (el empate vale)', 'Ne perdez pas (la nulle compte)', 'لا تخسر (التعادل يُحتسب)', 'نباز (مساوی هم قبول است)', 'אל תפסידו (תיקו נחשב)', 'ہاریں نہیں (برابری بھی چلے گی)', 'Не проиграйте (ничья засчитывается)', 'Не програйте (нічия зараховується)', 'Nie przegraj (remis się liczy)', 'Neprohraj (remíza se počítá)', 'Nu pierde (egalul contează)', 'Ne veszíts (a döntetlen is jó)', 'Μη χάσεις (μετρά και η ισοπαλία)', 'Non perdere (vale il pareggio)', 'Não perca (empate vale)', 'Verlies niet (gelijkspel telt)', 'Förlora inte (oavgjort räknas)', 'Tab ikke (uafgjort tæller)', 'Ikke tap (uavgjort teller)', 'Älä häviä (tasapeli kelpaa)', '負けないこと（引き分けも可）', '지지 마세요 (무승부도 인정)', '不输即可（平局也算）', 'हारें नहीं (बराबरी भी चलेगी)', 'হারবেন না (ড্র-ও চলবে)', 'Jangan kalah (seri juga dihitung)', 'Jangan kalah (seri pun dikira)', 'อย่าแพ้ (เสมอก็นับ)', 'Đừng thua (hòa cũng tính)', 'Huwag matalo (bilang ang tabla)'];
const _tYou = ['Sen', 'You', 'Du', 'Tú', 'Vous', 'أنت', 'شما', 'אתם', 'آپ', 'Вы', 'Ви', 'Ty', 'Ty', 'Tu', 'Te', 'Εσύ', 'Tu', 'Você', 'Jij', 'Du', 'Du', 'Du', 'Sinä', 'あなた', '나', '你', 'आप', 'আপনি', 'Kamu', 'Anda', 'คุณ', 'Bạn', 'Ikaw'];
