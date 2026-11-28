// Tavla, Satranç, Dama, Go ve Kızma Birader kural testleri (bağımsız QA, 28.11).
// Kaynaklar: FIDE Satranç Kuralları (2023) ve chessprogramming.org perft
// değerleri; Türk tavlası (Türkiye'de yaygın kural, bkz. bkgm.com kuralları);
// Wikipedia "Turkish draughts", WCDF İngiliz daması; Tromp-Taylor Go kuralları
// (alan sayımı, komi 6,5); "Mensch ärgere dich nicht" resmî kuralları.
import 'package:flutter_test/flutter_test.dart';
import 'package:masa_motoru/masa_motoru.dart';
import 'package:studio_core/core/rng.dart';

int sq(String a) => (8 - int.parse(a[1])) * 8 + a.codeUnitAt(0) - 97;

GridState fen(String f) {
  final parts = f.trim().split(RegExp(r'\s+'));
  final cells = List.filled(64, -1);
  final rows = parts[0].split('/');
  for (var r = 0; r < 8; r++) {
    var c = 0;
    for (final ch in rows[r].split('')) {
      final d = int.tryParse(ch);
      if (d != null) {
        c += d;
        continue;
      }
      final color = ch == ch.toUpperCase() ? 0 : 1;
      cells[r * 8 + c] = color * 8 + 'pnbrqk'.indexOf(ch.toLowerCase()) + 1;
      c++;
    }
  }
  final vars = List.filled(8, 0, growable: true);
  final cr = parts[2];
  vars[2] = (cr.contains('K') ? 1 : 0) | (cr.contains('Q') ? 2 : 0) | (cr.contains('k') ? 4 : 0) | (cr.contains('q') ? 8 : 0);
  vars[6] = 7 * 8 + 0;
  if (parts[3] != '-') vars[3] = sq(parts[3]) + 1;
  return GridState(8, 8, cells, vars)..turn = parts[1] == 'w' ? 0 : 1;
}

int perft(ChessRules rules, GridState s, int d) {
  final ms = rules.moves(s);
  if (d == 1) return ms.length;
  var n = 0;
  for (final m in ms) {
    final c = s.copy();
    rules.apply(c, m);
    n += perft(rules, c, d - 1);
  }
  return n;
}

int find(List<int> ms, int from, int to, [int extra = -1]) =>
    ms.firstWhere((m) => mvFrom(m) == from && mvTo(m) == to && (extra < 0 || mvExtra(m) == extra), orElse: () => -1);

void play(ChessRules rules, GridState s, String from, String to) {
  final m = find(rules.moves(s), sq(from), sq(to));
  expect(m, isNot(-1), reason: '$from-$to yasal olmalı');
  rules.apply(s, m);
}

