import 'dart:convert';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:thermo_core/thermo_core.dart';

import '../app_deps.dart';
import '../cities.dart';
import '../http/http_utils.dart';

/// Endereço público da API, para montar links que saem do app.
String publicBase(AppDeps d, Request req) {
  if (d.config.publicUrl.isNotEmpty) return d.config.publicUrl.replaceAll(RegExp(r'/+$'), '');
  final proto = req.headers['x-forwarded-proto'] ?? req.requestedUri.scheme;
  return '$proto://${req.requestedUri.authority}';
}

String _newToken() {
  final r = Random.secure();
  return base64Url.encode(List.generate(24, (_) => r.nextInt(256))).replaceAll('=', '');
}

/// Acompanhamento pelo responsável: a pessoa gera um link secreto e manda
/// para o contato de emergência. O link mostra, ao vivo, a água do dia e
/// os pedidos de ajuda ("Estou passando mal"), sem precisar de conta.
void registerGuardianRoutes(Router r, AppDeps d) {
  Future<Map<String, dynamic>?> linkOf(String userId) =>
      d.db.one('SELECT token, created_at FROM guardian_links WHERE user_id = CAST(@u AS uuid)', {'u': userId});

  r.get('/guardian/link', (Request req) async {
    final l = await linkOf(userIdOf(req));
    return jsonResponse({'url': l == null ? null : '${publicBase(d, req)}/acompanhar/${l['token']}'});
  });

  r.post('/guardian/link', (Request req) async {
    final userId = userIdOf(req);
    var l = await linkOf(userId);
    l ??= await d.db.one(
      'INSERT INTO guardian_links (user_id, token) VALUES (CAST(@u AS uuid), @t) RETURNING token, created_at',
      {'u': userId, 't': _newToken()},
    );
    await d.audit.log(userId, 'acompanhamento_link_criado', approved: true, source: 'servidor');
    return jsonResponse({'url': '${publicBase(d, req)}/acompanhar/${l!['token']}'}, status: 201);
  });

  /// Desfaz o link: quem tinha o endereço antigo perde o acesso na hora.
  r.delete('/guardian/link', (Request req) async {
    await d.db.query('DELETE FROM guardian_links WHERE user_id = CAST(@u AS uuid)', {'u': userIdOf(req)});
    await d.audit.log(userIdOf(req), 'acompanhamento_link_removido', approved: true, source: 'servidor');
    return jsonResponse({'ok': true});
  });

  /// "Estou passando mal" foi tocado: aparece na hora para o responsável.
  r.post('/emergency/alert', (Request req) async {
    final b = await readJson(req);
    final symptoms = (b['symptoms'] as List? ?? const []).map((e) => '$e').take(10).toList();
    await d.db.query(
      'INSERT INTO help_alerts (user_id, symptoms, lat, lng) VALUES (CAST(@u AS uuid), CAST(@s AS jsonb), @lat, @lng)',
      {
        'u': userIdOf(req),
        's': jsonEncode(symptoms),
        'lat': (b['lat'] as num?)?.toDouble(),
        'lng': (b['lng'] as num?)?.toDouble(),
      },
    );
    return jsonResponse({'ok': true}, status: 201);
  });

  Future<Map<String, dynamic>> status(String token) async {
    final link = await d.db.one('SELECT user_id FROM guardian_links WHERE token = @t', {'t': token});
    if (link == null) throw ApiError(404, 'Este link de acompanhamento não existe mais.');
    final userId = '${link['user_id']}';
    final user = (await d.users.byId(userId))!;
    final city = cityById(user['city_id'] as String?);
    final persona = Persona.fromName(user['persona'] as String?);

    final local = city.localWallClock(DateTime.now());
    final startUtc = DateTime.utc(local.year, local.month, local.day).subtract(city.utcOffset);
    final logs = await d.hydration.since(userId, startUtc);
    final water = logs.fold<int>(0, (a, l) => a + (l['amount_ml'] as int));

    // Meta de água: a mesma conta do app, com o calor de agora no centro da cidade.
    var goal = hydrationGoalMl(persona, RiskLevel.alto);
    try {
      final w = await d.weather.fetch(city.center.lat, city.center.lng);
      goal = const RiskEngine()
          .assess(w.current.withTime(local), UserContext(persona: persona, waterMlToday: water))
          .waterGoalMl;
    } catch (_) {}
    final expected = expectedWaterByNow(goal, local);

    final alerts = await d.db.query(
      '''SELECT symptoms, lat, lng, created_at FROM help_alerts
         WHERE user_id = CAST(@u AS uuid) AND created_at > now() - interval '24 hours'
         ORDER BY created_at DESC LIMIT 10''',
      {'u': userId},
    );
    final seen = await d.db.one(
      'SELECT max(created_at) AS at FROM audit_logs WHERE user_id = CAST(@u AS uuid)',
      {'u': userId},
    );
    String? iso(Object? v) => v is DateTime ? v.toUtc().toIso8601String() : null;
    return {
      'name': (user['name'] as String?)?.isNotEmpty == true ? user['name'] : 'Seu familiar',
      'waterMl': water,
      'goalMl': goal,
      'expectedMl': expected,
      'lastWaterAt': logs.isEmpty ? null : iso(logs.last['logged_at']),
      'lastSeenAt': iso(seen?['at']),
      'alerts': [
        for (final a in alerts)
          {
            'at': iso(a['created_at']),
            'symptoms': a['symptoms'],
            if (a['lat'] != null) 'mapsUrl': 'https://maps.google.com/?q=${a['lat']},${a['lng']}',
          },
      ],
    };
  }

  r.get('/acompanhar/<token>/status', (Request req, String token) async => jsonResponse(await status(token)));

  r.get('/acompanhar/<token>', (Request req, String token) async {
    await status(token); // link inválido já responde 404 aqui
    return Response.ok(_page, headers: {
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'no-store',
      'referrer-policy': 'no-referrer',
      'x-robots-tag': 'noindex',
    });
  });
}

