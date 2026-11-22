import 'board_levels.dart';
import 'chess.dart';
import 'connect_games.dart';
import 'draughts.dart';
import 'go.dart';
import 'mancala.dart';
import 'morris.dart';
import 'tavla.dart';
import 'dice_games.dart';
import 'race_games.dart';
import 'line_games.dart';
import 'reversi.dart';

/// Hazır oyun ayarları: her oyun deposu yalnızca kimliğini verir.
class MasaPresets {
  static BoardGameRules xox(String id) => BoardGameRules(
        gameId: id,
        rulesFor: (_) => const LineRules('xox', 3, 3, 3),
        opponentFor: (d) => Opponent(d <= 4 ? 2 : 9, 20000, const [1.0, 0.85, 0.7, 0.55, 0.35, 0.25, 0.15, 0.1, 0.05, 0.0][d - 1]),
        solverFor: (_) => const Opponent(9, 60000, 0),
        goalFor: (d) => d <= 4 ? BoardGoal.win : BoardGoal.notLose,
        openingFor: (d) => 0,
        humanSeatFor: (d) => d <= 4 ? 0 : null,
        levels: 50000,
      );

  static BoardGameRules dortle(String id) => BoardGameRules(
        gameId: id,
        rulesFor: (_) => const LineRules('dortle', 7, 6, 4, gravity: true),
        solverFor: (_) => const Opponent(6, 40000, 0),
        openingFor: (d) => d <= 3 ? 0 : 2,
      );

  static BoardGameRules besleme(String id) => BoardGameRules(
        gameId: id,
        rulesFor: (d) => d <= 4 ? const LineRules('besleme', 11, 11, 5) : const LineRules('besleme', 15, 15, 5),
        opponentFor: (d) => Opponent(d <= 3 ? 1 : (d <= 6 ? 2 : (d <= 8 ? 3 : 4)), 8000, const [1.0, 0.8, 0.65, 0.5, 0.4, 0.3, 0.2, 0.12, 0.06, 0.02][d - 1]),
        solverFor: (_) => const Opponent(4, 15000, 0),
        openingFor: (d) => d <= 3 ? 0 : 2,
        humanSeatFor: (_) => 0,
      );

  static BoardGameRules reversi(String id) => BoardGameRules(
        gameId: id,
        rulesFor: (d) => d <= 2 ? const ReversiRules(6) : const ReversiRules(8),
        opponentFor: (d) => Opponent(const [1, 1, 2, 2, 3, 3, 3, 4, 4, 4][d - 1], 6000, const [1.0, 0.8, 0.65, 0.5, 0.4, 0.3, 0.2, 0.12, 0.06, 0.02][d - 1]),
        solverFor: (_) => const Opponent(4, 15000, 0),
        openingFor: (d) => 0,
      );

  static BoardGameRules hex(String id) => BoardGameRules(
        gameId: id,
        rulesFor: (d) => HexRules(d <= 3 ? 7 : (d <= 6 ? 9 : 11)),
        opponentFor: (d) => Opponent(d <= 5 ? 1 : 2, 3000, const [1.0, 0.85, 0.7, 0.6, 0.45, 0.35, 0.25, 0.18, 0.1, 0.05][d - 1]),
        solverFor: (_) => const Opponent(2, 5000, 0),
        openingFor: (d) => 0,
      );

  static BoardGameRules dots(String id) => BoardGameRules(
        gameId: id,
        rulesFor: (d) => d <= 2 ? const DotsRules(3, 3) : (d <= 5 ? const DotsRules(4, 4) : const DotsRules(5, 5)),
        opponentFor: (d) => Opponent(const [1, 1, 2, 2, 2, 3, 3, 3, 4, 4][d - 1], 6000, const [1.0, 0.8, 0.65, 0.5, 0.4, 0.3, 0.2, 0.12, 0.06, 0.02][d - 1]),
        solverFor: (_) => const Opponent(4, 10000, 0),
        openingFor: (d) => 0,
      );

  static BoardGameRules draughts(String id, DraughtsRules rules) => BoardGameRules(
        gameId: id,
        rulesFor: (_) => rules,
        opponentFor: (d) => Opponent(const [1, 1, 2, 2, 3, 3, 4, 4, 5, 5][d - 1], 12000, const [1.0, 0.8, 0.65, 0.5, 0.4, 0.3, 0.2, 0.12, 0.06, 0.02][d - 1]),
        solverFor: (_) => const Opponent(5, 25000, 0),
        openingFor: (d) => d <= 3 ? 0 : 2,
      );

