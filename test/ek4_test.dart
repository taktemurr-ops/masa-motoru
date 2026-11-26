import 'package:flutter_test/flutter_test.dart';
import 'package:masa_motoru/masa_motoru.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/rng.dart';

/// Bir oyunu politikalarla sonuna kadar oynatır.
S playOut<S extends BoardState>(BoardRules<S> r, S s, SeededRandom rnd, {double noise = 0.3}) {
  final ai = BoardAI<S>(r, depth: 2, nodeBudget: 3000, noise: noise, r: rnd);
  var guard = 0;
  while (!r.isOver(s) && s.ply < r.maxPly && guard++ < 5000) {
    if (r.needsChance(s)) {
      r.applyChance(s, rnd);
      continue;
    }
    final ms = r.moves(s);
    expect(ms, isNotEmpty);
    final m = ai.choose(s);
    expect(ms.contains(m), isTrue);
    r.apply(s, m);
    // Her adımda JSON gidiş-dönüşü aynı durumu verir.
    if (s.ply % 17 == 0) expect(r.parse(s.serialize()).serialize(), s.serialize());
  }
  return s;
}

void levels(BoardGameRules rules, {int? local}) {
  final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
  if (local != null) expect(rules.localPlayers, local);
  for (final lv in [1, 7, 250, 9999, 99999]) {
    final gl = rules.build(planner.spec(lv));
    expect(gl.validation.ok, isTrue);
    final back = gl.puzzle.rules.parse(gl.puzzle.start.serialize());
    expect(back.serialize(), gl.puzzle.start.serialize());
  }
}