/// Página do responsável: atualiza sozinha a cada 30 s e, com a aba aberta,
/// toca um alerta quando chega um novo pedido de ajuda.
const _page = r'''<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Acompanhamento ThermoGuia</title>
<style>
:root{--bg:#F3F6F9;--card:#fff;--ink:#13212E;--muted:#5C6B78;--green:#178A6E;--warn:#C79A1E;--danger:#A8231F;--line:#DDE5EC}
@media (prefers-color-scheme:dark){:root{--bg:#0F1A24;--card:#172633;--ink:#EEF3F7;--muted:#9FB0BF;--line:#26394A}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.45 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
main{max-width:520px;margin:0 auto;padding:20px 16px 40px}
h1{font-size:22px;margin:4px 0 2px}.sub{color:var(--muted);margin:0 0 18px}
.card{background:var(--card);border:1px solid var(--line);border-radius:18px;padding:18px;margin-bottom:14px}
.label{color:var(--muted);font-size:14px}.big{font-size:34px;font-weight:700;margin:2px 0}
.bar{height:12px;border-radius:8px;background:var(--line);overflow:hidden;margin:10px 0 8px}
.bar>i{display:block;height:100%;background:linear-gradient(90deg,#58C995,#178A6E)}
.ok{color:var(--green);font-weight:600}.low{color:var(--warn);font-weight:600}
.alert{border-color:var(--danger);background:color-mix(in srgb,var(--danger) 10%,var(--card))}
.alert h2{color:var(--danger);font-size:18px;margin:0 0 6px}
a{color:var(--green)}.foot{color:var(--muted);font-size:13px;text-align:center}
button{font:inherit;border:0;border-radius:12px;padding:12px 16px;background:var(--green);color:#fff;width:100%;margin-top:6px}
</style>
</head>
<body>
<main>
<p class="label">ThermoGuia · acompanhamento</p>
<h1 id="name">Carregando…</h1>
<p class="sub" id="seen"></p>
<div id="alerts"></div>
<div class="card">
  <div class="label">Água hoje</div>
  <div class="big" id="water">–</div>
  <div class="bar"><i id="bar" style="width:0"></i></div>
  <div id="pace"></div>
  <div class="label" id="lastWater"></div>
</div>
<div class="card" id="notifyCard" hidden>
  Quer ser avisado por aqui quando houver um pedido de ajuda? Deixe esta página aberta.
  <button id="notify">Ativar alertas nesta página</button>
</div>
<p class="foot">Atualiza sozinho a cada 30 segundos. Em uma emergência, ligue 192 (SAMU).</p>
</main>
<script>
const base = location.pathname.replace(/\/$/, '');
let lastAlert = null;
const fmt = iso => iso ? new Date(iso).toLocaleTimeString('pt-BR', {hour:'2-digit', minute:'2-digit'}) : '';
const ago = iso => { if (!iso) return 'sem uso registrado hoje'; const m = Math.round((Date.now() - new Date(iso)) / 60000);
  return m < 2 ? 'usou o app agora há pouco' : m < 60 ? `usou o app há ${m} min` : `usou o app às ${fmt(iso)}`; };
const sym = {tontura:'tontura', dor_cabeca:'dor de cabeça forte', nausea:'enjoo', caibras:'cãibras', pele_quente:'pele quente e seca', confusao:'confusão', desmaio:'desmaio'};
function beep(){ try{ const c = new AudioContext(), o = c.createOscillator(); o.frequency.value = 880; o.connect(c.destination); o.start(); setTimeout(()=>o.stop(), 600);}catch(e){} }
async function load(){
  try{
    const r = await fetch(base + '/status', {cache:'no-store'});
    if (!r.ok){ document.getElementById('name').textContent = 'Link de acompanhamento desativado'; return; }
    const s = await r.json();
    document.getElementById('name').textContent = s.name;
    document.getElementById('seen').textContent = ago(s.lastSeenAt);
    document.getElementById('water').textContent = `${(s.waterMl/1000).toFixed(1).replace('.', ',')} de ${(s.goalMl/1000).toFixed(1).replace('.', ',')} L`;
    document.getElementById('bar').style.width = Math.min(100, s.waterMl / s.goalMl * 100) + '%';
    const behind = s.expectedMl - s.waterMl;
    document.getElementById('pace').innerHTML = behind > 250
      ? `<span class="low">Abaixo do esperado para este horário (faltam ${behind} ml)</span>`
      : `<span class="ok">Bebendo água como o app orienta</span>`;
    document.getElementById('lastWater').textContent = s.lastWaterAt ? `Último copo às ${fmt(s.lastWaterAt)}` : 'Nenhum copo registrado hoje';
    const box = document.getElementById('alerts');
    box.innerHTML = s.alerts.map(a => `<div class="card alert"><h2>Pediu ajuda às ${fmt(a.at)}</h2>
      ${a.symptoms.length ? 'Sinais: ' + a.symptoms.map(x => sym[x] || x).join(', ') + '.<br>' : ''}
      ${a.mapsUrl ? `<a href="${a.mapsUrl}" target="_blank" rel="noopener">Ver localização no mapa</a>` : 'Ligue para conferir se está tudo bem.'}</div>`).join('');
    const newest = s.alerts[0] && s.alerts[0].at;
    if (newest && lastAlert !== null && newest !== lastAlert){
      beep(); if (navigator.vibrate) navigator.vibrate([400,200,400]);
      if (window.Notification && Notification.permission === 'granted') new Notification(`${s.name} pediu ajuda`, {body:'Abra o ThermoGuia para ver os detalhes.'});
    }
    lastAlert = newest || '';
  }catch(e){}
}
if (window.Notification && Notification.permission === 'default'){
  document.getElementById('notifyCard').hidden = false;
  document.getElementById('notify').onclick = () => Notification.requestPermission().then(() => document.getElementById('notifyCard').hidden = true);
}
load(); setInterval(load, 30000);
</script>
</body>
</html>''';
