import 'dart:convert';
import 'dart:typed_data';

import 'package:postgres/postgres.dart' show Type, TypedValue;

import 'package:thermo_core/thermo_core.dart';

import 'db.dart';

/// Repositórios: único lugar com SQL. As rotas HTTP só falam com eles.

Map<String, dynamic> userJson(Map<String, dynamic> r) => {
      'id': r['id'],
      'name': r['name'],
      'email': r['email'],
      'persona': r['persona'],
      'plan': r['plan'],
      'cityId': r['city_id'],
      'isAnonymous': r['is_anonymous'],
      'avatarUpdatedAt': r['avatar_updated_at'],
      'createdAt': r['created_at'],
    };

class UserRepo {
  UserRepo(this._db);
  final Db _db;

  Future<Map<String, dynamic>?> byId(String id) =>
      _db.one('SELECT * FROM users WHERE id = CAST(@id AS uuid)', {'id': id});

  Future<Map<String, dynamic>?> byEmail(String email) =>
      _db.one('SELECT * FROM users WHERE email = @e', {'e': email.toLowerCase()});

  Future<Map<String, dynamic>> create({
    String? email,
    String? passwordHash,
    required String name,
    required String persona,
    required bool anonymous,
  }) async =>
      (await _db.one(
        '''INSERT INTO users (email, password_hash, name, persona, is_anonymous)
           VALUES (@e, @h, @n, @p, @a) RETURNING *''',
        {'e': email?.toLowerCase(), 'h': passwordHash, 'n': name, 'p': persona, 'a': anonymous},
      ))!;

  Future<Map<String, dynamic>> update(String id, {String? name, String? persona}) async =>
      (await _db.one(
        '''UPDATE users SET name = COALESCE(@n, name), persona = COALESCE(@p, persona)
           WHERE id = CAST(@id AS uuid) RETURNING *''',
        {'id': id, 'n': name, 'p': persona},
      ))!;

  Future<Map<String, dynamic>> setCredentials(String id, String email, String hash) async =>
      (await _db.one(
        '''UPDATE users SET email = @e, password_hash = @h, is_anonymous = false
           WHERE id = CAST(@id AS uuid) RETURNING *''',
        {'id': id, 'e': email.toLowerCase(), 'h': hash},
      ))!;

  Future<void> delete(String id) =>
      _db.query('DELETE FROM users WHERE id = CAST(@id AS uuid)', {'id': id});

  Future<Map<String, dynamic>> setAvatar(String id, List<int> image, String mime) => _db.tx((q) async {
        await q(
          '''INSERT INTO user_avatars (user_id, image, mime) VALUES (CAST(@id AS uuid), @img, @m)
             ON CONFLICT (user_id) DO UPDATE SET image = EXCLUDED.image, mime = EXCLUDED.mime, updated_at = now()''',
          // Tipo explícito: sem ele o driver grava a lista de inteiros como texto.
          {'id': id, 'img': TypedValue(Type.byteArray, Uint8List.fromList(image)), 'm': mime},
        );
        return (await q('UPDATE users SET avatar_updated_at = now() WHERE id = CAST(@id AS uuid) RETURNING *',
                {'id': id}))
            .first;
      });

  Future<Map<String, dynamic>> removeAvatar(String id) => _db.tx((q) async {
        await q('DELETE FROM user_avatars WHERE user_id = CAST(@id AS uuid)', {'id': id});
        return (await q('UPDATE users SET avatar_updated_at = NULL WHERE id = CAST(@id AS uuid) RETURNING *',
                {'id': id}))
            .first;
      });

  Future<Map<String, dynamic>?> avatar(String id) =>
      _db.one('SELECT image, mime FROM user_avatars WHERE user_id = CAST(@id AS uuid)', {'id': id});
}

class ProfileRepo {
  ProfileRepo(this._db);
  final Db _db;

  Future<AdaptiveProfile> get(String userId) async {
    final row = await _db.one(
      'SELECT data FROM adaptive_profiles WHERE user_id = CAST(@u AS uuid)',
      {'u': userId},
    );
    final data = row?['data'];
    return data is Map ? AdaptiveProfile.fromJson(data.cast<String, dynamic>()) : const AdaptiveProfile();
  }

