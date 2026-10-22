import 'heat_index.dart';
import 'models.dart';

/// Avisos de previsão do tempo, do mais grave para o mais leve.
enum WeatherAlertKind {
  alagamento('Risco de alagamento', Duration(hours: 3), urgent: true),
  tempestade('Temporal com raios', Duration(hours: 2), urgent: true),
  chuvaForte('Chuva forte', Duration(hours: 2)),
  calorExtremo('Calor extremo', Duration(hours: 2)),
  chuva('Vai chover', Duration(hours: 1)),
  solForte('Sol muito forte', Duration(hours: 1));

  const WeatherAlertKind(this.title, this.lead, {this.urgent = false});
  final String title;

  /// Antecedência da notificação: tempo para se preparar (sair antes, levar
  /// guarda-chuva, mudar o trajeto, tirar o carro da rua baixa).
  final Duration lead;

  /// Risco à vida: toca mesmo à noite e também abre um pop-up no app.
  final bool urgent;

  bool get isRain => this == alagamento || this == tempestade || this == chuvaForte || this == chuva;
}

class WeatherAlert {
  const WeatherAlert(this.kind, this.at, this.message);
  final WeatherAlertKind kind;

  /// Primeira hora em que a condição aparece na previsão.
  final DateTime at;
  final String message;

  String get title => kind.title;
}

/// Trovoada nos códigos da OMM usados pelo Open-Meteo.
bool _thunder(HourlyPoint h) => (h.weatherCode ?? 0) >= 95;

/// Pancada forte nos códigos da OMM (chuva forte, pancadas fortes ou violentas).
bool _heavyCode(HourlyPoint h) => const {65, 67, 81, 82}.contains(h.weatherCode) || _thunder(h);

String _hour(DateTime t, DateTime now) =>
    '${t.day == now.day ? '' : 'amanhã '}${t.hour == now.hour && t.day == now.day ? 'agora' : 'às ${t.hour}h'}';

String _mm(double mm) => '${mm.round()} mm';

/// Avisos para as próximas [hours] horas. Horários de [hourly] e [now] no
/// mesmo fuso. Os limites seguem a classificação usual de chuva por hora
/// (forte a partir de 7,6 mm/h) e o que costuma alagar ruas baixas e a beira
/// dos igarapés em Manaus (30 mm em 3 h ou 20 mm em 1 h).
List<WeatherAlert> forecastAlerts(List<HourlyPoint> hourly, {required DateTime now, int hours = 12}) {
  final next = hourly
      .where((h) => !h.time.isBefore(now.subtract(const Duration(minutes: 59))) && h.time.isBefore(now.add(Duration(hours: hours))))
      .toList()
    ..sort((a, b) => a.time.compareTo(b.time));
  if (next.isEmpty) return const [];
  final out = <WeatherAlert>[];

  // Chuva: o aviso mais grave entre alagamento, temporal, chuva forte e chuva.
  var best3h = 0.0;
  DateTime? best3hAt;
  for (var i = 0; i < next.length; i++) {
    final sum = next.skip(i).take(3).fold<double>(0, (s, h) => s + h.precipitationMm);
    if (sum > best3h) {
      best3h = sum;
      best3hAt = next[i].time;
    }
  }
  final wettest = next.reduce((a, b) => a.precipitationMm >= b.precipitationMm ? a : b);
  final storm = next.where((h) => _thunder(h) && h.precipitationProb >= 40).firstOrNull;
  final heavy = next.where((h) => h.precipitationMm >= 7.6 || (_heavyCode(h) && h.precipitationProb >= 50)).firstOrNull;
  final likely = next.where((h) => h.precipitationProb >= 60).firstOrNull;

  if (best3h >= 30 || wettest.precipitationMm >= 20) {
    final at = wettest.precipitationMm >= 20 ? wettest.time : best3hAt!;
    out.add(WeatherAlert(
      WeatherAlertKind.alagamento,
      at,
      'Chuva muito forte prevista ${_hour(at, now)} (até ${_mm(best3h)} em 3 horas). Ruas baixas e a beira dos '
      'igarapés podem alagar. Não atravesse ruas alagadas a pé, de bicicleta ou de moto: a correnteza arrasta. '
      'Em emergência, ligue 199 (Defesa Civil) ou 193 (Bombeiros).',
    ));
  } else if (storm != null) {
    out.add(WeatherAlert(
      WeatherAlertKind.tempestade,
      storm.time,
      'Previsão de temporal com raios ${_hour(storm.time, now)} (${storm.precipitationProb.round()}% de chance). '
      'Procure abrigo fechado, fique longe de árvores isoladas, postes e áreas abertas, e evite a beira dos igarapés.',
    ));
  } else if (heavy != null) {
    out.add(WeatherAlert(
      WeatherAlertKind.chuvaForte,
      heavy.time,
      'Chuva forte prevista ${_hour(heavy.time, now)}${heavy.precipitationMm > 0 ? ' (cerca de ${_mm(heavy.precipitationMm)} na hora)' : ''}. '
      'Leve guarda-chuva, cuidado com o chão escorregadio e evite ruas que costumam alagar.',
    ));
  } else if (likely != null) {
    out.add(WeatherAlert(
      WeatherAlertKind.chuva,
      likely.time,
      'Chance de ${likely.precipitationProb.round()}% de chuva ${_hour(likely.time, now)}. Leve guarda-chuva. '
      'Depois da chuva o ar fica mais úmido e a sensação de calor pode subir.',
    ));
  }

  // Calor e sol: só nas horas de dia sem chuva provável.
  final dry = next.where((h) => h.precipitationProb < 40 && h.uvIndex > 0.2).toList();
  final hottest = dry.isEmpty ? null : dry.reduce((a, b) => heatIndexC(a.temperatureC, a.humidity) >= heatIndexC(b.temperatureC, b.humidity) ? a : b);
  final peakFeels = hottest == null ? 0.0 : heatIndexC(hottest.temperatureC, hottest.humidity);
  if (hottest != null && peakFeels >= 41) {
    out.add(WeatherAlert(
      WeatherAlertKind.calorExtremo,
      hottest.time,
      'Sensação de ~${peakFeels.round()}°C ${_hour(hottest.time, now)}. Evite sol e esforço nesse horário, '
      'beba água a cada 15 a 20 minutos e prefira caminhos com sombra.',
    ));
  }
  final sunny = dry.where((h) => h.uvIndex >= 8).toList();
  if (sunny.isNotEmpty) {
    final peak = sunny.reduce((a, b) => a.uvIndex >= b.uvIndex ? a : b);
    out.add(WeatherAlert(
      WeatherAlertKind.solForte,
      sunny.first.time,
      'Sol forte com UV ${peak.uvIndex.round()} ${_hour(sunny.first.time, now)} até as ${sunny.last.time.hour + 1}h. '
      'Use protetor solar, boné e óculos escuros, e reaplique o protetor a cada 2 horas.',
    ));
  }

  out.sort((a, b) => a.kind.index.compareTo(b.kind.index));
  return out;
}

