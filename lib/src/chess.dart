import 'package:studio_core/core/rng.dart';

import 'board_game.dart';
import 'grid_state.dart';

/// Satranç taş kodları: renk * 8 + tür.
const cP = 1, cN = 2, cB = 3, cR = 4, cQ = 5, cK = 6;
int pieceColor(int v) => v < 0 ? -1 : v ~/ 8;
int pieceType(int v) => v < 0 ? 0 : v % 8;

/// Satranç ve çeşitleri. Beyaz (0) altta, yukarı oynar.
/// vars: [0] sonuç (0 sürüyor, 1 beyaz, 2 siyah, 3 berabere), [1] 50 hamle
/// sayacı, [2] rok hakları (1 beyaz kısa, 2 beyaz uzun, 4 siyah kısa,
/// 8 siyah uzun), [3] geçerken alma karesi + 1, [4..5] şah çekme sayısı
/// (üç şah çeşidi), [6] Chess960 kale sütunları (kısa*8 + uzun), [8..]
/// son alımsız/piyonsuz hamlelerden bu yana konum özetleri (üç kez tekrar).
enum ChessVariant { standard, chess960, threeCheck, kingOfHill, horde, atomic, racingKings, antichess, gardner, losAlamos, pawnRace }

class ChessRules extends BoardRules<GridState> {
  final ChessVariant variant;
  const ChessRules([this.variant = ChessVariant.standard]);

  @override
  String get id => 'satranc-${variant.name}';

  int get n => variant == ChessVariant.losAlamos ? 6 : (variant == ChessVariant.gardner ? 5 : 8);

  @override
  int get maxPly => 300;

  @override
  double get decisive => variant == ChessVariant.antichess ? double.infinity : 110;

