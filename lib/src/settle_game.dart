import 'dart:math' as math;

import 'package:studio_core/core/rng.dart';

import 'board_game.dart';
import 'grid_state.dart';

/// Yerleşim haritasının geometrisi: 19 altıgen, 54 köşe, 72 kenar.
class SettleGeo {
  final List<(double, double)> hexCenter = [];
  final List<(double, double)> vertex = [];
  final List<List<int>> hexVerts = [];
  final List<List<int>> vertHexes = [];
  final List<(int, int)> edges = [];
  final List<List<int>> vertEdges = [];
  final List<List<int>> vertNeighbors = [];

  SettleGeo._() {
    final key = <String, int>{};
    for (var r = -2; r <= 2; r++) {
      for (var q = -2; q <= 2; q++) {
        if ((q + r).abs() > 2) continue;
        final cx = math.sqrt(3) * (q + r / 2), cy = 1.5 * r;
        hexCenter.add((cx, cy));
        final vs = <int>[];
        for (var k = 0; k < 6; k++) {
          final a = math.pi / 6 + k * math.pi / 3;
          final x = cx + math.cos(a), y = cy + math.sin(a);
          final id = '${(x * 100).round()},${(y * 100).round()}';
          final v = key.putIfAbsent(id, () {
            vertex.add((x, y));
            vertHexes.add([]);
            return vertex.length - 1;
          });
          vs.add(v);
          vertHexes[v].add(hexCenter.length - 1);
        }
        hexVerts.add(vs);
      }
    }
    final seen = <String>{};
    for (final vs in hexVerts) {
      for (var k = 0; k < 6; k++) {
        final a = vs[k], b = vs[(k + 1) % 6];
        final id = a < b ? '$a-$b' : '$b-$a';
        if (seen.add(id)) edges.add(a < b ? (a, b) : (b, a));
      }
    }
    for (var v = 0; v < vertex.length; v++) {
      vertEdges.add([]);
      vertNeighbors.add([]);
    }
    for (var e = 0; e < edges.length; e++) {
      final (a, b) = edges[e];
      vertEdges[a].add(e);
      vertEdges[b].add(e);
      vertNeighbors[a].add(b);
      vertNeighbors[b].add(a);
    }
  }

  static final SettleGeo i = SettleGeo._();
}

/// Kaynaklar: 0 odun, 1 tuğla, 2 yün, 3 tahıl, 4 maden; 5 çöl.
const kSettleCost = <List<int>>[
  [1, 1, 0, 0, 0], // yol
  [1, 1, 1, 1, 0], // köy
  [0, 0, 0, 2, 3], // kasaba
];

/// Yerleşim kurma: 2-4 oyuncu. Önce herkes sırayla (sonra ters sırayla) bir
/// köy ve ona bitişik bir yol kurar; ikinci köy çevresindeki kaynakları verir.
/// Her tur iki zar atılır; o sayıdaki altıgenlere bitişik köyler 1, kasabalar 2
/// kaynak üretir. 7 gelirse hırsız en öndeki oyuncuya zarar verecek altıgene
/// gider ve oradan bir kaynak çalar; elinde 7'den fazla kaynak olan yarısını
/// atar. Yol (odun+tuğla), köy (odun+tuğla+yün+tahıl), kasaba (2 tahıl+3
/// maden) kurulur; bankayla 4'e 1 takas yapılır. Köyler arasında en az iki
/// kenar olmalıdır. Köy 1, kasaba 2 puandır; 8 puana ilk ulaşan kazanır.
///
/// Hücreler: 0..53 köşe (-1 boş, sahip * 2 + kasaba), 54..125 kenar (-1 boş,
/// sahip), 126..144 altıgen kaynağı, 145..163 altıgen sayısı.
/// Hamleler: köy/kasaba mv(-1, köşe[, 1]), yol mv(-1, 100 + kenar),
/// takas mv(200 + ver, 210 + al), tur sonu kPass.
/// vars: [0] sonuç, [1] aşama (0 kuruluş köyü, 1 kuruluş yolu, 2 zar, 3 oyun),
/// [2] kuruluş adımı, [3] son zar, [4] hırsızın altıgeni, [5] son kuruluş köyü,
/// [6] oyuncu sayısı, [7] hedef puan, [8..27] kaynaklar (oyuncu * 5 + tür).
class SettleRules extends BoardRules<GridState> {
  final int n;
  final int target;
  const SettleRules([this.n = 2, this.target = 8]);

  static const vBase = 0, eBase = 54, hRes = 126, hNum = 145;
  static const edgeMove = 100, giveCell = 200, getCell = 210;

