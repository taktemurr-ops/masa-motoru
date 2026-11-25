import 'package:flutter_test/flutter_test.dart';
import 'package:masa_motoru/masa_motoru.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/rng.dart';

void main() {
  test('paçisi: tahta düzeni (68 kare döngü, 12 kale, kollar)', () {
    expect(PachisiSkin.layoutOk(), isTrue);
    var castles = 0;
    for (var i = 0; i < 68; i++) {
      if (PachisiRules.castle(i)) castles++;
    }
    expect(castles, 12);
    // Yol: orta sütundan aşağı (7), döngü (68), orta sütundan yukarı, ev = 83.
    expect(PachisiRules.loopSquare(0, 7), 0);
    expect(PachisiRules.loopSquare(0, 75), 0);
    expect(PachisiRules.loopSquare(1, 8), 18);
    expect(PachisiRules.loopSquare(0, 74), 67);
    expect(PachisiRules.loopSquare(2, 6), -1);
  });

  test('paçisi: kabuk değerleri ve lütuf atışları', () {
    expect(PachisiRules.throwValue(0), 25);
    expect(PachisiRules.throwValue(1), 10);
    expect(PachisiRules.throwValue(4), 4);
    expect(PachisiRules.grace(6) && PachisiRules.grace(10) && PachisiRules.grace(25), isTrue);
    expect(PachisiRules.grace(5), isFalse);
  });

  test('paçisi: taş yalnızca lütufla çıkar, rakibi yakalayan yeniden atar', () {
    const r = PachisiRules();
    final s = r.initial(SeededRandom(1));
    s.vars[1] = 4;
    expect(r.moves(s), [kPass]);
    s.vars[1] = 10;
    expect(r.moves(s), [mv(-1, 0)]);
    // Oyuncu 0'ın taşı döngüde, oyuncu 1'in taşı 3 kare önünde (kale değil).
    s.cells[0] = 10; // kare 3
    s.cells[4] = 70; // oyuncu 1 için prog 70 → (17 + 63) % 68 = 12
    s.cells[1] = -1;
    s.vars[1] = 2;
    // prog 12 → kare 5 değil; uygun hedefi kur.
    s.cells[0] = 17; // kare 10
    s.vars[1] = 2; // 19 → kare 12
    expect(PachisiRules.loopSquare(0, 19), 12);
    expect(PachisiRules.castle(12), isFalse);
    r.apply(s, mv(-1, 0));
    expect(s.cells[4], -1);
    expect(s.turn, 0); // yakalayan yeniden atar
    expect(s.vars[1], 0);
  });

  test('paçisi: rakibin durduğu kaleye girilmez, ortak taşı bitince ortağını oynar', () {
    const r = PachisiRules(1);
    final s = r.initial(SeededRandom(2));
    s.cells[0] = 9; // kare 2
    s.cells[4] = 55; // oyuncu 1: (17 + 48) % 68 = 65? kaleyi ayrıca kur
    // Kare 4 kale: oyuncu 1 taşını oraya koy (prog p: (17 + p - 7) % 68 = 4 → p = 62).
    s.cells[4] = 62;
    expect(PachisiRules.loopSquare(1, 62), 4);
    s.vars[1] = 2; // 0'ın taşı 11 → kare 4
    expect(r.moves(s), [kPass]);
    // Oyuncu 0'ın taşı evde → ortağı 2'nin taşını oynar.
    s.cells[0] = PachisiRules.home;
    s.cells[8] = 20;
    s.vars[1] = 3;
    expect(r.mover(s), 2);
    expect(r.moves(s), [mv(-1, 8)]);
  });

  test('paçisi: rastgele oyunlar biter, takım kazanır', () {
    for (final n in [2, 4]) {
      final r = PachisiRules(n);
      final rnd = SeededRandom(n * 7);
      final s = r.initial(rnd);
      var guard = 0;
      while (!r.isOver(s) && guard++ < 20000) {
        if (r.needsChance(s)) {
          r.applyChance(s, rnd);
          continue;
        }
        r.apply(s, r.policy(s, 0.2, rnd)!);
      }
      expect(r.isOver(s), isTrue);
      final w = r.winner(s);
      expect(w == 0 || w == 1, isTrue);
      expect(r.sameSide(w, w + 2), isTrue);
      expect(outcomeFor(r, s, w + 2), Outcome.win);
    }
  });

  test('paçisi: bölümler üretilir', () {
    final rules = MasaPresets.pachisi('oyun-pacisi');
    expect(rules.localPlayers, 4);
    final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
    for (final lv in [1, 250, 9999, 49999, 99999]) {
      final gl = rules.build(planner.spec(lv));
      expect(gl.validation.ok, isTrue);
      final back = gl.puzzle.rules.parse(gl.puzzle.start.serialize());
      expect(back.serialize(), gl.puzzle.start.serialize());
    }
    final (end, _) = BoardGameRules.simulateJudged(rules.build(planner.spec(9)).puzzle);
    expect(rules.rulesFor(1).isOver(end) || end.ply >= 4000, isTrue);
  });
}
