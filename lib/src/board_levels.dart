import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:studio_core/core/missions.dart';
import 'package:studio_core/core/rng.dart';
import 'package:studio_core/core/stats.dart';

import 'board_ai.dart';
import 'board_game.dart';

/// Bölüm hedefi.
enum BoardGoal {
  /// Oyunu kazan.
  win,

  /// Kaybetme (berabere de olur). Kusursuz oynanınca berabere biten oyunlarda.
  notLose,
}

/// Rakibin gücü: arama derinliği, düğüm bütçesi ve gürültü.
class Opponent {
  final int depth;
  final int budget;
  final double noise;
  const Opponent(this.depth, this.budget, this.noise);
}

class BoardLevel {
  final BoardRules rules;
  final BoardState start;
  final int human; // oyuncunun koltuğu
  final Opponent opp;
  final BoardGoal goal;
  final int seed, difficulty;
  const BoardLevel(this.rules, this.start, this.human, this.opp, this.goal, this.seed, this.difficulty);

  bool goalMet(BoardState end) {
    final o = outcomeFor(rules, end, human);
    return goal == BoardGoal.win ? o == Outcome.win : o != Outcome.loss;
  }
}

/// Masa oyunlarının ortak bölüm kuralları: her bölüm bir maç. Zorluk
/// rakibin gücünü ve açılışı belirler. Bölüm, oyuncunun yerine oynayan güçlü
/// yapay zekâ hedefi tutturabiliyorsa kabul edilir; böylece her bölüm
/// kazanılabilir.
class BoardGameRules extends GameRules<BoardLevel> {
  @override
  final String gameId;
  final BoardRules Function(int difficulty) rulesFor;
  final Opponent Function(int difficulty) opponentFor;

  /// Oyuncunun yerine oynayan doğrulayıcı.
  final Opponent Function(int difficulty) solverFor;
  final BoardGoal Function(int difficulty) goalFor;

  /// Açılışta rastgele oynanacak hamle sayısı (çeşitlilik için).
  final int Function(int difficulty) openingFor;

  /// Oyuncu hangi koltukta başlar: null ise tohumdan.
  final int? Function(int difficulty) humanSeatFor;
  final int levels;
  final List<GameStat> stats;
  final List<MissionTemplate> missions;

  BoardGameRules({
    required this.gameId,
    required this.rulesFor,
    Opponent Function(int d)? opponentFor,
    Opponent Function(int d)? solverFor,
    BoardGoal Function(int d)? goalFor,
    int Function(int d)? openingFor,
    int? Function(int d)? humanSeatFor,
    this.levels = 50000,
    this.stats = const [
      GameStat('games_won', 'Kazanılan oyun', 'Games won', scale: 10),
      GameStat('moves_made', 'Yapılan hamle', 'Moves made', scale: 100),
    ],
    this.missions = const [
      MissionTemplate('wins', 'games_won', [1, 3, 6]),
      MissionTemplate('moves', 'moves_made', [30, 90, 200]),
    ],
  })  : opponentFor = opponentFor ?? defaultOpponent,
        solverFor = solverFor ?? defaultSolver,
        goalFor = goalFor ?? ((_) => BoardGoal.win),
        openingFor = openingFor ?? ((d) => d <= 3 ? 0 : 2),
        humanSeatFor = humanSeatFor ?? ((d) => d <= 2 ? 0 : null);

  static Opponent defaultOpponent(int d) => const [
        Opponent(1, 800, 1.0),
        Opponent(1, 1500, 0.8),
        Opponent(2, 3000, 0.7),
        Opponent(2, 5000, 0.55),
        Opponent(3, 8000, 0.45),
        Opponent(3, 12000, 0.35),
        Opponent(4, 18000, 0.25),
        Opponent(4, 26000, 0.18),
        Opponent(5, 36000, 0.1),
        Opponent(6, 50000, 0.05),
      ][(d - 1).clamp(0, 9)];

  static Opponent defaultSolver(int d) => Opponent(d >= 7 ? 6 : 5, 60000, 0);

  @override
  int get levelCount => levels;

  @override
  List<String> get optionalMechanics => const [];

  @override
  List<GameModeId> get modes => const [GameModeId.campaign, GameModeId.daily, GameModeId.weekly, GameModeId.challenge];

  @override
  List<GameStat> get gameStats => stats;

  @override
  List<MissionTemplate> get missionTemplates => missions;

  @override
  BoardLevel generate(LevelSpec spec) {
    final d = spec.difficulty.clamp(1, 10);
    final rules = rulesFor(d);
    final r = SeededRandom(mixSeed([spec.seed, 7331]));
    final s = rules.initial(r);
    final human = humanSeatFor(d) ?? r.nextInt(rules.players);
    // Açılış: kısa, gürültülü hamleler (oyun bitmemeli).
    final opening = openingFor(d);
    final ai = BoardAI(rules, depth: 1, nodeBudget: 400, noise: 1, r: r);
    for (var i = 0; i < opening && !rules.isOver(s); i++) {
      if (rules.needsChance(s)) {
        rules.applyChance(s, r);
        continue;
      }
      rules.apply(s, ai.choose(s));
    }
    return BoardLevel(rules, s, human, opponentFor(d), goalFor(d), spec.seed, d);
  }

  /// Bütün maçı oynat: oyuncu koltuğunda [solver], diğerlerinde bölümün rakibi.
  static BoardState simulate(BoardLevel l, {Opponent? solver, int seed = 11}) => simulateJudged(l, solver: solver, seed: seed).$1;

  /// Maçı oynat; ikinci değer: üstünlük eşiği aşılarak erken kazanıldı mı.
  static (BoardState, bool) simulateJudged(BoardLevel l, {Opponent? solver, int seed = 11}) {
    final rules = l.rules;
    final s = l.start.copy();
    final r = SeededRandom(mixSeed([l.seed, seed]));
    final sv = solver ?? const Opponent(5, 60000, 0);
    final me = BoardAI(rules, depth: sv.depth, nodeBudget: sv.budget, noise: sv.noise, r: r);
    final opp = BoardAI(rules, depth: l.opp.depth, nodeBudget: l.opp.budget, noise: l.opp.noise, r: r);
    var guard = 0;
    while (!rules.isOver(s) && s.ply < rules.maxPly && guard++ < 3000) {
      if (rules.needsChance(s)) {
        rules.applyChance(s, r);
        continue;
      }
      final ai = s.turn == l.human ? me : opp;
      rules.apply(s, ai.choose(s));
      if (rules.decisive.isFinite && s.ply > 16 && rules.evaluate(s, l.human) >= rules.decisive) return (s, true);
    }
    return (s, false);
  }

  @override
  Validation validate(BoardLevel level, LevelSpec spec) {
    if (level.rules.isOver(level.start)) return const Validation.fail('over at start');
    // Şanslı oyunlarda sonuç zara bağlı; maçın kurulması yeterli.
    if (level.rules.stochastic) return const Validation.ok(0);
    final (end, judged) = simulateJudged(level, solver: solverFor(level.difficulty));
    if (judged) return Validation.ok(end.ply);
    if (!level.rules.isOver(end) && end.ply < level.rules.maxPly) return const Validation.fail('did not finish');
    if (!level.goalMet(end)) return const Validation.fail('goal not reached');
    return Validation.ok(end.ply);
  }

  static int stars({required bool won, required int hints, required int undos}) {
    if (!won) return 0;
    if (hints == 0 && undos == 0) return 3;
    return hints == 0 ? 2 : 1;
  }
}