  Future<void> save(String userId, AdaptiveProfile p) => _db.query(
        '''INSERT INTO adaptive_profiles (user_id, data, updated_at)
           VALUES (CAST(@u AS uuid), CAST(@d AS jsonb), now())
           ON CONFLICT (user_id) DO UPDATE SET data = EXCLUDED.data, updated_at = now()''',
        {'u': userId, 'd': jsonEncode(p.toJson())},
      );
}

class HydrationRepo {
  HydrationRepo(this._db);
  final Db _db;

  Future<void> add(String userId, int ml, DateTime at) => _db.query(
        'INSERT INTO hydration_logs (user_id, amount_ml, logged_at) VALUES (CAST(@u AS uuid), @m, @t)',
        {'u': userId, 'm': ml, 't': at.toUtc()},
      );

  /// Total desde [since] (início do dia local, em UTC).
  Future<List<Map<String, dynamic>>> since(String userId, DateTime since) => _db.query(
        '''SELECT amount_ml, logged_at FROM hydration_logs
           WHERE user_id = CAST(@u AS uuid) AND logged_at >= @s ORDER BY logged_at''',
        {'u': userId, 's': since.toUtc()},
      );
}

class TripRepo {
  TripRepo(this._db);
  final Db _db;

  Future<Map<String, dynamic>> create(String userId, Map<String, dynamic> t) async =>
      (await _db.one(
        '''INSERT INTO trips (user_id, mode, route_label, origin_lat, origin_lng, dest_lat, dest_lng,
             distance_m, duration_s, shade_score, exposure_min, risk_level, feedback, started_at, ended_at)
           VALUES (CAST(@u AS uuid), @mode, @label, @olat, @olng, @dlat, @dlng,
             @dist, @dur, @shade, @expo, @risk, @fb, @start, @end) RETURNING id, created_at''',
        {
          'u': userId,
          'mode': t['mode'] ?? 'foot',
          'label': t['routeLabel'],
          'olat': (t['origin'] as Map?)?['lat'],
          'olng': (t['origin'] as Map?)?['lng'],
          'dlat': (t['destination'] as Map?)?['lat'],
          'dlng': (t['destination'] as Map?)?['lng'],
          'dist': (t['distanceM'] as num?)?.toDouble(),
          'dur': (t['durationS'] as num?)?.toDouble(),
          'shade': (t['shadeScore'] as num?)?.toDouble(),
          'expo': (t['exposureMin'] as num?)?.toDouble(),
          'risk': t['riskLevel'],
          'fb': t['feedback'],
          'start': DateTime.tryParse('${t['startedAt']}')?.toUtc(),
          'end': DateTime.tryParse('${t['endedAt']}')?.toUtc(),
        },
      ))!;

  Future<List<Map<String, dynamic>>> recent(String userId, {int limit = 30}) => _db.query(
        '''SELECT * FROM trips WHERE user_id = CAST(@u AS uuid)
           ORDER BY created_at DESC LIMIT @l''',
        {'u': userId, 'l': limit},
      );
}

class ContactRepo {
  ContactRepo(this._db);
  final Db _db;

  Future<List<Map<String, dynamic>>> list(String userId) => _db.query(
        'SELECT id, name, phone, relation FROM emergency_contacts WHERE user_id = CAST(@u AS uuid) ORDER BY created_at',
        {'u': userId},
      );

  Future<Map<String, dynamic>> add(String userId, String name, String phone, String relation) async =>
      (await _db.one(
        '''INSERT INTO emergency_contacts (user_id, name, phone, relation)
           VALUES (CAST(@u AS uuid), @n, @p, @r) RETURNING id, name, phone, relation''',
        {'u': userId, 'n': name, 'p': phone, 'r': relation},
      ))!;

  Future<void> remove(String userId, String id) => _db.query(
        'DELETE FROM emergency_contacts WHERE id = CAST(@id AS uuid) AND user_id = CAST(@u AS uuid)',
        {'id': id, 'u': userId},
      );
}

class ReportRepo {
  ReportRepo(this._db);
  final Db _db;

