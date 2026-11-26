import 'dart:typed_data';

import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import 'board_game.dart';
import 'chess.dart';

// ======================================================================
// Satranç bulmacaları: hızlı, kendine yeten bir satranç çekirdeği, mat ve
// malzeme çözücüleri, piyon oyunsonu tablosu ve yordamsal üretici.
//
// Kareler chess.dart ile aynı: r * 8 + c, r = 0 en üst (siyahın arka
// sırası). Taş: renk * 8 + tür, boş -1. Beyaz (0) yukarı (r - 1) oynar.
// Bulmacalarda rok hakkı yoktur; geçerken alma kurallara uygun işlenir.

/// Hamle: from | to << 6 | terfi << 12 | bayrak << 15 (1 geçerken alma,
/// 2 iki kare piyon).
int pmv(int from, int to, [int promo = 0, int flag = 0]) => from | (to << 6) | (promo << 12) | (flag << 15);
int pFrom(int m) => m & 63;
int pTo(int m) => (m >> 6) & 63;
int pPromo(int m) => (m >> 12) & 7;
int pFlag(int m) => m >> 15;

/// masa-motoru tahta hamlesine çevir (çizim ve dokunma eşlemesi için).
int pToBoard(int m) => mv(pFrom(m), pTo(m), pPromo(m));

const _kMate = 100000;
const pieceValues = [0, 100, 320, 330, 500, 900, 0];

final List<List<int>> _knightT = List.generate(64, (s) => _jumps(s, const [(1, 2), (2, 1), (-1, 2), (-2, 1), (1, -2), (2, -1), (-1, -2), (-2, -1)]));
final List<List<int>> _kingT = List.generate(64, (s) => _jumps(s, const [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)]));

List<int> _jumps(int s, List<(int, int)> d) {
  final r = s >> 3, c = s & 7;
  return [
    for (final (dr, dc) in d)
      if (r + dr >= 0 && r + dr < 8 && c + dc >= 0 && c + dc < 8) (r + dr) * 8 + c + dc
  ];
}

/// [s] karesinden [d] yönündeki ışın (8 yön: 0..3 düz, 4..7 çapraz).
final List<List<List<int>>> _rays = List.generate(64, (s) {
  const dirs = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)];
  final r0 = s >> 3, c0 = s & 7;
  return [
    for (final (dr, dc) in dirs)
      [
        for (var k = 1; k < 8; k++)
          if (r0 + dr * k >= 0 && r0 + dr * k < 8 && c0 + dc * k >= 0 && c0 + dc * k < 8) (r0 + dr * k) * 8 + c0 + dc * k
      ]
  ];
});

int _fwd(int side) => side == 0 ? -1 : 1;

/// Değiştirilebilir konum: hamle yap / geri al.
class PChess {
  final Int8List b;
  int stm;
  int ep;
  final List<int> _undo = [];

  PChess(Int8List cells, this.stm, [this.ep = -1]) : b = Int8List.fromList(cells);
  PChess.empty()
      : b = Int8List(64)..fillRange(0, 64, -1),
        stm = 0,
        ep = -1;

  PChess copy() => PChess(b, stm, ep);

  /// FEN'den konum (rok hakları yok sayılır).
  factory PChess.fromFen(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    final s = PChess.empty();
    var r = 0, c = 0;
    for (final ch in parts[0].split('')) {
      if (ch == '/') {
        r++;
        c = 0;
      } else if (int.tryParse(ch) != null) {
        c += int.parse(ch);
      } else {
        final t = 'pnbrqk'.indexOf(ch.toLowerCase()) + 1;
        s.b[r * 8 + c] = (ch == ch.toLowerCase() ? 8 : 0) + t;
        c++;
      }
    }
    s.stm = parts.length > 1 && parts[1] == 'b' ? 1 : 0;
    if (parts.length > 3 && parts[3] != '-') s.ep = squareOf(parts[3]);
    return s;
  }

  /// Konumun FEN'i (rok yok).
  String toFen() {
    final rows = <String>[];
    for (var r = 0; r < 8; r++) {
      var row = '', empty = 0;
      for (var c = 0; c < 8; c++) {
        final v = b[r * 8 + c];
        if (v < 0) {
          empty++;
          continue;
        }
        if (empty > 0) row += '$empty';
        empty = 0;
        final ch = ' pnbrqk'[v & 7];
        row += v >> 3 == 0 ? ch.toUpperCase() : ch;
      }
      if (empty > 0) row += '$empty';
      rows.add(row);
    }
    return '${rows.join('/')} ${stm == 0 ? 'w' : 'b'} - ${ep < 0 ? '-' : squareName(ep)} 0 1';
  }

  /// Yol sayımı (hamle üretiminin doğrulaması).
  int perft(int depth) {
    if (depth == 0) return 1;
    var n = 0;
    for (final m in legal()) {
      make(m);
      n += perft(depth - 1);
      unmake(m);
    }
    return n;
  }

  int king(int side) {
    final k = side * 8 + cK;
    for (var i = 0; i < 64; i++) {
      if (b[i] == k) return i;
    }
    return -1;
  }

  /// [by] rengi [sq] karesini tehdit ediyor mu.
  bool attacked(int sq, int by) {
    final base = by * 8;
    for (final t in _knightT[sq]) {
      if (b[t] == base + cN) return true;
    }
    for (final t in _kingT[sq]) {
      if (b[t] == base + cK) return true;
    }
    final pr = (sq >> 3) - _fwd(by), c = sq & 7;
    if (pr >= 0 && pr < 8) {
      if (c > 0 && b[pr * 8 + c - 1] == base + cP) return true;
      if (c < 7 && b[pr * 8 + c + 1] == base + cP) return true;
    }
    final rays = _rays[sq];
    for (var d = 0; d < 8; d++) {
      final slider = d < 4 ? cR : cB;
      for (final t in rays[d]) {
        final v = b[t];
        if (v < 0) continue;
        if (v == base + slider || v == base + cQ) return true;
        break;
      }
    }
    return false;
  }

  bool inCheck(int side) {
    final k = king(side);
    return k >= 0 && attacked(k, 1 - side);
  }

