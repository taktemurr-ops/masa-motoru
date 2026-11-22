import 'dart:math' as math;

import 'package:studio_core/core/rng.dart';

import 'board_game.dart';
import 'grid_state.dart';

/// Takımadalar haritası: 18 bölge, 5 ada. Konumlar birim karede.
const kConquestPos = <(double, double)>[
  (0.12, 0.12), (0.31, 0.10), (0.13, 0.31), (0.32, 0.29), // A
  (0.63, 0.10), (0.84, 0.13), (0.66, 0.29), (0.87, 0.32), // B
  (0.40, 0.50), (0.60, 0.48), (0.50, 0.64), // C
  (0.12, 0.69), (0.31, 0.70), (0.13, 0.88), (0.33, 0.88), // D
  (0.68, 0.79), (0.87, 0.75), (0.79, 0.93), // E
];
const kConquestIsland = [0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4];
const kConquestBonus = [2, 2, 1, 2, 1];
const kConquestLand = <(int, int)>[
  (0, 1), (0, 2), (1, 3), (2, 3), (1, 2),
  (4, 5), (4, 6), (5, 7), (6, 7), (5, 6),
  (8, 9), (8, 10), (9, 10),
  (11, 12), (11, 13), (12, 14), (13, 14), (12, 13),
  (15, 16), (15, 17), (16, 17),
];
const kConquestSea = <(int, int)>[(3, 8), (1, 4), (6, 9), (12, 8), (10, 15), (14, 15), (7, 16), (2, 11)];

final List<List<int>> _adj = () {
  final a = List.generate(18, (_) => <int>[]);
  for (final (x, y) in [...kConquestLand, ...kConquestSea]) {
    a[x].add(y);
    a[y].add(x);
  }
  return a;
}();
List<int> conquestNeighbors(int t) => _adj[t];

/// Dünya hâkimiyeti: 2-4 oyuncu. Tur başında bölge sayının üçte biri (en az
/// 3) ve tamamen tuttuğun adaların ödülü kadar asker yerleştirirsin. Sonra
/// komşu düşman bölgelere saldırırsın: saldıran en çok 3, savunan en çok 2 zar
/// atar, en yüksekler karşılaştırılır, eşitlikte savunan kazanır. Bölgeyi
/// boşaltan oraya asker taşır. Turu bir askeri kaydırmayla bitirirsin.
/// Bir oyuncu elendiğinde ya da biri 13 bölgeye ulaştığında oyun biter; en
/// çok bölgesi olan kazanır.
///
/// Hücreler: 18 bölge; sahip * 100 + asker.
/// vars: [0] sonuç, [1] aşama (0 yerleştir, 1 saldır, 2 kaydır, 3 zar
/// bekleniyor), [2] kalan asker, [3] saldıran bölge, [4] hedef bölge,
/// [5..7] saldıran zarları, [8..9] savunan zarları, [10] oyuncu sayısı.
class ConquestRules extends BoardRules<GridState> {
  final int n;
  const ConquestRules([this.n = 2]);

  @override
  String get id => 'fetih-$n';
  @override
  int get players => n;
  @override
  bool get stochastic => true;
  @override
  int get maxPly => 700;

  @override
  GridState initial(SeededRandom r) {
    final s = GridState(18, 1, List.filled(18, 0), List.filled(12, 0));
    final order = List.generate(18, (i) => i);
    for (var i = 17; i > 0; i--) {
      final j = r.nextInt(i + 1);
      final t = order[i];
      order[i] = order[j];
      order[j] = t;
    }
    for (var k = 0; k < 18; k++) {
      s.cells[order[k]] = (k % n) * 100 + 1;
    }
    final extra = const [0, 0, 12, 9, 7][n];
    for (var p = 0; p < n; p++) {
      final mine = [for (var t = 0; t < 18; t++) if (owner(s, t) == p) t];
      for (var k = 0; k < extra; k++) {
        s.cells[mine[r.nextInt(mine.length)]]++;
      }
    }
    s.vars[10] = n;
    s.vars[2] = reinforcements(s, 0);
    return s;
  }

  int owner(GridState s, int t) => s.cells[t] ~/ 100;
  int armies(GridState s, int t) => s.cells[t] % 100;
  int count(GridState s, int p) => [for (var t = 0; t < 18; t++) if (owner(s, t) == p) t].length;

  int reinforcements(GridState s, int p) {
    var v = math.max(3, count(s, p) ~/ 3);
    for (var isl = 0; isl < 5; isl++) {
      var all = true;
      for (var t = 0; t < 18; t++) {
        if (kConquestIsland[t] == isl && owner(s, t) != p) all = false;
      }
      if (all) v += kConquestBonus[isl];
    }
    return v;
  }

  bool border(GridState s, int t) => conquestNeighbors(t).any((u) => owner(s, u) != owner(s, t));

  @override
  bool needsChance(GridState s) => !isOver(s) && s.vars[1] == 3;

  @override
  void applyChance(GridState s, SeededRandom r) {
    final a = s.vars[3], d = s.vars[4];
    final ad = math.min(3, armies(s, a) - 1), dd = math.min(2, armies(s, d));
    final ar = [for (var k = 0; k < ad; k++) 1 + r.nextInt(6)]..sort((x, y) => y - x);
    final dr = [for (var k = 0; k < dd; k++) 1 + r.nextInt(6)]..sort((x, y) => y - x);
    for (var k = 0; k < 3; k++) {
      s.vars[5 + k] = k < ar.length ? ar[k] : 0;
    }
    for (var k = 0; k < 2; k++) {
      s.vars[8 + k] = k < dr.length ? dr[k] : 0;
    }
    for (var k = 0; k < math.min(ad, dd); k++) {
      if (ar[k] > dr[k]) {
        s.cells[d]--;
      } else {
        s.cells[a]--;
      }
    }
    if (armies(s, d) == 0) {
      final move = math.min(armies(s, a) - 1, math.max(ad, (armies(s, a) - 1) ~/ 2));
      s.cells[d] = owner(s, a) * 100 + move;
      s.cells[a] -= move;
      s.last = d;
    }
    s.vars[1] = 1;
    _checkEnd(s);
  }

