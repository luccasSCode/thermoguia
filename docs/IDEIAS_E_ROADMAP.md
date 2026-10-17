# Ideias, monetização e roadmap

## Já implementado além da proposta original

| Ideia | Onde está | Por que importa |
|---|---|---|
| **Pontos de refresco** (bebedouros, shoppings climatizados, farmácias, bibliotecas, parques) | Mapa, ícones azuis | Saber onde parar é tão importante quanto o caminho |
| **Relatos da comunidade** (toque longo no mapa) | Mapa + cálculo das rotas | Corrige as falhas do mapa de árvores e cria engajamento |
| **Desvios por áreas verdes** | Motor de rotas | O OSRM só oferece rotas "normais"; forçamos passagens por praças e matas |
| **Sombra conforme a hora de passagem** ("Agora", "Em 30 min"...) | Mapa | A mesma rua tem sombra às 16h e sol às 12h |
| **Melhores horários e período a evitar** | Tela inicial | Ajuda a planejar, não só a reagir |
| **"Por que 41°?"** | Tela inicial | Transparência: cada parcela do cálculo é mostrada |
| **"O que o ThermoGuia aprendeu sobre você"** | Perfil | O usuário vê e pode reiniciar o aprendizado |
| **Horários habituais** | Tela inicial e perfil | Base para alertas antecipados |
| **Conta sem e-mail** | Onboarding | Começa a usar em segundos; adiciona e-mail depois sem perder dados |
| **Exclusão de conta (LGPD)** | Perfil | Exigência legal e das lojas |
| **Funciona sem internet** | Risco, água e logs | Risco calculado no aparelho; logs sincronizam depois |
| **Tema escuro** | Automático | Uso à noite (o Modo Sol Forte tem prioridade de dia) |

## Próximas ideias, por impacto

### Muito relevantes para Manaus

1. **Qualidade do ar na época das queimadas.** Entre agosto e novembro a fumaça cobre a
   cidade. A API de qualidade do ar do Open-Meteo traz PM2,5 gratuitamente; somar ao risco
   e recomendar máscara PFF2 quando necessário.
2. **Alerta de chuva como alívio.** "Chuva em 20 minutos: se puder, espere para sair." A
   chuva derruba a temperatura em Manaus de forma marcante.
3. **Paradas de ônibus com cobertura.** Usar os dados de transporte da cidade para indicar
   paradas cobertas e sugerir esperar na sombra.
4. **Mapa de copa por satélite (NDVI Sentinel-2).** Medir a cobertura verde real, em vez de
   depender das árvores cadastradas no OpenStreetMap.
5. **Sombra 3D de prédios.** Com a altura dos edifícios, calcular a sombra exata de cada
   lado da rua conforme a posição do sol.

### Para cada público

- **Entregadores:** rotas com várias paradas, pausas sugeridas entre corridas e modo
  "mãos livres" por voz.
