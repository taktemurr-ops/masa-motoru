// Masa oyunları ekran görüntüleri: her oyunun 1. bölüm açılışı ve seçili
// oyunlarda baştan sona botlarla oynanan bir oyun (orta ve son). Yalnız
// SHOTS_DIR verilince çalışır (oyun testi iş akışı).
@Tags(['shots'])
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:masa_motoru/masa_motoru.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/app/studio_look.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';

final _out = Platform.environment['SHOTS_DIR'];
final _log = <String>[];

Future<void> _loadFonts() async {
  Future<void> load(String family, Iterable<File> files) async {
    final l = FontLoader(family);
    var n = 0;
    for (final f in files) {
      if (!f.existsSync()) continue;
      l.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
      n++;
    }
    if (n > 0) await l.load();
  }

  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
  final mf = Directory('${artifacts.path}/material_fonts');
  if (mf.existsSync()) {
    final all = mf.listSync().whereType<File>().toList();
    await load('Roboto', all.where((f) => f.path.contains('Roboto-') && f.path.endsWith('.ttf')));
    await load('MaterialIcons', all.where((f) => f.path.contains('MaterialIcons')));
  }
  const noto = '/usr/share/fonts/truetype/noto';
  await load('Noto Naskh Arabic', [File('$noto/NotoNaskhArabic-Regular.ttf'), File('$noto/NotoNaskhArabic-Bold.ttf')]);
  await load('Noto Sans CJK', [File('/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc')]);
}

PlayContext _ctx(GeneratedLevel gl, {List<SeatRole> seats = const [], void Function(RoundResult)? fin}) => PlayContext(
      spec: gl.spec,
      generated: gl,
      resume: const {},
      pieceColors: const [Color(0xFF3E6FB0), Color(0xFFC8553D), Color(0xFF2E8B57), Color(0xFFE0A100)],
      background: const [Color(0xFF1A2E5C), Color(0xFF3A6FC4)],
      colorBlind: false,
      reducedMotion: true,
      leftHanded: false,
      lang: 'tr',
      t: (k, [p = const {}]) => k,
      finish: fin ?? (_) {},
      saveResume: (_) {},
      requestHint: () async => true,
      requestBooster: () async => true,
      requestContinue: () async => false,
      sfx: (_) {},
      seats: seats,
    );

final _key = GlobalKey();

Widget _host(Widget child) => MaterialApp(
      theme: ThemeData(
        brightness: Brightness.light,
        extensions: const [StudioLook()],
        fontFamily: 'Roboto',
        fontFamilyFallback: const ['Noto Naskh Arabic', 'Noto Sans CJK'],
      ),
      home: Scaffold(backgroundColor: const Color(0xFF101426), body: RepaintBoundary(key: _key, child: child)),
    );

