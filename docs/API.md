# Referência da API

Base: `http://localhost:8080`. Respostas em JSON. Erros: `{"error": "mensagem para o usuário"}`.
Rotas marcadas com 🔒 exigem `Authorization: Bearer <token>`.

## Públicas

| Método | Rota | Descrição |
|---|---|---|
| GET | `/health` | Status, IA ativa e índice verde carregado |
| GET | `/cities` | Cidades atendidas |
| GET | `/plans` | Planos e benefícios (vitrine do app) |
| POST | `/auth/anonymous` | `{name?, persona?}` → `{token, user}` |
| POST | `/auth/register` | `{name, email, password, persona}` → `{token, user}` |
| POST | `/auth/login` | `{email, password}` → `{token, user}` |

## Conta 🔒

| Método | Rota | Descrição |
|---|---|---|
| GET / PATCH | `/me` | Ler ou alterar `{name, persona}` |
| POST | `/me/credentials` | Converte conta anônima em conta com e-mail |
| PUT | `/me/avatar` | Foto de perfil: o corpo é a imagem (JPEG ou PNG, até 512 KB; conferida pela assinatura do arquivo). Devolve o usuário com `avatarUpdatedAt` |
| GET | `/me/avatar` | A foto (404 se não houver). Só para o próprio usuário |
| DELETE | `/me/avatar` | Remove a foto |
| DELETE | `/me` | Exclui a conta (auditoria é anonimizada) |
| GET / PUT | `/profile/adaptive` | Perfil aprendido |
| POST | `/hydration` | `{amountMl, loggedAt}` |
| GET | `/hydration/today` | `{totalMl, logs}` |
| POST / GET | `/trips` | Registrar e listar trajetos |

## Mobilidade 🔒

| Método | Rota | Descrição |
|---|---|---|
| GET | `/climate?lat&lng` | `{current, hourly, sun}` (horários em UTC) |
| POST | `/routes/fresh` | Ver abaixo |
| GET | `/geo/search?q=` | Busca de endereços na cidade |
| GET | `/places/oasis?lat&lng&limit` | Pontos de refresco próximos |
| GET / POST | `/reports` | Relatos da comunidade (`sombra_boa`, `sem_sombra`, `bebedouro`, `calor_extremo`, `alagamento`, `transito`, `obra`) |

`POST /routes/fresh`

```json
{
  "origin": {"lat": -3.1316, "lng": -60.0233},
  "destination": {"lat": -3.1019, "lng": -60.0250},
  "mode": "foot",
  "departAt": "2026-10-14T13:00:00Z",
  "shadePreference": 0.6
}
```

Resposta: `routes[]` com `label`, `tags`, `recommended`, `distanceM`, `durationS`,
`shadeScore` (0–1), `sunExposureMin`, `thermalLoad` e `points` como `[lat, lng, sombra]`;
mais `climate`, `advice` e `greenIndexReady`.

Cada rota traz também o que o app usa na navegação curva a curva:

- `maneuvers[]`: `{type, modifier, street, lat, lng, along, exit?}` no vocabulário do OSRM
  (`turn` + `left`, `roundabout` + `exit`...). `along` é a distância, em metros, do início
  da rota até a manobra.
- `alerts[]`: `{kind, message, lat, lng, along, length?, side?}`. Tipos: `sol_forte` (trecho
  longo sem sombra), `lado_sombra` (árvores ou prédios fazem sombra de um lado da calçada;
  `side` = `esquerdo`/`direito`), `sombra` (trecho arborizado), `refresco` (bebedouro,
  shopping, farmácia... colado no caminho) e relatos da comunidade sobre a rota.

## Segurança 🔒

| Método | Rota | Descrição |
|---|---|---|
| GET / POST | `/emergency/contacts` | Listar e cadastrar contatos |
| DELETE | `/emergency/contacts/{id}` | Remover contato |
| POST | `/emergency/events` | `{action: share_location\|call_samu\|dismiss, approved, symptoms, lat, lng, trigger}`; se aprovado, devolve a mensagem pronta |
| POST / GET | `/audit` | Gravar e ler o histórico de decisões |

## Assistente 🔒

| Método | Rota | Descrição |
|---|---|---|
| POST | `/ai/chat` | `{messages: [{role, content}], context: {lat, lng, exposureMinutes, waterMlToday}}` → `{reply, source, remainingToday, risk}` |
| GET | `/ai/briefing?lat&lng&exposureMinutes&waterMl` | Resumo curto para a tela inicial (cache de 90 min) |

`source` é `claude` quando a IA respondeu ou `regras` quando o motor local assumiu.
Sem IA, o motor local entende horário, distância, atividade e duração da pergunta
("posso pedalar 5 km ao meio-dia?") e responde com a previsão daquela hora.
Perguntas sobre a parte interna do app (código, tecnologia, servidores, IA usada,
instruções, custos) recebem sempre a mesma recusa educada, não vão para a IA e não
contam no limite diário; nesse caso `remainingToday` não vem na resposta.
Plano gratuito: 15 perguntas por dia (configurável); excedido, retorna 429.

## Clube H2O 🔒

