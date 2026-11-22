import 'dart:math' as math;

import 'package:studio_core/core/rng.dart';

import 'board_game.dart';
import 'grid_state.dart';

/// Zar oyunlarında hamle kodları.
const kScoreBase = 100, kReroll = 200, kBank = 201, kToggleBase = 300;

// ---------------------------------------------------------------- Zar beşlisi

/// Zar beşlisi: beş zar, turda en çok üç atış; her tur bir kategoriye yazılır.
/// cells[0..4] zarlar, cells[5..17] oyuncu 0 kategorileri, cells[18..30]
/// oyuncu 1 (-1 boş). vars: [0] bitti, [1] bu turdaki atış (0: atılacak),
/// [2] tutulan zarlar (bit), [3] yeniden atış bekliyor.
class ZarBesliRules extends BoardRules<GridState> {
  const ZarBesliRules();

  @override
  String get id => 'zar-besli';

  @override
  bool get stochastic => true;

  @override
  int get maxPly => 2000;

  static const cats = 13;

  @override
  GridState initial(SeededRandom r) => GridState(31, 1, [0, 0, 0, 0, 0, ...List.filled(26, -1)]);

  List<int> dice(GridState s) => s.cells.sublist(0, 5);
  int slot(int p, int k) => 5 + p * 13 + k;

  @override
  bool needsChance(GridState s) => s.vars[0] == 0 && (s.vars[1] == 0 || s.vars[3] == 1);

  @override
  void applyChance(GridState s, SeededRandom r) {
    final keep = s.vars[1] == 0 ? 0 : s.vars[2];
    for (var i = 0; i < 5; i++) {
      if (keep & (1 << i) == 0) s.cells[i] = 1 + r.nextInt(6);
    }
    s.vars[1]++;
    s.vars[3] = 0;
    if (s.vars[1] >= 3) s.vars[2] = 0;
  }

  /// Kategori puanı: 0..5 birler..altılar, 6 üçlü, 7 dörtlü, 8 ful (3+2),
  /// 9 küçük kent (4 sıralı), 10 büyük kent (5 sıralı), 11 beşli, 12 şans.
  static int score(List<int> d, int k) {
    final cnt = List.filled(7, 0);
    for (final x in d) {
      cnt[x]++;
    }
    final sum = d.fold<int>(0, (a, b) => a + b);
    bool run(int len) {
      for (var st = 1; st + len - 1 <= 6; st++) {
        var ok = true;
        for (var v = st; v < st + len; v++) {
          if (cnt[v] == 0) ok = false;
        }
        if (ok) return true;
      }
      return false;
    }

    switch (k) {
      case < 6:
        return cnt[k + 1] * (k + 1);
      case 6:
        return cnt.any((c) => c >= 3) ? sum : 0;
      case 7:
        return cnt.any((c) => c >= 4) ? sum : 0;
      case 8:
        return cnt.contains(3) && cnt.contains(2) ? 25 : 0;
      case 9:
        return run(4) ? 30 : 0;
      case 10:
        return run(5) ? 40 : 0;
      case 11:
        return cnt.contains(5) ? 50 : 0;
      default:
        return sum;
    }
  }

  int total(GridState s, int p) {
    var upper = 0, all = 0;
    for (var k = 0; k < 13; k++) {
      final v = s.cells[slot(p, k)];
      if (v < 0) continue;
      all += v;
      if (k < 6) upper += v;
    }
    return all + (upper >= 63 ? 35 : 0);
  }

  @override
  List<int> moves(GridState s) {
    if (isOver(s) || needsChance(s)) return const [];
    final p = s.turn;
    final out = <int>[
      for (var k = 0; k < 13; k++)
        if (s.cells[slot(p, k)] < 0) mv(-1, kScoreBase + k)
    ];
    if (s.vars[1] < 3) {
      out.add(mv(-1, kReroll));
      for (var i = 0; i < 5; i++) {
        out.add(mv(-1, kToggleBase + i));
      }
    }
    return out;
  }

