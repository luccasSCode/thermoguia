/// Perfis de uso. A intensidade (MET) influencia o cálculo de risco
/// e a necessidade de hidratação.
enum Persona {
  pedestre('Pedestre', 3.5),
  ciclista('Ciclista', 6.0),
  entregador('Entregador(a)', 5.0),
  vendedor('Vendedor(a) ambulante', 2.5),
  carteiro('Carteiro(a)', 4.0),
  idoso('Pessoa idosa', 3.0);

  const Persona(this.label, this.met);
  final String label;
  final double met;

  bool get worksOutdoors =>
      this == entregador || this == vendedor || this == carteiro;

  static Persona fromName(String? name) => Persona.values.firstWhere(
        (p) => p.name == name,
        orElse: () => Persona.pedestre,
      );
}

enum RiskLevel {
  baixo('Baixo', 'Condições tranquilas para atividades ao ar livre.'),
  moderado('Moderado', 'Calor perceptível. Hidrate-se e prefira a sombra.'),
  alto('Alto', 'Exposição prolongada pode causar exaustão. Faça pausas.'),
  muitoAlto('Muito alto', 'Risco de exaustão térmica. Reduza o tempo ao sol.'),
  extremo('Extremo', 'Perigo de insolação. Evite o sol e procure abrigo.');

  const RiskLevel(this.label, this.summary);
  final String label;
  final String summary;

  static RiskLevel fromName(String? name) => RiskLevel.values.firstWhere(
        (r) => r.name == name,
        orElse: () => RiskLevel.baixo,
      );
}

/// Condições climáticas em um instante e local.
class ClimateSnapshot {
  const ClimateSnapshot({
    required this.time,
    required this.temperatureC,
    required this.humidity,
    required this.apparentC,
    required this.uvIndex,
    required this.windKmh,
    required this.precipitationProb,
    required this.cloudCover,
    required this.isDay,
  });

  final DateTime time;
  final double temperatureC;
  final double humidity;
  final double apparentC;
  final double uvIndex;
  final double windKmh;
  final double precipitationProb;
  final double cloudCover;
  final bool isDay;

  factory ClimateSnapshot.fromJson(Map<String, dynamic> j) => ClimateSnapshot(
        time: DateTime.parse(j['time'] as String),
        temperatureC: _d(j['temperatureC']),
        humidity: _d(j['humidity']),
        apparentC: _d(j['apparentC']),
        uvIndex: _d(j['uvIndex']),
        windKmh: _d(j['windKmh']),
        precipitationProb: _d(j['precipitationProb']),
        cloudCover: _d(j['cloudCover']),
        isDay: j['isDay'] == true,
      );

  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'temperatureC': temperatureC,
        'humidity': humidity,
        'apparentC': apparentC,
        'uvIndex': uvIndex,
        'windKmh': windKmh,
        'precipitationProb': precipitationProb,
        'cloudCover': cloudCover,
        'isDay': isDay,
      };

  ClimateSnapshot withTime(DateTime t) => ClimateSnapshot(
        time: t,
        temperatureC: temperatureC,
        humidity: humidity,
        apparentC: apparentC,
        uvIndex: uvIndex,
        windKmh: windKmh,
        precipitationProb: precipitationProb,
        cloudCover: cloudCover,
        isDay: isDay,
      );
}

/// Ponto da previsão horária.
class HourlyPoint {
  const HourlyPoint({
    required this.time,
    required this.temperatureC,
    required this.humidity,
    required this.uvIndex,
    required this.precipitationProb,
    this.precipitationMm = 0,
    this.weatherCode,
  });

  final DateTime time;
  final double temperatureC;
  final double humidity;
  final double uvIndex;
  final double precipitationProb;

  /// Chuva prevista na hora, em milímetros (0 em respostas antigas da API).
  final double precipitationMm;

  /// Código do tempo da OMM (95-99 = trovoada). Nulo em respostas antigas.
  final int? weatherCode;

  factory HourlyPoint.fromJson(Map<String, dynamic> j) => HourlyPoint(
        time: DateTime.parse(j['time'] as String),
        temperatureC: _d(j['temperatureC']),
        humidity: _d(j['humidity']),
        uvIndex: _d(j['uvIndex']),
        precipitationProb: _d(j['precipitationProb']),
        precipitationMm: _d(j['precipitationMm']),
        weatherCode: (j['weatherCode'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'time': time.toIso8601String(),
        'temperatureC': temperatureC,
        'humidity': humidity,
        'uvIndex': uvIndex,
        'precipitationProb': precipitationProb,
        'precipitationMm': precipitationMm,
        if (weatherCode != null) 'weatherCode': weatherCode,
      };

  HourlyPoint withTime(DateTime t) => HourlyPoint(
        time: t,
        temperatureC: temperatureC,
        humidity: humidity,
        uvIndex: uvIndex,
        precipitationProb: precipitationProb,
        precipitationMm: precipitationMm,
        weatherCode: weatherCode,
      );
}

/// Contexto do usuário que o agente considera além do clima.
class UserContext {
  const UserContext({
    required this.persona,
    this.exposureMinutesToday = 0,
    this.waterMlToday = 0,
    this.sensitivityOffset = 0,
    this.isMoving = false,
  });

  final Persona persona;
  final int exposureMinutesToday;
  final int waterMlToday;

  /// Ajuste pessoal aprendido (°C), entre -3 e +3.
  final double sensitivityOffset;
  final bool isMoving;
}

enum RecommendationKind { hidratacao, sombra, horario, saude, rota, roupa, chuva }

class Recommendation {
  const Recommendation({
    required this.id,
    required this.kind,
    required this.title,
    required this.message,
    required this.priority,
  });

  final String id;
  final RecommendationKind kind;
  final String title;
  final String message;

  /// Quanto maior, mais importante (0–100).
  final int priority;

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.name,
        'title': title,
        'message': message,
        'priority': priority,
      };
}

class RiskAssessment {
  const RiskAssessment({
    required this.heatIndexC,
    required this.effectiveIndexC,
    required this.level,
    required this.score,
    required this.hydrationIntervalMin,
    required this.waterGoalMl,
    required this.recommendations,
  });

  /// Índice de calor meteorológico puro.
  final double heatIndexC;

  /// Índice ajustado ao contexto (UV, esforço, exposição, hidratação, perfil).
  final double effectiveIndexC;
  final RiskLevel level;

  /// 0 a 100, para gráficos.
  final int score;
  final int hydrationIntervalMin;
  final int waterGoalMl;
  final List<Recommendation> recommendations;

  Map<String, dynamic> toJson() => {
        'heatIndexC': heatIndexC,
        'effectiveIndexC': effectiveIndexC,
        'level': level.name,
        'score': score,
        'hydrationIntervalMin': hydrationIntervalMin,
        'waterGoalMl': waterGoalMl,
        'recommendations': recommendations.map((r) => r.toJson()).toList(),
      };
}

double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
