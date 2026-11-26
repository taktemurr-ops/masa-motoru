import 'package:flutter_test/flutter_test.dart';
import 'package:masa_motoru/masa_motoru.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/rng.dart';

int sq(String n) => squareOf(n);

void main() {
  group('hamle üretimi (perft)', () {
    test('başlangıç konumu', () {
      final s = PChess.fromFen('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w - - 0 1');
      expect(s.perft(1), 20);
      expect(s.perft(2), 400);
      expect(s.perft(3), 8902);
      expect(s.perft(4), 197281);
    });
    test('geçerken alma ve şah tehditleri (3. konum)', () {
      final s = PChess.fromFen('8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1');
      expect(s.perft(1), 14);
      expect(s.perft(2), 191);
      expect(s.perft(3), 2812);
      expect(s.perft(4), 43238);
    });
    test('terfiler (4. konumun rok yapılmayan çeşidi)', () {
      // Terfi ve terfiyle alma: n1n5/PPPk4/8/8/8/8/4Kppp/5N1N b - - (yaygın test konumu).
      final s = PChess.fromFen('n1n5/PPPk4/8/8/8/8/4Kppp/5N1N b - - 0 1');
      expect(s.perft(1), 24);
      expect(s.perft(2), 496);
      expect(s.perft(3), 9483);
    });
    test('FEN gidiş-dönüş', () {
      const f = '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1';
      expect(PChess.fromFen(f).toFen(), f);
    });
  });

  group('çözücüler', () {
    test('tek anahtarlı iki hamlede mat', () {
      final s = PChess.fromFen('7k/2r5/6p1/8/2RN4/B2K4/1R6/8 w - - 0 1');
      expect(s.canMate(1), isFalse);
      final keys = s.mateKeys(2);
      expect(keys.map(uciOf).toList(), ['c4c7']);
    });
    test('bir hamlede mat ve pat ayrımı', () {
      final s = PChess.fromFen('6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1');
      expect(s.mateKeys(1).map(uciOf).toList(), ['a1a8']);
      final p = PChess.fromFen('7k/8/6Q1/8/8/8/8/6K1 b - - 0 1');
      expect(p.stalemated, isTrue);
    });
    test('malzeme araması çatalı bulur', () {
      // At çatalı: Nc7+ şah ve kaleyi vurur.
      final s = PChess.fromFen('r3k3/8/8/1N6/8/8/8/4K3 w - - 0 1');
      final (m, v) = s.bestMove(4);
      expect(uciOf(m), 'b5c7');
      expect(v, greaterThanOrEqualTo(300)); // at kaldı, kale gitti
    });
  });

  group('piyon oyunsonu tablosu', () {
    final t = Kpk.instance;
    (bool, int) probe(String fen) => kpkProbe(t, PChess.fromFen(fen));
    test('bilinen sonuçlar', () {
      // Şah piyonun önünde altıncı sırada: kim oynarsa oynasın kazanç.
      expect(probe('4k3/8/4K3/8/4P3/8/8/8 w - - 0 1').$1, isTrue);
      expect(probe('4k3/8/4K3/8/4P3/8/8/8 b - - 0 1').$1, isTrue);
      // Kale piyonu, savunan köşede: beraberlik.
      expect(probe('k7/8/8/1K6/P7/8/8/8 w - - 0 1').$1, isFalse);
      // Karenin dışında kalan şah: kazanç; karenin içinde: beraberlik.
      expect(probe('k7/8/8/8/8/8/7P/K7 w - - 0 1').$1, isTrue);
      expect(probe('8/8/8/4k3/8/8/7P/K7 w - - 0 1').$1, isFalse);
      // Siyah piyonlu taraf (aynalama).
      expect(probe('8/8/8/8/4p3/8/4k3/4K3 b - - 0 1').$1, isTrue);
    });
  });

  group('bulmaca üretimi', () {
    for (final kind in PuzzleKind.values) {
      test('${kind.name}: üretilir, tek çözümlü ve doğrulanır', () {
        final sw = Stopwatch()..start();
        var made = 0;
        for (var seed = 1; seed <= 3; seed++) {
          final pz = PuzzleGen(SeededRandom(seed * 977 + kind.index)).generate(kind, 5, seed);
          if (!pz.ok) continue;
          made++;
          expect(PuzzleGen.verify(pz), isTrue, reason: '${kind.name} $seed');
          // Çapraz denetim için günlüğe yaz.
          // ignore: avoid_print
          print('PUZZLE ${kind.name} ${pz.position().toFen()} ${pz.line.map(uciOf).join(' ')}');
        }
        // ignore: avoid_print
        print('TIME ${kind.name} ${sw.elapsedMilliseconds} ms');
        expect(made, greaterThanOrEqualTo(2), reason: kind.name);
      });
    }
  });

  test('bölümler kurulur ve doğrulanır', () {
    final rules = ChessPuzzleRules(gameId: 'oyun-satranc-bulmacalari');
    final planner = LevelPlanner(gameId: 'oyun-satranc-bulmacalari', optionalMechanics: const []);
    final kinds = <PuzzleKind>{};
    final sw = Stopwatch()..start();
    for (final lv in [1, 2, 3, 77, 500, 1500, 9999, 33333, 77777, 99999]) {
      final gl = rules.build(planner.spec(lv));
      expect(gl.validation.ok, isTrue, reason: 'bölüm $lv');
      kinds.add(gl.puzzle.kind);
      // ignore: avoid_print
      print('LEVEL $lv d${gl.spec.difficulty} ${gl.puzzle.kind.name} ${gl.puzzle.position().toFen()} ${gl.puzzle.line.map(uciOf).join(' ')} (${sw.elapsedMilliseconds} ms)');
    }
    expect(kinds.length, greaterThanOrEqualTo(3));
  });

  test('33 dilde tema adları', () {
    for (final l in [tpMateIn, tpFork, tpPin, tpSkewer, tpDiscovered, tpPawnWin, tpPawnDraw, tpGoalMate, tpGoalTactic, tpGoalPawnWin, tpGoalPawnDraw, tpWhiteToMove, tpBlackToMove, tpCorrect, tpWrong, tpTooSlow, tpPreparing, tpPromoteTo, tpProgress, tpSolved]) {
      expect(l.length, 33);
    }
    for (final k in PuzzleKind.values) {
      expect(puzzleKindLabel(k, 'ja'), isNotEmpty);
      expect(puzzleGoal(k, 'ar'), isNot(contains('{n}')));
    }
  });
}