  /// Yalancı-yasal hamleler.
  void pseudo(List<int> out, {bool capturesOnly = false}) {
    final p = stm;
    for (var i = 0; i < 64; i++) {
      final v = b[i];
      if (v < 0 || v >> 3 != p) continue;
      final t = v & 7;
      switch (t) {
        case cP:
          final f = _fwd(p);
          final r = i >> 3, c = i & 7;
          final r1 = r + f;
          if (r1 < 0 || r1 > 7) continue;
          final last = p == 0 ? 0 : 7;
          void pawn(int to, int flag) {
            if (to >> 3 == last) {
              for (final pr in const [cQ, cN, cR, cB]) {
                out.add(pmv(i, to, pr, flag));
              }
            } else {
              out.add(pmv(i, to, 0, flag));
            }
          }

          final ahead = r1 * 8 + c;
          if (b[ahead] < 0 && (!capturesOnly || r1 == last)) {
            pawn(ahead, 0);
            final start = p == 0 ? 6 : 1;
            final two = (r + 2 * f) * 8 + c;
            if (r == start && b[two] < 0 && !capturesOnly) out.add(pmv(i, two, 0, 2));
          }
          for (final dc in const [-1, 1]) {
            final cc = c + dc;
            if (cc < 0 || cc > 7) continue;
            final to = r1 * 8 + cc;
            final o = b[to];
            if (o >= 0 && o >> 3 != p) pawn(to, 0);
            if (to == ep && o < 0) out.add(pmv(i, to, 0, 1));
          }
        case cN:
        case cK:
          for (final to in t == cN ? _knightT[i] : _kingT[i]) {
            final o = b[to];
            if (o >= 0 && o >> 3 == p) continue;
            if (capturesOnly && o < 0) continue;
            out.add(pmv(i, to));
          }
        default:
          final rays = _rays[i];
          final d0 = t == cB ? 4 : 0, d1 = t == cR ? 4 : 8;
          for (var d = d0; d < d1; d++) {
            for (final to in rays[d]) {
              final o = b[to];
              if (o >= 0 && o >> 3 == p) break;
              if (!capturesOnly || o >= 0) out.add(pmv(i, to));
              if (o >= 0) break;
            }
          }
      }
    }
  }

  void make(int m) {
    final from = pFrom(m), to = pTo(m), promo = pPromo(m), flag = pFlag(m);
    var capSq = to;
    if (flag == 1) capSq = to - _fwd(stm) * 8;
    final captured = b[capSq];
    _undo.add((captured + 1) | (capSq << 5) | ((ep + 1) << 11));
    final v = b[from];
    b[capSq] = -1;
    b[to] = promo > 0 ? stm * 8 + promo : v;
    b[from] = -1;
    ep = flag == 2 ? (from + to) >> 1 : -1;
    stm ^= 1;
  }

  void unmake(int m) {
    final u = _undo.removeLast();
    stm ^= 1;
    final from = pFrom(m), to = pTo(m), promo = pPromo(m);
    final captured = (u & 31) - 1, capSq = (u >> 5) & 63;
    ep = (u >> 11) - 1;
    b[from] = promo > 0 ? stm * 8 + cP : b[to];
    b[to] = -1;
    b[capSq] = captured;
  }

  List<int> legal({bool capturesOnly = false}) {
    final ps = <int>[];
    pseudo(ps, capturesOnly: capturesOnly);
    final me = stm;
    final out = <int>[];
    for (final m in ps) {
      make(m);
      if (!inCheck(me)) out.add(m);
      unmake(m);
    }
    return out;
  }

  bool hasLegal() {
    final ps = <int>[];
    pseudo(ps);
    final me = stm;
    for (final m in ps) {
      make(m);
      final ok = !inCheck(me);
      unmake(m);
      if (ok) return true;
    }
    return false;
  }

  bool get mated => inCheck(stm) && !hasLegal();
  bool get stalemated => !inCheck(stm) && !hasLegal();

  /// Sıradaki tarafın bakışıyla malzeme farkı.
  int material() {
    var s = 0;
    for (var i = 0; i < 64; i++) {
      final v = b[i];
      if (v < 0) continue;
      final val = pieceValues[v & 7];
      s += v >> 3 == stm ? val : -val;
    }
    return s;
  }

  int count() {
    var n = 0;
    for (final v in b) {
      if (v >= 0) n++;
    }
    return n;
  }

  // ---- Mat çözücü -------------------------------------------------------

  /// Sıradaki taraf en çok [n] hamlede mat edebiliyor mu.
  bool canMate(int n) {
    final ms = legal();
    for (final m in ms) {
      if (matesWithin(m, n)) return true;
    }
    return false;
  }

  /// [m] oynanınca rakip en çok [n] hamle içinde (bu hamle dahil) mat olur mu.
  bool matesWithin(int m, int n) {
    make(m);
    final bool ok;
    if (n == 1) {
      ok = inCheck(stm) && !hasLegal();
    } else {
      ok = _allLose(n);
    }
    unmake(m);
    return ok;
  }

  /// Savunan sırada: her yanıtın ardından saldıran [n] - 1 hamlede mat eder mi.
  bool _allLose(int n) {
    final rs = legal();
    if (rs.isEmpty) return inCheck(stm);
    // Önce şahın kaçışları ve almalar: çürütme çabuk bulunur.
    rs.sort((a, b2) => _defOrder(b2) - _defOrder(a));
    for (final r in rs) {
      make(r);
      final ok = canMate(n - 1);
      unmake(r);
      if (!ok) return false;
    }
    return true;
  }

  int _defOrder(int m) {
    final v = b[pFrom(m)];
    var o = 0;
    if (b[pTo(m)] >= 0) o += 2 + pieceValues[b[pTo(m)] & 7] ~/ 100;
    if (v & 7 == cK) o += 1;
    return o;
  }

  /// En kısa matın uzunluğu (en çok [max]); yoksa 0.
  int mateLength(int max) {
    for (var n = 1; n <= max; n++) {
      if (canMate(n)) return n;
    }
    return 0;
  }

  /// En çok [n] hamlede mat eden ilk hamleler (en çok [limit] tane).
  List<int> mateKeys(int n, {int limit = 2}) {
    final out = <int>[];
    for (final m in legal()) {
      if (matesWithin(m, n)) {
        out.add(m);
        if (out.length >= limit) break;
      }
    }
    return out;
  }

  /// Savunanın en dirençli yanıtı: ardından matın en geç geldiği hamle.
  /// [left] saldıranın kalan hamle hakkı.
  int bestDefence(int left) {
    var best = -1, bestLen = -1;
    for (final r in legal()) {
      make(r);
      final len = left <= 0 ? 0 : mateLength(left);
      unmake(r);
      final score = len == 0 ? 99 : len;
      if (score > bestLen) {
        bestLen = score;
        best = r;
      }
    }
    return best;
  }

  // ---- Malzeme çözücü ---------------------------------------------------

