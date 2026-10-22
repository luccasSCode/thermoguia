// Prepara as pastas android/ e ios/ do app. Funciona em Windows, macOS e Linux.
//
//   cd app
//   dart run tool/setup_platforms.dart
//
// O que faz:
//  1. flutter create (gera android/ e ios/ se ainda não existirem)
//  2. copia o AndroidManifest (permissões), a MainActivity e os ícones de
//     notificação (platform/android)
//  3. habilita o "desugaring" exigido pelas notificações locais e desliga o
//     R8 no release (ele apaga código que os plugins chamam por JNI: tela preta)
//  4. adiciona as descrições de permissão no Info.plist do iOS
//  5. gera os ícones (no iOS, com as variantes Escuro e Tingido) e a tela de abertura
//
// Mudou o desenho do ícone? Antes, rode: flutter test tool/render_brand_assets.dart
import 'dart:io';

Future<void> main() async {
  await _run('flutter', ['create', '.', '--org', 'br.com.thermoguia', '--project-name', 'thermoguia', '--platforms', 'android,ios']);
  // O flutter create recria o teste de exemplo do contador, que não compila neste app.
  final sample = File('test/widget_test.dart');
  if (sample.existsSync() && sample.readAsStringSync().contains('MyApp')) sample.deleteSync();

  File('platform/android/AndroidManifest.xml')
      .copySync('android/app/src/main/AndroidManifest.xml');
  stdout.writeln('✓ AndroidManifest com permissões de localização e notificação');
  File('platform/android/MainActivity.kt')
      .copySync('android/app/src/main/kotlin/br/com/thermoguia/thermoguia/MainActivity.kt');
  _copyDir(Directory('platform/android/res'), Directory('android/app/src/main/res'));
  stdout.writeln('✓ Ícones de notificação do Android');

  _patchGradle();
  _patchInfoPlist();

  await _run('flutter', ['pub', 'get']);
  await _run('dart', ['run', 'flutter_launcher_icons']);
  await _run('dart', ['run', 'flutter_native_splash:create']);
  stdout.writeln('\nPronto. Rode: flutter run --dart-define=API_URL=http://10.0.2.2:8080');
}

void _copyDir(Directory from, Directory to) {
  for (final f in from.listSync(recursive: true).whereType<File>()) {
    final rel = f.path.substring(from.path.length + 1);
    final dest = File('${to.path}/$rel')..parent.createSync(recursive: true);
    f.copySync(dest.path);
  }
}

Future<void> _run(String cmd, List<String> args) async {
  stdout.writeln('\$ $cmd ${args.join(' ')}');
  final p = await Process.start(cmd, args, runInShell: true, mode: ProcessStartMode.inheritStdio);
  final code = await p.exitCode;
  if (code != 0) {
    stderr.writeln('Falhou ($code): $cmd ${args.join(' ')}');
    exit(code);
  }
}

void _patchGradle() {
  final kts = File('android/app/build.gradle.kts');
  final groovy = File('android/app/build.gradle');
  final file = kts.existsSync() ? kts : groovy;
  if (!file.existsSync()) {
    stderr.writeln('! build.gradle não encontrado; configure o desugaring manualmente (ver README).');
    return;
  }
  var s = file.readAsStringSync();
  final isKts = file == kts;
  s = _noShrink(s, isKts);
  file.writeAsStringSync(s);
  if (s.contains('desugar_jdk_libs')) return;
  final flag = isKts ? 'isCoreLibraryDesugaringEnabled = true' : 'coreLibraryDesugaringEnabled true';
  if (s.contains('compileOptions {')) {
    s = s.replaceFirst('compileOptions {', 'compileOptions {\n        $flag');
  } else {
    s = s.replaceFirst('android {', 'android {\n    compileOptions {\n        $flag\n    }');
  }
  final dep = isKts
      ? 'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")'
      : "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'";
  s += '\ndependencies {\n    $dep\n}\n';
  file.writeAsStringSync(s);
  stdout.writeln('✓ Desugaring habilitado em ${file.path}');
}

void _patchInfoPlist() {
  final f = File('ios/Runner/Info.plist');
  if (!f.existsSync()) return;
  var s = f.readAsStringSync();
  s = _ensurePhotoKeys(s);
  if (s.contains('NSLocationWhenInUseUsageDescription')) {
    f.writeAsStringSync(s);
    return;
  }
  const keys = '''
	<key>NSLocationWhenInUseUsageDescription</key>
	<string>O ThermoGuia usa sua localização para medir o calor onde você está e sugerir Rotas Frescas.</string>
	<key>LSApplicationQueriesSchemes</key>
	<array>
		<string>tel</string>
		<string>sms</string>
		<string>whatsapp</string>
		<string>https</string>
	</array>
	<key>CFBundleDisplayName</key>
	<string>ThermoGuia</string>
''';
  s = s.replaceFirst(RegExp(r'\s*<key>CFBundleDisplayName</key>\s*<string>[^<]*</string>'), '');
  final i = s.lastIndexOf('</dict>');
  if (i < 0) return;
  s = '${s.substring(0, i)}$keys${s.substring(i)}';
  f.writeAsStringSync(s);
  stdout.writeln('✓ Permissões adicionadas ao Info.plist');
}

/// Câmera e galeria para a foto de perfil e da comunidade (cada chave entra uma vez só).
String _ensurePhotoKeys(String s) {
  const keys = {
    'NSCameraUsageDescription': 'O ThermoGuia usa a câmera só quando você escolhe tirar uma foto de perfil ou para a comunidade.',
    'NSPhotoLibraryUsageDescription': 'O ThermoGuia acessa suas fotos só quando você escolhe uma foto de perfil ou para a comunidade.',
  };
  for (final e in keys.entries) {
    if (s.contains(e.key)) continue;
    final i = s.lastIndexOf('</dict>');
    if (i < 0) return s;
    s = '${s.substring(0, i)}\t<key>${e.key}</key>\n\t<string>${e.value}</string>\n${s.substring(i)}';
  }
  return s;
}

/// Desliga o R8 (encolhimento e ofuscação) no release. Plugins como o
/// shared_preferences chamam código Kotlin por JNI pelo nome; o R8 apaga ou
/// renomeia essas classes e o app trava ao abrir, com a tela preta.
String _noShrink(String s, bool isKts) {
  if (s.contains('isMinifyEnabled') || s.contains('minifyEnabled')) return s;
  final flags = isKts
      ? 'isMinifyEnabled = false\n            isShrinkResources = false'
      : 'minifyEnabled false\n            shrinkResources false';
  final release = RegExp(r'release\s*\{');
  if (!release.hasMatch(s)) return s;
  stdout.writeln('✓ R8 desligado no release (evita tela preta ao abrir)');
  return s.replaceFirstMapped(release, (m) => '${m[0]}\n            $flags');
}
