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
    'rus-damasi': MasaPresets.draughts('x-rus', DraughtsRules.russian),
    'brezilya': MasaPresets.draughts('x-bre', DraughtsRules.brazilian),
    'pool': MasaPresets.draughts('x-pool', DraughtsRules.pool),
    'uluslararasi': MasaPresets.draughts('x-int', DraughtsRules.international),
    'italyan': MasaPresets.draughts('x-ita', DraughtsRules.italian),
    'ispanyol': MasaPresets.draughts('x-isp', DraughtsRules.spanish),
    'cek': MasaPresets.draughts('x-cek', DraughtsRules.czech),
    'kanada': MasaPresets.draughts('x-kan', DraughtsRules.canadian),
    'kalah6': MasaPresets.mancala('x-k6', MancalaRules.kalah6),
    'kalah3': MasaPresets.mancala('x-k3', MancalaRules.kalah3),
    'oware5': MasaPresets.mancala('x-o5', MancalaRules.owareShort),
    'mangala5': MasaPresets.mancala('x-m5', MancalaRules.mangala5),
    'mangala4': MasaPresets.mancala('x-m4', MancalaRules.mangalaShort),
    'mangala8': MasaPresets.mancala('x-m8', MancalaRules.mangalaLong),
    'hiper': MasaPresets.tavla('x-hiper', TavlaVariant.hyper),
    'nack': MasaPresets.tavla('x-nack', TavlaVariant.nack),
    'yaris': MasaPresets.tavla('x-yaris', TavlaVariant.race),
    'dokuz-tas': MasaPresets.morris('oyun-dokuz-tas'),
    'go': MasaPresets.go('oyun-go'),
    'tavla': MasaPresets.tavla('oyun-tavla'),
    'plakoto': MasaPresets.tavla('oyun-plakoto', TavlaVariant.plakoto),
    'fevga': MasaPresets.tavla('oyun-fevga', TavlaVariant.fevga),
    'kizma': MasaPresets.kizma('oyun-kizma-birader'),
    'yilan': MasaPresets.snakes('oyun-yilan-merdiven'),
    'zar-besli': MasaPresets.zarBesli('oyun-zar-beslisi'),
    'farkle': MasaPresets.farkle('oyun-farkle'),
    'yalanci': MasaPresets.liar('oyun-yalanci-zari'),
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

  test('italyan: taş damayı alamaz', () {
    const r = DraughtsRules.italian;
    final s = GridState(8, 8, List.filled(64, -1));
    s.cells[5 * 8 + 2] = 0; // oyuncu 0 taşı
    s.cells[4 * 8 + 3] = 3; // oyuncu 1 daması
    s.cells[0] = 1;
    s.turn = 0;
    for (final m in r.moves(s)) {
      expect((mvTo(m) - mvFrom(m)).abs() < 14, isTrue);
    }
  });

  test('hiper tavla: 3 pul toplanınca biter', () {
    const r = TavlaRules(TavlaVariant.hyper);
    final rnd = SeededRandom(3);
    final s = r.initial(rnd);
    expect(s.cells.sublist(0, 24).where((x) => x > 0).fold<int>(0, (a, b) => a + b), 3);
    var n = 0;
    while (!r.isOver(s) && n++ < 2000) {
      if (r.needsChance(s)) {
        r.applyChance(s, rnd);
        continue;
      }
      final ms = r.moves(s);
      r.apply(s, ms[rnd.nextInt(ms.length)]);
    }
    expect(r.isOver(s), isTrue);
  });

  test('yarış tavlası: temas yok', () {
    const r = TavlaRules(TavlaVariant.race);
    final s = r.initial(SeededRandom(1));
    for (var i = 0; i < 12; i++) {
      expect(s.cells[i] >= 0, isTrue);
      expect(s.cells[23 - i] <= 0, isTrue);
    }
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

  test('farkle puanları', () {
    expect(FarkleRules.scoreOf([1, 1, 1]), 1000);
    expect(FarkleRules.scoreOf([5]), 50);
    expect(FarkleRules.scoreOf([1, 2, 3, 4, 5, 6]), 1500);
    expect(FarkleRules.scoreOf([2]), -1);
    expect(ZarBesliRules.score([2, 3, 4, 5, 1], 10), 40);
    expect(ZarBesliRules.score([3, 3, 3, 5, 5], 8), 25);
  });
}