  static const lifetimes = {
    'sombra_boa': Duration(days: 180),
    'sem_sombra': Duration(days: 180),
    'bebedouro': Duration(days: 90),
    'calor_extremo': Duration(hours: 6),
    'alagamento': Duration(hours: 12),
    'transito': Duration(hours: 2),
    'obra': Duration(days: 14),
  };

  Future<Map<String, dynamic>> add(String userId, String kind, double lat, double lng, String note) async =>
      (await _db.one(
        '''INSERT INTO community_reports (user_id, kind, lat, lng, note, expires_at)
           VALUES (CAST(@u AS uuid), @k, @lat, @lng, @n, @exp)
           RETURNING id, kind, lat, lng, note, created_at''',
        {
          'u': userId,
          'k': kind,
          'lat': lat,
          'lng': lng,
          'n': note,
          'exp': DateTime.now().toUtc().add(lifetimes[kind]!),
        },
      ))!;

  Future<List<Map<String, dynamic>>> inBox(double s, double w, double n, double e) => _db.query(
        '''SELECT id, kind, lat, lng, note, created_at FROM community_reports
           WHERE expires_at > now() AND lat BETWEEN @s AND @n AND lng BETWEEN @w AND @e
           ORDER BY created_at DESC LIMIT 300''',
        {'s': s, 'w': w, 'n': n, 'e': e},
      );
}

class AuditRepo {
  AuditRepo(this._db);
  final Db _db;

  Future<Map<String, dynamic>> log(
    String? userId,
    String action, {
    bool? approved,
    Map<String, dynamic> details = const {},
    String source = 'app',
  }) async =>
      (await _db.one(
        '''INSERT INTO audit_logs (user_id, action, approved, details, source)
           VALUES (CAST(@u AS uuid), @a, @ap, CAST(@d AS jsonb), @s)
           RETURNING id, action, approved, details, source, created_at''',
        {'u': userId, 'a': action, 'ap': approved, 'd': jsonEncode(details), 's': source},
      ))!;

  Future<List<Map<String, dynamic>>> list(String userId, {int limit = 50}) => _db.query(
        '''SELECT id, action, approved, details, source, created_at FROM audit_logs
           WHERE user_id = CAST(@u AS uuid) ORDER BY created_at DESC LIMIT @l''',
        {'u': userId, 'l': limit},
      );
}

class AiUsageRepo {
  AiUsageRepo(this._db);
  final Db _db;

  /// Incrementa e retorna o total de perguntas do dia.
  Future<int> increment(String userId, DateTime localDay) async {
    final row = await _db.one(
      '''INSERT INTO ai_usage (user_id, day, count) VALUES (CAST(@u AS uuid), CAST(@d AS date), 1)
         ON CONFLICT (user_id, day) DO UPDATE SET count = ai_usage.count + 1
         RETURNING count''',
      {'u': userId, 'd': '${localDay.year}-${_pad2(localDay.month)}-${_pad2(localDay.day)}'},
    );
    return (row!['count'] as num).toInt();
  }

  String _pad2(int v) => v.toString().padLeft(2, '0');
}

class RewardRepo {
  RewardRepo(this._db);
  final Db _db;

  static String day(DateTime localDay) =>
      '${localDay.year}-${localDay.month.toString().padLeft(2, '0')}-${localDay.day.toString().padLeft(2, '0')}';

  /// Lança pontos. Para motivos únicos por dia (checkin, agua), devolve
  /// `false` se já houve lançamento hoje.
  Future<bool> add(String userId, int points, String reason, DateTime localDay, {String? ref}) async {
    final row = await _db.one(
      '''INSERT INTO reward_ledger (user_id, points, reason, day, ref)
         VALUES (CAST(@u AS uuid), @p, @r, CAST(@d AS date), @ref)
         ON CONFLICT (user_id, day, reason) WHERE reason IN ('checkin', 'agua') DO NOTHING
         RETURNING id''',
      {'u': userId, 'p': points, 'r': reason, 'd': day(localDay), 'ref': ref},
    );
    return row != null;
  }

  Future<int> countToday(String userId, String reason, DateTime localDay) async {
    final row = await _db.one(
      '''SELECT count(*)::int AS n FROM reward_ledger
         WHERE user_id = CAST(@u AS uuid) AND reason = @r AND day = CAST(@d AS date)''',
      {'u': userId, 'r': reason, 'd': day(localDay)},
    );
    return (row?['n'] as num? ?? 0).toInt();
  }

