import 'dart:io' show Platform;

/// Configuração em tempo de compilação:
///   flutter run --dart-define=API_URL=https://api.thermoguia.app
abstract final class AppConfig {
  static const _apiUrlOverride = String.fromEnvironment('API_URL');

  /// Sem API_URL, usa o computador local: 10.0.2.2 é o "localhost" visto pelo
  /// emulador Android; no simulador iOS e no macOS, localhost funciona direto.
  static final apiUrl = _apiUrlOverride.isNotEmpty
      ? _apiUrlOverride
      : Platform.isAndroid
          ? 'http://10.0.2.2:8080'
          : 'http://localhost:8080';

  /// Em produção, use um provedor de mapas com contrato (MapTiler, Stadia, etc.).
  static const tileUrl = String.fromEnvironment(
    'TILE_URL',
    defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  );

  static const packageName = 'br.com.thermoguia.thermoguia';

  /// Centro de Manaus, usado quando a localização não está disponível.
  static const defaultLat = -3.1190;
  static const defaultLng = -60.0217;
  static const cityName = 'Manaus';
}
