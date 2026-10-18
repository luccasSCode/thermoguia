import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Notificações locais: lembretes de hidratação, alertas de calor e as
/// notificações programadas do dia (resumo da manhã, pico, Clube H2O...).
class NotificationService {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Chamado com o `payload` (rota do app) quando a pessoa toca numa notificação.
  void Function(String route)? onTap;

  Future<void> init() async {
    if (_ready) return;
    _ready = true;
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('America/Manaus'));
    }
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        final route = r.payload;
        if (route != null && route.startsWith('/')) onTap?.call(route);
      },
    );
  }

  /// Rota da notificação que abriu o app (com ele fechado), se houver.
  Future<String?> launchRoute() async {
    await init();
    final details = await _plugin.getNotificationAppLaunchDetails();
    final route = details?.notificationResponse?.payload;
    return (details?.didNotificationLaunchApp ?? false) && route != null && route.startsWith('/') ? route : null;
  }

  Future<void> requestPermission() async {
    await init();
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, sound: true);
  }

  Future<void> hydrationReminder(int intervalMin) => _show(
        1,
        'Hora de beber água',
        'Um copo agora. Próximo lembrete em $intervalMin minutos.',
        'hidratacao',
        'Lembretes de hidratação',
      );

  Future<void> heatAlert(String title, String body) =>
      _show(2, title, body, 'alertas', 'Alertas de calor');

  /// Fumaça agora (ou o ar que acabou de melhorar). Abre o card do ar na tela Agora.
  Future<void> airAlert(String title, String body) =>
      _show(3, title, body, _airChannel, _airChannelName, route: '/agora', bigText: true);

  static const _airChannel = 'qualidade_ar';
  static const _airChannelName = 'Qualidade do ar e fumaça';

  /// Programa uma notificação para [at] (horário local do aparelho).
  /// [air] usa o canal urgente de qualidade do ar em vez do resumo do dia.
  Future<void> schedule(int id, DateTime at, String title, String body, {required String route, bool air = false}) async {
    try {
      await init();
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(at, tz.local),
        air
            ? NotificationDetails(
                android: AndroidNotificationDetails(
                  _airChannel,
                  _airChannelName,
                  channelDescription: 'Avisos de fumaça, quando usar máscara e quando o ar fica bom para sair',
                  importance: Importance.max,
                  priority: Priority.max,
                  styleInformation: BigTextStyleInformation(body),
                ),
                iOS: const DarwinNotificationDetails(interruptionLevel: InterruptionLevel.timeSensitive),
              )
            : const NotificationDetails(
                android: AndroidNotificationDetails(
                  'dia',
                  'Resumo do dia e Clube H2O',
                  channelDescription: 'Resumo da manhã, aviso do pico de calor, janela fresca e Clube H2O',
                  importance: Importance.defaultImportance,
                ),
                iOS: DarwinNotificationDetails(),
              ),
        // Sem alarme exato: não exige permissão extra e poupa bateria.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: route,
      );
    } catch (_) {
      // Notificação é complementar; falhas não podem derrubar o fluxo.
    }
  }

  /// Cancela as notificações programadas com id em [from, to].
  Future<void> cancelRange(int from, int to) async {
    try {
      await init();
      final pending = await _plugin.pendingNotificationRequests();
      for (final p in pending) {
        if (p.id >= from && p.id <= to) await _plugin.cancel(p.id);
      }
    } catch (_) {}
  }

  Future<void> _show(int id, String title, String body, String channel, String channelName,
      {String? route, bool bigText = false}) async {
    try {
      await init();
      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel,
            channelName,
            importance: bigText ? Importance.max : Importance.high,
            priority: bigText ? Priority.max : Priority.high,
            styleInformation: bigText ? BigTextStyleInformation(body) : null,
          ),
          iOS: DarwinNotificationDetails(interruptionLevel: bigText ? InterruptionLevel.timeSensitive : null),
        ),
        payload: route,
      );
    } catch (_) {
      // Notificação é complementar; falhas não podem derrubar o fluxo.
    }
  }
}