  /// Água comprovada que já rendeu gotas hoje (o `ref` guarda "post:ml").
  Future<int> verifiedMlToday(String userId, DateTime localDay) async {
    final rows = await _db.query(
      '''SELECT ref FROM reward_ledger
         WHERE user_id = CAST(@u AS uuid) AND reason = 'agua_comprovada' AND day = CAST(@d AS date)''',
      {'u': userId, 'd': day(localDay)},
    );
    return rows.fold<int>(0, (a, r) => a + (int.tryParse('${r['ref']}'.split(':').last) ?? 0));
  }

  /// Saldo atual e total já ganho (para o nível).
  Future<(int, int)> totals(String userId) async {
    final row = await _db.one(
      '''SELECT COALESCE(sum(points), 0)::int AS balance,
                COALESCE(sum(points) FILTER (WHERE points > 0), 0)::int AS lifetime
         FROM reward_ledger WHERE user_id = CAST(@u AS uuid)''',
      {'u': userId},
    );
    return ((row!['balance'] as num).toInt(), (row['lifetime'] as num).toInt());
  }

  /// Dias (locais) com check-in, do mais recente para trás.
  Future<List<DateTime>> checkinDays(String userId, {int limit = 120}) async {
    final rows = await _db.query(
      '''SELECT day FROM reward_ledger WHERE user_id = CAST(@u AS uuid) AND reason = 'checkin'
         ORDER BY day DESC LIMIT @l''',
      {'u': userId, 'l': limit},
    );
    return rows.map((r) => r['day'] as DateTime).toList();
  }

  Future<List<Map<String, dynamic>>> history(String userId, {int limit = 20}) => _db.query(
        '''SELECT points, reason, day, ref, created_at FROM reward_ledger
           WHERE user_id = CAST(@u AS uuid) ORDER BY created_at DESC LIMIT @l''',
        {'u': userId, 'l': limit},
      );

  /// Gotas ganhas e trajetos nos últimos 7 dias (para o resumo semanal).
  Future<(int, int)> lastWeek(String userId, DateTime localDay) async {
    final row = await _db.one(
      '''SELECT COALESCE(sum(points) FILTER (WHERE points > 0), 0)::int AS earned,
                count(*) FILTER (WHERE reason = 'trajeto')::int AS trips
         FROM reward_ledger
         WHERE user_id = CAST(@u AS uuid) AND day > CAST(@d AS date) - 7''',
      {'u': userId, 'd': day(localDay)},
    );
    return ((row!['earned'] as num).toInt(), (row['trips'] as num).toInt());
  }

  Future<List<Map<String, dynamic>>> offers() => _db.query(
        '''SELECT id, partner, category, title, details, neighborhood, cost, plus_only, demo
           FROM partner_offers WHERE active ORDER BY plus_only, cost''',
      );

  Future<Map<String, dynamic>?> offer(String id) => _db.one(
        'SELECT * FROM partner_offers WHERE id = @id AND active',
        {'id': id},
      );

  Future<int> redeemsSince(String userId, DateTime since) async {
    final row = await _db.one(
      '''SELECT count(*)::int AS n FROM reward_coupons
         WHERE user_id = CAST(@u AS uuid) AND created_at >= @s''',
      {'u': userId, 's': since},
    );
    return (row!['n'] as num).toInt();
  }