  int qs(int alpha, int beta, int ply) {
    if (ply > 24) return material();
    if (inCheck(stm)) {
      final ms = legal();
      if (ms.isEmpty) return -_kMate + ply;
      for (final m in ms) {
        make(m);
        final v = -qs(-beta, -alpha, ply + 1);
        unmake(m);
        if (v >= beta) return v;
        if (v > alpha) alpha = v;
      }
      return alpha;
    }
    final stand = material();
    if (stand >= beta) return stand;
    if (stand > alpha) alpha = stand;
    if (ply > 12) return alpha;
    final ms = legal(capturesOnly: true)..sort((a, c) => _capOrder(c) - _capOrder(a));
    for (final m in ms) {
      make(m);
      final v = -qs(-beta, -alpha, ply + 1);
      unmake(m);
      if (v >= beta) return v;
      if (v > alpha) alpha = v;
    }
    return alpha;
  }

  int _capOrder(int m) => pieceValues[b[pTo(m)] < 0 ? cP : b[pTo(m)] & 7] * 10 - pieceValues[b[pFrom(m)] & 7] + (pPromo(m) > 0 ? 800 : 0);

  int search(int depth, int alpha, int beta, int ply) {
    if (depth <= 0) return qs(alpha, beta, ply);
    final ms = legal();
    if (ms.isEmpty) return inCheck(stm) ? -_kMate + ply : 0;
    ms.sort((a, c) => _order(c) - _order(a));
    for (final m in ms) {
      make(m);
      final v = -search(depth - 1, -beta, -alpha, ply + 1);
      unmake(m);
      if (v >= beta) return v;
      if (v > alpha) alpha = v;
    }
    return alpha;
  }

  int _order(int m) {
    var o = 0;
    if (b[pTo(m)] >= 0) o += 1000 + _capOrder(m);
    if (pPromo(m) > 0) o += 900;
    make(m);
    if (inCheck(stm)) o += 500;
    unmake(m);
    return o;
  }

  /// [m] hamlesinin [depth] derinlikteki değeri (oynayanın bakışıyla).
  int scoreMove(int m, int depth) {
    make(m);
    final v = -search(depth - 1, -_kMate * 2, _kMate * 2, 1);
    unmake(m);
    return v;
  }

  /// [m] hamlesinin değeri en az [t] mi (dar pencereli hızlı sınama).
  bool moveAtLeast(int m, int depth, int t) {
    make(m);
    final v = -search(depth - 1, -t, -t + 1, 1);
    unmake(m);
    return v >= t;
  }

  /// En iyi hamle ve değeri.
  (int, int) bestMove(int depth) {
    var best = -1, bv = -_kMate * 2;
    final ms = legal()..sort((a, c) => _order(c) - _order(a));
    for (final m in ms) {
      make(m);
      final v = -search(depth - 1, -_kMate * 2, -bv, 1);
      unmake(m);
      if (v > bv || best < 0) {
        bv = v;
        best = m;
      }
    }
    return (best, bv);
  }
}

/// 'e4' → kare.
int squareOf(String name) => (8 - int.parse(name[1])) * 8 + name.codeUnitAt(0) - 97;
String squareName(int sq) => '${String.fromCharCode(97 + (sq & 7))}${8 - (sq >> 3)}';

/// Hamlenin UCI yazımı (ör. e7e8q).
String uciOf(int m) => '${squareName(pFrom(m))}${squareName(pTo(m))}${pPromo(m) > 0 ? ' pnbrqk'[pPromo(m)] : ''}';

bool isMateScore(int v) => v.abs() > _kMate - 1000;

// ======================================================================
// Piyon oyunsonu (Ş+P / Ş) tablosu: her konum için kazanç ya da beraberlik
// ve terfiye kalan yarım hamle sayısı. Piyonlu taraf "beyaz" sayılır.

class Kpk {
  /// 0 berabere, 255 yasa dışı, 1..254 kazanç (terfiye kalan yarım hamle).
  final Uint8List res;
  Kpk._(this.res);

  static Kpk? _cache;
  static Kpk get instance => _cache ??= Kpk._(build());
  static Kpk fromData(Uint8List data) => _cache = Kpk._(data);
  static bool get ready => _cache != null;

  static int index(int stm, int wk, int bk, int p) => ((stm * 48 + (p - 8)) * 64 + wk) * 64 + bk;

  static bool _adj(int a, int b) => a != b && ((a >> 3) - (b >> 3)).abs() <= 1 && ((a & 7) - (b & 7)).abs() <= 1;

  /// Piyonun tehdit ettiği kareler (beyaz piyon yukarı vurur).
  static bool _pawnHits(int p, int sq) => (sq >> 3) == (p >> 3) - 1 && ((sq & 7) - (p & 7)).abs() == 1;

  /// Terfi sonrası (siyah sırada) vezir/kale güvenli ve pat yok mu.
  static bool promoWins(int wk, int bk, int q, bool queen) {
    // Yeni taş korumasızsa ve şaha bitişikse alınır.
    if (_adj(bk, q) && !_adj(wk, q)) return false;
    // Siyahın kaçış karesi var mı ya da şahta mı.
    bool hits(int sq) {
      if (_adj(wk, sq)) return true;
      final qr = q >> 3, qc = q & 7, r = sq >> 3, c = sq & 7;
      if (sq == q) return false;
      final dr = r - qr, dc = c - qc;
      final straight = dr == 0 || dc == 0;
      final diag = dr.abs() == dc.abs();
      if (!(straight || (queen && diag))) return false;
      final sr = dr.sign, sc = dc.sign;
      var rr = qr + sr, cc = qc + sc;
      while (rr != r || cc != c) {
        final s = rr * 8 + cc;
        if (s == wk) return false;
        rr += sr;
        cc += sc;
      }
      return true;
    }

    if (hits(bk)) return true; // şah: kaçamazsa mat, kaçarsa yine kazanç
    for (final t in _kingT[bk]) {
      if (t == wk) continue;
      if (t == q) {
        if (!_adj(wk, q)) return true; // alabiliyor ama yukarıda elendi
        continue;
      }
      if (!hits(t)) return true;
    }
    return false; // pat
  }

  static Uint8List build() {
    final res = Uint8List(2 * 48 * 64 * 64);
    // Yasa dışı konumlar.
    for (var stm = 0; stm < 2; stm++) {
      for (var p = 8; p < 56; p++) {
        for (var wk = 0; wk < 64; wk++) {
          for (var bk = 0; bk < 64; bk++) {
            final i = index(stm, wk, bk, p);
            if (wk == bk || wk == p || bk == p || _adj(wk, bk) || (stm == 0 && _pawnHits(p, bk))) {
              res[i] = 255;
            }
          }
        }
      }
    }
    final pending = <int>[];
    for (var i = 0; i < res.length; i++) {
      if (res[i] == 0) pending.add(i);
    }
    var pass = 0;
    final won = <int>[];
    while (true) {
      pass++;
      won.clear();
      for (final i in pending) {
        final bk = i & 63, wk = (i >> 6) & 63, rest = i >> 12;
        final p = rest % 48 + 8, stm = rest ~/ 48;
        if (stm == 0) {
          if (_whiteWins(res, wk, bk, p, pass)) won.add(i);
        } else {
          if (_blackLoses(res, wk, bk, p, pass)) won.add(i);
        }
      }
      if (won.isEmpty || pass >= 250) break;
      for (final i in won) {
        res[i] = pass;
      }
      final keep = <int>[];
      for (final i in pending) {
        if (res[i] == 0) keep.add(i);
      }
      pending
        ..clear()
        ..addAll(keep);
    }
    return res;
  }

