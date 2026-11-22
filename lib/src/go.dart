import 'package:studio_core/core/rng.dart';

import 'board_game.dart';
import 'grid_state.dart';

/// Go: alan sayımı, komi 6,5. Siyah (0) başlar. İki pas oyunu bitirir.
/// vars: [0] bitti, [1] üst üste pas, [2] ko noktası + 1, [3..4] esirler.
class GoRules extends BoardRules<GridState> {
  final int n;
  const GoRules([this.n = 9]);

  @override
  String get id => 'go';

  /// Komi ikiyle çarpılmış (6,5 → 13).
  static const komi2 = 13;

  @override
  int get maxPly => n * n * 3;

  @override
  GridState initial(SeededRandom r) => GridState(n, n, List.filled(n * n, -1));

  List<int> nb(int i) {
    final c = i % n, r = i ~/ n;
    return [if (c > 0) i - 1, if (c < n - 1) i + 1, if (r > 0) i - n, if (r < n - 1) i + n];
  }

  /// Grup ve özgürlük sayısı.
  (List<int>, int) group(List<int> cells, int i) {
    final col = cells[i];
    final seen = <int>{i};
    final libs = <int>{};
    final stack = [i];
    while (stack.isNotEmpty) {
      final x = stack.removeLast();
      for (final y in nb(x)) {
        final v = cells[y];
        if (v < 0) {
          libs.add(y);
        } else if (v == col && seen.add(y)) {
          stack.add(y);
        }
      }
    }
    return (seen.toList(), libs.length);
  }

  bool legalAt(GridState s, int i) {
    if (s.cells[i] >= 0 || s.vars[2] - 1 == i) return false;
    final p = s.turn;
    for (final y in nb(i)) {
      final v = s.cells[y];
      if (v < 0) return true;
      final (_, libs) = group(s.cells, y);
      if (v == p && libs > 1) return true;
      if (v == 1 - p && libs == 1) return true;
    }
    return false;
  }

  /// Kendi gözünü doldurmak (her komşu kendi taşı, çaprazların çoğu da).
  bool ownEye(GridState s, int i, int p) {
    if (s.cells[i] >= 0) return false;
    for (final y in nb(i)) {
      if (s.cells[y] != p) return false;
    }
    final c = i % n, r = i ~/ n;
    var bad = 0, edge = 0;
    for (final (dc, dr) in const [(1, 1), (1, -1), (-1, 1), (-1, -1)]) {
      final x = c + dc, y = r + dr;
      if (x < 0 || y < 0 || x >= n || y >= n) {
        edge++;
        continue;
      }
      if (s.cells[y * n + x] == 1 - p) bad++;
    }
    return edge > 0 ? bad == 0 : bad <= 1;
  }

  @override
  List<int> moves(GridState s) {
    if (isOver(s)) return const [];
    return [for (var i = 0; i < n * n; i++) if (legalAt(s, i)) mv(-1, i), kPass];
  }

  @override
  List<int> searchMoves(GridState s) {
    final p = s.turn;
    final near = <int>{};
    var stones = 0;
    for (var i = 0; i < n * n; i++) {
      if (s.cells[i] < 0) continue;
      stones++;
      final c = i % n, r = i ~/ n;
      for (var dr = -2; dr <= 2; dr++) {
        for (var dc = -2; dc <= 2; dc++) {
          if (dr.abs() + dc.abs() > 2) continue;
          final x = c + dc, y = r + dr;
          if (x >= 0 && y >= 0 && x < n && y < n) near.add(y * n + x);
        }
      }
    }
    if (stones < 2) {
      final h = n ~/ 2, q = n >= 13 ? 3 : 2;
      near.addAll([h * n + h, q * n + q, q * n + n - 1 - q, (n - 1 - q) * n + q, (n - 1 - q) * n + n - 1 - q]);
    }
    final ms = [
      for (final i in near)
        if (legalAt(s, i) && !ownEye(s, i, p)) mv(-1, i)
    ]..sort((a, b) => moveOrder(s, b).compareTo(moveOrder(s, a)));
    final top = ms.length > 12 ? ms.sublist(0, 12) : ms;
    return [...top, kPass];
  }