  /// Troca gotas por um cupom, numa transação travada por usuário: dois
  /// toques seguidos não gastam o mesmo saldo duas vezes. Devolve o cupom ou
  /// o motivo da recusa.
  Future<(Map<String, dynamic>?, String?)> redeem({
    required String userId,
    required Map<String, dynamic> offer,
    required DateTime localDay,
    required DateTime monthStartUtc,
    required int? monthlyLimit,
    required String code,
    required DateTime expires,
  }) =>
      _db.tx((q) async {
        await q('SELECT pg_advisory_xact_lock(hashtext(@u))', {'u': userId});
        final bal = (await q(
          'SELECT COALESCE(sum(points), 0)::int AS b FROM reward_ledger WHERE user_id = CAST(@u AS uuid)',
          {'u': userId},
        ))
            .first['b'] as int;
        final cost = offer['cost'] as int;
        if (bal < cost) return (null, 'Faltam ${cost - bal} gotas para este desconto.');
        if (monthlyLimit != null) {
          final used = (await q(
            '''SELECT count(*)::int AS n FROM reward_coupons
               WHERE user_id = CAST(@u AS uuid) AND created_at >= @s''',
            {'u': userId, 's': monthStartUtc},
          ))
              .first['n'] as int;
          if (used >= monthlyLimit) {
            return (null, 'Você já usou os $monthlyLimit resgates do mês. No ThermoGuia+ os resgates são ilimitados.');
          }
        }
        await q(
          '''INSERT INTO reward_ledger (user_id, points, reason, day, ref)
             VALUES (CAST(@u AS uuid), @p, 'resgate', CAST(@d AS date), @ref)''',
          {'u': userId, 'p': -cost, 'd': day(localDay), 'ref': offer['id']},
        );
        final c = (await q(
          '''INSERT INTO reward_coupons (user_id, offer_id, code, expires_at)
             VALUES (CAST(@u AS uuid), @o, @c, @e) RETURNING id, code, created_at, expires_at''',
          {'u': userId, 'o': offer['id'], 'c': code, 'e': expires},
        ))
            .first;
        return (c, null);
      });

  Future<List<Map<String, dynamic>>> activeCoupons(String userId) => _db.query(
        '''SELECT c.id, c.code, c.created_at, c.expires_at, o.partner, o.title, o.category, o.neighborhood, o.demo
           FROM reward_coupons c JOIN partner_offers o ON o.id = c.offer_id
           WHERE c.user_id = CAST(@u AS uuid) AND c.expires_at > now()
           ORDER BY c.created_at DESC''',
        {'u': userId},
      );
}

class SocialRepo {
  SocialRepo(this._db);
  final Db _db;

  static const _farFuture = '9999-01-01T00:00:00Z';

  Future<String> createPost(String userId, String category, String caption, String status) async =>
      (await _db.one(
        '''INSERT INTO posts (user_id, category, caption, status)
           VALUES (CAST(@u AS uuid), @c, @t, @s) RETURNING id''',
        {'u': userId, 'c': category, 't': caption, 's': status},
      ))!['id'] as String;

  Future<void> addImage(String postId, String kind, List<int> bytes, String mime, String sha, int dhash) => _db.query(
        '''INSERT INTO post_images (post_id, kind, image, mime, sha256, dhash)
           VALUES (CAST(@p AS uuid), @k, @img, @m, @sha, @h)''',
        {
          'p': postId,
          'k': kind,
          'img': TypedValue(Type.byteArray, Uint8List.fromList(bytes)),
          'm': mime,
          'sha': sha,
          'h': dhash,
        },
      );

  Future<Map<String, dynamic>?> post(String id) => _db.one(
        '''SELECT p.id, p.user_id, p.category, p.caption, p.status, p.verified_by, p.reason, p.verified_ml,
                  p.hidden, p.created_at, p.verified_at,
                  (SELECT uploaded_at FROM post_images i WHERE i.post_id = p.id AND i.kind = 'antes') AS before_at
           FROM posts p WHERE p.id = CAST(@id AS uuid)''',
        {'id': id},
      );

  Future<Map<String, dynamic>?> image(String postId, String kind) => _db.one(
        'SELECT image, mime FROM post_images WHERE post_id = CAST(@p AS uuid) AND kind = @k',
        {'p': postId, 'k': kind},
      );

  Future<void> setCaption(String id, String caption) => _db.query(
        'UPDATE posts SET caption = @c WHERE id = CAST(@id AS uuid)',
        {'id': id, 'c': caption},
      );

  Future<void> setStatus(String id, String status, {String? reason}) => _db.query(
        'UPDATE posts SET status = @s, reason = COALESCE(@r, reason) WHERE id = CAST(@id AS uuid)',
        {'id': id, 's': status, 'r': reason},
      );

