import 'package:flutter_test/flutter_test.dart';
import 'package:masa_motoru/masa_motoru.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/rng.dart';

void main() {
  final games = <String, BoardGameRules>{
    'xox': MasaPresets.xox('oyun-xox'),
    'dortle': MasaPresets.dortle('oyun-dortle'),
    'besleme': MasaPresets.besleme('oyun-besleme'),
    'reversi': MasaPresets.reversi('oyun-reversi'),
    'hex': MasaPresets.hex('oyun-hex'),
    'dots': MasaPresets.dots('oyun-noktalar-ve-kutular'),
    'dama': MasaPresets.draughts('oyun-dama', DraughtsRules.english),
    'turk-damasi': MasaPresets.draughts('oyun-turk-damasi', DraughtsRules.turkish),
    'satranc': MasaPresets.chess('oyun-satranc'),
    'mangala': MasaPresets.mancala('oyun-mangala', MancalaRules.mangala),
    'kalah': MasaPresets.mancala('oyun-kalah', MancalaRules.kalah),
    'oware': MasaPresets.mancala('oyun-oware', MancalaRules.oware),
    'dokuz-tas': MasaPresets.morris('oyun-dokuz-tas'),
    'go': MasaPresets.go('oyun-go'),
  };

  games.forEach((name, rules) {
    test('$name: bölümler üretilir, maç biter, hedef tutar', () {
      final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
      for (final lv in [1, 250, 9999, 49999]) {
        final sw = Stopwatch()..start();
        final gl = rules.build(planner.spec(lv));
        expect(gl.validation.ok, isTrue, reason: '$name $lv');
        final back = gl.puzzle.rules.parse(gl.puzzle.start.serialize());
        expect(back.serialize(), gl.puzzle.start.serialize());
        // ignore: avoid_print
        print('$name $lv d=${gl.spec.difficulty} attempts=${gl.attempts} ${sw.elapsedMilliseconds}ms ply=${gl.validation.metric} goal=${gl.puzzle.goal}');
      }
    }, timeout: const Timeout(Duration(minutes: 8)));
  });

  test('reversi başlangıç: 4 hamle', () {
    const r = ReversiRules();
    final s = r.initial(SeededRandom(1));
    expect(r.moves(s).length, 4);
  });

  test('dörtle: dikey dört kazanır', () {
    const r = LineRules('d', 7, 6, 4, gravity: true);
    final s = r.initial(SeededRandom(1));
    for (var i = 0; i < 3; i++) {
      r.apply(s, r.moves(s)[0]);
      r.apply(s, r.moves(s)[1]);
    }
    r.apply(s, r.moves(s)[0]);
    expect(r.winner(s), 0);
  });

  test('noktalar: kutuyu kapatan tekrar oynar', () {
    const r = DotsRules(2, 2);
    final s = r.initial(SeededRandom(1));
    for (final e in r.boxEdges(0, 0).take(3)) {
      r.apply(s, mv(-1, e));
    }
    final who = s.turn;
    r.apply(s, mv(-1, r.boxEdges(0, 0)[3]));
    expect(s.turn, who);
    expect(s.vars[1 + who], 1);
  });

  int perft(ChessRules r, GridState s, int d) {
    if (d == 0) return 1;
    var n = 0;
    for (final m in r.moves(s)) {
      final c = s.copy();
      r.apply(c, m);
      n += perft(r, c, d - 1);
    }
    return n;
  }

  test('satranç perft', () {
    const r = ChessRules();
    final s = r.initial(SeededRandom(1));
    expect(perft(r, s, 1), 20);
    expect(perft(r, s, 2), 400);
    expect(perft(r, s, 3), 8902);
  });

  test('satranç çeşitleri başlar ve biter', () {
    for (final v in ChessVariant.values) {
      final rules = MasaPresets.chess('oyun-satranc-cesitleri', v);
      final gl = rules.build(LevelPlanner(gameId: 'x-${v.name}', optionalMechanics: const []).spec(40));
      // ignore: avoid_print
      print('${v.name} ok=${gl.validation.ok} ply=${gl.validation.metric}');
      expect(gl.validation.ok, isTrue, reason: v.name);
    }
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('dama başlangıç hamleleri', () {
    expect(DraughtsRules.english.moves(DraughtsRules.english.initial(SeededRandom(1))).length, 7);
    expect(DraughtsRules.turkish.moves(DraughtsRules.turkish.initial(SeededRandom(1))).length, 8);
    expect(DraughtsRules.international.moves(DraughtsRules.international.initial(SeededRandom(1))).length, 9);
  });
}