  @override
  void apply(GridState s, int m) {
    final p = s.turn;
    final a = mvTo(m);
    s.ply++;
    if (a >= kToggleBase) {
      s.vars[2] ^= 1 << (a - kToggleBase);
      return;
    }
    if (a == kReroll) {
      s.vars[3] = 1;
      return;
    }
    final k = a - kScoreBase;
    s.cells[slot(p, k)] = score(dice(s), k);
    s.last = slot(p, k);
    s.vars[1] = 0;
    s.vars[2] = 0;
    s.turn = 1 - p;
    if (!s.cells.sublist(5).contains(-1)) s.vars[0] = 1;
  }

  @override
  bool isOver(GridState s) => s.vars[0] == 1;

  @override
  int winner(GridState s) {
    final a = total(s, 0), b = total(s, 1);
    return a == b ? -1 : (a > b ? 0 : 1);
  }

  @override
  double evaluate(GridState s, int player) => (total(s, player) - total(s, 1 - player)).toDouble();

  /// Kategoriye yazmanın değeri (geleceği de düşünerek kabaca).
  double _catValue(GridState s, int p, List<int> d, int k) {
    final v = score(d, k).toDouble();
    final cnt = List.filled(7, 0);
    for (final x in d) {
      cnt[x]++;
    }
    var bonus = 0.0;
    if (k < 6) {
      bonus = (cnt[k + 1] - 3) * (k + 1) * 1.2; // üst bölüm primi için 3 adet hedefi
    }
    const expect = [2.0, 5, 8, 11, 14, 17, 18, 8, 15, 18, 12, 6, 22];
    return v - expect[k] * 0.55 + bonus;
  }

  int _bestCat(GridState s, int p, List<int> d) {
    var best = -1;
    var bv = -1e9;
    for (var k = 0; k < 13; k++) {
      if (s.cells[slot(p, k)] >= 0) continue;
      final v = _catValue(s, p, d, k);
      if (v > bv) {
        bv = v;
        best = k;
      }
    }
    return best;
  }

  @override
  int? policy(GridState s, double noise, SeededRandom r) {
    final p = s.turn;
    final d = dice(s);
    if (s.vars[1] >= 3) return mv(-1, kScoreBase + _bestCat(s, p, d));
    // Tutma seçimi: her maskeyi birkaç benzetimle dene.
    final samples = noise >= 0.8 ? 3 : (noise >= 0.4 ? 8 : 16);
    var bestMask = 31;
    var bestV = -1e9;
    for (var mask = 0; mask < 32; mask++) {
      var tot = 0.0;
      for (var k = 0; k < samples; k++) {
        final nd = [for (var i = 0; i < 5; i++) mask & (1 << i) != 0 ? d[i] : 1 + r.nextInt(6)];
        final c = _bestCat(s, p, nd);
        tot += _catValue(s, p, nd, c);
      }
      final v = tot / samples + (mask == 31 ? 0.5 : 0) + r.nextDouble() * noise * 6;
      if (v > bestV) {
        bestV = v;
        bestMask = mask;
      }
    }
    if (bestMask == 31) return mv(-1, kScoreBase + _bestCat(s, p, d));
    // İstenen maskeye ulaşmak için önce zarları tut/bırak, sonra at.
    for (var i = 0; i < 5; i++) {
      final want = bestMask & (1 << i) != 0, has = s.vars[2] & (1 << i) != 0;
      if (want != has) return mv(-1, kToggleBase + i);
    }
    return mv(-1, kReroll);
  }

  @override
  String status(GridState s, String lang) => '${total(s, 0)} : ${total(s, 1)}';

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}

// ---------------------------------------------------------------- Farkle

/// Farkle: altı zar. Puan veren zarları ayır, ya kalanları at ya da puanı
/// kasaya koy. Puansız atış turun puanını sıfırlar. Hedefe ilk varan kazanır.
/// cells[0..5] zarlar, cells[6..11] ayrılan (1)/seçili (2)/boşta (0).
/// vars: [0] bitti, [1] atış bekliyor, [2..3] oyuncu skorları, [4] tur puanı,
/// [5] hedef/50.
class FarkleRules extends BoardRules<GridState> {
  final int target;
  const FarkleRules([this.target = 4000]);

  @override
  String get id => 'farkle';

  @override
  bool get stochastic => true;

  @override
  int get maxPly => 3000;

  @override
  GridState initial(SeededRandom r) {
    final s = GridState(12, 1, List.filled(12, 0));
    s.vars[1] = 1;
    return s;
  }