- **Idosos:** acompanhamento familiar com consentimento ("sua mãe não registrou água desde
  as 10h"), letras grandes permanentes e ligação simplificada para um familiar.
- **Ciclistas:** considerar subidas no esforço e indicar pontos de água no trajeto.
- **Vendedores ambulantes:** "melhor lado da rua" para montar a banca conforme a hora.

### Produto

- **Widget na tela inicial** do celular com o risco atual.
- **Relógio inteligente:** frequência cardíaca e temperatura da pele para detectar estresse
  térmico antes do mal-estar.
- **Selo "Guardião da Sombra"** para quem mais relata, com ranking por bairro.
- **Estabelecimentos parceiros "Ponto Amigo do Calor"**, que oferecem água e sombra.

## Clube H2O (engajamento)

Gotas ganhas com hábitos que protegem do calor (abrir o app, Rotas Frescas, relatos e
**comprovações por foto na Comunidade**) e trocadas por descontos em parceiros. A água só rende
gotas comprovada com duas fotos (antes e depois), verificadas por IA; tocar no botão de ml serve só
para o controle pessoal. Níveis: Semente, Broto, Muda, Árvore e Floresta.

| Plano | Benefício |
|---|---|
| Grátis | Ganha gotas e troca por descontos de até 10%, com até 2 trocas por mês |
| ThermoGuia+ | Gotas em dobro, trocas ilimitadas e cupons exclusivos de até 25% |
| Empresas | Clube da equipe, com recompensas pagas pela empresa |

As ofertas atuais são **de exemplo** (`demo = true`): aparecem com a etiqueta "Exemplo" e geram
cupons `EXEMPLO-...`, que não valem em lojas. Para cadastrar um parceiro real, depois de fechar o
acordo com o estabelecimento:

```sql
INSERT INTO partner_offers (id, partner, category, title, details, neighborhood, cost, plus_only, demo)
VALUES ('acai-do-joao-10', 'Açaí do João', 'acai', '10% no açaí de 500 ml', 'Seg a sex.', 'Centro', 80, false, false);
-- e, para tirar os exemplos do ar:
UPDATE partner_offers SET active = false WHERE demo;
```

Cupons reais saem com o prefixo `TG-`. A validação no caixa (o lojista confirmar o código) é o
próximo passo: um painel simples para parceiros ou uma rota `POST /partners/coupons/{code}/use`.

### Notificações programadas

Agendadas no aparelho para os próximos 7 dias e refeitas a cada abertura do app, com a previsão
mais recente. Nunca entre 19h30 e 6h30; no máximo 4 por dia; cada uma pode ser desligada no Perfil.

| Horário | Notificação | Quando |
|---|---|---|
| 6h30 | Resumo da manhã: pico do dia e melhor horário | Todo dia (após 3 dias sem abrir: convite para voltar) |
| 10h30 | Aviso antes do pico de calor | Só em dias com sensação de 38°C ou mais |
| 16h30 | Janela fresca do fim da tarde | Quando o fim da tarde fica 4°C ou mais abaixo do pico |
| 19h30 | Clube H2O: sequência e gotas do dia | Se a pessoa ainda não abriu o app no dia |
| Dom 10h | Resumo da semana: trajetos, gotas e descontos | Todo domingo |

## Monetização

| Fonte | Modelo | Observação |
|---|---|---|
| **ThermoGuia+** | Assinatura (sugestão: R$ 9,90/mês ou R$ 79,90/ano) | Modelo "grátis limitado × Plus ilimitado": smartwatch (1 relógio × ilimitados, com navegação no pulso), assistente (15/dia × ilimitado), Saúde, alertas de trajetos, família, rotas com paradas, mapas offline, lugares salvos, agenda, widgets e histórico |
| **ThermoGuia Empresas** | Por funcionário/mês | Painel para empresas de entrega, correios e obras; apoio à gestão de exposição ao calor prevista nas normas regulamentadoras de segurança do trabalho |
| **Parceiros** | Destaque pago no mapa | Farmácias, lojas e shoppings como pontos de refresco |
| **Poder público** | Licença de dados agregados e anônimos | "Onde plantar a próxima árvore": trechos mais usados e mais expostos ao sol |

Princípio dos planos: **o que protege a saúde é sempre grátis e sem limite** (risco,
Rotas Frescas com navegação por voz, lembretes de água, botão de emergência, Modo Sol
Forte). O ThermoGuia+ amplia conveniência e personalização.

A estrutura já está pronta: o campo `plan` no usuário, o limite diário do assistente por
plano e o catálogo `/plans/compare` vindo do servidor (preços, limites e recursos mudam
sem nova versão do app; `soon: true` marca o que ainda será lançado). Para
cobrar, integrar Google Play Billing e App Store (ou um serviço como RevenueCat) e atualizar
`users.plan` por webhook.

## Roadmap

**Fase 1, MVP (este código).** Risco personalizado, Rotas Frescas, hidratação, Modo Sol
Forte, assistente, emergência com consentimento e auditoria.

**Fase 2, piloto.** Testar com estudantes da UNIESBAM e um grupo de entregadores no Centro.
Medir: minutos de sol evitados por trajeto, adesão aos lembretes de água e precisão do
risco comparada ao feedback. Ajustar limiares e pesos com esses dados.

**Fase 3, lançamento.** Infraestrutura própria de mapas, HTTPS, política de privacidade,
publicação na Google Play e App Store, ThermoGuia+.

**Fase 4, expansão.** Cidades com calor e umidade parecidos: Belém, Porto Velho, Rio Branco,
Macapá, Boa Vista, Cuiabá, Teresina e São Luís. Cada uma exige só uma entrada em
`backend/lib/cities.dart`.

## Divisão de responsabilidades no código

| Integrante | Pastas principais |
|---|---|
| Luana (regras do agente) | `packages/thermo_core/lib/src/` (risco, hidratação, aprendizado) |
| Lucas (APIs, dados, logs) | `backend/lib/services/`, `backend/lib/data/`, `app/lib/core/services/audit_logger.dart` |
| Flávia (Flutter, Modo Sol Forte) | `app/lib/features/`, `app/lib/core/theme/`, `app/lib/features/adaptive/sun_mode.dart` |
| Angel (arquitetura, banco, contexto) | `backend/lib/data/schema.dart`, `backend/lib/app_deps.dart`, `climate_providers.dart` |
| Sara (UX/UI, rotas, testes, aprovações) | `app/lib/features/routes/`, `app/lib/features/safety/`, `test/` |
