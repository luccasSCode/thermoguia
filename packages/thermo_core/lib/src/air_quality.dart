import 'heat_index.dart';
import 'models.dart';

/// Qualidade do ar no padrão brasileiro (IQAr, Resolução CONAMA 491/2018).
enum AirLevel {
  boa('Boa', 'Ar limpo. Ótimo para sair e arejar a casa.'),
  moderada('Moderada', 'Ar aceitável. Quem tem asma, bronquite ou problema cardíaco pode sentir.'),
  ruim('Ruim', 'Fumaça no ar. Use máscara de proteção na rua e evite esforço.'),
  muitoRuim('Muito ruim', 'Ar muito poluído. Evite sair e mantenha as janelas fechadas.'),
  pessima('Péssima', 'Perigo: fumaça intensa. Fique em ambiente fechado.');

  const AirLevel(this.label, this.summary);
  final String label;
  final String summary;

  /// A partir de "Ruim", a fumaça já faz mal a qualquer pessoa.
  bool get isBad => index >= AirLevel.ruim.index;

  static AirLevel fromName(String? name) => AirLevel.values.firstWhere(
        (l) => l.name == name,
        orElse: () => AirLevel.boa,
      );
}

/// Poluentes em uma hora (µg/m³). PM2.5 é a fumaça das queimadas.
class AirPoint {
  const AirPoint({required this.time, required this.pm25, required this.pm10});

  final DateTime time;
  final double pm25;
  final double pm10;

  int get index => airIndex(pm25, pm10);
  AirLevel get level => airLevelFor(index);

  AirPoint withTime(DateTime t) => AirPoint(time: t, pm25: pm25, pm10: pm10);