void main() {
  group('Satranç (FIDE)', () {
    const rules = ChessRules();

    test('perft: başlangıç 20 / 400 / 8902', () {
      final s = rules.initial(SeededRandom(1));
      expect(perft(rules, s, 1), 20);
      expect(perft(rules, s, 2), 400);
      expect(perft(rules, s, 3), 8902);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('perft: Kiwipete 48 / 2039 (rok, geçerken alma, terfi)', () {
      final s = fen('r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1');
      expect(perft(rules, s, 1), 48);
      expect(perft(rules, s, 2), 2039);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('perft: konum 3 (14 / 191 / 2812) ve konum 4 (6 / 264)', () {
      final s3 = fen('8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1');
      expect(perft(rules, s3, 1), 14);
      expect(perft(rules, s3, 2), 191);
      expect(perft(rules, s3, 3), 2812);
      final s4 = fen('r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1');
      expect(perft(rules, s4, 1), 6);
      expect(perft(rules, s4, 2), 264);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('çoban matı: siyah kazanır', () {
      final s = rules.initial(SeededRandom(1));
      play(rules, s, 'f2', 'f3');
      play(rules, s, 'e7', 'e5');
      play(rules, s, 'g2', 'g4');
      play(rules, s, 'd8', 'h4');
      expect(rules.isOver(s), isTrue);
      expect(rules.winner(s), 1);
    });

    test('pat berabere', () {
      final s = fen('7k/8/6K1/8/8/8/5Q2/8 w - - 0 1');
      play(rules, s, 'f2', 'f7');
      expect(rules.isOver(s), isTrue);
      expect(rules.winner(s), -1);
    });

    test('üç kez tekrar berabere (yalnız üçüncüde)', () {
      final s = rules.initial(SeededRandom(1));
      for (var round = 0; round < 2; round++) {
        play(rules, s, 'g1', 'f3');
        play(rules, s, 'g8', 'f6');
        play(rules, s, 'f3', 'g1');
        expect(rules.isOver(s), isFalse);
        play(rules, s, 'f6', 'g8');
      }
      expect(rules.isOver(s), isTrue);
      expect(rules.winner(s), -1);
      // Serileştirilip açılan durumda da tekrar izlenir.
      final t = rules.initial(SeededRandom(1));
      play(rules, t, 'g1', 'f3');
      play(rules, t, 'g8', 'f6');
      final back = rules.parse(t.serialize());
      play(rules, back, 'f3', 'g1');
      play(rules, back, 'f6', 'g8');
      play(rules, back, 'g1', 'f3');
      play(rules, back, 'g8', 'f6');
      play(rules, back, 'f3', 'g1');
      expect(rules.isOver(back), isFalse);
      play(rules, back, 'f6', 'g8');
      expect(rules.isOver(back), isTrue);
    });

    test('50 hamle kuralı ve yetersiz taş berabere', () {
      final s = rules.initial(SeededRandom(1));
      s.vars[1] = 99;
      play(rules, s, 'g1', 'f3');
      expect(rules.isOver(s), isTrue);
      expect(rules.winner(s), -1);
      final t = fen('8/8/8/8/8/2k5/3r4/1N2K3 w - - 0 1');
      play(rules, t, 'b1', 'd2');
      expect(rules.isOver(t), isTrue);
      expect(rules.winner(t), -1);
    });

    test('rok: tehdit altındaki kareden geçilmez; şah oynayınca hak gider', () {
      final s = fen('4k3/8/8/8/8/8/5r2/R3K2R w KQ - 0 1');
      final ms = rules.moves(s);
      expect(find(ms, sq('e1'), sq('g1'), 9), -1);
      expect(find(ms, sq('e1'), sq('c1'), 10), isNot(-1));
      final t = fen('4k3/8/8/8/8/8/8/R3K2R w KQ - 0 1');
      play(rules, t, 'e1', 'e2');
      play(rules, t, 'e8', 'd8');
      play(rules, t, 'e2', 'e1');
      play(rules, t, 'd8', 'e8');
      final ms2 = rules.moves(t);
      expect(ms2.where((m) => mvExtra(m) >= 9), isEmpty);
    });

    test('geçerken alma yalnız hemen ve doğru piyonu alır; terfi dört seçenek', () {
      final s = fen('4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1');
      play(rules, s, 'e5', 'd6');
      expect(s.cells[sq('d5')], -1);
      expect(s.cells[sq('d6')], cP);
      final t = fen('4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1');
      play(rules, t, 'e1', 'f1');
      play(rules, t, 'e8', 'f8');
      expect(find(rules.moves(t), sq('e5'), sq('d6')), -1);
      final p = fen('4k3/1P6/8/8/8/8/8/4K3 w - - 0 1');
      final promos = rules.moves(p).where((m) => mvFrom(m) == sq('b7') && mvTo(m) == sq('b8')).map(mvExtra).toSet();
      expect(promos, {cQ, cR, cB, cN});
    });

    test('rastgele 40 oyun: şah hiç tehdit altında bırakılmaz, oyunlar kuralla biter', () {
      final r = SeededRandom(2024);
      var ended = 0;
      for (var g = 0; g < 40; g++) {
        final s = rules.initial(r);
        while (!rules.isOver(s) && s.ply < 5000) {
          final ms = rules.moves(s);
          expect(ms, isNotEmpty);
          final p = s.turn;
          rules.apply(s, ms[r.nextInt(ms.length)]);
          expect(rules.inCheck(s, p), isFalse);
          expect(s.vars.length, lessThanOrEqualTo(8 + 102));
        }
        if (rules.isOver(s)) ended++;
      }
      expect(ended, 40);
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('Tavla', () {
    const rules = TavlaRules();
    TavlaState st(Map<int, int> cells, int d1, int d2, {int turn = 0}) {
      final c = List.filled(28, 0);
      cells.forEach((k, v) => c[k] = v);
      final s = TavlaState(c, List.filled(8, 0), List.filled(27, 0))..turn = turn;
      s.vars[5] = 1;
      if (d1 == d2) {
        for (var i = 1; i <= 4; i++) {
          s.vars[i] = d1;
        }
      } else {
        s.vars[1] = d1;
        s.vars[2] = d2;
      }
      return s;
    }

    test('başlangıç: 15\'er pul, 167 pip, ilk atış eşit olamaz', () {
      for (var seed = 1; seed < 30; seed++) {
        final s = rules.initial(SeededRandom(seed));
        expect(rules.pips(s, 0), 167);
        expect(rules.pips(s, 1), 167);
        final d = rules.dice(s);
        expect(d.length, 2);
        expect(d[0], isNot(d[1]));
        expect(s.turn, d[0] > d[1] ? 0 : 1);
      }
    });

    test('kırık pul önce girer', () {
      final s = st({24: 1, 5: 14, 18: -15}, 3, 4);
      final ms = rules.moves(s);
      expect(ms.every((m) => mvFrom(m) == 24), isTrue);
      expect(ms.map(mvTo).toSet(), {21, 20});
    });

    test('iki zar oynanabiliyorsa ikisi, yalnız biri oynanabiliyorsa büyüğü', () {
      final s = st({12: 1, 26: 14, 1: -2, 20: -13}, 6, 5);
      expect(rules.moves(s), [mv(12, 6, 6)]);
    });

    test('çift zar dört kez oynanır; iki pul olan noktaya konmaz; tek pul vurulur', () {
      final s = st({20: 2, 10: 13, 16: -2, 22: -13}, 2, 2);
      // 20'den 18'e (16 kapalı olduğundan 4 ileri gidilemez)…
      var plays = 0;
      while (s.turn == 0 && plays < 6) {
        final ms = rules.moves(s);
        if (ms.first == kPass) break;
        expect(ms.any((m) => mvTo(m) == 16), isFalse);
        rules.apply(s, ms.first);
        plays++;
      }
      expect(plays, 4);
      final h = st({10: 1, 9: 14, 7: -1, 20: -14}, 3, 1);
      rules.apply(h, mv(10, 7, 3));
      expect(h.cells[25], 1);
      expect(h.cells[7], 1);
    });

    test('toplama: dışarıda pul varken toplanmaz; tam zar ya da en arkadaki pul büyük zarla', () {
      final s = st({10: 1, 1: 14, 20: -15}, 6, 5);
      expect(rules.moves(s).where((m) => mvTo(m) == 26), isEmpty);
      final t = st({3: 2, 1: 13, 20: -15}, 6, 1);
      final ms = rules.moves(t);
      expect(ms, contains(mv(3, 26, 6)));
      expect(ms, isNot(contains(mv(1, 26, 6))));
    });

    test('mars: rakip hiç pul toplamadıysa 2; rakibin pulu kırıkta ya da evimizde ise 3', () {
      final s = st({0: 1, 26: 14, 20: -15}, 1, 2);
      rules.apply(s, mv(0, 26, 1));
      expect(rules.isOver(s), isTrue);
      expect(rules.winner(s), 0);
      expect(s.vars[6], 2);
      final t = st({0: 1, 26: 14, 20: -14, 2: -1}, 1, 2);
      rules.apply(t, mv(0, 26, 1));
      expect(t.vars[6], 3);
      final u = st({0: 1, 26: 14, 20: -10, 27: 5}, 1, 2);
      rules.apply(u, mv(0, 26, 1));
      expect(u.vars[6], 1);
    });

    test('Plakoto: rakibin başlangıç noktasındaki son pulunu (anne) sıkıştıran kazanır, kendi annesi yerindeyse kazanmaz', () {
      const pr = TavlaRules(TavlaVariant.plakoto);
      // Siyahın (1) başlangıcı 0; orada tek pulu kalmış. Beyaz 3'ten 3 atıp 0'a konar.
      final s = st({3: 1, 10: 14, 0: -1, 15: -14}, 3, 5);
      pr.apply(s, mv(3, 0, 3));
      expect(pr.isOver(s), isTrue);
      expect(pr.winner(s), 0);
      expect(s.vars[6], 2);
      final t = st({3: 1, 23: 2, 10: 12, 0: -1, 15: -14}, 3, 5);
      pr.apply(t, mv(3, 0, 3));
      expect(pr.isOver(t), isFalse);
      expect(t.pins[0], -1);
    });

    for (final v in TavlaVariant.values) {
      test('botlar ($v): 40 oyun yasal, pul korunur, oyun biter', () {
        final rr = TavlaRules(v);
        final r = SeededRandom(v.index * 100 + 7);
        var w0 = 0;
        for (var g = 0; g < 40; g++) {
          final s = rr.initial(r);
          var guard = 0;
          while (!rr.isOver(s) && guard++ < 3000) {
            if (rr.needsChance(s)) {
              rr.applyChance(s, r);
              continue;
            }
            final ms = rr.moves(s);
            final m = rr.policy(s, g.isEven ? 0.0 : 0.6, r) ?? ms.first;
            expect(ms, contains(m));
            rr.apply(s, m);
            for (final p in [0, 1]) {
              var n = s.cells[p == 0 ? 24 : 25] + s.cells[p == 0 ? 26 : 27];
              for (var i = 0; i < 24; i++) {
                n += rr.mine(s, i, p);
                if (v == TavlaVariant.plakoto && s.pins[i] == (p == 0 ? 1 : -1)) n++;
              }
              expect(n, rr.checkers, reason: '$v oyun $g pul sayısı');
            }
          }
          expect(rr.isOver(s), isTrue, reason: '$v oyun $g bitmedi');
          if (rr.winner(s) == 0) w0++;
        }
        // ignore: avoid_print
        print('tavla $v: 40 oyun, beyaz $w0');
      }, timeout: const Timeout(Duration(minutes: 4)));
    }
  });

  group('Dama', () {
    GridState board(Map<int, int> pieces, {int turn = 0}) {
      final c = List.filled(64, -1);
      pieces.forEach((k, v) => c[k] = v);
      return GridState(8, 8, c)..turn = turn;
    }

    test('Türk daması: 16\'şar taş, ikinci-üçüncü sırada', () {
      final s = DraughtsRules.turkish.initial(SeededRandom(1));
      expect(s.cells.where((v) => v == 0).length, 16);
      expect(s.cells.where((v) => v == 1).length, 16);
      expect([for (var c = 0; c < 8; c++) s.cells[c]].every((v) => v < 0), isTrue);
    });

    test('Türk daması: en çok taş alan yol zorunlu, alınan taşlar kalkar', () {
      const rules = DraughtsRules.turkish;
      final s = board({43: 0, 46: 0, 35: 1, 19: 1, 38: 1});
      final ms = rules.moves(s);
      expect(ms.map((m) => (mvFrom(m), mvTo(m))).toList(), [(43, 11)]);
      rules.apply(s, ms.single);
      expect(s.cells[35], -1);
      expect(s.cells[19], -1);
      expect(s.cells[11], 0);
    });

    test('Türk daması: taş geri gitmez, geri almaz; ileri ve yana yürür', () {
      const rules = DraughtsRules.turkish;
      final s = board({27: 0, 35: 1, 7: 1});
      final ms = rules.moves(s);
      expect(ms.map(mvTo).toSet(), {19, 26, 28});
    });

    test('Türk daması: uçan dama uzaktan alır, ardındaki her boş kareye konabilir; 180° dönüş yok', () {
      const rules = DraughtsRules.turkish;
      final s = board({56: 2, 24: 1, 7: 1});
      expect(rules.moves(s).map(mvTo).toSet(), {16, 8, 0});
      final t = board({35: 2, 34: 1, 37: 1});
      final ms = rules.moves(t);
      expect(ms.map(mvTo).toSet(), {33, 32, 38, 39});
    });

    test('Türk daması: son sıraya varan taş dama olur; oynayamayan kaybeder', () {
      const rules = DraughtsRules.turkish;
      final s = board({11: 0, 60: 1});
      rules.apply(s, mv(11, 3));
      expect(s.cells[3], 2);
      // Siyahın (1) tek taşı 48'de: altı, yanı dolu, alamaz → beyaz 40→32 sonrası hamlesi yok.
      final t = board({48: 1, 56: 0, 49: 0, 50: 0, 40: 0});
      rules.apply(t, mv(40, 32));
      expect(rules.isOver(t), isTrue);
      expect(rules.winner(t), 0);
    });

    test('İngiliz daması: 12\'şer taş, açılışta 7 hamle; taş geriye almaz, alım zorunlu', () {
      const rules = DraughtsRules.english;
      final s = rules.initial(SeededRandom(1));
      expect(s.cells.where((v) => v == 0).length, 12);
      expect(rules.moves(s).length, 7);
      // Beyaz taş 36 (r4 c4); siyah 27 (ileride) alınabilir, 45 (geride) alınamaz.
      final t = board({36: 0, 27: 1, 45: 1});
      expect(rules.moves(t).map((m) => (mvFrom(m), mvTo(m))).toList(), [(36, 18)]);
    });

    for (final rr in [DraughtsRules.turkish, DraughtsRules.english]) {
      test('botlar (${rr.id}): rastgele 60 oyun yasal ve biter', () {
        final r = SeededRandom(5);
        for (var g = 0; g < 60; g++) {
          final s = rr.initial(r);
          while (!rr.isOver(s) && s.ply < 2000) {
            final ms = rr.moves(s);
            rr.apply(s, ms[r.nextInt(ms.length)]);
          }
          expect(rr.isOver(s), isTrue);
        }
      });
    }
  });

  group('Go', () {
    const rules = GoRules();
    GridState board(Map<int, int> stones, {int turn = 0}) {
      final c = List.filled(81, -1);
      stones.forEach((k, v) => c[k] = v);
      return GridState(9, 9, c)..turn = turn;
    }

    test('alma, intihar yasağı, ko', () {
      final s = board({10: 1, 1: 0, 9: 0, 11: 0});
      rules.apply(s, mv(-1, 19));
      expect(s.cells[10], -1);
      expect(s.vars[3], 1);
      final t = board({1: 1, 9: 1, 11: 1, 19: 1});
      expect(rules.legalAt(t, 10), isFalse);
      // Ko
      final k = board({1: 0, 9: 0, 19: 0, 10: 1, 2: 1, 12: 1, 20: 1});
      rules.apply(k, mv(-1, 11));
      expect(k.cells[10], -1);
      expect(rules.legalAt(k, 10), isFalse);
      rules.apply(k, mv(-1, 80));
      rules.apply(k, mv(-1, 79));
      expect(rules.legalAt(k, 10), isTrue);
    });

    test('iki pas oyunu bitirir; alan sayımı + 6,5 komi', () {
      final s = board({});
      rules.apply(s, kPass);
      expect(rules.isOver(s), isFalse);
      rules.apply(s, kPass);
      expect(rules.isOver(s), isTrue);
      expect(rules.winner(s), 1);
      final t = board({40: 0});
      expect(rules.area(t), (81, 0));
      expect(rules.winner(t), 0);
      // 4 puan fark komiyi geçmez.
      final u = board({for (var r = 0; r < 9; r++) r * 9 + 4: 0, for (var r = 0; r < 9; r++) r * 9 + 5: 1});
      expect(rules.area(u), (45, 36));
      expect(rules.winner(u), 0);
      final w = board({for (var r = 0; r < 9; r++) r * 9 + 3: 0, for (var r = 0; r < 9; r++) r * 9 + 4: 1});
      expect(rules.area(w), (36, 45));
      expect(rules.winner(w), 1);
    });
  });

  group('Kızma Birader', () {
    const rules = KizmaRules(4);

    test('6 atmadan çıkılmaz, hepsi evdeyken üç deneme; 6 ile çıkış zorunlu ve yeniden atış', () {
      final s = rules.initial(SeededRandom(1));
      s.vars[1] = 5;
      expect(rules.moves(s), [kPass]);
      rules.apply(s, kPass);
      expect(s.turn, 0);
      expect(s.vars[2], 2);
      s.vars[1] = 4;
      rules.apply(s, kPass);
      s.vars[1] = 3;
      rules.apply(s, kPass);
      expect(s.turn, 1);
      final t = rules.initial(SeededRandom(1));
      t.vars[1] = 6;
      final ms = rules.moves(t);
      expect(ms.length, 1);
      rules.apply(t, ms.single);
      expect(t.cells.where((v) => v == 0).length, 1);
      expect(t.turn, 0);
      expect(rules.needsChance(t), isTrue);
    });

    test('rakip piyonun üstüne gelen onu eve yollar; hedefe tam zarla girilir', () {
      final s = rules.initial(SeededRandom(1));
      s.cells[0] = 2; // oyuncu 0, 2. kare
      s.cells[4] = 35; // oyuncu 1, mutlak kare (10 + 35) % 40 = 5
      s.vars[1] = 3;
      rules.apply(s, mv(-1, 0));
      expect(s.cells[0], 5);
      expect(s.cells[4], -1);
      final t = rules.initial(SeededRandom(1));
      t.cells[0] = 42;
      t.vars[1] = 2;
      expect(rules.moves(t), [kPass]);
    });

    test('botlar: 40 oyun (2-4 kişi) biter', () {
      final r = SeededRandom(8);
      for (var g = 0; g < 40; g++) {
        final rr = KizmaRules(2 + g % 3);
        final s = rr.initial(r);
        var guard = 0;
        while (!rr.isOver(s) && guard++ < 6000) {
          if (rr.needsChance(s)) {
            rr.applyChance(s, r);
            continue;
          }
          final ms = rr.moves(s);
          final m = rr.policy(s, 0.3, r) ?? ms.first;
          expect(ms, contains(m));
          rr.apply(s, m);
        }
        expect(rr.isOver(s), isTrue, reason: 'oyun $g');
      }
    });
  });
}