  Future<void> setVerdict(String id, String status, String by, Map<String, dynamic>? verdict, String reason, int? ml) =>
      _db.query(
        '''UPDATE posts SET status = @s, verified_by = @by, verdict = CAST(@v AS jsonb), reason = @r,
             verified_ml = @ml, verified_at = now()
           WHERE id = CAST(@id AS uuid)''',
        {'id': id, 's': status, 'by': by, 'v': jsonEncode(verdict), 'r': reason, 'ml': ml},
      );

  Future<bool> shaSeen(String sha, {int days = 180}) async =>
      (await _db.one(
        '''SELECT 1 AS x FROM post_images WHERE sha256 = @sha
           AND uploaded_at > now() - make_interval(days => @d) LIMIT 1''',
        {'sha': sha, 'd': days},
      )) !=
      null;

  /// Hashes perceptuais recentes: os da própria pessoa (180 dias) e os de
  /// todo mundo (30 dias), para achar a mesma foto reenviada.
  Future<List<(int, bool)>> recentHashes(String userId, {String? kind}) async {
    final rows = await _db.query(
      '''SELECT i.dhash, p.user_id = CAST(@u AS uuid) AS mine
         FROM post_images i JOIN posts p ON p.id = i.post_id
         WHERE (@k::text IS NULL OR i.kind = @k::text)
           AND (i.uploaded_at > now() - interval '30 days'
                OR (p.user_id = CAST(@u AS uuid) AND i.uploaded_at > now() - interval '180 days'))
         ORDER BY i.uploaded_at DESC LIMIT 5000''',
      {'u': userId, 'k': kind},
    );
    return rows.map((r) => ((r['dhash'] as num).toInt(), r['mine'] == true)).toList();
  }

  Future<int> postsSince(String userId, DateTime sinceUtc, {required bool water}) async =>
      ((await _db.one(
        '''SELECT count(*)::int AS n FROM posts WHERE user_id = CAST(@u AS uuid) AND created_at >= @s
           AND (category = 'agua') = @w''',
        {'u': userId, 's': sinceUtc, 'w': water},
      ))!['n'] as num)
          .toInt();

  static const _postFields = '''
    p.id, p.user_id, p.category, p.caption, p.status, p.reason, p.verified_ml, p.verified_by,
    p.created_at, p.verified_at, u.name AS author_name, u.avatar_updated_at AS author_avatar,
    (SELECT count(*) FROM post_reactions r WHERE r.post_id = p.id)::int AS reactions,
    (SELECT COALESCE(jsonb_object_agg(kind, n), '{}'::jsonb)
       FROM (SELECT kind, count(*) AS n FROM post_reactions r WHERE r.post_id = p.id GROUP BY kind) k) AS by_kind,
    (SELECT count(*) FROM post_comments c WHERE c.post_id = p.id AND NOT c.hidden)::int AS comments,
    (SELECT kind FROM post_reactions r WHERE r.post_id = p.id AND r.user_id = CAST(@v AS uuid)) AS my_reaction,
    EXISTS (SELECT 1 FROM post_images i WHERE i.post_id = p.id AND i.kind = 'antes') AS has_before''';

  static const _notBlocked = '''
    NOT EXISTS (SELECT 1 FROM user_blocks b
                WHERE (b.user_id = CAST(@v AS uuid) AND b.blocked_id = p.user_id)
                   OR (b.user_id = p.user_id AND b.blocked_id = CAST(@v AS uuid)))''';

  /// Feed: só posts aprovados e visíveis, sem quem a pessoa bloqueou.
  Future<List<Map<String, dynamic>>> feed(String viewerId, {DateTime? before, int limit = 20}) => _db.query(
        '''SELECT $_postFields FROM posts p JOIN users u ON u.id = p.user_id
           WHERE p.status = 'aprovado' AND NOT p.hidden AND p.created_at < @b AND $_notBlocked
           ORDER BY p.created_at DESC LIMIT @l''',
        {'v': viewerId, 'b': before ?? DateTime.parse(_farFuture), 'l': limit},
      );

  /// Posts da própria pessoa, em qualquer situação (para acompanhar a verificação).
  Future<List<Map<String, dynamic>>> mine(String userId) => _db.query(
        '''SELECT $_postFields FROM posts p JOIN users u ON u.id = p.user_id
           WHERE p.user_id = CAST(@v AS uuid) ORDER BY p.created_at DESC LIMIT 50''',
        {'v': userId},
      );