  factory AirPoint.fromJson(Map<String, dynamic> j) => AirPoint(
        time: DateTime.parse(j['time'] as String),
        pm25: (j['pm25'] as num?)?.toDouble() ?? 0,
        pm10: (j['pm10'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {'time': time.toIso8601String(), 'pm25': pm25, 'pm10': pm10};
}

// Faixas do IQAr: concentração (µg/m³) → índice.
const _indexBreaks = <double>[0, 40, 80, 120, 200, 400];
const _pm25Breaks = <double>[0, 25, 50, 75, 125, 300];
const _pm10Breaks = <double>[0, 50, 100, 150, 250, 600];

double _subIndex(double c, List<double> breaks) {
  if (c <= 0) return 0;
  for (var i = 1; i < breaks.length; i++) {
    if (c <= breaks[i]) {
      final f = (c - breaks[i - 1]) / (breaks[i] - breaks[i - 1]);
      return _indexBreaks[i - 1] + f * (_indexBreaks[i] - _indexBreaks[i - 1]);
    }
  }
  return _indexBreaks.last;
}

/// Índice de qualidade do ar (0–400): o pior entre PM2.5 e PM10.
int airIndex(double pm25, double pm10) {
  final a = _subIndex(pm25, _pm25Breaks);
  final b = _subIndex(pm10, _pm10Breaks);
  return (a > b ? a : b).round();
}

AirLevel airLevelFor(int index) => index <= 40
    ? AirLevel.boa
    : index <= 80
        ? AirLevel.moderada
        : index <= 120
            ? AirLevel.ruim
            : index <= 200
                ? AirLevel.muitoRuim
                : AirLevel.pessima;

/// Quanto ar a pessoa respira em relação a alguém em atividade leve.
/// Quem pedala ou carrega peso inspira mais fumaça a cada minuto.
double breathingFactor(Persona p) => (p.met / 3.0).clamp(0.8, 2.0).toDouble();

/// Equivalência em cigarros: respirar 22 µg/m³ de PM2.5 por 24 horas faz
/// ao pulmão o mesmo que fumar um cigarro (Berkeley Earth, 2015).
double cigarettesFor(double pm25, {double hours = 24, double breathing = 1}) =>
    pm25 / 22 * (hours / 24) * breathing;

/// O que fazer com a qualidade do ar de agora, ajustado ao perfil.
class AirAdvice {
  const AirAdvice({required this.level, required this.mask, required this.title, required this.message});
  final AirLevel level;

  /// true quando a recomendação inclui máscara de proteção (a que veda o rosto) na rua.
  final bool mask;
  final String title;
  final String message;
}

AirAdvice adviseAir(AirLevel level, Persona persona) {
  final sensitive = persona == Persona.idoso;
  final hard = persona == Persona.ciclista;
  final street = persona.worksOutdoors;
  switch (level) {
    case AirLevel.boa:
      return const AirAdvice(
        level: AirLevel.boa,
        mask: false,
        title: 'Ar limpo agora',
        message: 'Boa hora para sair, se exercitar e abrir as janelas de casa.',
      );
    case AirLevel.moderada:
      return AirAdvice(
        level: level,
        mask: sensitive,
        title: sensitive ? 'Ar aceitável, mas cuide-se' : 'Ar aceitável',
        message: sensitive
            ? 'Para pessoas idosas, a fumaça leve já irrita. Prefira caminhadas curtas e leve uma máscara de proteção.'
            : 'Dá para sair normalmente. Quem tem asma ou bronquite deve evitar esforço longo na rua.',
      );
    case AirLevel.ruim:
      return AirAdvice(
        level: level,
        mask: true,
        title: 'Fumaça no ar: use máscara de proteção',
        message: hard
            ? 'Pedalando você respira 2× mais fumaça. Hoje, prefira ônibus ou deixe a pedalada para a Hora Segura.'
            : street
                ? 'Use máscara de proteção durante o turno e leve uma reserva para trocar quando ficar úmida. Faça pausas em lugar fechado.'
                : 'Na rua, use máscara de proteção bem ajustada ao rosto. Evite esforço e deixe as janelas fechadas.',
      );
    case AirLevel.muitoRuim:
      return AirAdvice(
        level: level,
        mask: true,
        title: 'Ar muito poluído: evite sair',
        message: street
            ? 'Se não puder parar, use máscara de proteção o tempo todo e troque a cada 4 horas. Beba água para aliviar a garganta.'
            : 'Saia só se precisar, sempre de máscara de proteção. Feche janelas e portas; um pano úmido na fresta ajuda.',
      );
    case AirLevel.pessima:
      return const AirAdvice(
        level: AirLevel.pessima,
        mask: true,
        title: 'Perigo: fumaça intensa',
        message: 'Fique em casa com tudo fechado. Se precisar sair, use máscara de proteção. '
            'Falta de ar, chiado ou dor no peito: procure atendimento.',
      );
  }
}

/// Período com ar limpo e calor suportável ao mesmo tempo: a Hora Segura.
class SafeWindow {
  const SafeWindow({required this.start, required this.end, required this.airIndex, required this.feelsC});
  final DateTime start;
  final DateTime end;
  final int airIndex;
  final double feelsC;

  String get rangeLabel => '${start.hour}h–${end.hour}h';
}

double _feels(HourlyPoint h) => heatIndexC(h.temperatureC, h.humidity) + h.uvIndex * 0.35;

/// Horas, nas próximas 24h, em que o ar está bom ou moderado e a sensação
/// fica abaixo de "muito alto" (38 °C). Junta horas seguidas em janelas.
List<SafeWindow> safeOutdoorWindows(
  List<AirPoint> air,
  List<HourlyPoint> heat, {
  required DateTime now,
  int minHour = 6,
  int maxHour = 20,
  int take = 2,
}) {
  final start = DateTime(now.year, now.month, now.day, now.hour);
  final horizon = start.add(const Duration(hours: 24));
  HourlyPoint? heatAt(DateTime t) {
    for (final h in heat) {
      if (h.time.difference(t).inMinutes.abs() < 31) return h;
    }
    return null;
  }

  final hours = air.where((a) => !a.time.isBefore(start) && a.time.isBefore(horizon)).toList()
    ..sort((a, b) => a.time.compareTo(b.time));

  final windows = <SafeWindow>[];
  final run = <(AirPoint, double)>[];
  void close() {
    if (run.isNotEmpty) {
      windows.add(SafeWindow(
        start: run.first.$1.time,
        end: run.last.$1.time.add(const Duration(hours: 1)),
        airIndex: (run.map((r) => r.$1.index).reduce((a, b) => a + b) / run.length).round(),
        feelsC: run.map((r) => r.$2).reduce((a, b) => a + b) / run.length,
      ));
      run.clear();
    }
  }

  for (final a in hours) {
    final h = heatAt(a.time);
    final feels = h == null ? 30.0 : _feels(h);
    final good = a.time.hour >= minHour && a.time.hour < maxHour && !a.level.isBad && feels < 38;
    final follows = run.isNotEmpty && a.time.difference(run.last.$1.time).inHours == 1;
    if (!good || !follows) close();
    if (good) run.add((a, feels));
  }
  close();

  // Melhores primeiro: ar mais limpo e mais fresco, com bônus para janelas longas.
  double score(SafeWindow w) => w.airIndex + w.feelsC * 2 - w.end.difference(w.start).inHours * 3;
  windows.sort((a, b) => score(a).compareTo(score(b)));
  final picked = windows.take(take).toList()..sort((a, b) => a.start.compareTo(b.start));
  return picked;
}

enum AirAlertKind { piora, melhora }

/// Aviso de qualidade do ar programado a partir da previsão.
class AirAlert {
  const AirAlert({required this.at, required this.kind, required this.level, required this.title, required this.body});
  final DateTime at;
  final AirAlertKind kind;
  final AirLevel level;
  final String title;
  final String body;

  @override
  String toString() => '${kind.name} ${at.toIso8601String()} | $title | $body';
}

bool _quiet(DateTime t) => t.hour >= 22 || t.hour < 6;

/// Avisos das próximas [horizonHours]: 1 hora antes de a fumaça chegar e
/// quando o ar volta a ficar bom. Nada entre 22h e 6h: o aviso noturno vai
/// para as 6h, se a situação continuar. Puro, para testar.
List<AirAlert> planAirAlerts(
  List<AirPoint> air, {
  required DateTime now,
  required Persona persona,
  int horizonHours = 48,
  int max = 6,
}) {
  final hours = air
      .where((a) => a.time.isAfter(now) && a.time.isBefore(now.add(Duration(hours: horizonHours))))
      .toList()
    ..sort((a, b) => a.time.compareTo(b.time));
  if (hours.isEmpty) return const [];

  AirLevel levelAt(DateTime t) {
    var best = hours.first;
    for (final h in hours) {
      if (h.time.difference(t).abs() < best.time.difference(t).abs()) best = h;
    }
    return best.level;
  }

  // Até quando o ar segue bom depois de [from] (para dizer "até as 15h").
  DateTime? cleanUntil(DateTime from) {
    for (final h in hours) {
      if (h.time.isAfter(from) && h.level.isBad) return h.time;
    }
    return null;
  }

  final past = air.where((a) => !a.time.isAfter(now)).toList()..sort((a, b) => a.time.compareTo(b.time));
  var bad = (past.isEmpty ? hours.first : past.last).level.isBad;
  // "O ar melhorou" só faz sentido se a pessoa soube da fumaça (pelo app ou por aviso).
  var announced = bad;
  final out = <AirAlert>[];

  for (final h in hours) {
    final nowBad = h.level.isBad;
    if (nowBad == bad) continue;
    bad = nowBad;

    var at = nowBad ? h.time.subtract(const Duration(hours: 1)) : h.time;
    if (!at.isAfter(now)) at = now.add(const Duration(minutes: 1));
    if (_quiet(at)) {
      final six = DateTime(at.year, at.month, at.day + (at.hour >= 22 ? 1 : 0), 6);
      // De madrugada a situação pode ter mudado de novo: só avisa se ainda vale às 6h.
      if (levelAt(six).isBad != nowBad) continue;
      at = six;
    }
    if (!nowBad && !announced) continue;
    announced = nowBad;

    if (nowBad) {
      final advice = adviseAir(h.level, persona);
      out.add(AirAlert(
        at: at,
        kind: AirAlertKind.piora,
        level: h.level,
        title: h.level.index >= AirLevel.muitoRuim.index
            ? 'Alerta de fumaça: qualidade do ar ${h.level.label.toLowerCase()} às ${h.time.hour}h'
            : 'Fumaça chegando por volta das ${h.time.hour}h',
        body: '${advice.title}. ${advice.message}',
      ));
    } else {
      final until = cleanUntil(h.time);
      out.add(AirAlert(
        at: at,
        kind: AirAlertKind.melhora,
        level: h.level,
        title: 'O ar melhorou: pode sair',
        body: 'Qualidade do ar ${h.level.label.toLowerCase()}${until != null ? ' até as ${until.hour}h' : ''}. '
            'Boa hora para sair e arejar a casa.',
      ));
    }
    if (out.length == max) break;
  }
  return out;
}