  @override
  String get id => 'yerlesim-$n';
  @override
  int get players => n;
  @override
  bool get stochastic => true;
  @override
  int get maxPly => 500;

  SettleGeo get geo => SettleGeo.i;

  @override
  GridState initial(SeededRandom r) {
    final s = GridState(19, 1, List.filled(164, -1), List.filled(28, 0));
    final res = [0, 0, 0, 0, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 5];
    final nums = [2, 3, 3, 4, 4, 5, 5, 6, 6, 8, 8, 9, 9, 10, 10, 11, 11, 12];
    for (final l in [res, nums]) {
      for (var i = l.length - 1; i > 0; i--) {
        final j = r.nextInt(i + 1);
        final t = l[i];
        l[i] = l[j];
        l[j] = t;
      }
    }
    var k = 0;
    for (var h = 0; h < 19; h++) {
      s.cells[hRes + h] = res[h];
      if (res[h] == 5) {
        s.cells[hNum + h] = 0;
        s.vars[4] = h;
      } else {
        s.cells[hNum + h] = nums[k++];
      }
    }
    s.vars[6] = n;
    s.vars[7] = target;
    s.vars[1] = 0;
    s.turn = 0;
    return s;
  }

  int vOwner(GridState s, int v) => s.cells[vBase + v] < 0 ? -1 : s.cells[vBase + v] ~/ 2;
  bool isCity(GridState s, int v) => s.cells[vBase + v] >= 0 && s.cells[vBase + v] % 2 == 1;
  int eOwner(GridState s, int e) => s.cells[eBase + e];
  int res(GridState s, int p, int k) => s.vars[8 + p * 5 + k];
  int handSize(GridState s, int p) => [for (var k = 0; k < 5; k++) res(s, p, k)].fold(0, (a, b) => a + b);

  int points(GridState s, int p) {
    var v = 0;
    for (var i = 0; i < 54; i++) {
      if (vOwner(s, i) == p) v += isCity(s, i) ? 2 : 1;
    }
    return v;
  }

  int count(GridState s, int p, {required bool city}) {
    var c = 0;
    for (var i = 0; i < 54; i++) {
      if (vOwner(s, i) == p && isCity(s, i) == city) c++;
    }
    return c;
  }

  int roads(GridState s, int p) => [for (var e = 0; e < 72; e++) if (eOwner(s, e) == p) e].length;

  /// Sayının iki zarla gelme ağırlığı (6 ve 8 için 5).
  static int pips(int num) => num == 0 ? 0 : 6 - (7 - num).abs();

  bool _distanceOk(GridState s, int v) => vOwner(s, v) < 0 && geo.vertNeighbors[v].every((u) => vOwner(s, u) < 0);

  bool _touchesRoad(GridState s, int v, int p) => geo.vertEdges[v].any((e) => eOwner(s, e) == p);

  bool _canRoad(GridState s, int e, int p) {
    if (eOwner(s, e) >= 0) return false;
    final (a, b) = geo.edges[e];
    for (final v in [a, b]) {
      if (vOwner(s, v) == p) return true;
      if (vOwner(s, v) < 0 && _touchesRoad(s, v, p)) return true;
    }
    return false;
  }

  bool _afford(GridState s, int p, int item) {
    for (var k = 0; k < 5; k++) {
      if (res(s, p, k) < kSettleCost[item][k]) return false;
    }
    return true;
  }

  void _payCost(GridState s, int p, int item) {
    for (var k = 0; k < 5; k++) {
      s.vars[8 + p * 5 + k] -= kSettleCost[item][k];
    }
  }

  int _setupPlayer(int step) => step < n ? step : 2 * n - 1 - step;

  @override
  bool needsChance(GridState s) => !isOver(s) && s.vars[1] == 2;

  @override
  void applyChance(GridState s, SeededRandom r) {
    final roll = 2 + r.nextInt(6) + r.nextInt(6);
    s.vars[3] = roll;
    if (roll == 7) {
      _robber(s, r);
    } else {
      for (var h = 0; h < 19; h++) {
        if (s.cells[hNum + h] != roll || h == s.vars[4]) continue;
        final k = s.cells[hRes + h];
        for (final v in geo.hexVerts[h]) {
          final o = vOwner(s, v);
          if (o >= 0) s.vars[8 + o * 5 + k] += isCity(s, v) ? 2 : 1;
        }
      }
    }
    s.vars[1] = 3;
  }

