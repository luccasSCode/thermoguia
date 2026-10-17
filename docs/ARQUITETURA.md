# Arquitetura

## Visão geral

```
┌──────────────── App Flutter ────────────────┐        ┌──────────── API (Dart/shelf) ────────────┐
│ presentation  telas, widgets, controllers   │  HTTPS │ api/        rotas HTTP finas              │
│ (Riverpod)    ─────────────────────────────  │ ─────► │ services/   clima, rotas, verde, IA       │
│ data          repositórios, cache local     │  JWT   │ data/       repositórios SQL              │
│ domain        thermo_core (compartilhado)   │        │ domain      thermo_core (compartilhado)   │
└─────────────────────────────────────────────┘        └───────────────┬───────────────────────────┘
                                                                        │
                       ┌────────────────────┬──────────────────┬────────┴─────────┬────────────────┐
                       │ PostgreSQL         │ Open-Meteo       │ OpenStreetMap     │ Claude (IA)    │
                       │ usuários, logs,    │ temperatura, UV, │ Overpass, OSRM,   │ assistente e   │
                       │ trajetos, relatos  │ umidade, chuva   │ Nominatim         │ resumo diário  │
                       └────────────────────┴──────────────────┴───────────────────┴────────────────┘
```

## Clean Architecture na prática

A camada de domínio é o pacote `packages/thermo_core`, em Dart puro, sem Flutter e sem
servidor. Ele contém o "cérebro" do agente:

| Arquivo | Responsabilidade |
|---|---|
| `heat_index.dart` | Índice de calor oficial (NOAA, regressão de Rothfusz) |
| `risk_engine.dart` | Risco personalizado e recomendações, com parcelas explicáveis |
| `hydration.dart` | Meta diária de água e intervalo de lembretes |
| `best_windows.dart` | Melhores e piores horários para sair nas próximas 24 h |
| `adaptive_profile.dart` | Aprendizado: sensibilidade, preferência por sombra, horários habituais |
| `sun_position.dart` | Altura e direção do sol (sombra de prédios e árvores) |

Por ser compartilhado, o risco é calculado **no aparelho** (responde na hora e funciona
sem internet) e **no servidor** (para o assistente de IA), sempre com as mesmas regras.

No app, cada funcionalidade em `lib/features/` separa `data` (repositórios e cache) de
`presentation` (telas e controllers). As telas nunca chamam a API diretamente.

## O agente: observar, contextualizar, recomendar, adaptar

1. **Observar.** Clima do Open-Meteo a cada 10 min para a posição do GPS; previsão horária.
2. **Contextualizar.** `UserContext` junta perfil (pedestre, entregador...), minutos ao sol
   hoje, água bebida e a sensibilidade aprendida.
3. **Recomendar.** `RiskEngine` calcula o índice efetivo:

   ```
   índice efetivo = índice de calor
                  + radiação UV (até +3 °C, reduzida por nuvens)
                  + tempo ao sol hoje (até +4 °C)
                  + esforço do perfil (MET)
                  + déficit de água (até +2 °C)
                  + faixa etária (idosos +1,5 °C)
                  + sensibilidade aprendida (−3 a +3 °C)
                  − vento (−1 °C acima de 15 km/h)
   ```
   Cada parcela aparece para o usuário em "Por que 41°?". Os níveis (27/32/38/45 °C) foram
   calibrados para Manaus, onde o índice de calor passa de 38 °C com frequência.
4. **Adaptar.**
   - *Sensibilidade:* após cada trajeto, "Como você se sentiu?". A taxa de aprendizado começa
     alta e estabiliza (`max(0,15; 1/(n+2))`). Respostas que contrariam a previsão pesam mais.
   - *Preferência por sombra:* se a pessoa escolhe uma rota mais longa e sombreada, o peso da
     sombra sobe; se escolhe sempre a mais curta, desce. Esse peso ordena as próximas rotas.
   - *Horários habituais:* histograma de saídas; vira aviso antecipado.
   - *Interface:* o Modo Sol Forte liga sozinho com UV ≥ 7 ou quando a pessoa está na rua.

## Rotas Frescas

1. OSRM retorna a rota mais rápida e alternativas (a pé ou de bicicleta).
2. O índice verde gera **desvios por áreas verdes**: escolhe até 2 células arborizadas no
   corredor entre origem e destino e pede rotas passando por elas.
3. Cada rota é reamostrada a cada 20 m. Em cada ponto:
   `sombra = copa + sombra_urbana × (1 − copa) ± relatos da comunidade`.
   A sombra urbana depende da altura do sol no **horário de passagem**: sol baixo (< 20°)
   projeta sombras longas de prédios; ao meio-dia, só a copa das árvores conta.
4. Minutos ao sol = duração × (1 − sombra) × fator de nuvens.
5. Custo = (1 − w)·duração relativa + w·(1 − sombra)·1,5 + w·exposição relativa·0,5,
   onde *w* é a preferência por sombra aprendida.

O índice verde vem do OpenStreetMap (árvores, fileiras de árvores, parques, matas),
rasterizado numa grade de ~45 m. A cobertura de árvores no OSM de Manaus é incompleta; por
isso os relatos da comunidade entram no cálculo, e o roadmap prevê NDVI do Sentinel-2.

## Ações sensíveis e auditoria

- Ligar para o SAMU e enviar localização a contatos **sempre** passam por um diálogo de
  confirmação. A mensagem é preparada pelo servidor, mas quem envia é o próprio usuário
  (WhatsApp/SMS), que continua no controle.
- Toda decisão, aprovada ou recusada, vai para `audit_logs`. O app grava primeiro no
  aparelho e sincroniza depois, então nada se perde sem internet.
- `audit_logs` é **somente inclusão**: um gatilho no PostgreSQL impede UPDATE e DELETE. A
  única exceção é anonimizar (`user_id → NULL`) quando o usuário exclui a conta (LGPD).
- O usuário vê tudo em Perfil → Histórico de decisões.

## Expansão para outras cidades

Adicione uma entrada em `backend/lib/cities.dart` (centro, limites, fuso). O índice verde e
os pontos de refresco são gerados automaticamente para o novo recorte. As rotas, a busca e
os relatos já são limitados à cidade do usuário (`users.city_id`).

## Serviços externos: desenvolvimento x produção

| Serviço | Desenvolvimento | Produção recomendada |
|---|---|---|
| Clima | Open-Meteo gratuito | Open-Meteo comercial (pago, com SLA) |
| Rotas | routing.openstreetmap.de | OSRM próprio com o recorte do Amazonas (Docker) |
| Busca | nominatim.openstreetmap.org | Nominatim próprio ou provedor contratado |
| Mapa (tiles) | tile.openstreetmap.org | MapTiler, Stadia Maps ou servidor próprio |
| IA | Claude, modelo leve | Mesmo; ajustar limite diário por plano |

Os servidores públicos do OpenStreetMap têm políticas de uso justo e não podem receber o
tráfego de um app publicado.

## Escalando

- A API não guarda estado entre requisições além de caches; pode rodar em várias réplicas.
- Caches em memória (clima, busca, resumo) podem migrar para Redis.
- Para muitas cidades, mover o índice verde para PostGIS (`ST_DWithin`).