  Future<Map<String, dynamic>?> postView(String id, String viewerId) => _db.one(
        '''SELECT $_postFields FROM posts p JOIN users u ON u.id = p.user_id
           WHERE p.id = CAST(@id AS uuid) AND $_notBlocked''',
        {'id': id, 'v': viewerId},
      );

  Future<void> react(String postId, String userId, String kind) => _db.query(
        '''INSERT INTO post_reactions (post_id, user_id, kind) VALUES (CAST(@p AS uuid), CAST(@u AS uuid), @k)
           ON CONFLICT (post_id, user_id) DO UPDATE SET kind = EXCLUDED.kind, created_at = now()''',
        {'p': postId, 'u': userId, 'k': kind},
      );

  Future<void> unreact(String postId, String userId) => _db.query(
        'DELETE FROM post_reactions WHERE post_id = CAST(@p AS uuid) AND user_id = CAST(@u AS uuid)',
        {'p': postId, 'u': userId},
      );

  Future<List<Map<String, dynamic>>> comments(String postId, String viewerId) => _db.query(
        '''SELECT c.id, c.user_id, c.text, c.created_at, u.name AS author_name, u.avatar_updated_at AS author_avatar
           FROM post_comments c JOIN users u ON u.id = c.user_id
           WHERE c.post_id = CAST(@p AS uuid) AND NOT c.hidden
             AND NOT EXISTS (SELECT 1 FROM user_blocks b
                             WHERE (b.user_id = CAST(@v AS uuid) AND b.blocked_id = c.user_id)
                                OR (b.user_id = c.user_id AND b.blocked_id = CAST(@v AS uuid)))
           ORDER BY c.created_at LIMIT 200''',
        {'p': postId, 'v': viewerId},
      );

  Future<Map<String, dynamic>> addComment(String postId, String userId, String text) async => (await _db.one(
        '''INSERT INTO post_comments (post_id, user_id, text) VALUES (CAST(@p AS uuid), CAST(@u AS uuid), @t)
           RETURNING id, created_at''',
        {'p': postId, 'u': userId, 't': text},
      ))!;

  Future<int> deleteComment(String id, String userId) async => (await _db.query(
        'DELETE FROM post_comments WHERE id = CAST(@id AS uuid) AND user_id = CAST(@u AS uuid) RETURNING id',
        {'id': id, 'u': userId},
      ))
          .length;

  Future<int> deletePost(String id, String userId) async => (await _db.query(
        'DELETE FROM posts WHERE id = CAST(@id AS uuid) AND user_id = CAST(@u AS uuid) RETURNING id',
        {'id': id, 'u': userId},
      ))
          .length;

  /// Registra a denúncia; com 3 pessoas diferentes, o conteúdo sai do ar
  /// até a equipe revisar. Devolve o total de denúncias.
  Future<int> report(String type, String id, String userId, String reason) async {
    await _db.query(
      '''INSERT INTO content_reports (target_type, target_id, user_id, reason)
         VALUES (@t, CAST(@id AS uuid), CAST(@u AS uuid), @r) ON CONFLICT DO NOTHING''',
      {'t': type, 'id': id, 'u': userId, 'r': reason},
    );
    final n = ((await _db.one(
      'SELECT count(*)::int AS n FROM content_reports WHERE target_type = @t AND target_id = CAST(@id AS uuid)',
      {'t': type, 'id': id},
    ))!['n'] as num)
        .toInt();
    if (n >= 3) {
      await _db.query(
        type == 'post'
            ? 'UPDATE posts SET hidden = true WHERE id = CAST(@id AS uuid)'
            : 'UPDATE post_comments SET hidden = true WHERE id = CAST(@id AS uuid)',
        {'id': id},
      );
    }
    return n;
  }

  Future<void> block(String userId, String blockedId) => _db.query(
        '''INSERT INTO user_blocks (user_id, blocked_id) VALUES (CAST(@u AS uuid), CAST(@b AS uuid))
           ON CONFLICT DO NOTHING''',
        {'u': userId, 'b': blockedId},
      );

