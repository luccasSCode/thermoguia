// Prepara as pastas android/ e ios/ do app. Funciona em Windows, macOS e Linux.
//
//   cd app
//   dart run tool/setup_platforms.dart
//
// O que faz:
//  1. flutter create (gera android/ e ios/ se ainda não existirem)
//  2. copia o AndroidManifest com as permissões do ThermoGuia
//  3. habilita o "desugaring" exigido pelas notificações locais
//  4. adiciona as descrições de permissão no Info.plist do iOS
//  5. gera os ícones (logo) e a tela de abertura
import 'dart:io';

Future<void> main() async {
  await _run('flutter', ['create', '.', '--org', 'br.com.thermoguia', '--project-name', 'thermoguia', '--platforms', 'android,ios']);
  // O flutter create recria o teste de exemplo do contador, que não compila neste app.
  final sample = File('test/widget_test.dart');
  if (sample.existsSync() && sample.readAsStringSync().contains('MyApp')) sample.deleteSync();

  File('platform/android/AndroidManifest.xml')
      .copySync('android/app/src/main/AndroidManifest.xml');
  stdout.writeln('✓ AndroidManifest com permissões de localização e notificação');

  _patchGradle();
  _patchInfoPlist();

  await _run('flutter', ['pub', 'get']);
  await _run('dart', ['run', 'flutter_launcher_icons']);
  await _run('dart', ['run', 'flutter_native_splash:create']);
  stdout.writeln('\nPronto. Rode: flutter run --dart-define=API_URL=http://10.0.2.2:8080');
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
  if (s.contains('desugar_jdk_libs')) return;
  final isKts = file == kts;
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