  void _robber(GridState s, SeededRandom r) {
    final p = s.turn;
    // Fazla kaynak atma: en bol olandan başlayarak yarısı.
    for (var o = 0; o < n; o++) {
      var drop = handSize(s, o) > 7 ? handSize(s, o) ~/ 2 : 0;
      while (drop-- > 0) {
        var k = 0;
        for (var j = 1; j < 5; j++) {
          if (res(s, o, j) > res(s, o, k)) k = j;
        }
        s.vars[8 + o * 5 + k]--;
      }
    }
    // Hırsız: sıradaki oyuncu dışındaki en çok puanlıya en çok zarar.
    var best = s.vars[4], bv = -1;
    for (var h = 0; h < 19; h++) {
      if (h == s.vars[4] || s.cells[hRes + h] == 5) continue;
      var v = 0;
      var mine = false;
      for (final x in geo.hexVerts[h]) {
        final o = vOwner(s, x);
        if (o == p) mine = true;
        if (o >= 0 && o != p) v += (points(s, o) + 1) * (isCity(s, x) ? 2 : 1);
      }
      v = v * pips(s.cells[hNum + h]);
      if (mine) v -= 50;
      if (v > bv) {
        bv = v;
        best = h;
      }
    }
    s.vars[4] = best;
    final victims = <int>{for (final x in geo.hexVerts[best]) if (vOwner(s, x) >= 0 && vOwner(s, x) != p && handSize(s, vOwner(s, x)) > 0) vOwner(s, x)}.toList();
    if (victims.isEmpty) return;
    final o = victims[r.nextInt(victims.length)];
    final have = [for (var k = 0; k < 5; k++) for (var c = 0; c < res(s, o, k); c++) k];
    final k = have[r.nextInt(have.length)];
    s.vars[8 + o * 5 + k]--;
    s.vars[8 + p * 5 + k]++;
  }

  @override
  List<int> moves(GridState s) {
    if (isOver(s) || s.vars[1] == 2) return const [];
    final p = s.turn;
    final out = <int>[];
    switch (s.vars[1]) {
      case 0:
        for (var v = 0; v < 54; v++) {
          if (_distanceOk(s, v)) out.add(mv(-1, v));
        }
      case 1:
        for (final e in geo.vertEdges[s.vars[5]]) {
          if (eOwner(s, e) < 0) out.add(mv(-1, edgeMove + e));
        }
      default:
        if (_afford(s, p, 2) && count(s, p, city: true) < 4) {
          for (var v = 0; v < 54; v++) {
            if (vOwner(s, v) == p && !isCity(s, v)) out.add(mv(-1, v, 1));
          }
        }
        if (_afford(s, p, 1) && count(s, p, city: false) < 5) {
          for (var v = 0; v < 54; v++) {
            if (_distanceOk(s, v) && _touchesRoad(s, v, p)) out.add(mv(-1, v));
          }
        }
        if (_afford(s, p, 0) && roads(s, p) < 15) {
          for (var e = 0; e < 72; e++) {
            if (_canRoad(s, e, p)) out.add(mv(-1, edgeMove + e));
          }
        }
        for (var g = 0; g < 5; g++) {
          if (res(s, p, g) < 4) continue;
          for (var k = 0; k < 5; k++) {
            if (k != g) out.add(mv(giveCell + g, getCell + k));
          }
        }
        out.add(kPass);
    }
    return out;
  }

  @override
  void apply(GridState s, int m) {
    final p = s.turn;
    switch (s.vars[1]) {
      case 0:
        final v = mvTo(m);
        s.cells[vBase + v] = p * 2;
        s.vars[5] = v;
        s.last = v;
        if (s.vars[2] >= n) {
          for (final h in geo.vertHexes[v]) {
            final k = s.cells[hRes + h];
            if (k < 5) s.vars[8 + p * 5 + k]++;
          }
        }
        s.vars[1] = 1;
      case 1:
        s.cells[eBase + mvTo(m) - edgeMove] = p;
        s.vars[2]++;
        if (s.vars[2] >= 2 * n) {
          s.turn = 0;
          s.vars[1] = 2;
        } else {
          s.turn = _setupPlayer(s.vars[2]);
          s.vars[1] = 0;
        }
      default:
        if (m == kPass) {
          s.turn = (p + 1) % n;
          s.vars[1] = 2;
        } else if (mvFrom(m) >= giveCell) {
          s.vars[8 + p * 5 + mvFrom(m) - giveCell] -= 4;
          s.vars[8 + p * 5 + mvTo(m) - getCell]++;
        } else if (mvTo(m) >= edgeMove) {
          _payCost(s, p, 0);
          s.cells[eBase + mvTo(m) - edgeMove] = p;
        } else if (mvExtra(m) == 1) {
          _payCost(s, p, 2);
          s.cells[vBase + mvTo(m)] = p * 2 + 1;
          s.last = mvTo(m);
        } else {
          _payCost(s, p, 1);
          s.cells[vBase + mvTo(m)] = p * 2;
          s.last = mvTo(m);
        }
        if (points(s, p) >= target) s.vars[0] = p + 1;
    }
    s.ply++;
  }