/// Notificação programada para um aviso: [notifyAt] já descontada a antecedência.
class WeatherNotice {
  const WeatherNotice(this.alert, this.notifyAt);
  final WeatherAlert alert;
  final DateTime notifyAt;

  WeatherAlertKind get kind => alert.kind;

  /// Identifica o mesmo evento entre atualizações da previsão (janela de 3 h),
  /// para não avisar duas vezes se a hora prevista mudar um pouco.
  String get key => '${kind.name}@${alert.at.year}-${alert.at.month}-${alert.at.day}-${alert.at.hour ~/ 3}';

  String get title => '${kind.title} ${_hourLabel(alert.at, notifyAt)}';

  String get body {
    final ahead = alert.at.difference(notifyAt);
    final lead = ahead.inMinutes >= 90
        ? 'Daqui a cerca de ${(ahead.inMinutes / 60).round()} horas. '
        : ahead.inMinutes >= 20
            ? 'Daqui a cerca de ${ahead.inMinutes ~/ 10 * 10} minutos. '
            : '';
    // A mensagem foi escrita com o "agora" do cálculo; vale o dia de quando toca.
    final h = alert.at.hour;
    final message = alert.at.day == notifyAt.day
        ? alert.message.replaceFirst('amanhã às ${h}h', 'às ${h}h')
        : alert.message.replaceFirst(RegExp('(?<!amanhã )às ${h}h'), 'amanhã às ${h}h');
    return '$lead$message';
  }
}

String _hourLabel(DateTime at, DateTime from) => '${at.day == from.day ? 'às' : 'amanhã às'} ${at.hour}h';

/// Horário de silêncio: avisos comuns não tocam das 22h às 6h.
bool _quiet(DateTime t) => t.hour >= 22 || t.hour < 6;

/// Notificações das próximas [hours] horas, cada uma com antecedência para a
/// pessoa se preparar. Se a antecedência já passou, avisa agora (desde que
/// falte pelo menos 20 minutos). Avisos comuns respeitam o silêncio da
/// noite: vão para as 6h se o evento for de dia, ou não tocam se for de
/// madrugada. Alagamento e temporal tocam a qualquer hora.
List<WeatherNotice> planWeatherNotices(List<HourlyPoint> hourly, {required DateTime now, int hours = 24}) {
  final out = <WeatherNotice>[];
  for (final a in forecastAlerts(hourly, now: now, hours: hours)) {
    if (a.at.difference(now).inMinutes < 20) continue;
    var at = a.at.subtract(a.kind.lead);
    if (!a.kind.urgent && _quiet(at)) {
      if (_quiet(a.at)) continue;
      at = DateTime(a.at.year, a.at.month, a.at.day, 6);
    }
    if (at.isBefore(now)) at = now;
    out.add(WeatherNotice(a, at));
  }
  return out;
}
