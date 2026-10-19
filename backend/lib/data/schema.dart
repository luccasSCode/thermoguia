/// Esquema do banco. Idempotente: executado a cada inicialização.
const schemaSql = r'''
CREATE TABLE IF NOT EXISTS users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email         text UNIQUE,
  password_hash text,
  name          text NOT NULL DEFAULT '',
  persona       text NOT NULL DEFAULT 'pedestre',
  plan          text NOT NULL DEFAULT 'free',
  city_id       text NOT NULL DEFAULT 'manaus',
  is_anonymous  boolean NOT NULL DEFAULT false,
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- Foto de perfil: a imagem fica em tabela própria (users é lida o tempo todo);
-- users guarda só a data, que serve de versão para o app atualizar o cache.
ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_updated_at timestamptz;
CREATE TABLE IF NOT EXISTS user_avatars (
  user_id    uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  image      bytea NOT NULL,
  mime       text NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS adaptive_profiles (
  user_id    uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  data       jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS hydration_logs (
  id        bigserial PRIMARY KEY,
  user_id   uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  amount_ml int NOT NULL CHECK (amount_ml > 0 AND amount_ml <= 2000),
  logged_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS hydration_user_time ON hydration_logs (user_id, logged_at);

CREATE TABLE IF NOT EXISTS trips (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  mode         text NOT NULL DEFAULT 'foot',
  route_label  text,
  origin_lat   double precision, origin_lng double precision,
  dest_lat     double precision, dest_lng   double precision,
  distance_m   double precision,
  duration_s   double precision,
  shade_score  double precision,
  exposure_min double precision,
  risk_level   text,
  feedback     text,
  started_at   timestamptz,
  ended_at     timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS trips_user ON trips (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS emergency_contacts (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name       text NOT NULL,
  phone      text NOT NULL,
  relation   text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Acompanhamento pelo responsável (perfil idoso): um link secreto mostra a
-- água do dia e os pedidos de ajuda, sem precisar de conta.
CREATE TABLE IF NOT EXISTS guardian_links (
  user_id    uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  token      text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS help_alerts (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  symptoms   jsonb NOT NULL DEFAULT '[]'::jsonb,
  lat        double precision,
  lng        double precision,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS help_alerts_user ON help_alerts (user_id, created_at DESC);

-- Login social: o mesmo usuário entra pelo Google ou pelo Facebook.
ALTER TABLE users ADD COLUMN IF NOT EXISTS google_sub text UNIQUE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS facebook_id text UNIQUE;

CREATE TABLE IF NOT EXISTS community_reports (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid REFERENCES users(id) ON DELETE SET NULL,
  city_id    text NOT NULL DEFAULT 'manaus',
  kind       text NOT NULL,
  lat        double precision NOT NULL,
  lng        double precision NOT NULL,
  note       text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS reports_geo ON community_reports (lat, lng);
-- Tipos aceitos (recriada a cada inicialização para incluir tipos novos).
ALTER TABLE community_reports DROP CONSTRAINT IF EXISTS community_reports_kind_check;
ALTER TABLE community_reports ADD CONSTRAINT community_reports_kind_check
  CHECK (kind IN ('sombra_boa','sem_sombra','bebedouro','calor_extremo','alagamento','transito','obra','fumaca'));

CREATE TABLE IF NOT EXISTS ai_usage (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day     date NOT NULL,
  count   int NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, day)
);

-- Trilha de auditoria: somente inclusão.
CREATE TABLE IF NOT EXISTS audit_logs (
  id         bigserial PRIMARY KEY,
  user_id    uuid REFERENCES users(id) ON DELETE SET NULL,
  action     text NOT NULL,
  approved   boolean,
  details    jsonb NOT NULL DEFAULT '{}'::jsonb,
  source     text NOT NULL DEFAULT 'app',
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS audit_user_time ON audit_logs (user_id, created_at DESC);

-- Impede edição e exclusão de registros de auditoria. A única alteração
-- permitida é a anonimização (user_id -> NULL) quando a conta é excluída (LGPD).
CREATE OR REPLACE FUNCTION audit_logs_guard() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'UPDATE'
     AND NEW.user_id IS NULL
     AND NEW.action = OLD.action
     AND NEW.details = OLD.details
     AND NEW.created_at = OLD.created_at THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'audit_logs é somente-inclusão';
END;
$$ LANGUAGE plpgsql;

-- Clube H2O: gotas ganhas com hábitos saudáveis e trocadas por descontos.
CREATE TABLE IF NOT EXISTS reward_ledger (
  id         bigserial PRIMARY KEY,
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  points     int NOT NULL,
  reason     text NOT NULL,          -- checkin, sequencia, trajeto, agua, relato, resgate
  day        date NOT NULL,          -- dia local da cidade
  ref        text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS reward_user_day ON reward_ledger (user_id, day);
CREATE UNIQUE INDEX IF NOT EXISTS reward_once_per_day
  ON reward_ledger (user_id, day, reason) WHERE reason IN ('checkin', 'agua');

CREATE TABLE IF NOT EXISTS partner_offers (
  id           text PRIMARY KEY,
  partner      text NOT NULL,
  category     text NOT NULL,         -- acai, farmacia, coco, mercado, bike, cafe, otica, esporte...
  title        text NOT NULL,
  details      text NOT NULL DEFAULT '',
  neighborhood text NOT NULL DEFAULT '',
  cost         int NOT NULL CHECK (cost > 0),
  plus_only    boolean NOT NULL DEFAULT false,
  demo         boolean NOT NULL DEFAULT false,
  active       boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- Ofertas de exemplo, para demonstrar o clube enquanto não há parceiros reais.
-- Parceiros reais entram com demo = false (ver docs/IDEIAS_E_ROADMAP.md).
INSERT INTO partner_offers (id, partner, category, title, details, neighborhood, cost, plus_only, demo) VALUES
  ('demo-acai',     'Açaíteria (exemplo)',          'acai',     '10% no açaí de 500 ml',                    'Válido de segunda a sexta.',              'Centro',        80,  false, true),
  ('demo-coco',     'Quiosque de água de coco (exemplo)', 'coco', 'Leve 3 águas de coco e pague 2',          'No quiosque parceiro mais próximo.',      'Ponta Negra',   100, false, true),
  ('demo-mercado',  'Supermercado (exemplo)',       'mercado',  '5% no fardo de água mineral',              'Um uso por cupom.',                      'Adrianópolis',  60,  false, true),
  ('demo-cafe',     'Café climatizado (exemplo)',   'cafe',     'Bebida gelada pela metade do preço',       'Fique no ar-condicionado enquanto o pico passa.', 'Vieiralves', 120, false, true),
  ('demo-esporte',  'Loja de esportes (exemplo)',   'esporte',  '10% em garrafas térmicas',                 'Garrafas de 500 ml a 1 litro.',          'Chapada',       90,  false, true),
  ('demo-farmacia', 'Farmácia (exemplo)',           'farmacia', '15% em protetor solar',                    'Exclusivo ThermoGuia+.',                 'Centro',        150, true,  true),
  ('demo-bike',     'Oficina de bicicletas (exemplo)', 'bike',  '20% na revisão da bicicleta',              'Exclusivo ThermoGuia+.',                 'Parque 10',     250, true,  true),
  ('demo-otica',    'Ótica (exemplo)',              'otica',    '25% em óculos de sol com proteção UV',     'Exclusivo ThermoGuia+.',                 'Aleixo',        300, true,  true)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS reward_coupons (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  offer_id   text NOT NULL REFERENCES partner_offers(id),
  code       text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL
);
CREATE INDEX IF NOT EXISTS coupons_user ON reward_coupons (user_id, created_at DESC);

-- Comunidade: posts com foto, verificados pela IA (ou por revisão humana)
-- antes de aparecer para os outros. Nada rende gotas sem verificação.
CREATE TABLE IF NOT EXISTS posts (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  category      text NOT NULL,
  caption       text NOT NULL DEFAULT '',
  -- aguardando_depois (prova de água em andamento), verificando, revisao, aprovado, recusado
  status        text NOT NULL,
  verified_by   text,              -- ia, revisao
  verdict       jsonb,             -- resposta completa da IA e motivos (auditoria)
  reason        text,              -- explicação para a pessoa
  verified_ml   int,               -- água comprovada (só categoria agua)
  hidden        boolean NOT NULL DEFAULT false,
  created_at    timestamptz NOT NULL DEFAULT now(),
  verified_at   timestamptz
);
-- Categorias aceitas (a lista cresceu: máscara, sombra e print do app aberto).
ALTER TABLE posts DROP CONSTRAINT IF EXISTS posts_category_check;
ALTER TABLE posts ADD CONSTRAINT posts_category_check
  CHECK (category IN ('agua','bone','protetor','guarda_sol','oculos','mascara','sombra','app_aberto'));
CREATE INDEX IF NOT EXISTS posts_feed ON posts (status, created_at DESC);
CREATE INDEX IF NOT EXISTS posts_user ON posts (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS post_images (
  id          bigserial PRIMARY KEY,
  post_id     uuid NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  kind        text NOT NULL,       -- foto, antes, depois
  image       bytea NOT NULL,
  mime        text NOT NULL,
  sha256      text NOT NULL,
  dhash       bigint NOT NULL,     -- hash perceptual, acha a mesma foto reenviada
  uploaded_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (post_id, kind)
);
CREATE INDEX IF NOT EXISTS post_images_sha ON post_images (sha256);
CREATE INDEX IF NOT EXISTS post_images_time ON post_images (uploaded_at DESC);

CREATE TABLE IF NOT EXISTS post_reactions (
  post_id    uuid NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind       text NOT NULL CHECK (kind IN ('curtir','hidratado','protegido','inspirou')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (post_id, user_id)
);

CREATE TABLE IF NOT EXISTS post_comments (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id    uuid NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  text       text NOT NULL,
  hidden     boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS comments_post ON post_comments (post_id, created_at);

CREATE TABLE IF NOT EXISTS content_reports (
  target_type text NOT NULL,       -- post, comentario
  target_id   uuid NOT NULL,
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  reason      text NOT NULL DEFAULT '',
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (target_type, target_id, user_id)
);

CREATE TABLE IF NOT EXISTS user_blocks (
  user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  blocked_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, blocked_id)
);

-- Selos da semana ("+ Hidratado", "+ Usou boné"...), fechados no domingo.
CREATE TABLE IF NOT EXISTS weekly_badges (
  week     date NOT NULL,          -- segunda-feira da semana (dia local)
  category text NOT NULL,
  user_id  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  score    int NOT NULL,
  PRIMARY KEY (week, category)
);

DROP TRIGGER IF EXISTS audit_logs_guard_trg ON audit_logs;
CREATE TRIGGER audit_logs_guard_trg
  BEFORE UPDATE OR DELETE ON audit_logs
  FOR EACH ROW EXECUTE FUNCTION audit_logs_guard();
''';
