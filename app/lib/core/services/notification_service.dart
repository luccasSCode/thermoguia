import 'package:flutter/painting.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../storage/local_store.dart';
import 'notification_inbox.dart';

/// Notificações locais: lembretes de hidratação, alertas de calor e de
/// fumaça e as notificações programadas do dia (resumo da manhã, pico,
/// Clube H2O...). Cada tipo pode ser desligado em Configurações, e tudo o
/// que é mostrado também vai para o sino da tela Agora.
class NotificationService {
  NotificationService(this._store, this.inbox);
  final LocalStore _store;
  final NotificationInbox inbox;

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Chamado com o `payload` (rota do app) quando a pessoa toca numa notificação.
  void Function(String route)? onTap;

  /// Verde da logo: pinta o ícone pequeno na barra do Android.
  static const _brand = Color(0xFF178A6E);

  /// Folha em branco (o Android exige ícone de uma cor só na barra de status)
  /// e o ícone completo do app ao lado do texto.
  static const _smallIcon = 'ic_notification';
  static const _largeIcon = DrawableResourceAndroidBitmap('ic_notification_large');

  bool enabled(NotifKind k) => _store.getString('notif_kind_${k.name}') != '0';

  Future<void> setEnabled(NotifKind k, bool on) => _store.setString('notif_kind_${k.name}', on ? '1' : '0');

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
        android: AndroidInitializationSettings(_smallIcon),
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
        ?.requestPermissions(alert: true, sound: true, badge: true);
  }

  Future<void> hydrationReminder(int intervalMin) => _show(
        1,
        NotifKind.agua,
        'Hora de beber água',
        'Um copo agora. Próximo lembrete em $intervalMin minutos.',
        route: '/agora',
      );

  Future<void> heatAlert(String title, String body) => _show(2, NotifKind.calor, title, body, route: '/agora');

  /// Fumaça agora (ou o ar que acabou de melhorar). Abre o card do ar na tela Agora.
  Future<void> airAlert(String title, String body) => _show(3, NotifKind.ar, title, body, route: '/agora');

  NotificationDetails _details(NotifKind k, String body) {
    final urgent = k == NotifKind.ar || k == NotifKind.calor || k == NotifKind.tempo;
    final (channel, name, description) = switch (k) {
      NotifKind.agua => ('hidratacao', 'Lembretes de água', 'Lembretes para beber água enquanto você está na rua'),
      NotifKind.calor => ('alertas', 'Alertas de calor', 'Avisos quando o calor fica perigoso'),
      NotifKind.ar => ('qualidade_ar', 'Fumaça e qualidade do ar', 'Quando usar máscara de proteção e quando o ar fica bom'),
      NotifKind.dia => ('dia', 'Resumo do dia e Clube H2O', 'Resumo da manhã, pico de calor, fim de tarde e Clube H2O'),
      NotifKind.tempo => ('previsao', 'Chuva, temporal e sol', 'Avisos com antecedência de alagamento, temporal, chuva forte, calor e sol'),
    };
    return NotificationDetails(
      android: AndroidNotificationDetails(
        channel,
        name,
        channelDescription: description,
        icon: _smallIcon,
        largeIcon: _largeIcon,
        color: _brand,
        importance: urgent ? Importance.max : Importance.high,
        priority: urgent ? Priority.max : Priority.high,
        styleInformation: BigTextStyleInformation(body),
        category: urgent ? AndroidNotificationCategory.alarm : AndroidNotificationCategory.reminder,
      ),
      iOS: DarwinNotificationDetails(
        threadIdentifier: k.name,
        interruptionLevel: urgent ? InterruptionLevel.timeSensitive : InterruptionLevel.active,
      ),
    );
  }

  /// Programa uma notificação para [at] (horário local do aparelho).
  Future<void> schedule(int id, DateTime at, String title, String body,
      {required String route, NotifKind kind = NotifKind.dia}) async {
    if (!enabled(kind)) return;
    try {
      await init();
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(at, tz.local),
        _details(kind, body),
        // Sem alarme exato: não exige permissão extra e poupa bateria.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        payload: route,
      );
      await inbox.remember(id, InboxItem(title: title, body: body, at: at, kind: kind, route: route));
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
    await inbox.forget((id) => id >= from && id <= to);
  }

  Future<void> _show(int id, NotifKind kind, String title, String body, {String? route}) async {
    if (!enabled(kind)) return;
    await inbox.add(InboxItem(title: title, body: body, at: DateTime.now(), kind: kind, route: route));
    try {
      await init();
      await _plugin.show(id, title, body, _details(kind, body), payload: route);
    } catch (_) {
      // Notificação é complementar; falhas não podem derrubar o fluxo.
    }
  }
}