  static bool _isWin(int v, int pass) => v > 0 && v < 255 && v < pass;

  static bool _whiteWins(Uint8List res, int wk, int bk, int p, int pass) {
    // Piyon.
    final ahead = p - 8;
    if (ahead != wk && ahead != bk) {
      if (ahead < 8) {
        if (pass == 1 && (promoWins(wk, bk, ahead, true) || promoWins(wk, bk, ahead, false))) return true;
      } else {
        if (_isWin(res[index(1, wk, bk, ahead)], pass)) return true;
        if (p >> 3 == 6) {
          final two = p - 16;
          if (two != wk && two != bk && _isWin(res[index(1, wk, bk, two)], pass)) return true;
        }
      }
    }
    for (final t in _kingT[wk]) {
      if (t == p || t == bk || _adj(t, bk)) continue;
      if (_isWin(res[index(1, t, bk, p)], pass)) return true;
    }
    return false;
  }

  static bool _blackLoses(Uint8List res, int wk, int bk, int p, int pass) {
    var any = false;
    for (final t in _kingT[bk]) {
      if (t == wk || _adj(t, wk) || _pawnHits(p, t)) continue;
      if (t == p) return false; // piyon alındı: beraberlik
      any = true;
      if (!_isWin(res[index(0, wk, t, p)], pass)) return false;
    }
    if (!any) {
      // Hamlesi yok: piyon şah çekiyorsa mat (kazanç), değilse pat.
      return _pawnHits(p, bk);
    }
    return true;
  }

  int value(int stm, int wk, int bk, int p) => res[index(stm, wk, bk, p)];
  bool win(int stm, int wk, int bk, int p) {
    final v = value(stm, wk, bk, p);
    return v > 0 && v < 255;
  }
}

/// Konum Ş+P / Ş mi; öyleyse piyonlu tarafı beyaza çeviren görünüm
/// (piyonlu renk, şah, şah, piyon kareleri).
(int, int, int, int)? kpkView(PChess s) {
  int? pawn;
  int wk = -1, bk = -1;
  for (var i = 0; i < 64; i++) {
    final v = s.b[i];
    if (v < 0) continue;
    final t = v & 7;
    if (t == cK) continue;
    if (t != cP || pawn != null) return null;
    pawn = i;
  }
  if (pawn == null) return null;
  final side = s.b[pawn] >> 3;
  wk = s.king(side);
  bk = s.king(1 - side);
  if (wk < 0 || bk < 0) return null;
  int f(int sq) => side == 0 ? sq : (7 - (sq >> 3)) * 8 + (sq & 7);
  return (side, f(wk), f(bk), f(pawn));
}

/// Ş+P / Ş: sıradaki taraf için sonuç. 1 piyonlu taraf kazanır, 0 beraberlik.
/// İkinci değer terfiye kalan yarım hamle.
(bool, int) kpkProbe(Kpk t, PChess s) {
  final v = kpkView(s);
  if (v == null) return (false, 0);
  final (side, wk, bk, p) = v;
  if (p < 8 || p >= 56) return (false, 0);
  final stm = s.stm == side ? 0 : 1;
  final r = t.value(stm, wk, bk, p);
  return (r > 0 && r < 255, r);
}

// ======================================================================
// Bulmaca

enum PuzzleKind { mate1, mate2, mate3, fork, pin, skewer, discovered, pawnWin, pawnDraw }

extension PuzzleKindX on PuzzleKind {
  bool get isMate => this == PuzzleKind.mate1 || this == PuzzleKind.mate2 || this == PuzzleKind.mate3;
  bool get isTactic => this == PuzzleKind.fork || this == PuzzleKind.pin || this == PuzzleKind.skewer || this == PuzzleKind.discovered;
  bool get isEndgame => this == PuzzleKind.pawnWin || this == PuzzleKind.pawnDraw;
  int get mateIn => switch (this) { PuzzleKind.mate1 => 1, PuzzleKind.mate2 => 2, PuzzleKind.mate3 => 3, _ => 0 };
}

class ChessPuzzle {
  final PuzzleKind kind;
  final Int8List start;

  /// Oyuncunun rengi (sıradaki taraf).
  final int side;

  /// Çözücünün ana çizgisi (oyuncu, yanıt, oyuncu, ...). Boşsa bulmaca kurulamadı.
  final List<int> line;

  /// Taktiklerde kazanılacak malzeme (centipiyon), oyunsonunda tutulacak hamle sayısı.
  final int target;
  final int difficulty, seed;

  const ChessPuzzle(this.kind, this.start, this.side, this.line, this.target, this.difficulty, this.seed);

  PChess position() => PChess(start, side);
  bool get ok => line.isNotEmpty;
}

/// Taktik: oyuncu hamlesi en iyinin bu kadar altındaysa yanlış sayılır.
const kTacticSlack = 60;

/// Taktik derinliği (yarım hamle).
const kTacticDepth = 4;

/// Oyunsonu beraberlik bulmacasında tutulacak hamle sayısı.
const kHoldMoves = 5;

/// Bulmaca motoru: oyuncunun hamlesini yargılar, rakibin yanıtını seçer.
/// Görünüm ve doğrulama aynı kuralları kullanır.
class PuzzleJudge {
  final ChessPuzzle p;
  final PChess s;

  /// Oyuncunun yaptığı doğru hamle sayısı.
  int done = 0;
  bool solved = false;
  final int startMaterial;

  PuzzleJudge(this.p)
      : s = p.position(),
        startMaterial = p.position().material();

  int get playerMovesNeeded => switch (p.kind) {
        PuzzleKind.mate1 => 1,
        PuzzleKind.mate2 => 2,
        PuzzleKind.mate3 => 3,
        PuzzleKind.pawnDraw => kHoldMoves,
        PuzzleKind.pawnWin => p.target,
        _ => 3,
      };

  /// Sıra oyuncuda mı.
  bool get playerToMove => s.stm == p.side && !solved;

