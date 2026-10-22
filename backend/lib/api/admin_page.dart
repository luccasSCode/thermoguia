/// Página da fila de revisão (GET /admin/revisao). A página em si não tem
/// dados: ela pede a ADMIN_TOKEN e chama as rotas /admin com o cabeçalho
/// X-Admin-Token. A chave fica só na aba (sessionStorage).
const adminReviewPage = r'''<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Revisão da Comunidade</title>
<style>
:root{--bg:#F3F6F9;--card:#fff;--ink:#13212E;--muted:#5C6B78;--green:#178A6E;--danger:#A8231F;--warn:#C79A1E;--line:#DDE5EC}
@media (prefers-color-scheme:dark){:root{--bg:#0F1A24;--card:#172633;--ink:#EEF3F7;--muted:#9FB0BF;--line:#26394A}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:16px/1.45 system-ui,-apple-system,Segoe UI,Roboto,sans-serif}
main{max-width:760px;margin:0 auto;padding:20px 16px 48px}
h1{font-size:22px;margin:4px 0}.sub{color:var(--muted);margin:0 0 16px}
.card{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:16px;margin-bottom:14px}
.row{display:flex;gap:8px;flex-wrap:wrap;align-items:center}
input,select,button{font:inherit;border-radius:10px;border:1px solid var(--line);padding:9px 12px;background:var(--card);color:var(--ink)}
input,select{flex:1;min-width:0}
button{cursor:pointer;font-weight:600}
.ok{background:var(--green);border-color:var(--green);color:#fff}
.no{background:var(--danger);border-color:var(--danger);color:#fff}
.imgs{display:flex;gap:8px;margin:10px 0;flex-wrap:wrap}
.imgs figure{margin:0;flex:1;min-width:200px}
.imgs img{width:100%;max-height:420px;object-fit:contain;border-radius:12px;background:#0002}
.imgs figcaption{color:var(--muted);font-size:13px}
.tag{display:inline-block;font-size:13px;padding:2px 8px;border-radius:20px;background:var(--line);margin-right:4px}
.tag.warn{background:var(--warn);color:#fff}.tag.bad{background:var(--danger);color:#fff}
.muted{color:var(--muted);font-size:14px}
.msg{padding:10px 12px;border-radius:10px;background:var(--line);margin-bottom:14px}
</style>
</head>
<body>
<main>
<h1>Revisão da Comunidade</h1>
<p class="sub">Fotos que a verificação automática não conseguiu decidir e publicações denunciadas.
Recuse tudo que tiver conteúdo sexual, racista, homofóbico, nazista, propaganda política ou outro conteúdo impróprio.</p>

<div class="card" id="login">
  <div class="row">
    <input id="token" type="password" placeholder="ADMIN_TOKEN" autocomplete="off">
    <button class="ok" id="enter">Entrar</button>
  </div>
</div>
<div id="status"></div>
<div id="list"></div>
</main>
<script>
const CATS = {agua:'Hidratação',bone:'Boné ou chapéu',protetor:'Protetor solar',guarda_sol:'Guarda-sol',oculos:'Óculos de sol',mascara:'Máscara na fumaça',sombra:'Caminho pela sombra',app_aberto:'App aberto hoje'};
const REASONS = [
  'A equipe não conseguiu confirmar pela foto.',
  'Fotos com nudez ou conteúdo sexual não são permitidas na Comunidade.',
  'Conteúdo racista não é permitido na Comunidade.',
  'Conteúdo homofóbico ou transfóbico não é permitido na Comunidade.',
  'Símbolos ou apologia ao nazismo e a grupos extremistas não são permitidos.',
  'Propaganda política ou de partidos não é permitida na Comunidade.',
  'Conteúdo com ódio, preconceito ou ataque a alguém não é permitido na Comunidade.',
  'Conteúdo com violência ou armas não é permitido na Comunidade.',
  'A foto mostra dados pessoais (documento, cartão ou placa). Tire outra sem eles.',
  'A foto parece editada ou tirada da internet.',
];
const $ = (id) => document.getElementById(id);
let token = sessionStorage.getItem('adm') || '';
$('token').value = token;

function el(tag, attrs, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (k === 'class') e.className = v; else if (k.startsWith('on')) e[k] = v; else e.setAttribute(k, v);
  }
  for (const k of kids) if (k != null) e.append(k);
  return e;
}
function say(text) { $('status').replaceChildren(text ? el('div', {class: 'msg'}, text) : ''); }

async function api(path, body) {
  const res = await fetch(path, {
    method: body ? 'POST' : 'GET',
    headers: Object.assign({'x-admin-token': token}, body ? {'content-type': 'application/json'} : {}),
    body: body ? JSON.stringify(body) : undefined,
  });
  if (res.status === 404 && path === 'queue') throw new Error('Chave inválida, ou ADMIN_TOKEN não configurado no servidor.');
  if (!res.ok) {
    let msg = 'Erro ' + res.status;
    try { msg = (await res.json()).error || msg; } catch (_) {}
    throw new Error(msg);
  }
  return res;
}

async function image(id, kind) {
  const res = await api('posts/' + id + '/image/' + kind);
  return URL.createObjectURL(await res.blob());
}

async function decide(p, approve, reason, ml) {
  try {
    const body = {approve};
    if (reason) body.reason = reason;
    if (ml) body.ml = Number(ml);
    await api('posts/' + p.id + '/decide', body);
    say(approve ? 'Aprovada.' : 'Recusada.');
    load();
  } catch (e) { say(e.message); }
}

async function restore(p) {
  try { await api('posts/' + p.id + '/restore', {}); say('Publicação mantida.'); load(); }
  catch (e) { say(e.message); }
}

function card(p) {
  const v = p.verdict || {};
  const tags = el('div', {},
    el('span', {class: 'tag'}, CATS[p.category] || p.category),
    p.status === 'revisao' ? el('span', {class: 'tag warn'}, 'Em revisão') : null,
    p.hidden ? el('span', {class: 'tag bad'}, 'Oculta por denúncias (' + p.reports + ')') : null,
    v.violacao && v.violacao !== 'nenhuma' ? el('span', {class: 'tag bad'}, 'IA: ' + v.violacao) : null,
  );
  const imgs = el('div', {class: 'imgs'});
  for (const kind of p.images || []) {
    const fig = el('figure', {}, el('figcaption', {}, kind));
    imgs.append(fig);
    image(p.id, kind).then((src) => fig.prepend(el('img', {src, alt: 'Foto ' + kind}))).catch(() => fig.append(' (não carregou)'));
  }
  const reason = el('select', {}, ...REASONS.map((r) => el('option', {value: r}, r)));
  const ml = p.category === 'agua' ? el('input', {type: 'number', min: '100', step: '50', placeholder: 'ml comprovados', value: p.verified_ml || ''}) : null;
  const actions = el('div', {class: 'row'},
    ml,
    el('button', {class: 'ok', onclick: () => decide(p, true, null, ml && ml.value)}, 'Aprovar'),
    p.hidden && p.status === 'aprovado' ? el('button', {onclick: () => restore(p)}, 'Manter publicada') : null,
  );
  const reject = el('div', {class: 'row', style: 'margin-top:8px'},
    reason,
    el('button', {class: 'no', onclick: () => decide(p, false, reason.value)}, 'Recusar'),
  );
  return el('div', {class: 'card'},
    tags,
    el('p', {}, p.caption ? '“' + p.caption + '”' : el('span', {class: 'muted'}, 'Sem legenda')),
    imgs,
    v.descricao ? el('p', {class: 'muted'}, 'O que a IA viu: ' + v.descricao) : null,
    p.reason ? el('p', {class: 'muted'}, 'Motivo atual: ' + p.reason) : null,
    el('p', {class: 'muted'}, 'Enviada em ' + new Date(p.created_at).toLocaleString('pt-BR')),
    actions,
    reject,
  );
}

async function load() {
  if (!token) return;
  try {
    const rows = await (await api('queue')).json();
    $('login').style.display = 'none';
    $('list').replaceChildren(...(rows.length ? rows.map(card) : [el('div', {class: 'card'}, 'Nada para revisar agora.')]));
  } catch (e) {
    $('login').style.display = '';
    say(e.message);
  }
}

$('enter').onclick = () => { token = $('token').value.trim(); sessionStorage.setItem('adm', token); say(''); load(); };
$('token').onkeydown = (e) => { if (e.key === 'Enter') $('enter').click(); };
load();
</script>
</body>
</html>
''';