  static const _knight = [(1, 2), (2, 1), (-1, 2), (-2, 1), (1, -2), (2, -1), (-1, -2), (-2, -1)];
  static const _king = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)];
  static const _rook = [(1, 0), (-1, 0), (0, 1), (0, -1)];
  static const _bishop = [(1, 1), (1, -1), (-1, 1), (-1, -1)];

  @override
  GridState initial(SeededRandom r) {
    final s = GridState(n, n, List.filled(n * n, -1), List.filled(8, 0, growable: true));
    if (variant == ChessVariant.gardner) {
      const back = [cR, cN, cB, cQ, cK];
      for (var c = 0; c < 5; c++) {
        s.cells[c] = 8 + back[c];
        s.cells[5 + c] = 8 + cP;
        s.cells[15 + c] = cP;
        s.cells[20 + c] = back[c];
      }
      return s;
    }
    if (variant == ChessVariant.losAlamos) {
      const back = [cR, cN, cQ, cK, cN, cR];
      for (var c = 0; c < 6; c++) {
        s.cells[c] = 8 + back[c];
        s.cells[6 + c] = 8 + cP;
        s.cells[24 + c] = cP;
        s.cells[30 + c] = back[c];
      }
      return s;
    }
    var back = [cR, cN, cB, cQ, cK, cB, cN, cR];
    if (variant == ChessVariant.chess960) back = _rank960(r);
    if (variant == ChessVariant.racingKings) {
      // İki şah da en alttan yarışır; piyon yok.
      const w = [cK, cR, cB, cN], b = [cK, cR, cB, cN];
      for (var i = 0; i < 4; i++) {
        s.cells[7 * 8 + i] = 8 + b[i];
        s.cells[6 * 8 + i] = 8 + [cQ, cR, cB, cN][i];
        s.cells[7 * 8 + 7 - i] = w[i];
        s.cells[6 * 8 + 7 - i] = [cQ, cR, cB, cN][i];
      }
      return s;
    }
    for (var c = 0; c < 8; c++) {
      s.cells[c] = 8 + back[c];
      s.cells[8 + c] = 8 + cP;
      s.cells[48 + c] = cP;
      s.cells[56 + c] = back[c];
    }
    if (variant == ChessVariant.pawnRace) {
      // Piyon savaşı: yalnızca şahlar ve piyonlar; ilk terfi eden kazanır.
      for (var c = 0; c < 8; c++) {
        if (c != 4) {
          s.cells[c] = -1;
          s.cells[56 + c] = -1;
        }
      }
      return s;
    }
    if (variant == ChessVariant.horde) {
      // Beyaz 36 piyonla siyah tam orduya karşı.
      for (var i = 32; i < 64; i++) {
        s.cells[i] = cP;
      }
      for (final i in [25, 26, 29, 30]) {
        s.cells[i] = cP;
      }
    }
    if (variant != ChessVariant.antichess && variant != ChessVariant.horde) {
      s.vars[2] = 15;
      final kc = back.indexOf(cK);
      final rooks = [for (var c = 0; c < 8; c++) if (back[c] == cR) c];
      s.vars[6] = rooks.last * 8 + rooks.first;
      assert(kc > rooks.first && kc < rooks.last);
    }
    return s;
  }

  static List<int> _rank960(SeededRandom r) {
    final b = List.filled(8, 0);
    b[r.nextInt(4) * 2] = cB;
    b[r.nextInt(4) * 2 + 1] = cB;
    List<int> free() => [for (var i = 0; i < 8; i++) if (b[i] == 0) i];
    var f = free();
    b[f[r.nextInt(f.length)]] = cQ;
    f = free();
    b[f[r.nextInt(f.length)]] = cN;
    f = free();
    b[f[r.nextInt(f.length)]] = cN;
    f = free();
    b[f[0]] = cR;
    b[f[1]] = cK;
    b[f[2]] = cR;
    return b;
  }

  bool _in(int c, int r) => c >= 0 && r >= 0 && c < n && r < n;
  int fwd(int p) => p == 0 ? -1 : 1;

  /// [p] rengindeki taşlar [sq] karesini tehdit ediyor mu.
  bool attacked(GridState s, int sq, int p) {
    final c0 = sq % n, r0 = sq ~/ n;
    for (final (dc, dr) in _knight) {
      final c = c0 + dc, r = r0 + dr;
      if (_in(c, r) && s.cells[r * n + c] == p * 8 + cN) return true;
    }
    for (final (dc, dr) in _king) {
      final c = c0 + dc, r = r0 + dr;
      if (_in(c, r) && s.cells[r * n + c] == p * 8 + cK) return true;
    }
    // Piyon: p rengindeki piyon bir sıra geriden çapraz vurur.
    for (final dc in const [-1, 1]) {
      final c = c0 + dc, r = r0 - fwd(p);
      if (_in(c, r) && s.cells[r * n + c] == p * 8 + cP) return true;
    }
    for (final (dirs, types) in [(_rook, const [cR, cQ]), (_bishop, const [cB, cQ])]) {
      for (final (dc, dr) in dirs) {
        var c = c0 + dc, r = r0 + dr;
        while (_in(c, r)) {
          final v = s.cells[r * n + c];
          if (v >= 0) {
            if (pieceColor(v) == p && types.contains(pieceType(v))) return true;
            break;
          }
          c += dc;
          r += dr;
        }
      }
    }
    return false;
  }

  int kingSq(GridState s, int p) => s.cells.indexOf(p * 8 + cK);

  bool inCheck(GridState s, int p) {
    final k = kingSq(s, p);
    return k >= 0 && attacked(s, k, 1 - p);
  }

  /// Yalancı-yasal hamleler (şah tehdidi denetlenmeden).
  List<int> _pseudo(GridState s, {bool capturesOnly = false}) {
    final p = s.turn;
    final out = <int>[];
    final ep = s.vars[3] - 1;
    for (var i = 0; i < s.cells.length; i++) {
      final v = s.cells[i];
      if (pieceColor(v) != p) continue;
      final t = pieceType(v);
      final c0 = i % n, r0 = i ~/ n;
      void add(int to, [int promo = 0]) => out.add(mv(i, to, promo));
      switch (t) {
        case cP:
          final r1 = r0 + fwd(p);
          final last = p == 0 ? 0 : n - 1;
          void pawnTo(int to) {
            if (to ~/ n == last) {
              for (final pr in variant == ChessVariant.antichess ? const [cQ, cR, cB, cN, cK] : (variant == ChessVariant.losAlamos ? const [cQ, cN, cR] : const [cQ, cN, cR, cB])) {
                add(to, pr);
              }
            } else {
              add(to);
            }
          }

          if (_in(c0, r1) && s.cells[r1 * n + c0] < 0 && !capturesOnly) {
            pawnTo(r1 * n + c0);
            final start = p == 0 ? n - 2 : 1;
            final hordeStart = variant == ChessVariant.horde && p == 0 && r0 == n - 1;
            final r2 = r0 + 2 * fwd(p);
            if (n == 8 && (r0 == start || hordeStart) && _in(c0, r2) && s.cells[r2 * n + c0] < 0) add(r2 * n + c0);
          }
          for (final dc in const [-1, 1]) {
            final c = c0 + dc;
            if (!_in(c, r1)) continue;
            final to = r1 * n + c;
            if (pieceColor(s.cells[to]) == 1 - p) pawnTo(to);
            if (to == ep) add(to);
          }
        case cN || cK:
          for (final (dc, dr) in t == cN ? _knight : _king) {
            final c = c0 + dc, r = r0 + dr;
            if (!_in(c, r)) continue;
            final to = r * n + c;
            final o = pieceColor(s.cells[to]);
            if (o == p) continue;
            if (capturesOnly && o < 0) continue;
            add(to);
          }
          if (t == cK && !capturesOnly) _castles(s, i, out);
        default:
          final dirs = t == cR ? _rook : (t == cB ? _bishop : _king);
          for (final (dc, dr) in dirs) {
            var c = c0 + dc, r = r0 + dr;
            while (_in(c, r)) {
              final to = r * n + c;
              final o = pieceColor(s.cells[to]);
              if (o == p) break;
              if (!capturesOnly || o >= 0) add(to);
              if (o >= 0) break;
              c += dc;
              r += dr;
            }
          }
      }
    }
    return out;
  }

  /// Rok (Chess960 kuralıyla genel): şah g/c sütununa, kale f/d sütununa.
  /// Hamle kodu: şahın varış karesi (aynıysa kale karesi), extra 9 kısa / 10 uzun.
  void _castles(GridState s, int kSq, List<int> out) {
    final p = s.turn;
    final rights = s.vars[2];
    if (rights == 0 || n != 8) return;
    final row = p == 0 ? 7 : 0;
    if (kSq ~/ 8 != row) return;
    final kc = kSq % 8;
    for (final side in const [0, 1]) {
      final bit = (p == 0 ? 1 : 4) << side;
      if (rights & bit == 0) continue;
      final rc = side == 0 ? s.vars[6] ~/ 8 : s.vars[6] % 8;
      final rookSq = row * 8 + rc;
      if (s.cells[rookSq] != p * 8 + cR) continue;
      final kTo = side == 0 ? 6 : 2, rTo = side == 0 ? 5 : 3;
      var ok = true;
      final lo = [kc, rc, kTo, rTo].reduce((a, b) => a < b ? a : b);
      final hi = [kc, rc, kTo, rTo].reduce((a, b) => a > b ? a : b);
      for (var c = lo; c <= hi && ok; c++) {
        final v = s.cells[row * 8 + c];
        if (v >= 0 && c != kc && c != rc) ok = false;
      }
      final klo = kc < kTo ? kc : kTo, khi = kc < kTo ? kTo : kc;
      for (var c = klo; c <= khi && ok; c++) {
        if (attacked(s, row * 8 + c, 1 - p)) ok = false;
      }
      if (ok) out.add(mv(kSq, kTo == kc ? rookSq : row * 8 + kTo, 9 + side));
    }
  }

  @override
  List<int> moves(GridState s) {
    if (isOver(s)) return const [];
    var ps = _pseudo(s);
    if (variant == ChessVariant.antichess) {
      final caps = ps.where((m) => s.cells[mvTo(m)] >= 0 || (pieceType(s.cells[mvFrom(m)]) == cP && mvTo(m) % n != mvFrom(m) % n)).toList();
      return caps.isNotEmpty ? caps : ps;
    }
    final p = s.turn;
    final legal = <int>[];
    for (final m in ps) {
      final c = s.copy();
      _move(c, m);
      if (variant == ChessVariant.atomic && kingSq(c, 1 - p) < 0 && kingSq(c, p) >= 0) {
        legal.add(m);
        continue;
      }
      if (variant == ChessVariant.horde && p == 0) {
        legal.add(m);
        continue;
      }
      if (kingSq(c, p) < 0) continue;
      if (variant == ChessVariant.racingKings && inCheck(c, 1 - p)) continue;
      if (!inCheck(c, p)) legal.add(m);
    }
    return legal;
  }

  /// Taşı oynat (yasallık denetlemeden).
  void _move(GridState s, int m) {
    final p = s.turn;
    final from = mvFrom(m), to = mvTo(m), extra = mvExtra(m);
    final v = s.cells[from];
    final t = pieceType(v);
    var captured = s.cells[to];
    s.vars[3] = 0;
    if (extra >= 9) {
      // Rok (9 kısa, 10 uzun).
      final row = from ~/ 8;
      final side = extra - 9;
      final rc = side == 0 ? s.vars[6] ~/ 8 : s.vars[6] % 8;
      s.cells[from] = -1;
      s.cells[row * 8 + rc] = -1;
      s.cells[row * 8 + (side == 0 ? 6 : 2)] = p * 8 + cK;
      s.cells[row * 8 + (side == 0 ? 5 : 3)] = p * 8 + cR;
      s.vars[2] &= ~(p == 0 ? 3 : 12);
      s.vars[1]++;
      s.last = row * 8 + (side == 0 ? 6 : 2);
      return;
    }
    if (t == cP && to % n != from % n && captured < 0) {
      // Geçerken alma.
      final victim = (from ~/ n) * n + to % n;
      captured = s.cells[victim];
      s.cells[victim] = -1;
    }
    s.cells[from] = -1;
    s.cells[to] = extra > 0 ? p * 8 + extra : v;
    if (t == cP && (to ~/ n - from ~/ n).abs() == 2) s.vars[3] = (from + to) ~/ 2 + 1;
    s.vars[1] = (t == cP || captured >= 0) ? 0 : s.vars[1] + 1;
    // Rok hakları: şah ya da kale oynadıysa / kale alındıysa.
    if (n == 8 && s.vars[2] != 0) {
      if (t == cK) s.vars[2] &= ~(p == 0 ? 3 : 12);
      for (final sq in [from, to]) {
        for (final pl in const [0, 1]) {
          final row = pl == 0 ? 7 : 0;
          if (sq == row * 8 + s.vars[6] ~/ 8) s.vars[2] &= ~(pl == 0 ? 1 : 4);
          if (sq == row * 8 + s.vars[6] % 8) s.vars[2] &= ~(pl == 0 ? 2 : 8);
        }
      }
    }
    if (variant == ChessVariant.atomic && captured >= 0) {
      // Patlama: alınan karenin çevresindeki piyon olmayan taşlar da gider.
      s.cells[to] = -1;
      final c0 = to % n, r0 = to ~/ n;
      for (final (dc, dr) in _king) {
        final c = c0 + dc, r = r0 + dr;
        if (_in(c, r) && pieceType(s.cells[r * n + c]) != cP) s.cells[r * n + c] = -1;
      }
    }
    s.last = to;
  }

  /// Konum özeti: taşlar, sıra, rok hakları ve geçerken alma karesi.
  /// (Web'de de taşmasın diye 30 bitte tutulur.)
  int positionKey(GridState s) {
    var h = s.turn + 1;
    for (final v in s.cells) {
      h = (h * 31 + v + 2) & 0x3fffffff;
    }
    h = (h * 31 + s.vars[2]) & 0x3fffffff;
    return (h * 31 + s.vars[3]) & 0x3fffffff;
  }

  /// Üç kez tekrar (FIDE 9.2): aynı konum aynı oyuncu sıradayken üçüncü kez
  /// oluşursa berabere. Alım ya da piyon hamlesi geçmişi sıfırlar.
  bool _repetition(GridState s, int before) {
    try {
      if (s.vars.length == 8) s.vars.add(before);
      if (s.vars[1] == 0) s.vars.length = 8;
      final k = positionKey(s);
      s.vars.add(k);
      var n = 0;
      for (var i = 8; i < s.vars.length; i++) {
        if (s.vars[i] == k) n++;
      }
      return n >= 3;
    } on UnsupportedError {
      return false; // sabit uzunluklu eski durum: tekrar izlenmez
    }
  }

  @override
  void apply(GridState s, int m) {
    final p = s.turn;
    final before = s.vars.length == 8 ? positionKey(s) : 0;
    _move(s, m);
    s.ply++;
    s.turn = 1 - p;
    if (_repetition(s, before)) {
      _judge(s, p);
      if (!isOver(s)) s.vars[0] = 3;
      return;
    }
    _judge(s, p);
  }

  void _judge(GridState s, int mover) {
    final o = 1 - mover;
    switch (variant) {
      case ChessVariant.threeCheck:
        if (inCheck(s, o)) s.vars[4 + mover]++;
        if (s.vars[4 + mover] >= 3) {
          s.vars[0] = mover + 1;
          return;
        }
      case ChessVariant.kingOfHill:
        final k = kingSq(s, mover);
        if (k >= 0 && const [27, 28, 35, 36].contains(k)) {
          s.vars[0] = mover + 1;
          return;
        }
      case ChessVariant.racingKings:
        final k = kingSq(s, mover);
        if (k >= 0 && k ~/ 8 == 0) {
          s.vars[0] = mover + 1;
          return;
        }
      case ChessVariant.atomic:
        if (kingSq(s, o) < 0) {
          s.vars[0] = mover + 1;
          return;
        }
      case ChessVariant.horde:
        if (!s.cells.any((v) => pieceColor(v) == 0)) {
          s.vars[0] = 2;
          return;
        }
      case ChessVariant.pawnRace:
        if (s.cells.any((v) => pieceColor(v) == mover && pieceType(v) != cP && pieceType(v) != cK)) {
          s.vars[0] = mover + 1;
          return;
        }
      case ChessVariant.antichess:
        if (!s.cells.any((v) => pieceColor(v) == o)) {
          s.vars[0] = o + 1;
          return;
        }
      default:
    }
    if (s.vars[1] >= 100) {
      s.vars[0] = 3;
      return;
    }
    final ms = moves(s);
    if (ms.isEmpty) {
      if (variant == ChessVariant.antichess) {
        s.vars[0] = o + 1; // hamlesi kalmayan kazanır
      } else if (variant == ChessVariant.horde && o == 0 || inCheck(s, o)) {
        s.vars[0] = mover + 1;
      } else {
        s.vars[0] = 3;
      }
      return;
    }
    if (_insufficient(s)) s.vars[0] = 3;
  }

  bool _insufficient(GridState s) {
    if (variant != ChessVariant.standard && variant != ChessVariant.chess960) return false;
    var minor = 0;
    for (final v in s.cells) {
      final t = pieceType(v);
      if (t == cP || t == cR || t == cQ) return false;
      if (t == cN || t == cB) minor++;
    }
    return minor <= 1;
  }

  @override
  bool isOver(GridState s) => s.vars[0] != 0;

  @override
  int winner(GridState s) => s.vars[0] == 1 ? 0 : (s.vars[0] == 2 ? 1 : -1);

  static const _val = [0, 100, 320, 330, 500, 900, 0];

  @override
  int moveOrder(GridState s, int m) {
    final victim = s.cells[mvTo(m)];
    final attacker = pieceType(s.cells[mvFrom(m)]);
    var v = 0;
    if (victim >= 0 && mvExtra(m) < 9) v += _val[pieceType(victim)] * 10 - _val[attacker];
    if (mvExtra(m) > 0 && mvExtra(m) < 9) v += _val[mvExtra(m) % 7];
    return v;
  }

  @override
  double evaluate(GridState s, int player) {
    var v = 0.0;
    final anti = variant == ChessVariant.antichess;
    for (var i = 0; i < s.cells.length; i++) {
      final x = s.cells[i];
      if (x < 0) continue;
      final t = pieceType(x), o = pieceColor(x);
      final c = i % n, r = i ~/ n;
      var val = _val[t].toDouble();
      final centre = 3.5 - ((c - (n - 1) / 2).abs() + (r - (n - 1) / 2).abs()) / 2;
      if (t == cN || t == cB) val += centre * 6;
      if (t == cP) val += (o == 0 ? (n - 2 - r) : (r - 1)) * 6 + centre * 2;
      if (t == cK) {
        if (variant == ChessVariant.kingOfHill) val += centre * 40;
        if (variant == ChessVariant.racingKings) val += (n - 1 - r) * 60;
      }
      v += (o == player) != anti ? val : -val;
    }
    if (variant == ChessVariant.threeCheck) v += (s.vars[4 + player] - s.vars[5 - player]) * 250;
    return v / 10;
  }

  @override
  String status(GridState s, String lang) {
    if (variant == ChessVariant.threeCheck) return '+${s.vars[4]}  ·  +${s.vars[5]}';
    return '';
  }

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}