  /// Seçilen zarların puanı; geçersizse -1 (her zar puana katılmalı).
  static int scoreOf(List<int> d) {
    if (d.isEmpty) return -1;
    final cnt = List.filled(7, 0);
    for (final x in d) {
      cnt[x]++;
    }
    if (d.length == 6) {
      if (cnt.sublist(1).every((c) => c == 1)) return 1500;
      if (cnt.where((c) => c == 2).length == 3) return 1500;
    }
    var pts = 0;
    for (var v = 1; v <= 6; v++) {
      var c = cnt[v];
      if (c >= 3) {
        final base = v == 1 ? 1000 : v * 100;
        pts += c == 3 ? base : (c == 4 ? base * 2 : (c == 5 ? base * 3 : base * 4));
        c = 0;
      }
      if (v == 1) pts += c * 100;
      if (v == 5) pts += c * 50;
      if (c > 0 && v != 1 && v != 5) return -1;
    }
    return pts;
  }

  List<int> free(GridState s) => [for (var i = 0; i < 6; i++) if (s.cells[6 + i] != 1) i];
  List<int> chosen(GridState s) => [for (var i = 0; i < 6; i++) if (s.cells[6 + i] == 2) s.cells[i]];

  /// Boştaki zarlarda puan veren bir şey var mı.
  bool _hasScore(GridState s) {
    final d = [for (final i in free(s)) s.cells[i]];
    if (d.contains(1) || d.contains(5)) return true;
    final cnt = List.filled(7, 0);
    for (final x in d) {
      cnt[x]++;
    }
    return cnt.any((c) => c >= 3) || scoreOf(d) > 0;
  }

  @override
  bool needsChance(GridState s) => s.vars[0] == 0 && s.vars[1] == 1;

  @override
  void applyChance(GridState s, SeededRandom r) {
    if (free(s).isEmpty) {
      for (var i = 0; i < 6; i++) {
        s.cells[6 + i] = 0; // sıcak zar: hepsi yeniden
      }
    }
    for (final i in free(s)) {
      s.cells[i] = 1 + r.nextInt(6);
      s.cells[6 + i] = 0;
    }
    s.vars[1] = 0;
    if (!_hasScore(s)) {
      // Farkle: tur puanı yanar, sıra geçer.
      s.vars[4] = 0;
      s.turn = 1 - s.turn;
      for (var i = 0; i < 6; i++) {
        s.cells[6 + i] = 0;
      }
      s.vars[1] = 1;
      s.last = -2;
    }
  }

  @override
  List<int> moves(GridState s) {
    if (isOver(s) || needsChance(s)) return const [];
    final out = <int>[for (final i in free(s)) mv(-1, kToggleBase + i)];
    final sc = scoreOf(chosen(s));
    if (sc > 0) {
      out.add(mv(-1, kReroll));
      out.add(mv(-1, kBank));
    }
    return out;
  }

  @override
  void apply(GridState s, int m) {
    final a = mvTo(m);
    final p = s.turn;
    s.ply++;
    s.last = -1;
    if (a >= kToggleBase) {
      final i = a - kToggleBase;
      s.cells[6 + i] = s.cells[6 + i] == 2 ? 0 : 2;
      return;
    }
    s.vars[4] += scoreOf(chosen(s));
    for (var i = 0; i < 6; i++) {
      if (s.cells[6 + i] == 2) s.cells[6 + i] = 1;
    }
    if (a == kBank) {
      s.vars[2 + p] += s.vars[4];
      s.vars[4] = 0;
      if (s.vars[2 + p] >= target) {
        s.vars[0] = 1;
        return;
      }
      for (var i = 0; i < 6; i++) {
        s.cells[6 + i] = 0;
      }
      s.turn = 1 - p;
    }
    s.vars[1] = 1;
  }

  @override
  bool isOver(GridState s) => s.vars[0] == 1;

  @override
  int winner(GridState s) => s.vars[2] == s.vars[3] ? -1 : (s.vars[2] > s.vars[3] ? 0 : 1);

  @override
  double evaluate(GridState s, int player) => (s.vars[2 + player] - s.vars[3 - player]) / 50.0;