  @override
  int moveOrder(GridState s, int m) {
    if (m == kPass) return -100;
    final i = mvTo(m);
    final p = s.turn;
    var v = 0;
    for (final y in nb(i)) {
      final x = s.cells[y];
      if (x < 0) continue;
      final (_, libs) = group(s.cells, y);
      if (x == 1 - p && libs == 1) v += 60; // alır
      if (x == p && libs == 1) v += 40; // kurtarır
      if (x == 1 - p && libs == 2) v += 10;
    }
    final c = i % n, r = i ~/ n;
    final line = [c, r, n - 1 - c, n - 1 - r].reduce((a, b) => a < b ? a : b);
    if (line == 0) v -= 8;
    if (line == 2 || line == 3) v += 4;
    return v;
  }

  @override
  void apply(GridState s, int m) {
    final p = s.turn;
    s.ply++;
    if (m == kPass) {
      s.vars[1]++;
      s.vars[2] = 0;
      s.last = -1;
      s.turn = 1 - p;
      if (s.vars[1] >= 2) s.vars[0] = 1;
      return;
    }
    final i = mvTo(m);
    s.cells[i] = p;
    s.vars[1] = 0;
    var captured = <int>[];
    for (final y in nb(i)) {
      if (s.cells[y] != 1 - p) continue;
      final (stones, libs) = group(s.cells, y);
      if (libs == 0) {
        for (final x in stones) {
          s.cells[x] = -1;
        }
        captured = [...captured, ...stones];
      }
    }
    s.vars[3 + p] += captured.length;
    final (own, libs) = group(s.cells, i);
    s.vars[2] = captured.length == 1 && own.length == 1 && libs == 1 ? captured.first + 1 : 0;
    s.last = i;
    s.turn = 1 - p;
  }

  @override
  bool isOver(GridState s) => s.vars[0] == 1;

  /// Alan sayımı: taşlar + yalnız bir rengin çevrelediği boş alanlar.
  (int, int) area(GridState s) {
    final a = [0, 0];
    final seen = List.filled(n * n, false);
    for (var i = 0; i < n * n; i++) {
      final v = s.cells[i];
      if (v >= 0) {
        a[v]++;
        continue;
      }
      if (seen[i]) continue;
      final region = <int>[];
      final borders = <int>{};
      final stack = [i];
      seen[i] = true;
      while (stack.isNotEmpty) {
        final x = stack.removeLast();
        region.add(x);
        for (final y in nb(x)) {
          final w = s.cells[y];
          if (w >= 0) {
            borders.add(w);
          } else if (!seen[y]) {
            seen[y] = true;
            stack.add(y);
          }
        }
      }
      if (borders.length == 1) a[borders.first] += region.length;
    }
    return (a[0], a[1]);
  }

  @override
  int winner(GridState s) {
    final (b, w) = area(s);
    return b * 2 > w * 2 + komi2 ? 0 : 1;
  }

  @override
  double evaluate(GridState s, int player) {
    // Etki: her boş nokta 2 adım içindeki taşlara göre paylaşılır.
    var score = 0.0;
    for (var i = 0; i < n * n; i++) {
      final v = s.cells[i];
      if (v >= 0) {
        score += v == player ? 1 : -1;
        final (_, libs) = group(s.cells, i);
        if (libs == 1) score += v == player ? -0.8 : 0.8;
        continue;
      }
      var inf = 0.0;
      final c = i % n, r = i ~/ n;
      for (var dr = -2; dr <= 2; dr++) {
        for (var dc = -2; dc <= 2; dc++) {
          final d = dr.abs() + dc.abs();
          if (d == 0 || d > 2) continue;
          final x = c + dc, y = r + dr;
          if (x < 0 || y < 0 || x >= n || y >= n) continue;
          final w = s.cells[y * n + x];
          if (w < 0) continue;
          inf += (w == player ? 1 : -1) * (d == 1 ? 1.0 : 0.5);
        }
      }
      score += inf.clamp(-1, 1);
    }
    final komi = komi2 / 2;
    return (score + (player == 1 ? komi : -komi)) * 2;
  }

  @override
  String status(GridState s, String lang) {
    final (b, w) = area(s);
    return '● $b  ·  ○ $w + 6.5';
  }

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}