  /// Oyuncunun hamlesi doğru mu (konumu değiştirmez).
  bool accepts(int m) {
    if (!s.legal().contains(m)) return false;
    switch (p.kind) {
      case PuzzleKind.mate1 || PuzzleKind.mate2 || PuzzleKind.mate3:
        final left = p.kind.mateIn - done;
        return s.matesWithin(m, left);
      case PuzzleKind.pawnWin:
        s.make(m);
        final promo = pPromo(m);
        final ok = promo > 0 ? (promo == cQ || promo == cR) && !_promotionFails() : kpkProbe(Kpk.instance, s).$1;
        s.unmake(m);
        return ok;
      case PuzzleKind.pawnDraw:
        s.make(m);
        final ok = _holds();
        s.unmake(m);
        return ok;
      default:
        final (best, bv) = s.bestMove(kTacticDepth - 2 * (done.clamp(0, 1)));
        if (best == m) return true;
        final v = s.scoreMove(m, kTacticDepth - 2 * (done.clamp(0, 1)));
        return v >= bv - kTacticSlack && !(isMateScore(bv) && !isMateScore(v));
    }
  }

  // Terfiden sonra rakip (sıradaki) yeni taşı alabiliyor ya da pat ise başarısız.
  bool _promotionFails() {
    if (!s.hasLegal()) return !s.inCheck(s.stm);
    for (final r in s.legal()) {
      if (s.b[pTo(r)] >= 0 && (s.b[pTo(r)] & 7) != cP) return true;
    }
    return false;
  }

  /// Yalnız şahlar kaldı mı.
  bool get _bareKings {
    for (final v in s.b) {
      if (v >= 0 && (v & 7) != cK) return false;
    }
    return true;
  }

  /// Beraberlik bulmacası: oyuncunun hamlesinden sonra (rakip sırada)
  /// konum hâlâ berabere mi.
  bool _holds() {
    if (_bareKings) return true;
    if (kpkView(s) == null) return false;
    return !kpkProbe(Kpk.instance, s).$1;
  }

  /// Oyuncunun hamlesini uygular; bulmaca bittiyse true.
  bool play(int m) {
    s.make(m);
    done++;
    switch (p.kind) {
      case PuzzleKind.mate1 || PuzzleKind.mate2 || PuzzleKind.mate3:
        if (s.mated) solved = true;
      case PuzzleKind.pawnWin:
        if (pPromo(m) > 0) solved = true;
      case PuzzleKind.pawnDraw:
        if (_bareKings || done >= kHoldMoves) solved = true;
      default:
        // Kazanç gerçekleşti mi: rakip sırada, alabileceği her şeyden sonra.
        final now = -s.qs(-_kMate * 2, _kMate * 2, 0);
        if (now - startMaterial >= p.target - kTacticSlack && done >= 2) solved = true;
    }
    if (s.mated) solved = true;
    return solved;
  }

  /// Rakibin yanıtından sonra: beraberlik bulmacasında pat da başarıdır.
  void _afterReply() {
    if (p.kind == PuzzleKind.pawnDraw && s.stalemated) solved = true;
  }

  /// Rakibin yanıtı.
  int reply() {
    switch (p.kind) {
      case PuzzleKind.mate1 || PuzzleKind.mate2 || PuzzleKind.mate3:
        return s.bestDefence(p.kind.mateIn - done);
      case PuzzleKind.pawnWin:
        // En uzun direnen savunma.
        var best = -1, bv = -1;
        for (final r in s.legal()) {
          s.make(r);
          final (w, d) = kpkProbe(Kpk.instance, s);
          s.unmake(r);
          final v = w ? d : 1000;
          if (v > bv) {
            bv = v;
            best = r;
          }
        }
        return best;
      case PuzzleKind.pawnDraw:
        // En çetin deneme: oyuncunun en az doğru yanıtı kaldığı hamle.
        var best = -1, bv = 1 << 30;
        for (final r in s.legal()) {
          s.make(r);
          var good = 0;
          if (kpkView(s) != null) {
            for (final y in s.legal()) {
              s.make(y);
              if (_holds()) good++;
              s.unmake(y);
            }
          } else {
            good = 99;
          }
          s.unmake(r);
          final v = good * 4 + (pPromo(r) > 0 || (s.b[pFrom(r)] & 7) == cP ? 0 : 1);
          if (v < bv) {
            bv = v;
            best = r;
          }
        }
        return best;
      default:
        return s.bestMove(kTacticDepth - 1).$1;
    }
  }

  void applyReply(int r) {
    s.make(r);
    _afterReply();
  }

  /// İpucu: doğru hamlelerden biri.
  int hint() {
    switch (p.kind) {
      case PuzzleKind.mate1 || PuzzleKind.mate2 || PuzzleKind.mate3:
        final left = p.kind.mateIn - done;
        for (var n = 1; n <= left; n++) {
          final k = s.mateKeys(n, limit: 1);
          if (k.isNotEmpty) return k.first;
        }
        return -1;
      case PuzzleKind.pawnWin:
        var best = -1, bv = 1 << 30;
        for (final m in s.legal()) {
          if (!accepts(m)) continue;
          s.make(m);
          final d = pPromo(m) > 0 ? 0 : kpkProbe(Kpk.instance, s).$2;
          s.unmake(m);
          if (d < bv) {
            bv = d;
            best = m;
          }
        }
        return best;
      case PuzzleKind.pawnDraw:
        for (final m in s.legal()) {
          if (accepts(m)) return m;
        }
        return -1;
      default:
        return s.bestMove(kTacticDepth - 2 * (done.clamp(0, 1))).$1;
    }
  }
}

// ======================================================================
// Üretici

class PuzzleGen {
  final SeededRandom r;
  PuzzleGen(this.r);

  /// Zorluğa göre bulmaca türü (karışık, zorlaştıkça uzun matlar ve oyunsonu).
  static PuzzleKind kindFor(int d, SeededRandom r) {
    const table = <List<int>>[
      // mate1 mate2 mate3 fork pin skewer disc pawnWin pawnDraw
      [60, 0, 0, 25, 0, 15, 0, 0, 0],
      [45, 0, 0, 25, 5, 20, 5, 0, 0],
      [30, 20, 0, 20, 10, 10, 10, 0, 0],
      [15, 30, 0, 15, 10, 10, 10, 10, 0],
      [10, 35, 0, 12, 10, 8, 10, 10, 5],
      [5, 35, 10, 10, 10, 8, 10, 7, 5],
      [0, 30, 20, 10, 10, 5, 10, 8, 7],
      [0, 25, 30, 8, 10, 5, 10, 6, 6],
      [0, 20, 40, 6, 10, 4, 8, 6, 6],
      [0, 15, 50, 5, 8, 4, 8, 5, 5],
    ];
    return PuzzleKind.values[r.weighted(table[(d - 1).clamp(0, 9)])];
  }

