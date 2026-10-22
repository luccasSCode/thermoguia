// Gera os PNGs do ícone a partir do desenho vetorial em lib/core/widgets/leaf_icon.dart.
//
//   cd app
//   flutter test tool/render_brand_assets.dart
//   dart run tool/setup_platforms.dart   # aplica nos projetos Android e iOS
//
// Roda como teste porque precisa do motor de desenho do Flutter.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thermoguia/core/widgets/leaf_icon.dart';

/// Quadro do ícone adaptativo do Android: só os 72 dp do meio de 108 dp aparecem.
const _adaptive = 72 / 108;

Future<void> _png(String path, int px, CustomPainter painter) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), Size(px.toDouble(), px.toDouble()));
  final image = await recorder.endRecording().toImage(px, px);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
  stdout.writeln('✓ $path');
}

void main() {
  test('gera os ícones', () async {
    await TestWidgetsFlutterBinding.ensureInitialized().runAsync(() async {
      const b = 'assets/branding';
      // iOS e lojas: quadrado cheio (o sistema arredonda os cantos).
      await _png('$b/app_icon.png', 1024, LeafIconPainter(rounded: false));
      await _png('$b/app_icon_dark.png', 1024, LeafIconPainter(variant: LeafVariant.escuro, rounded: false));
      await _png('$b/app_icon_tinted.png', 1024, LeafIconPainter(variant: LeafVariant.tingido, rounded: false));
      await _png('$b/store_icon_512.png', 512, LeafIconPainter(rounded: false));
      // Logo dentro do app, já com os cantos arredondados.
      await _png('$b/logo.png', 1024, LeafIconPainter());

      // Android: camadas do ícone adaptativo e o ícone temático (monocromático).
      // O flutter_launcher_icons já põe 16% de margem na frente; o fundo não tem margem.
      await _png('$b/app_icon_background.png', 1024,
          LeafIconPainter(contentScale: _adaptive, frame: const LeafFrame(sunOpacity: 0, leafOpacity: 0, stemOpacity: 0, destScale: 0)));
      await _png('$b/app_icon_foreground.png', 1024, LeafIconPainter(background: false));
      await _png('$b/app_icon_monochrome.png', 1024, LeafIconPainter(silhouette: true));

      // Notificações do Android: folha branca na barra de status e o ícone do app ao lado do texto.
      const res = 'platform/android/res';
      await _png('$res/drawable-nodpi/ic_notification.png', 96, LeafIconPainter(silhouette: true));
      await _png('$res/drawable-nodpi/ic_notification_large.png', 256, LeafIconPainter());

      // Tela de abertura nativa vazia: a animação da folha começa logo em seguida.
      await _png('$b/splash_blank.png', 1152, _Blank());
    });
  });
}

class _Blank extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {}
  @override
  bool shouldRepaint(_Blank old) => false;
}