void main() {
  group('Kaplan ve Keçiler', () {
    const r = TigerGoatRules();
    test('başlangıç: dört köşede kaplan, keçiler konarak başlar', () {
      final s = r.initial(SeededRandom(1));
      expect(s.cells.where((x) => x == TigerGoatRules.tiger).length, 4);
      expect(s.turn, TigerGoatRules.goat);
      expect(r.moves(s).length, 21);
      expect(r.moves(s).every((m) => mvFrom(m) == -1), isTrue);
    });
    test('kaplan keçinin üstünden atlayıp yakalar', () {
      final s = r.initial(SeededRandom(1));
      r.apply(s, mv(-1, 6)); // keçi (1,1): köşedeki kaplanın çaprazında
      expect(r.moves(s).contains(mv(0, 12)), isTrue);
      r.apply(s, mv(0, 12));
      expect(s.cells[6], -1);
      expect(s.vars[3], 1);
      expect(s.cells[12], TigerGoatRules.tiger);
    });
    test('kıpırdayamayan kaplanlar kaybeder', () {
      final s = r.initial(SeededRandom(1));
      for (var i = 0; i < 25; i++) {
        s.cells[i] = -1;
      }
      s.cells[0] = TigerGoatRules.tiger;
      // (0,0) kaplanı: komşular (1,0) (0,1) (1,1); arkaları da dolu.
      for (final i in [1, 2, 5, 10, 6, 12]) {
        s.cells[i] = TigerGoatRules.goat;
      }
      s.vars[2] = 20;
      s.turn = TigerGoatRules.goat;
      r.apply(s, mv(12, 18));
      // 12 boşaldı: kaplan 6'nın üstünden atlayabilir → oyun sürer.
      expect(r.isOver(s), isFalse);
    });
    test('oyunlar biter, bölümler üretilir', () {
      for (final seed in [3, 4]) {
        final s = playOut(r, r.initial(SeededRandom(seed)), SeededRandom(seed));
        expect(r.isOver(s) || s.ply >= r.maxPly, isTrue);
      }
      levels(MasaPresets.tigerGoats('oyun-kaplan-ve-keciler'), local: 2);
    });
  });

  group('Gizli Rütbeler', () {
    const r = HiddenRanksRules();
    test('diziliş: 16 taş, yuva arka sırada, göller boş', () {
      final s = r.initial(SeededRandom(5));
      for (final p in [0, 1]) {
        final mine = [for (final x in s.cells) if (x >= 0 && HiddenRanksRules.owner(x) == p) HiddenRanksRules.rank(x)]..sort();
        expect(mine, [...HiddenRanksRules.army]..sort());
      }
      for (final l in HiddenRanksRules.lakes) {
        expect(s.cells[l], -2);
      }
      final f0 = s.cells.indexWhere((x) => x == HiddenRanksRules.piece(0, HiddenRanksRules.flag));
      expect(f0 ~/ 8, 7);
    });
    test('çarpışma kuralları', () {
      expect(HiddenRanksRules.battle(1, 10), 1); // fare fili yener
      expect(HiddenRanksRules.battle(10, 1), 1);
      expect(HiddenRanksRules.battle(3, 11), 1); // köstebek kapanı söker
      expect(HiddenRanksRules.battle(9, 11), -1);
      expect(HiddenRanksRules.battle(5, 5), 0);
      expect(HiddenRanksRules.battle(2, 0), 2);
    });
    test('tavşan uzun gider, saldırılan taşın rütbesi açılır', () {
      final s = r.initial(SeededRandom(1));
      for (var i = 0; i < 64; i++) {
        if (s.cells[i] >= 0) s.cells[i] = -1;
      }
      s.cells[56] = HiddenRanksRules.piece(0, 2);
      s.cells[0] = HiddenRanksRules.piece(1, 0);
      s.cells[63] = HiddenRanksRules.piece(0, 0);
      s.cells[7] = HiddenRanksRules.piece(1, 7);
      final ms = r.moves(s);
      expect(ms.contains(mv(56, 0)), isTrue); // sütun boyunca yuvaya
      r.apply(s, mv(56, 0));
      expect(r.winner(s), 0);
    });
    test('politika gizli rütbelere bakmaz: aynı açık bilgi aynı hamle', () {
      final a = r.initial(SeededRandom(9));
      final b = a.copy();
      // b'de rakibin iki gizli taşının yerini değiştir (açık bilgi aynı).
      final hidden = [for (var i = 0; i < 64; i++) if (b.cells[i] >= 0 && HiddenRanksRules.owner(b.cells[i]) == 1) i];
      final t = b.cells[hidden[0]];
      b.cells[hidden[0]] = b.cells[hidden[5]];
      b.cells[hidden[5]] = t;
      expect(r.policy(a, 0, SeededRandom(4)), r.policy(b, 0, SeededRandom(4)));
    });
    test('oyunlar biter, bölümler üretilir', () {
      for (final seed in [1, 2]) {
        final s = playOut(r, r.initial(SeededRandom(seed)), SeededRandom(seed));
        expect(r.isOver(s) || s.ply >= r.maxPly, isTrue);
      }
      levels(MasaPresets.hiddenRanks('oyun-gizli-rutbeler'), local: 2);
    });
  });

  group('Çini Döşeme', () {
    test('duvar deseni: her sırada ve sütunda her renk bir kez', () {
      for (var row = 0; row < 5; row++) {
        expect({for (var c = 0; c < 5; c++) TileDraftRules.wallCol(row, c)}.length, 5);
        for (var c = 0; c < 5; c++) {
          expect(TileDraftRules.wallColor(row, TileDraftRules.wallCol(row, c)), c);
        }
      }
      expect(TileDraftRules.placeScore(0, 2, 2), 1);
      // Yatay iki komşu + dikey bir komşu.
      final w = (1 << (2 * 5 + 1)) | (1 << (2 * 5 + 3)) | (1 << (1 * 5 + 2));
      expect(TileDraftRules.placeScore(w | (1 << 12), 2, 2), 3 + 2);
      expect(TileDraftRules.bonus(31), 2);
    });
    test('dağıtım, alma ve tur sonu', () {
      const r = TileDraftRules(2);
      final rnd = SeededRandom(3);
      final s = r.initial(rnd);
      expect(r.needsChance(s), isTrue);
      r.applyChance(s, rnd);
      expect(s.src.fold(0, (a, b) => a + b), 20);
      final m = r.moves(s).first;
      r.apply(s, m);
      expect(s.turn, 1);
      final played = playOut(r, s, rnd);
      expect(r.isOver(played), isTrue);
      expect(played.score.any((x) => x > 0), isTrue);
    });
    test('2-4 oyuncu biter, bölümler üretilir', () {
      for (final n in [3, 4]) {
        final r = TileDraftRules(n);
        final rnd = SeededRandom(n);
        expect(r.isOver(playOut(r, r.initial(rnd), rnd)), isTrue);
      }
      levels(MasaPresets.tileDraft('oyun-cini-doseme'), local: 2);
    });
  });

  group('Kartlı Beşleme', () {
    test('tahta: köşeler hariç her kart iki kez, vale yok', () {
      expect(CardLineRules.layout.where((c) => c < 0).length, 4);
      for (var c = 0; c < 52; c++) {
        expect(CardLineRules.spots[c]?.length ?? 0, CardLineRules.isJack(c) ? 0 : 2);
      }
    });
    test('beşli dizi kilitlenir, joker ve kaldırma valeleri', () {
      const r = CardLineRules(2);
      final s = r.initial(SeededRandom(1));
      // Üst sıra: köşe (0) + 1..4 oyuncu 0 → bir dizi.
      for (final i in [1, 2, 3]) {
        s.cells[i] = 0;
      }
      s.hands[0] = 3 * 13 + 10; // ♦ vale: joker
      r.apply(s, mv(CardLineRules.handBase, 4));
      expect(s.vars[4], 1);
      expect(s.cells[2], 10);
      expect(r.isOver(s), isFalse);
      // Rakip kaldırma valesiyle kilitli pulu alamaz.
      s.hands[s.handSize] = 0 * 13 + 10;
      final ms = r.moves(s).where((m) => mvFrom(m) == CardLineRules.handBase).toList();
      expect(ms.every((m) => s.cells[mvTo(m)] >= 0 && s.cells[mvTo(m)] < 10), isTrue);
    });
    test('oyunlar biter, bölümler üretilir', () {
      for (final n in [2, 3]) {
        final r = CardLineRules(n);
        final rnd = SeededRandom(n + 10);
        final s = playOut(r, r.initial(rnd), rnd);
        expect(r.isOver(s) || s.ply >= r.maxPly, isTrue);
      }
      levels(MasaPresets.cardLine('oyun-kartli-besleme'), local: 2);
    });
  });
}