  ChessPuzzle generate(PuzzleKind kind, int d, int seed, {int tries = 400}) {
    for (var i = 0; i < tries; i++) {
      final p = switch (kind) {
        PuzzleKind.mate1 || PuzzleKind.mate2 || PuzzleKind.mate3 => _mate(kind.mateIn, d),
        PuzzleKind.fork => _fork(d),
        PuzzleKind.pin => _pin(d),
        PuzzleKind.skewer => _skewer(d),
        PuzzleKind.discovered => _discovered(d),
        PuzzleKind.pawnWin => _pawnWin(),
        PuzzleKind.pawnDraw => _pawnDraw(),
      };
      if (p == null) continue;
      final (pos, target) = p;
      // Yarı yarıya siyahın bakışından: tahta dikey aynalanır, renkler değişir.
      final flip = r.nextInt(2) == 1;
      final cells = flip ? mirrorColors(pos.b) : Int8List.fromList(pos.b);
      final side = flip ? 1 : 0;
      final pz = ChessPuzzle(kind, cells, side, const [], target, d, seed);
      final line = solveLine(pz);
      if (line == null) continue;
      return ChessPuzzle(kind, cells, side, line, target, d, seed);
    }
    return ChessPuzzle(kind, Int8List(64), 0, const [], 0, d, seed);
  }

  static Int8List mirrorColors(Int8List b) {
    final out = Int8List(64)..fillRange(0, 64, -1);
    for (var i = 0; i < 64; i++) {
      final v = b[i];
      if (v < 0) continue;
      out[(7 - (i >> 3)) * 8 + (i & 7)] = ((1 - (v >> 3)) * 8 + (v & 7));
    }
    return out;
  }

  int _free(PChess s, bool Function(int sq) ok, [Set<int> avoid = const {}]) {
    for (var k = 0; k < 200; k++) {
      final q = r.nextInt(64);
      if (s.b[q] < 0 && !avoid.contains(q) && ok(q)) return q;
    }
    return -1;
  }

  static bool _pawnRow(int sq) => (sq >> 3) > 0 && (sq >> 3) < 7;
  static int _dist(int a, int b) {
    final dr = ((a >> 3) - (b >> 3)).abs(), dc = ((a & 7) - (b & 7)).abs();
    return dr > dc ? dr : dc;
  }

  /// Konum kurallara uygun ve beyaz sırada mı: şahlar tek, bitişik değil,
  /// siyah şahta değil, uç sıralarda piyon yok.
  static bool sane(PChess s) {
    var wk = 0, bk = 0;
    for (var i = 0; i < 64; i++) {
      final v = s.b[i];
      if (v < 0) continue;
      if (v == cK) wk++;
      if (v == 8 + cK) bk++;
      if ((v & 7) == cP && (i >> 3 == 0 || i >> 3 == 7)) return false;
    }
    if (wk != 1 || bk != 1) return false;
    if (_dist(s.king(0), s.king(1)) < 2) return false;
    if (s.inCheck(1)) return false;
    return true;
  }

  // ---- Mat ----------------------------------------------------------------

  (PChess, int)? _mate(int n, int d) {
    final s = PChess.empty();
    final f = r.nextInt(8);
    final rank = r.chance(0.7) ? 0 : 1;
    final bk = rank * 8 + f;
    s.b[bk] = 8 + cK;
    // Şahın önünde siper piyonları.
    for (final df in const [-1, 0, 1]) {
      final ff = f + df;
      if (ff < 0 || ff > 7 || !r.chance(0.55)) continue;
      final q = (rank + (r.chance(0.8) ? 1 : 2)) * 8 + ff;
      if (q < 56 && s.b[q] < 0) s.b[q] = 8 + cP;
    }
    final defenders = r.nextInt(3) + (d >= 6 ? 1 : 0);
    for (var i = 0; i < defenders; i++) {
      final t = [cR, cB, cN, cP, r.chance(0.2) ? cQ : cR][r.nextInt(5)];
      final q = _free(s, (q) => (q >> 3) <= 4 && (t != cP || _pawnRow(q)));
      if (q >= 0) s.b[q] = 8 + t;
    }
    final wk = _free(s, (q) => (q >> 3) >= 5 && _dist(q, bk) > 1);
    if (wk < 0) return null;
    s.b[wk] = cK;
    final attackers = 2 + r.nextInt(3);
    for (var i = 0; i < attackers; i++) {
      final t = const [cQ, cR, cR, cB, cN, cP, cB, cN][r.nextInt(8)];
      final q = _free(s, (q) => t != cP || ((q >> 3) >= 1 && (q >> 3) <= 6));
      if (q >= 0) s.b[q] = t;
    }
    if (!sane(s) || s.inCheck(0) || !s.hasLegal()) return null;
    if (n > 1 && s.canMate(n - 1)) return null;
    final keys = s.mateKeys(n);
    if (keys.length != 1) return null;
    return (s, 0);
  }

  // ---- Taktik -------------------------------------------------------------

  void _fill(PChess s, Set<int> avoid, {int white = 2, int black = 2}) {
    for (var i = 0; i < white; i++) {
      final t = const [cP, cP, cR, cB, cN][r.nextInt(5)];
      final q = _free(s, _pawnRow, avoid);
      if (q >= 0) s.b[q] = t;
    }
    for (var i = 0; i < black; i++) {
      final t = const [cP, cP, cB, cN, cP][r.nextInt(5)];
      final q = _free(s, _pawnRow, avoid);
      if (q >= 0) s.b[q] = 8 + t;
    }
  }

  /// Kurulan konumda [key] tek ve kazançlı hamle mi; öyleyse kazanç.
  int? _tacticOk(PChess s, int key, int gain) {
    if (!sane(s) || s.inCheck(0)) return null;
    final ms = s.legal();
    if (!ms.contains(key) || ms.length < 3) return null;
    final m0 = s.material();
    // Yalnız almalarla zaten kazanılıyorsa bulmaca değil.
    if (s.qs(-_kMate * 2, _kMate * 2, 0) - m0 >= gain - 50) return null;
    final kv = s.scoreMove(key, kTacticDepth);
    if (isMateScore(kv) || kv - m0 < gain) return null;
    // Başka hamle yakın bir sonuç veriyorsa anahtar tek değil.
    for (final m in ms) {
      if (m == key) continue;
      if (s.moveAtLeast(m, kTacticDepth, kv - 150)) return null;
    }
    return kv - m0;
  }