  @override
  int? policy(GridState s, double noise, SeededRandom r) {
    final p = s.turn;
    final fr = free(s);
    // En iyi puan veren alt küme (en çok puan, eşitlikte az zar).
    var bestMask = 0, bestScore = 0, bestCount = 99;
    for (var mask = 1; mask < (1 << fr.length); mask++) {
      final d = [for (var k = 0; k < fr.length; k++) if (mask & (1 << k) != 0) s.cells[fr[k]]];
      final sc = scoreOf(d);
      if (sc <= 0) continue;
      final greedy = noise < 0.5 ? sc - d.length * 40 : sc;
      if (greedy > bestScore - bestCount * 40 || bestScore == 0) {
        bestScore = sc;
        bestMask = mask;
        bestCount = d.length;
      }
    }
    for (var k = 0; k < fr.length; k++) {
      final want = bestMask & (1 << k) != 0;
      final has = s.cells[6 + fr[k]] == 2;
      if (want != has) return mv(-1, kToggleBase + fr[k]);
    }
    final turnPts = s.vars[4] + scoreOf(chosen(s));
    final left = fr.length - bestCount;
    final need = target - s.vars[2 + p];
    final stopAt = left == 0 ? 99999 : (left >= 4 ? 450 : (left == 3 ? 400 : (left == 2 ? 300 : 250)));
    final bold = noise * 200 * (r.nextDouble() - 0.5);
    if (turnPts >= need || turnPts >= stopAt + bold) return mv(-1, kBank);
    return mv(-1, kReroll);
  }

  @override
  String status(GridState s, String lang) => '${s.vars[2]} : ${s.vars[3]}  ·  +${s.vars[4]}  ·  → $target';

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}

// ---------------------------------------------------------------- Yalancı zarı

/// Yalancı zarı (puanla): her oyuncunun 5 gizli zarı. Sırayla "masada en az
/// N tane X var" denir; ya artırılır ya da "yalan" denir. Birler her sayı
/// yerine geçer. Yanılan bir zar kaybeder; zarı kalan son oyuncu kazanır.
/// cells[p*5+k]: zar (0 = kaybedilmiş). vars: [0] kazanan+1, [1] teklif
/// (adet*10+yüz, 0 yok), [2] teklif sahibi, [3] atış bekliyor, [4] oyuncu sayısı,
/// [5] son açılışta kaybeden+1.
class LiarRules extends BoardRules<GridState> {
  final int count;
  const LiarRules([this.count = 2]);

  @override
  String get id => 'yalanci-zari';

  @override
  int get players => count;

  @override
  bool get stochastic => true;

  @override
  int get maxPly => 600;

  static const kLiar = 1;

  @override
  GridState initial(SeededRandom r) {
    final s = GridState(20, 1, List.filled(20, 1));
    for (var i = count * 5; i < 20; i++) {
      s.cells[i] = 0;
    }
    s.vars[3] = 1;
    s.vars[4] = count;
    return s;
  }

  int diceOf(GridState s, int p) => [for (var k = 0; k < 5; k++) s.cells[p * 5 + k]].where((x) => x > 0).length;
  int get totalDiceMax => count * 5;
  int alive(GridState s) => [for (var p = 0; p < count; p++) diceOf(s, p)].where((n) => n > 0).length;

  @override
  bool needsChance(GridState s) => s.vars[0] == 0 && s.vars[3] == 1;

  @override
  void applyChance(GridState s, SeededRandom r) {
    for (var i = 0; i < count * 5; i++) {
      if (s.cells[i] > 0) s.cells[i] = 1 + r.nextInt(6);
    }
    s.vars[3] = 0;
    s.vars[1] = 0;
  }

  int totalDice(GridState s) => [for (var p = 0; p < count; p++) diceOf(s, p)].fold<int>(0, (a, b) => a + b);

  /// Bir yüzün masadaki gerçek sayısı (birler joker).
  int countFace(GridState s, int face) {
    var n = 0;
    for (var i = 0; i < count * 5; i++) {
      final v = s.cells[i];
      if (v == face || (v == 1 && face != 1)) n++;
    }
    return n;
  }