  static BoardGameRules chess(String id, [ChessVariant v = ChessVariant.standard]) => BoardGameRules(
        gameId: id,
        rulesFor: (_) => ChessRules(v),
        opponentFor: (d) => Opponent(const [1, 1, 2, 2, 2, 3, 3, 3, 4, 4][d - 1], 6000, const [1.0, 0.85, 0.7, 0.55, 0.4, 0.3, 0.2, 0.12, 0.06, 0.03][d - 1]),
        solverFor: (_) => const Opponent(4, 12000, 0),
        openingFor: (d) => d <= 3 ? 0 : 2,
      );

  static BoardGameRules mancala(String id, MancalaRules rules) => BoardGameRules(
        gameId: id,
        rulesFor: (_) => rules,
        opponentFor: (d) => Opponent(const [1, 1, 2, 3, 3, 4, 5, 6, 7, 8][d - 1], 20000, const [1.0, 0.8, 0.65, 0.5, 0.4, 0.3, 0.2, 0.12, 0.06, 0.02][d - 1]),
        solverFor: (_) => const Opponent(9, 40000, 0),
        openingFor: (d) => 0,
      );

  static BoardGameRules morris(String id) => BoardGameRules(
        gameId: id,
        rulesFor: (_) => const MorrisRules(),
        opponentFor: (d) => Opponent(const [1, 1, 2, 2, 3, 3, 4, 4, 5, 5][d - 1], 12000, const [1.0, 0.8, 0.65, 0.5, 0.4, 0.3, 0.2, 0.12, 0.06, 0.02][d - 1]),
        solverFor: (_) => const Opponent(5, 25000, 0),
        openingFor: (d) => 0,
      );

  static BoardGameRules go(String id) => BoardGameRules(
        gameId: id,
        rulesFor: (d) => GoRules(d <= 7 ? 9 : 13),
        opponentFor: (d) => Opponent(const [1, 1, 1, 2, 2, 2, 2, 2, 3, 3][d - 1], 3000, const [1.0, 0.85, 0.7, 0.6, 0.45, 0.35, 0.25, 0.18, 0.1, 0.05][d - 1]),
        solverFor: (_) => const Opponent(2, 6000, 0),
        openingFor: (d) => 0,
        humanSeatFor: (_) => 0,
      );

  static BoardGameRules tavla(String id, [TavlaVariant v = TavlaVariant.tavla]) => BoardGameRules(
        gameId: id,
        rulesFor: (_) => TavlaRules(v),
        opponentFor: (d) => Opponent(const [1, 1, 1, 2, 2, 2, 3, 3, 4, 4][d - 1], 0, const [1.0, 0.8, 0.65, 0.5, 0.4, 0.3, 0.2, 0.12, 0.06, 0.02][d - 1]),
        solverFor: (_) => const Opponent(4, 0, 0),
        openingFor: (d) => 0,
      );

  static Opponent _noisy(int d) => Opponent(2, 0, const [1.0, 0.85, 0.7, 0.55, 0.45, 0.35, 0.25, 0.15, 0.08, 0.03][d - 1]);

  static BoardGameRules kizma(String id) => BoardGameRules(
        gameId: id,
        rulesFor: (d) => KizmaRules(d <= 3 ? 2 : (d <= 6 ? 3 : 4)),
        opponentFor: _noisy,
        solverFor: (_) => const Opponent(2, 0, 0),
        openingFor: (d) => 0,
        humanSeatFor: (_) => 0,
      );

  static BoardGameRules snakes(String id) => BoardGameRules(
        gameId: id,
        rulesFor: (d) => SnakesRules(d <= 4 ? 2 : (d <= 7 ? 3 : 4)),
        opponentFor: _noisy,
        solverFor: (_) => const Opponent(2, 0, 0),
        openingFor: (d) => 0,
        humanSeatFor: (_) => 0,
      );

  static BoardGameRules zarBesli(String id) => BoardGameRules(
        gameId: id,
        rulesFor: (_) => const ZarBesliRules(),
        opponentFor: _noisy,
        solverFor: (_) => const Opponent(2, 0, 0),
        openingFor: (d) => 0,
        humanSeatFor: (_) => 0,
      );

  static BoardGameRules farkle(String id) => BoardGameRules(
        gameId: id,
        rulesFor: (d) => FarkleRules(d <= 3 ? 2000 : (d <= 6 ? 3000 : 4000)),
        opponentFor: _noisy,
        solverFor: (_) => const Opponent(2, 0, 0),
        openingFor: (d) => 0,
        humanSeatFor: (_) => 0,
      );

  static BoardGameRules liar(String id) => BoardGameRules(
        gameId: id,
        rulesFor: (d) => LiarRules(d <= 4 ? 2 : (d <= 7 ? 3 : 4)),
        opponentFor: _noisy,
        solverFor: (_) => const Opponent(2, 0, 0),
        openingFor: (d) => 0,
        humanSeatFor: (_) => 0,
      );
}