  @override
  bool isOver(GridState s) => s.vars[0] != 0;

  @override
  int winner(GridState s) {
    if (s.vars[0] != 0) return s.vars[0] - 1;
    if (s.ply < maxPly) return -1;
    var best = 0;
    for (var p = 1; p < n; p++) {
      if (points(s, p) > points(s, best)) best = p;
    }
    return best;
  }

  /// Köşenin üretim gücü (bitişik altıgenlerin ağırlık toplamı, çeşitlilikle).
  int vertexValue(GridState s, int v) {
    var w = 0;
    final kinds = <int>{};
    for (final h in geo.vertHexes[v]) {
      if (s.cells[hRes + h] == 5) continue;
      w += pips(s.cells[hNum + h]) * 2;
      kinds.add(s.cells[hRes + h]);
    }
    return w + kinds.length * 3;
  }

  @override
  double evaluate(GridState s, int player) {
    double score(int p) {
      var v = points(s, p) * 30.0;
      for (var x = 0; x < 54; x++) {
        if (vOwner(s, x) == p) v += vertexValue(s, x) * (isCity(s, x) ? 2 : 1) * 0.5;
      }
      return v + handSize(s, p) * 0.5;
    }

    var other = 0.0;
    for (var p = 0; p < n; p++) {
      if (p != player) other = math.max(other, score(p));
    }
    return (score(player) - other) / 5;
  }

  @override
  int? policy(GridState s, double noise, SeededRandom r) {
    final ms = moves(s);
    if (ms.isEmpty) return null;
    if (ms.length == 1) return ms.first;
    final p = s.turn;
    int pick(Iterable<int> cands, int Function(int) value) {
      var best = cands.first, bv = -1 << 30;
      for (final m in cands) {
        final v = value(m) + (noise > 0 ? r.nextInt(1 + (noise * 10).round()) : 0);
        if (v > bv) {
          bv = v;
          best = m;
        }
      }
      return best;
    }

    switch (s.vars[1]) {
      case 0:
        return pick(ms, (m) => vertexValue(s, mvTo(m)));
      case 1:
        // Yolu en iyi boş köşeye doğru uzat.
        return pick(ms, (m) {
          final (a, b) = geo.edges[mvTo(m) - edgeMove];
          final far = a == s.vars[5] ? b : a;
          var best = 0;
          for (final u in geo.vertNeighbors[far]) {
            if (_distanceOk(s, u)) best = math.max(best, vertexValue(s, u));
          }
          return best;
        });
    }
    final cities = ms.where((m) => m != kPass && mvExtra(m) == 1).toList();
    if (cities.isNotEmpty) return pick(cities, (m) => vertexValue(s, mvTo(m)));
    final towns = ms.where((m) => m != kPass && mvFrom(m) < 0 && mvTo(m) < edgeMove && mvExtra(m) == 0).toList();
    if (towns.isNotEmpty) return pick(towns, (m) => vertexValue(s, mvTo(m)));
    final roadMoves = ms.where((m) => m != kPass && mvFrom(m) < 0 && mvTo(m) >= edgeMove).toList();
    final hasSpot = [for (var v = 0; v < 54; v++) if (_distanceOk(s, v) && _touchesRoad(s, v, p)) v].isNotEmpty;
    if (roadMoves.isNotEmpty && (!hasSpot || r.chance(0.25))) {
      return pick(roadMoves, (m) {
        final (a, b) = geo.edges[mvTo(m) - edgeMove];
        var best = 0;
        for (final v in [a, b]) {
          if (_distanceOk(s, v)) best = math.max(best, vertexValue(s, v));
        }
        return best;
      });
    }
    // Takas: eksik olan kaynağa.
    final trades = ms.where((m) => m != kPass && mvFrom(m) >= giveCell).toList();
    if (trades.isNotEmpty) {
      final want = count(s, p, city: false) > 0 && res(s, p, 4) < 3 ? 4 : 3;
      final t = trades.where((m) => mvTo(m) - getCell == want || res(s, p, mvTo(m) - getCell) == 0).toList();
      if (t.isNotEmpty) return t[r.nextInt(t.length)];
    }
    return kPass;
  }

  @override
  String status(GridState s, String lang) => '🎲 ${s.vars[3] == 0 ? '-' : s.vars[3]}  ·  ★ ${[for (var p = 0; p < n; p++) points(s, p)].join(' · ')} / $target';

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}