Future<void> _shot(WidgetTester t, String name) async {
  await t.pump(const Duration(milliseconds: 50));
  final ro = _key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await t.runAsync(() async {
    final img = await ro.toImage(pixelRatio: 1);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    File('$_out/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

typedef _G = (String, BoardGameRules, BoardSkin);

final List<_G> _games = [
  ('xox', MasaPresets.xox('oyun-xox'), const XoxSkin()),
  ('dortle', MasaPresets.dortle('oyun-dortle'), const DiscSkin(DiscBoard.frame, kRedYellow)),
  ('besleme', MasaPresets.besleme('oyun-besleme'), const DiscSkin(DiscBoard.wood, kBlackWhite)),
  ('reversi', MasaPresets.reversi('oyun-reversi'), const DiscSkin(DiscBoard.felt, kBlackWhite)),
  ('hex', MasaPresets.hex('oyun-hex'), const HexSkin()),
  ('noktalar', MasaPresets.dots('oyun-noktalar-ve-kutular'), const DotsSkin()),
  ('dama', MasaPresets.draughts('oyun-dama', DraughtsRules.english), const DraughtsSkin()),
  ('turk-damasi', MasaPresets.draughts('oyun-turk-damasi', DraughtsRules.turkish), const DraughtsSkin(plain: true)),
  ('satranc', MasaPresets.chess('oyun-satranc'), const ChessSkin()),
  ('mangala', MasaPresets.mancala('oyun-mangala', MancalaRules.mangala), const MancalaSkin()),
  ('dokuz-tas', MasaPresets.morris('oyun-dokuz-tas'), const MorrisSkin()),
  ('go', MasaPresets.go('oyun-go'), const DiscSkin(DiscBoard.wood, kBlackWhite)),
  ('tavla', MasaPresets.tavla('oyun-tavla'), const TavlaSkin()),
  ('kizma', MasaPresets.kizma('oyun-kizma-birader'), const KizmaSkin()),
  ('yilan', MasaPresets.snakes('oyun-yilan-merdiven'), const SnakesSkin()),
  ('zar-besli', MasaPresets.zarBesli('oyun-zar-beslisi'), const ZarBesliSkin()),
  ('farkle', MasaPresets.farkle('oyun-farkle'), const FarkleSkin()),
  ('yalanci', MasaPresets.liar('oyun-yalanci-zari'), const LiarSkin()),
  ('kapmali', MasaPresets.pente('oyun-kapmali-besleme'), const DiscSkin(DiscBoard.wood, kBlackWhite)),
  ('altili', MasaPresets.connect6('oyun-altili-bag'), const DiscSkin(DiscBoard.wood, kBlackWhite)),
  ('halma', MasaPresets.halma('oyun-halma'), const HalmaSkin()),
  ('cin-damasi', MasaPresets.starHalma('oyun-cin-damasi'), const StarSkin()),
  ('alquerque', MasaPresets.alquerque('oyun-alquerque'), const LinesSkin()),
  ('surakarta', MasaPresets.surakarta('oyun-surakarta'), const SurakartaSkin()),
  ('hnefatafl', MasaPresets.tafl('oyun-hnefatafl'), const TaflSkin()),
  ('halka', MasaPresets.havannah('oyun-halka-ve-kopru'), const HexHexSkin()),
  ('fanorona', MasaPresets.fanorona('oyun-fanorona'), const LinesSkin()),
  ('mermer', MasaPresets.marblePush('oyun-mermer-itme'), const MarbleSkin()),
  ('duvar', MasaPresets.wallRace('oyun-duvar-yarisi'), const WallRaceSkin()),
  ('ur', MasaPresets.ur('oyun-ur'), const UrSkin()),
  ('senet', MasaPresets.senet('oyun-senet'), const SenetSkin()),
  ('yut', MasaPresets.yut('oyun-yut'), const YutSkin()),
  ('pacisi', MasaPresets.pachisi('oyun-pacisi'), const PachisiSkin()),
  ('amiral', MasaPresets.naval('oyun-amiral-batti'), const NavalSkin()),
  ('cin-satranci', MasaPresets.xiangqi('oyun-cin-satranci'), const XiangqiSkin()),
  ('kore-satranci', MasaPresets.janggi('oyun-kore-satranci'), const XiangqiSkin(janggi: true)),
  ('japon-satranci', MasaPresets.shogi('oyun-japon-satranci'), const ShogiSkin()),
  ('kose', MasaPresets.corner('oyun-kose-yerlestirme'), const CornerSkin()),
  ('emlak', MasaPresets.property('oyun-emlak-ticareti'), const PropertySkin()),
  ('dunya', MasaPresets.conquest('oyun-dunya-hakimiyeti'), const ConquestSkin()),
  ('yerlesim', MasaPresets.settle('oyun-yerlesim-kurma'), const SettleSkin()),
  ('kaplan', MasaPresets.tigerGoats('oyun-kaplan-ve-keciler'), const TigerGoatSkin()),
  ('gizli', MasaPresets.hiddenRanks('oyun-gizli-rutbeler'), const HiddenRanksSkin()),
  ('cini', MasaPresets.tileDraft('oyun-cini-doseme'), const TileDraftSkin()),
  ('kartli', MasaPresets.cardLine('oyun-kartli-besleme'), const CardLineSkin()),
];

Future<void> _run(WidgetTester t, int ms) async {
  for (var k = 0; k < ms ~/ 200; k++) {
    await t.pump(const Duration(milliseconds: 200));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
  }
}

void main() {
  final skip = _out == null;
  setUpAll(() async {
    if (!skip) await _loadFonts();
  });
  tearDownAll(() {
    if (skip) return;
    File('$_out/log.txt')
      ..createSync(recursive: true)
      ..writeAsStringSync(_log.join('\n'));
  });

  GeneratedLevel lv(BoardGameRules r, int n) => r.build(LevelPlanner(gameId: r.gameId, optionalMechanics: const []).spec(n));

  testWidgets('her oyunun açılışı (1. ve 5. bölüm, telefon)', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(393, 760);
    for (final (name, rules, skin) in _games) {
      for (final n in [1, 5]) {
        try {
          final gl = lv(rules, n);
          await t.pumpWidget(_host(BoardView(key: UniqueKey(), ctx: _ctx(gl), skin: skin)));
          await _run(t, 1200);
          await _shot(t, '${name}_b$n');
          _log.add('$name b$n ok ${t.takeException() ?? ''}');
        } catch (e) {
          _log.add('$name b$n HATA $e');
        }
      }
    }
    await t.pumpWidget(const SizedBox());
    await _run(t, 2000);
    t.view.reset();
  }, skip: skip, timeout: const Timeout(Duration(minutes: 25)));

  testWidgets('botlarla baştan sona oyunlar (telefon + tablet)', (t) async {
    for (final (name, rules, skin) in _games) {
      final tablet = name.hashCode % 3 == 0;
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = tablet ? const Size(1280, 740) : const Size(393, 760);
      RoundResult? res;
      try {
        final gl = lv(rules, 3);
        final seats = List.filled(8, SeatRole.ai);
        await t.pumpWidget(_host(BoardView(key: UniqueKey(), ctx: _ctx(gl, seats: seats, fin: (r) => res = r), skin: skin)));
        var ms = 0;
        while (res == null && ms < 90000) {
          await _run(t, 1000);
          ms += 1000;
          if (ms == 8000) await _shot(t, '${name}_orta${tablet ? '_tablet' : ''}');
        }
        await _shot(t, '${name}_son${tablet ? '_tablet' : ''}');
        _log.add('$name bot: ${ms ~/ 1000}s ${res == null ? 'BİTMEDİ' : 'bitti won=${res!.won}'} ${t.takeException() ?? ''}');
      } catch (e) {
        _log.add('$name bot HATA $e');
      }
      await t.pumpWidget(const SizedBox());
      await _run(t, 600);
    }
    t.view.reset();
  }, skip: skip, timeout: const Timeout(Duration(minutes: 40)));
}
