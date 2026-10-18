# ThermoGuia Manaus

Assistente inteligente e adaptativo de conforto térmico urbano. Mostra o risco de calor
onde você está, sugere **Rotas Frescas** (caminhos com mais sombra no horário em que você
vai passar), lembra de beber água e aprende com o seu uso.

Projeto do curso de Análise e Desenvolvimento de Sistemas, Centro Universitário UNIESBAM.

## Estrutura

```
thermoguia/
├── app/                    App Flutter (Android e iOS)
├── backend/                API em Dart (shelf + PostgreSQL)
├── packages/thermo_core/   Regras do agente, em Dart puro, usadas pelo app e pela API
├── docs/                   Arquitetura, API, ideias e roadmap
└── docker-compose.yml      Banco + API prontos para rodar
```

## Pré-requisitos

- Flutter 3.27 ou mais recente (inclui o Dart)
- Docker Desktop (para o banco e a API) ou PostgreSQL 14+ instalado
- Android Studio com um emulador, ou um celular com depuração USB

## 1. Subir o backend

```bash
cd backend
cp .env.example .env        # no Windows: copy .env.example .env
# Edite o .env: troque JWT_SECRET e, se quiser IA, preencha ANTHROPIC_API_KEY
cd ..
docker compose up --build
```

Teste: abra http://localhost:8080/health. Deve aparecer `"status":"ok"`.

Se a porta 8080 já estiver em uso, escolha outra: `API_PORT=8090 docker compose up --build`
(e use essa porta no `API_URL` do app).

Na primeira execução a API baixa do OpenStreetMap as árvores, parques e bebedouros de
Manaus (alguns minutos). Enquanto isso, as rotas funcionam com sombra estimada só pela
posição do sol. O resultado fica em cache por 30 dias.

**Sem Docker:** crie o banco `thermoguia` no PostgreSQL, ajuste `DB_*` no `.env` e rode
`cd backend && dart pub get && dart run bin/server.dart`. As tabelas são criadas sozinhas.

**Sem chave de IA:** o assistente funciona com o motor de regras local. Para usar o Claude,
crie uma chave em https://console.anthropic.com e coloque em `ANTHROPIC_API_KEY`.

## 2. Rodar o app

```bash
cd app
dart run tool/setup_platforms.dart   # só na primeira vez
flutter run --dart-define=API_URL=http://10.0.2.2:8080
```

O script de preparação gera as pastas `android/` e `ios/`, aplica as permissões de
localização e notificação, habilita o desugaring exigido pelas notificações e gera os
ícones e a tela de abertura a partir da logo em `app/assets/branding/`.

`10.0.2.2` é o endereço do seu computador visto pelo emulador Android. Em um celular
físico, use o IP do computador na rede (ex.: `http://192.168.0.10:8080`).

## 3. Testes

```bash
cd packages/thermo_core && dart test   # regras do agente
cd app && flutter test                 # widgets
```

## Logo e ícones

O ícone é desenhado em vetor em `app/lib/core/widgets/leaf_icon.dart`, e o mesmo
desenho anima a abertura do app. Os PNGs de `app/assets/branding/` saem dele:

| Arquivo | Uso |
|---|---|
| `app_icon.png`, `app_icon_dark.png`, `app_icon_tinted.png` | Ícone do iOS nas variantes Padrão, Escuro e Tingido (iOS 18 troca sozinho) |
| `app_icon_foreground.png`, `app_icon_background.png` | Ícone adaptativo do Android: folha na zona segura sobre o degradê |
| `app_icon_monochrome.png` | Ícone temático do Android 13+ |
| `app/platform/android/res/` | Variantes Escuro e Tingido do Android, escolhidas em Perfil → Ícone do app |
| `store_icon_512.png` | Ícone da ficha da Google Play (512×512) |
| `logo.png` | Logo dentro do app (topo da tela inicial e carregamento) |
| `splash_blank.png` | Tela de abertura nativa vazia; a animação da folha vem logo depois |

Para mudar o ícone, edite o desenho e rode, dentro de `app`:

```bash
flutter test tool/render_brand_assets.dart
dart run tool/setup_platforms.dart
```

## Antes de publicar nas lojas

1. Hospedar a API com HTTPS e remover `usesCleartextTraffic` do AndroidManifest.
2. Trocar os servidores públicos de mapa (tiles, OSRM, Nominatim) por serviços próprios ou
   contratados; os públicos são só para desenvolvimento (ver `docs/ARQUITETURA.md`).
3. Embutir as fontes Sora e Manrope em `assets/` em vez de baixá-las em tempo de execução.
4. Publicar a Política de Privacidade (LGPD), exigida pelas lojas por usarmos localização.
5. Assinar o app (keystore Android, certificados Apple).

## Documentação

- [Arquitetura](docs/ARQUITETURA.md)
- [Referência da API](docs/API.md)
- [Ideias, monetização e roadmap](docs/IDEIAS_E_ROADMAP.md)
