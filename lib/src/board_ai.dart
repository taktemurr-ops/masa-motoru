import 'package:studio_core/core/rng.dart';

import 'board_game.dart';

/// Masa oyunları rakibi. Tam bilgili oyunlarda alfa-beta (minimaks, sıra
/// değişmeyen ekstra hamleleri de doğru işler) ve yinelemeli derinleşme;
/// şanslı oyunlarda her aday hamle için kısa benzetimler.
/// [noise]: 0 kusursuz; büyüdükçe rakip ara sıra zayıf hamle seçer.
class BoardAI<S extends BoardState> {
  final BoardRules<S> rules;
  final int depth;
  final int nodeBudget;
  final double noise;
  final SeededRandom r;
  int nodes = 0;

  BoardAI(this.rules, {required this.depth, this.nodeBudget = 60000, this.noise = 0, required this.r});

  static const _win = 100000.0;

  int choose(S s) {
    final all = rules.moves(s);
    if (all.length == 1) return all.first;
    final pol = rules.policy(s, noise, r);
    if (pol != null) return pol;
    if (rules.stochastic || rules.players > 2) return _simulate(s, all);
    final me = s.turn;
    var cand = rules.searchMoves(s);
    if (cand.isEmpty) cand = all;
    cand = _ordered(s, cand);
    nodes = 0;
    var scores = <int, double>{};
    for (var d = 1; d <= depth; d++) {
      final now = <int, double>{};
      var alpha = -double.infinity;
      var complete = true;
      for (final m in cand) {
        final c = s.copy() as S;
        rules.apply(c, m);
        final v = _search(c, d - 1, alpha, double.infinity, me);
        now[m] = v;
        if (v > alpha) alpha = v;
        if (nodes > nodeBudget) {
          complete = false;
          break;
        }
      }
      if (complete || scores.isEmpty) {
        // Eksik derinlikte yalnızca bakılabilen hamleler güncellenir.
        scores = {...scores, ...now};
      }
      cand = List.of(cand)..sort((a, b) => (scores[b] ?? -_win * 2).compareTo(scores[a] ?? -_win * 2));
      if (!complete) break;
      if ((scores[cand.first] ?? 0) >= _win / 2) break; // kesin kazanç bulundu
    }
    return _pick(scores, cand);
  }

  /// Gürültü: değerlere rastgele pay ekler; büyük gürültüde ara sıra ilk
  /// üçten birini seçer.
  int _pick(Map<int, double> scores, List<int> ordered) {
    if (noise <= 0) return ordered.first;
    var best = ordered.first;
    var bestV = -double.infinity;
    for (final m in ordered) {
      final base = scores[m] ?? -_win;
      final v = (base.abs() >= _win / 2 ? base : base + (r.nextDouble() * 2 - 1) * noise * 30);
      if (v > bestV) {
        bestV = v;
        best = m;
      }
    }
    if (noise >= 0.6 && ordered.length > 2 && r.nextDouble() < (noise - 0.5) * 0.5) {
      final topV = scores[ordered.first] ?? 0;
      if (topV.abs() < _win / 2) return ordered[r.nextInt(3)];
    }
    return best;
  }

  List<int> _ordered(S s, List<int> ms) {
    final l = List.of(ms);
    shuffle(l, r);
    l.sort((a, b) => rules.moveOrder(s, b).compareTo(rules.moveOrder(s, a)));
    return l;
  }

  double _search(S s, int d, double alpha, double beta, int me) {
    nodes++;
    if (rules.isOver(s) || s.ply >= rules.maxPly) {
      final w = rules.winner(s);
      if (w < 0) return 0;
      return w == me ? _win - s.ply : -_win + s.ply;
    }
    if (d <= 0 || nodes > nodeBudget) return rules.evaluate(s, me);
    var ms = rules.searchMoves(s);
    if (ms.isEmpty) ms = rules.moves(s);
    ms = List.of(ms)..sort((a, b) => rules.moveOrder(s, b).compareTo(rules.moveOrder(s, a)));
    if (s.turn == me) {
      var v = -double.infinity;
      for (final m in ms) {
        final c = s.copy() as S;
        rules.apply(c, m);
        final x = _search(c, d - 1, alpha, beta, me);
        if (x > v) v = x;
        if (v > alpha) alpha = v;
        if (alpha >= beta) break;
      }
      return v;
    } else {
      var v = double.infinity;
      for (final m in ms) {
        final c = s.copy() as S;
        rules.apply(c, m);
        final x = _search(c, d - 1, alpha, beta, me);
        if (x < v) v = x;
        if (v < beta) beta = v;
        if (alpha >= beta) break;
      }
      return v;
    }
  }

  // ---- şanslı / çok oyunculu oyunlar ----

  int _simulate(S s, List<int> all) {
    final me = s.turn;
    final runs = (depth * 6).clamp(4, 80);
    final score = <int, double>{};
    for (final m in all) {
      var total = 0.0;
      for (var k = 0; k < runs; k++) {
        final c = s.copy() as S;
        rules.apply(c, m);
        total += playout(c, me);
      }
      score[m] = total / runs;
    }
    final ordered = List.of(all)..sort((a, b) => score[b]!.compareTo(score[a]!));
    if (noise > 0 && r.nextDouble() < noise * 0.5 && ordered.length > 1) {
      return ordered[r.nextInt(ordered.length < 3 ? ordered.length : 3)];
    }
    return ordered.first;
  }

  /// Hızlı politika ile oyunu belli bir ufka kadar oynat, sonucu değerlendir.
  double playout(S s, int me) {
    var steps = 0;
    final horizon = 12 + depth * 8;
    while (!rules.isOver(s) && steps++ < horizon && s.ply < rules.maxPly) {
      if (rules.needsChance(s)) {
        rules.applyChance(s, r);
        continue;
      }
      final ms = rules.moves(s);
      if (ms.isEmpty) break;
      rules.apply(s, greedy(s, ms));
    }
    if (rules.isOver(s)) {
      final w = rules.winner(s);
      return w == me ? 200 : (w < 0 ? 0 : -200);
    }
    return rules.evaluate(s, me);
  }

  /// Bir adım ileri bakan açgözlü seçim (biraz rastgelelikle).
  int greedy(S s, List<int> ms) {
    if (ms.length == 1) return ms.first;
    if (r.nextDouble() < 0.25) return ms[r.nextInt(ms.length)];
    final p = s.turn;
    var best = ms.first;
    var bestV = -double.infinity;
    for (final m in ms) {
      final c = s.copy() as S;
      rules.apply(c, m);
      final v = rules.isOver(c) && rules.winner(c) == p ? 1e9 : rules.evaluate(c, p) + r.nextDouble();
      if (v > bestV) {
        bestV = v;
        best = m;
      }
    }
    return best;
  }
}

void shuffle<T>(List<T> l, SeededRandom r) {
  for (var i = l.length - 1; i > 0; i--) {
    final j = r.nextInt(i + 1);
    final t = l[i];
    l[i] = l[j];
    l[j] = t;
  }
}