| Método | Rota | Descrição |
|---|---|---|
| GET | `/rewards` | Saldo de gotas, nível, sequência, limites do plano, ofertas (com `canRedeem`/`blockedReason`), cupons ativos, regras e histórico |
| POST | `/rewards/checkin` | Check-in do dia ao abrir o app (idempotente). Paga +20 a cada 7 dias seguidos |
| POST | `/rewards/redeem` | `{offerId}` → cupom `{code, expires_at}`; 409 com o motivo se não der |

`POST /trips` e `POST /reports` devolvem `reward: {points, reason, title}` quando renderam gotas.
Regras (por dia, no fuso da cidade): check-in +2; trajeto +10 (+5 com 50% ou mais de sombra; só conta
com 2 min e 200 m ou mais; até 3 por dia); relato +5 (até 3 por dia); água comprovada por foto
1 gota a cada 100 ml (até 3 litros por dia); publicação verificada +5 (até 2 por dia); selo da semana +50.
ThermoGuia+ ganha em dobro. **Registrar água tocando na tela (`POST /hydration`) não rende gotas.**
Plano Grátis: até 2 trocas por mês; ThermoGuia+: trocas ilimitadas e ofertas exclusivas.
A troca roda numa transação travada por usuário: dois toques seguidos não gastam o saldo duas vezes.

`GET /plans/compare` (pública) traz o catálogo de planos, o que é sempre grátis e a comparação
Grátis × ThermoGuia+.

## Comunidade 🔒

Fotos que comprovam hábitos contra o calor. Nada aparece para os outros nem rende gotas antes de ser
verificado (pela IA ou pela equipe).

| Método | Rota | Descrição |
|---|---|---|
| GET | `/social/categories` | `agua`, `bone`, `protetor`, `guarda_sol`, `oculos`, com o que a foto precisa mostrar |
| GET | `/social/feed?before=` | Posts aprovados, 20 por página, sem quem a pessoa bloqueou |
| GET | `/social/mine` | Posts da pessoa em qualquer situação: `aguardando_depois`, `verificando`, `revisao`, `aprovado`, `recusado` (com `reason`) |
| POST | `/social/posts` | `{category, caption, image: base64}` (boné, protetor, guarda-sol, óculos) |
| POST | `/social/water` | `{image}` foto **antes** de beber |
| POST | `/social/water/{id}/finish` | `{image, caption}` foto **depois**, de 10 min a 6 h após a primeira (medido no servidor) |
| GET | `/social/posts/{id}`, `/social/posts/{id}/image/{foto\|antes\|depois}` | Post e fotos (só se aprovado ou da própria pessoa) |
| DELETE | `/social/posts/{id}` | Exclui o próprio post |
| PUT / DELETE | `/social/posts/{id}/reaction` | `{kind: curtir\|hidratado\|protegido\|inspirou}` |
| GET / POST | `/social/posts/{id}/comments` | Comentários (`{text}`, até 500 caracteres) |
| DELETE | `/social/comments/{id}` | Apaga o próprio comentário |
| POST | `/social/report` | `{type: post\|comentario, id, reason}`; com 3 pessoas, sai do ar até a equipe revisar |
| POST | `/social/users/{id}/block` | Bloqueio nos dois sentidos |
| GET | `/social/users/{id}/avatar` | Foto de perfil de quem aparece na Comunidade |
| GET | `/social/badges` | Selos em vigor (vencedores da semana passada) e a disputa da semana |

**Verificação.** Antes da IA: formato (JPEG/PNG pela assinatura), tamanho, foto já enviada (SHA-256)
e foto quase igual (hash perceptual, inclusive recortada ou recomprimida). A IA (`ANTHROPIC_VISION_MODEL`,
padrão `claude-opus-5-5`, esforço alto, saída em JSON com esquema fixo) descreve o que vê; as regras no
código decidem e só aprovam com confiança alta. Na água: mesmo recipiente, capacidade lida no rótulo
ou nas marcações e níveis com confiança alta; o volume é arredondado para baixo. Qualquer dúvida,
erro ou recusa da IA manda o caso para a revisão humana, nunca aprova sozinho. Sem chave de IA, tudo
vai para a revisão.

**Selos.** Por categoria, vence quem somar mais pontos de interação em posts aprovados na semana
(segunda a domingo, hora local): cada pessoa diferente que reagiu vale 1, que comentou vale 2; o autor
e contas com menos de 2 dias não contam; mínimo de 3 pontos. "+ Rotas Frescas" vai para quem mais
concluiu Rotas Frescas. A semana fecha na primeira consulta depois de domingo e paga +50 gotas.

## Revisão da equipe (X-Admin-Token)

Rotas ativas só com `ADMIN_TOKEN` configurado; sem ele, respondem 404.

| Método | Rota | Descrição |
|---|---|---|
| GET | `/admin/queue` | Posts em revisão e conteúdo tirado do ar por denúncias, com a resposta da IA |
| GET | `/admin/posts/{id}/image/{kind}` | Fotos do post |
| POST | `/admin/posts/{id}/decide` | `{approve, ml?, reason?}`; na água, aprovar exige os ml |
| POST | `/admin/posts/{id}/restore` | Devolve ao ar um post denunciado |