  void _checkEnd(GridState s) {
    final counts = [for (var p = 0; p < n; p++) count(s, p)];
    if (counts.any((c) => c == 0) || counts.any((c) => c >= 13)) s.vars[0] = _leader(s) + 1;
  }

  int _leader(GridState s) {
    var best = 0;
    var bv = -1;
    for (var p = 0; p < n; p++) {
      var arm = 0;
      for (var t = 0; t < 18; t++) {
        if (owner(s, t) == p) arm += armies(s, t);
      }
      final v = count(s, p) * 1000 + arm;
      if (v > bv) {
        bv = v;
        best = p;
      }
    }
    return best;
  }

  @override
  List<int> moves(GridState s) {
    if (isOver(s) || s.vars[1] == 3) return const [];
    final p = s.turn;
    final out = <int>[];
    switch (s.vars[1]) {
      case 0:
        for (var t = 0; t < 18; t++) {
          if (owner(s, t) == p) out.add(mv(-1, t));
        }
        return out;
      case 1:
        for (var t = 0; t < 18; t++) {
          if (owner(s, t) != p || armies(s, t) < 2) continue;
          for (final u in conquestNeighbors(t)) {
            if (owner(s, u) != p) out.add(mv(t, u));
          }
        }
        out.add(kPass);
        return out;
      default:
        for (var t = 0; t < 18; t++) {
          if (owner(s, t) != p || armies(s, t) < 2) continue;
          for (final u in conquestNeighbors(t)) {
            if (owner(s, u) == p) out.add(mv(t, u, 2));
          }
        }
        out.add(kPass);
        return out;
    }
  }

  @override
  void apply(GridState s, int m) {
    final p = s.turn;
    switch (s.vars[1]) {
      case 0:
        final t = mvTo(m);
        s.cells[t]++;
        s.last = t;
        if (--s.vars[2] <= 0) s.vars[1] = 1;
      case 1:
        if (m == kPass) {
          s.vars[1] = 2;
        } else {
          s.vars[3] = mvFrom(m);
          s.vars[4] = mvTo(m);
          s.vars[1] = 3;
        }
      default:
        if (m != kPass) {
          final a = mvFrom(m), b = mvTo(m);
          final k = (armies(s, a)) ~/ 2;
          s.cells[a] -= k;
          s.cells[b] += k;
          s.last = b;
        }
        var q = p;
        do {
          q = (q + 1) % n;
        } while (count(s, q) == 0 && q != p);
        s.turn = q;
        s.vars[1] = 0;
        s.vars[2] = reinforcements(s, q);
        for (var k = 5; k < 10; k++) {
          s.vars[k] = 0;
        }
    }
    s.ply++;
  }

  @override
  bool isOver(GridState s) => s.vars[0] != 0;

  @override
  int winner(GridState s) {
    if (s.vars[0] != 0) return s.vars[0] - 1;
    return s.ply >= maxPly ? _leader(s) : -1;
  }

  @override
  double evaluate(GridState s, int player) {
    var mine = 0.0, other = 0.0;
    for (var t = 0; t < 18; t++) {
      final v = 10.0 + armies(s, t);
      if (owner(s, t) == player) {
        mine += v;
      } else {
        other += v / (n - 1);
      }
    }
    return (mine - other) / 4;
  }

  @override
  int? policy(GridState s, double noise, SeededRandom r) {
    final ms = moves(s);
    if (ms.isEmpty) return null;
    if (ms.length == 1) return ms.first;
    final p = s.turn;
    if (r.chance(noise * 0.25)) return ms[r.nextInt(ms.length)];
    switch (s.vars[1]) {
      case 0:
        // En büyük tehdit ya da en iyi saldırı fırsatı olan sınır bölgesi.
        var best = ms.first;
        var bv = -1 << 20;
        for (final m in ms) {
          final t = mvTo(m);
          var v = -armies(s, t);
          for (final u in conquestNeighbors(t)) {
            if (owner(s, u) != p) v += armies(s, u) * 2 + 4;
          }
          if (!border(s, t)) v -= 100;
          if (v > bv) {
            bv = v;
            best = m;
          }
        }
        return best;
      case 1:
        var best = kPass;
        var bv = 1.25 - noise * 0.5;
        for (final m in ms) {
          if (m == kPass) continue;
          final v = (armies(s, mvFrom(m)) - 1) / armies(s, mvTo(m));
          if (v > bv) {
            bv = v;
            best = m;
          }
        }
        return best;
      default:
        var best = kPass;
        var bv = 2;
        for (final m in ms) {
          if (m == kPass) continue;
          final a = mvFrom(m), b = mvTo(m);
          if (border(s, a) || !border(s, b)) continue;
          if (armies(s, a) > bv) {
            bv = armies(s, a);
            best = m;
          }
        }
        return best;
    }
  }

  @override
  String status(GridState s, String lang) {
    final phase = switch (s.vars[1]) { 0 => '+${s.vars[2]}', 1 || 3 => '⚔', _ => '⇄' };
    return '$phase  ·  ${[for (var p = 0; p < n; p++) count(s, p)].join(' · ')}';
  }

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}