  @override
  List<int> moves(GridState s) {
    if (isOver(s) || needsChance(s)) return const [];
    final bid = s.vars[1];
    final q0 = bid ~/ 10, f0 = bid % 10;
    final out = <int>[];
    if (bid > 0) out.add(mv(-1, kLiar));
    final tot = totalDice(s);
    for (var q = q0 == 0 ? 1 : q0; q <= tot; q++) {
      for (var f = 2; f <= 6; f++) {
        if (q == q0 && f <= f0) continue;
        out.add(mv(-1, q * 10 + f));
      }
      if (out.length > 40) break;
    }
    return out;
  }

  int _nextAlive(GridState s, int p) {
    var q = p;
    for (var k = 0; k < count; k++) {
      q = (q + 1) % count;
      if (diceOf(s, q) > 0) return q;
    }
    return p;
  }

  void _lose(GridState s, int p) {
    for (var k = 4; k >= 0; k--) {
      if (s.cells[p * 5 + k] > 0) {
        s.cells[p * 5 + k] = 0;
        break;
      }
    }
  }

  @override
  void apply(GridState s, int m) {
    final p = s.turn;
    final a = mvTo(m);
    s.ply++;
    if (a == kLiar) {
      final bid = s.vars[1];
      final real = countFace(s, bid % 10);
      final loser = real >= bid ~/ 10 ? p : s.vars[2];
      _lose(s, loser);
      s.vars[5] = loser + 1;
      s.last = -3;
      if (alive(s) == 1) {
        s.vars[0] = [for (var q = 0; q < count; q++) if (diceOf(s, q) > 0) q].first + 1;
        return;
      }
      s.turn = diceOf(s, loser) > 0 ? loser : _nextAlive(s, loser);
      s.vars[3] = 1;
      return;
    }
    s.vars[1] = a;
    s.vars[2] = p;
    s.last = -1;
    s.turn = _nextAlive(s, p);
  }

  @override
  bool isOver(GridState s) => s.vars[0] != 0;

  @override
  int winner(GridState s) => s.vars[0] - 1;

  @override
  double evaluate(GridState s, int player) {
    var others = 0;
    for (var p = 0; p < count; p++) {
      if (p != player) others += diceOf(s, p);
    }
    return (diceOf(s, player) * (count - 1) - others) * 10.0;
  }

  /// Oyuncunun yalnız kendi zarlarını bilerek, teklifin doğru olma olasılığı (yaklaşık).
  double _plausible(GridState s, int p, int q, int f) {
    var mine = 0;
    for (var k = 0; k < 5; k++) {
      final v = s.cells[p * 5 + k];
      if (v == f || (v == 1 && f != 1)) mine++;
    }
    final unknown = totalDice(s) - diceOf(s, p);
    final need = q - mine;
    if (need <= 0) return 1;
    final pr = f == 1 ? 1 / 6 : 1 / 3;
    final mean = unknown * pr;
    // Normal yaklaşık: kuyruk olasılığı
    final sd = math.sqrt(math.max(0.0001, unknown * pr * (1 - pr)));
    final z = (need - 0.5 - mean) / sd;
    return 1 / (1 + math.exp((1.7 * z).clamp(-30, 30)));
  }

  @override
  int? policy(GridState s, double noise, SeededRandom r) {
    final p = s.turn;
    final bid = s.vars[1];
    final ms = moves(s);
    if (bid > 0) {
      final pl = _plausible(s, p, bid ~/ 10, bid % 10);
      final callAt = 0.42 + (r.nextDouble() - 0.5) * noise * 0.4;
      if (pl < callAt) return mv(-1, kLiar);
    }
    // En inandırıcı artırım; zayıf rakip ara sıra blöf yapar.
    var best = ms.firstWhere((m) => mvTo(m) != kLiar, orElse: () => ms.first);
    var bv = -1.0;
    for (final m in ms) {
      final a = mvTo(m);
      if (a == kLiar) continue;
      final v = _plausible(s, p, a ~/ 10, a % 10) - (a ~/ 10) * 0.02 + r.nextDouble() * (0.05 + noise * 0.2);
      if (v > bv) {
        bv = v;
        best = m;
      }
    }
    return best;
  }

  @override
  String status(GridState s, String lang) => [for (var q = 0; q < count; q++) '${diceOf(s, q)}'].join(' · ');

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}