  static const _dirs = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)];

  (PChess, int)? _fork(int d) {
    final s = PChess.empty();
    final f = r.nextInt(48) + 8;
    final att = _knightT[f];
    if (att.length < 3) return null;
    final t1 = att[r.nextInt(att.length)];
    final t2 = att[r.nextInt(att.length)];
    if (t1 == t2 || _dist(t1, t2) < 2) return null;
    s.b[t1] = 8 + cK;
    s.b[t2] = 8 + const [cQ, cR, cR][r.nextInt(3)];
    final froms = [for (final q in _knightT[f]) if (s.b[q] < 0) q];
    if (froms.isEmpty) return null;
    final n0 = froms[r.nextInt(froms.length)];
    s.b[n0] = cN;
    final wk = _free(s, (q) => _dist(q, t1) > 2, {f});
    if (wk < 0) return null;
    s.b[wk] = cK;
    _fill(s, {f}, white: 1 + r.nextInt(3), black: 1 + r.nextInt(2 + (d > 5 ? 1 : 0)));
    final g = _tacticOk(s, pmv(n0, f), 200);
    return g == null ? null : (s, g);
  }

  (PChess, int)? _skewer(int d) {
    final s = PChess.empty();
    final (dr, dc) = _dirs[r.nextInt(8)];
    final k = r.nextInt(64), kr = k >> 3, kc = k & 7;
    final g = 1 + r.nextInt(3), a = 2 + r.nextInt(4);
    final br = kr + dr * g, bc = kc + dc * g, ar = kr - dr * a, ac = kc - dc * a;
    if (br < 0 || br > 7 || bc < 0 || bc > 7 || ar < 0 || ar > 7 || ac < 0 || ac > 7) return null;
    final diag = dr != 0 && dc != 0;
    s.b[k] = 8 + cK;
    s.b[br * 8 + bc] = 8 + (r.chance(0.5) ? cQ : cR);
    final aSq = ar * 8 + ac;
    final pt = diag ? (r.chance(0.6) ? cB : cQ) : (r.chance(0.6) ? cR : cQ);
    // Saldıran taş, hedef kareye tek hamlede gidebileceği bir yere.
    s.b[aSq] = pt;
    final reach = [for (final m in s.legal()) if (pFrom(m) == aSq && s.b[pTo(m)] < 0) pTo(m)];
    s.b[aSq] = -1;
    if (reach.isEmpty) return null;
    final from = reach[r.nextInt(reach.length)];
    s.b[from] = pt;
    final wk = _free(s, (q) => _dist(q, k) > 2, {aSq});
    if (wk < 0) return null;
    s.b[wk] = cK;
    _fill(s, {aSq}, white: 1 + r.nextInt(2), black: 1 + r.nextInt(2 + (d > 5 ? 1 : 0)));
    final gn = _tacticOk(s, pmv(from, aSq), 200);
    return gn == null ? null : (s, gn);
  }

  (PChess, int)? _pin(int d) {
    final s = PChess.empty();
    final (dr, dc) = _dirs[r.nextInt(8)];
    final k = r.nextInt(64), kr = k >> 3, kc = k & 7;
    final g = 1 + r.nextInt(3), a = g + 1 + r.nextInt(3);
    final xr = kr + dr * g, xc = kc + dc * g, ar = kr + dr * a, ac = kc + dc * a;
    if (xr < 0 || xr > 7 || xc < 0 || xc > 7 || ar < 0 || ar > 7 || ac < 0 || ac > 7) return null;
    final diag = dr != 0 && dc != 0;
    s.b[k] = 8 + cK;
    // Açmaza düşen taş çizgi boyunca kaçamamalı.
    final xt = diag ? const [cQ, cR, cN, cR][r.nextInt(4)] : const [cQ, cB, cN, cB][r.nextInt(4)];
    s.b[xr * 8 + xc] = 8 + xt;
    final aSq = ar * 8 + ac;
    final pt = diag ? cB : cR;
    s.b[aSq] = pt;
    final reach = [for (final m in s.legal()) if (pFrom(m) == aSq && s.b[pTo(m)] < 0) pTo(m)];
    s.b[aSq] = -1;
    if (reach.isEmpty) return null;
    final from = reach[r.nextInt(reach.length)];
    s.b[from] = pt;
    final wk = _free(s, (q) => _dist(q, k) > 2, {aSq});
    if (wk < 0) return null;
    s.b[wk] = cK;
    _fill(s, {aSq}, white: 1 + r.nextInt(3), black: 1 + r.nextInt(2 + (d > 5 ? 1 : 0)));
    final gn = _tacticOk(s, pmv(from, aSq), 200);
    return gn == null ? null : (s, gn);
  }

  (PChess, int)? _discovered(int d) {
    final s = PChess.empty();
    final (dr, dc) = _dirs[r.nextInt(8)];
    final k = r.nextInt(64), kr = k >> 3, kc = k & 7;
    final g = 1 + r.nextInt(3), a = g + 1 + r.nextInt(3);
    final mr = kr + dr * g, mc = kc + dc * g, ar = kr + dr * a, ac = kc + dc * a;
    if (mr < 0 || mr > 7 || mc < 0 || mc > 7 || ar < 0 || ar > 7 || ac < 0 || ac > 7) return null;
    final diag = dr != 0 && dc != 0;
    s.b[k] = 8 + cK;
    s.b[ar * 8 + ac] = diag ? (r.chance(0.6) ? cB : cQ) : (r.chance(0.6) ? cR : cQ);
    final mSq = mr * 8 + mc;
    final mt = const [cN, cN, cB, cR][r.nextInt(4)];
    if ((mt == cB && diag) || (mt == cR && !diag)) return null;
    s.b[mSq] = mt;
    bool onLine(int q) => ((q & 7) - kc) * dr == ((q >> 3) - kr) * dc;
    // Önce şahlar: legal() şah ister.
    final wk = _free(s, (q) => _dist(q, k) > 2);
    if (wk < 0) return null;
    s.b[wk] = cK;
    final tos = [for (final m in s.legal()) if (pFrom(m) == mSq && s.b[pTo(m)] < 0 && !onLine(pTo(m))) pTo(m)];
    if (tos.isEmpty) return null;
    final to = tos[r.nextInt(tos.length)];
    // Hedef: yeni karedeki taşın vurduğu bir kareye vezir ya da kale.
    s.b[mSq] = -1;
    s.b[to] = mt;
    final hits = [
      for (final m in s.legal())
        if (pFrom(m) == to && s.b[pTo(m)] < 0 && _dist(pTo(m), k) > 1) pTo(m)
    ];
    s.b[to] = -1;
    s.b[mSq] = mt;
    if (hits.isEmpty) return null;
    s.b[hits[r.nextInt(hits.length)]] = 8 + (r.chance(0.6) ? cQ : cR);
    _fill(s, {to}, white: r.nextInt(3), black: 1 + r.nextInt(2 + (d > 5 ? 1 : 0)));
    final gn = _tacticOk(s, pmv(mSq, to), 200);
    return gn == null ? null : (s, gn);
  }

  // ---- Piyon oyunsonu -----------------------------------------------------

  (PChess, int)? _pawnWin() {
    final t = Kpk.instance;
    final p = 8 + r.nextInt(40); // 7..3. sıralar (r 1..5)
    final wk = r.nextInt(64), bk = r.nextInt(64);
    if (t.value(0, wk, bk, p) == 255 || !t.win(0, wk, bk, p)) return null;
    final dist = t.value(0, wk, bk, p);
    if (dist < 7) return null;
    final s = PChess.empty();
    s.b[wk] = cK;
    s.b[bk] = 8 + cK;
    s.b[p] = cP;
    final ms = s.legal();
    if (ms.length < 4) return null;
    var wins = 0;
    for (final m in ms) {
      s.make(m);
      final ok = pPromo(m) > 0 ? false : kpkProbe(t, s).$1;
      s.unmake(m);
      if (ok) wins++;
    }
    if (wins != 1) return null;
    // Oyuncuya terfi için tanınan hamle sayısı: en iyi yolun iki katı + pay.
    return (s, (dist + 1) ~/ 2 * 2 + 6);
  }

  (PChess, int)? _pawnDraw() {
    final t = Kpk.instance;
    // Oyuncu savunan (beyaz), piyonlu taraf siyah. Önce piyonlu tarafı beyaz
    // sayarak arar, sonra aynalar.
    final p = 8 + r.nextInt(40);
    final wk = r.nextInt(64), bk = r.nextInt(64);
    final v = t.value(1, wk, bk, p);
    if (v != 0) return null; // yasa dışı ya da kaybediyor
    final s = PChess.empty();
    s.b[wk] = cK;
    s.b[bk] = 8 + cK;
    s.b[p] = cP;
    s.stm = 1;
    if (s.inCheck(0)) return null;
    final ms = s.legal();
    if (ms.length < 3) return null;
    var holds = 0, capture = false;
    for (final m in ms) {
      s.make(m);
      final ok = kpkView(s) == null || !kpkProbe(t, s).$1;
      s.unmake(m);
      if (ok) {
        holds++;
        if (s.b[pTo(m)] >= 0) capture = true;
      }
    }
    // Tek kurtaran hamle piyonu almaksa bulmaca değil.
    if (holds != 1 || capture) return null;
    // Aynala: savunan beyaz, sırada.
    final out = PChess(mirrorColors(s.b), 0);
    return (out, kHoldMoves);
  }

  /// Bulmacayı çözücüyle baştan sona oynat; ana çizgi ya da null.
  static List<int>? solveLine(ChessPuzzle pz) {
    final j = PuzzleJudge(pz);
    final line = <int>[];
    final limit = j.playerMovesNeeded + 2;
    for (var k = 0; k < limit * 2 + 2; k++) {
      if (j.solved) return line;
      if (!j.playerToMove) return null;
      final m = j.hint();
      if (m < 0 || !j.accepts(m)) return null;
      line.add(m);
      if (j.play(m)) return line;
      if (j.done >= (pz.kind.isTactic ? 3 : j.playerMovesNeeded)) return null;
      final rep = j.reply();
      if (rep < 0) return null;
      line.add(rep);
      j.applyReply(rep);
    }
    return null;
  }

  /// Bulmacayı yeniden doğrula: tek anahtar, kısa mat yok, ana çizgi çözüyor.
  static bool verify(ChessPuzzle pz) {
    if (!pz.ok) return false;
    final s = pz.position();
    if (!s.hasLegal() || s.inCheck(1 - pz.side)) return false;
    switch (pz.kind) {
      case PuzzleKind.mate1 || PuzzleKind.mate2 || PuzzleKind.mate3:
        final n = pz.kind.mateIn;
        if (n > 1 && s.canMate(n - 1)) return false;
        if (s.mateKeys(n).length != 1) return false;
      case PuzzleKind.pawnWin:
        var wins = 0;
        for (final m in s.legal()) {
          s.make(m);
          if (pPromo(m) == 0 && kpkProbe(Kpk.instance, s).$1) wins++;
          s.unmake(m);
        }
        if (wins != 1) return false;
      case PuzzleKind.pawnDraw:
        var holds = 0;
        for (final m in s.legal()) {
          s.make(m);
          if (kpkView(s) == null || !kpkProbe(Kpk.instance, s).$1) holds++;
          s.unmake(m);
        }
        if (holds != 1) return false;
      default:
        final key = pz.line.first;
        final kv = s.scoreMove(key, kTacticDepth);
        for (final m in s.legal()) {
          if (m != key && s.moveAtLeast(m, kTacticDepth, kv - 150)) return false;
        }
    }
    final line = solveLine(pz);
    return line != null && line.isNotEmpty && line.first == pz.line.first;
  }
}