  /// Placar da semana numa categoria. Pontua cada pessoa diferente que
  /// reagiu (1) ou comentou (2) em posts aprovados, sem contar o autor e só
  /// contas com 2 dias ou mais (evita contas criadas para inflar o placar).
  Future<List<Map<String, dynamic>>> weekScores(String category, DateTime startUtc, DateTime endUtc) => _db.query(
        '''SELECT p.user_id, u.name, u.avatar_updated_at,
             sum((SELECT count(DISTINCT r.user_id) FROM post_reactions r JOIN users ru ON ru.id = r.user_id
                  WHERE r.post_id = p.id AND r.user_id <> p.user_id AND ru.created_at < now() - interval '2 days')
               + 2 * (SELECT count(DISTINCT c.user_id) FROM post_comments c JOIN users cu ON cu.id = c.user_id
                  WHERE c.post_id = p.id AND c.user_id <> p.user_id AND NOT c.hidden
                    AND cu.created_at < now() - interval '2 days'))::int AS score,
             count(*)::int AS posts
           FROM posts p JOIN users u ON u.id = p.user_id
           WHERE p.category = @c AND p.status = 'aprovado' AND NOT p.hidden
             AND p.created_at >= @s AND p.created_at < @e
           GROUP BY p.user_id, u.name, u.avatar_updated_at
           ORDER BY score DESC, posts DESC, min(p.created_at) ASC
           LIMIT 3''',
        {'c': category, 's': startUtc, 'e': endUtc},
      );

  /// Rotas Frescas concluídas na semana (dados do próprio app, já validados).
  Future<List<Map<String, dynamic>>> weekTrips(DateTime startDay, DateTime endDay) => _db.query(
        '''SELECT l.user_id, u.name, u.avatar_updated_at, count(*)::int AS score, 0 AS posts
           FROM reward_ledger l JOIN users u ON u.id = l.user_id
           WHERE l.reason = 'trajeto' AND l.day >= CAST(@s AS date) AND l.day < CAST(@e AS date)
           GROUP BY l.user_id, u.name, u.avatar_updated_at
           ORDER BY score DESC, min(l.created_at) ASC LIMIT 3''',
        {'s': RewardRepo.day(startDay), 'e': RewardRepo.day(endDay)},
      );

  Future<List<Map<String, dynamic>>> badgesOf(DateTime week) => _db.query(
        '''SELECT b.category, b.user_id, b.score, u.name, u.avatar_updated_at
           FROM weekly_badges b JOIN users u ON u.id = b.user_id WHERE b.week = CAST(@w AS date)''',
        {'w': RewardRepo.day(week)},
      );

  Future<bool> weekClosed(DateTime week) async =>
      (await _db.one('SELECT 1 AS x FROM weekly_badges WHERE week = CAST(@w AS date) LIMIT 1',
          {'w': RewardRepo.day(week)})) !=
      null;

  /// Grava o vencedor; devolve false se a semana/categoria já tinha dono.
  Future<bool> saveBadge(DateTime week, String category, String userId, int score) async =>
      (await _db.one(
        '''INSERT INTO weekly_badges (week, category, user_id, score) VALUES (CAST(@w AS date), @c, CAST(@u AS uuid), @s)
           ON CONFLICT DO NOTHING RETURNING week''',
        {'w': RewardRepo.day(week), 'c': category, 'u': userId, 's': score},
      )) !=
      null;

  /// Fila da equipe: posts em revisão e conteúdo tirado do ar por denúncias.
  Future<List<Map<String, dynamic>>> reviewQueue() => _db.query(
        '''SELECT p.id, p.user_id, p.category, p.caption, p.status, p.reason, p.verified_ml, p.hidden, p.created_at,
                  p.verdict,
                  (SELECT count(*) FROM content_reports r WHERE r.target_type = 'post' AND r.target_id = p.id)::int AS reports,
                  (SELECT array_agg(kind) FROM post_images i WHERE i.post_id = p.id) AS images
           FROM posts p WHERE p.status = 'revisao' OR p.hidden
           ORDER BY p.created_at LIMIT 100''',
      );

  Future<void> restore(String id) => _db.query(
        'UPDATE posts SET hidden = false WHERE id = CAST(@id AS uuid)',
        {'id': id},
      );
}