// ======================================================================
// Bölüm kuralları

class ChessPuzzleRules extends GameRules<ChessPuzzle> {
  @override
  final String gameId;
  final int levels;
  ChessPuzzleRules({required this.gameId, this.levels = 100000});

  @override
  int get levelCount => levels;

  @override
  List<String> get optionalMechanics => const [];

  @override
  List<GameModeId> get modes => const [GameModeId.campaign, GameModeId.daily, GameModeId.weekly, GameModeId.challenge];

  @override
  List<GameStat> get gameStats => const [
        GameStat('puzzles_solved', 'Çözülen bulmaca', 'Puzzles solved', scale: 10),
        GameStat('mates_found', 'Bulunan mat', 'Mates found', scale: 5),
        GameStat('tactics_won', 'Kazanılan taktik', 'Tactics won', scale: 5),
      ];

  @override
  List<MissionTemplate> get missionTemplates => const [
        MissionTemplate('puzzles', 'puzzles_solved', [2, 5, 10]),
        MissionTemplate('mates', 'mates_found', [1, 3, 6]),
        MissionTemplate('tactics', 'tactics_won', [1, 3, 5]),
      ];

  @override
  ChessPuzzle generate(LevelSpec spec) {
    final d = spec.difficulty.clamp(1, 10);
    final r = SeededRandom(mixSeed([spec.seed, 4421]));
    final kind = PuzzleGen.kindFor(d, r);
    return PuzzleGen(r).generate(kind, d, spec.seed);
  }

  @override
  Validation validate(ChessPuzzle puzzle, LevelSpec spec) {
    if (!puzzle.ok) return const Validation.fail('no puzzle');
    if (!PuzzleGen.verify(puzzle)) return const Validation.fail('not unique');
    return Validation.ok(puzzle.line.length);
  }

  static int stars({required int mistakes, required int hints}) {
    if (mistakes == 0 && hints == 0) return 3;
    if (hints == 0 && mistakes <= 1) return 2;
    return 1;
  }
}
