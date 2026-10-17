import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../cities.dart';
import '../data/repositories.dart';
import '../http/http_utils.dart';
import 'rewards_service.dart';
import 'verification_service.dart';

/// Comunidade: posts com foto que comprovam hábitos de proteção ao calor.
///
/// Fluxo: a foto chega → checagens antifraude (formato, foto repetida) →
/// verificação pela IA em segundo plano → aprovado (aparece no feed e rende
/// gotas), revisão (equipe decide) ou recusado (só a pessoa vê, com o motivo).
class SocialService {
  SocialService(this._repo, this._verify, this._rewards, this._users);
  final SocialRepo _repo;
  final VerificationService _verify;
  final RewardsService _rewards;
  final UserRepo _users;

  static const maxImageBytes = 1536 * 1024;
  static const maxPostsPerDay = 5;
  static const maxWaterProofsPerDay = 8;

  /// Tempo mínimo entre a foto "antes" e a "depois" da água (medido no servidor).
  static const minWaterInterval = Duration(minutes: 10);
  static const maxWaterInterval = Duration(hours: 6);

  /// Distância máxima (bits do dHash) para considerar a mesma foto.
  static const _sameAsOwn = 4;
  static const _sameAsOthers = 3;

  /// Valida e devolve (mime, sha256, dHash). Lança [ApiError] com o motivo.
  Future<(String, String, int)> _checkImage(String userId, List<int> bytes, {required bool strictOwn}) async {
    if (bytes.length > maxImageBytes) throw ApiError(413, 'A foto é grande demais.');
    final mime = imageMime(bytes);
    if (mime == null) throw ApiError(400, 'Envie uma foto em JPEG ou PNG.');
    final int hash;
    try {
      hash = dHash(Uint8List.fromList(bytes));
    } catch (_) {
      throw ApiError(400, 'Não foi possível ler esta foto.');
    }
    final sha = sha256.convert(bytes).toString();
    if (await _repo.shaSeen(sha)) throw ApiError(409, 'Esta foto já foi enviada antes. Tire uma foto nova.');
    // Na água, a mesma garrafa na mesma mesa todo dia é normal: só barra
    // fotos praticamente idênticas. Nas outras categorias, é mais rígido.
    for (final (h, mine) in await _repo.recentHashes(userId)) {
      final limit = mine ? (strictOwn ? _sameAsOwn : 1) : _sameAsOthers;
      if (hammingDistance(h, hash) <= limit) {
        throw ApiError(409, 'Esta foto é igual a uma já enviada. Tire uma foto nova.');
      }
    }
    return (mime, sha, hash);
  }

  DateTime _todayStartUtc(City city) {
    final t = city.localWallClock(DateTime.now());
    return DateTime.utc(t.year, t.month, t.day).subtract(city.utcOffset);
  }

  String _caption(String? s) {
    final t = (s ?? '').trim();
    return t.length > 280 ? t.substring(0, 280) : t;
  }

  /// Boné, protetor, guarda-sol, óculos: uma foto.
  Future<Map<String, dynamic>> createPost(String userId, City city, String category, String? caption, List<int> photo) async {
    final c = categoryById(category);
    if (c == null || c.id == 'agua') throw ApiError(400, 'Categoria inválida.');
    if (await _repo.postsSince(userId, _todayStartUtc(city), water: false) >= maxPostsPerDay) {
      throw ApiError(429, 'Você já publicou $maxPostsPerDay fotos hoje. Volte amanhã!');
    }
    final (mime, sha, hash) = await _checkImage(userId, photo, strictOwn: true);
    final id = await _repo.createPost(userId, c.id, _caption(caption), 'verificando');
    await _repo.addImage(id, 'foto', photo, mime, sha, hash);
    unawaited(_run(id, () => _verify.verifyPost(c, photo, mime)));
    return (await _repo.post(id))!;
  }

  /// Água, passo 1: foto do recipiente antes de beber.
  Future<Map<String, dynamic>> startWater(String userId, City city, List<int> photo) async {
    if (await _repo.postsSince(userId, _todayStartUtc(city), water: true) >= maxWaterProofsPerDay) {
      throw ApiError(429, 'Limite de $maxWaterProofsPerDay provas de água por dia atingido.');
    }
    final (mime, sha, hash) = await _checkImage(userId, photo, strictOwn: false);
    final id = await _repo.createPost(userId, 'agua', '', 'aguardando_depois');
    await _repo.addImage(id, 'antes', photo, mime, sha, hash);
    return (await _repo.post(id))!;
  }

  /// Água, passo 2: a foto depois, entre 10 minutos e 6 horas mais tarde.
  Future<Map<String, dynamic>> finishWater(String userId, String postId, String? caption, List<int> photo) async {
    final p = await _repo.post(postId);
    if (p == null || p['user_id'] != userId) throw ApiError(404, 'Prova de água não encontrada.');
    if (p['status'] != 'aguardando_depois') throw ApiError(409, 'Esta prova de água já foi enviada.');
    final elapsed = DateTime.now().toUtc().difference((p['before_at'] as DateTime).toUtc());
    if (elapsed < minWaterInterval) {
      final wait = (minWaterInterval - elapsed).inMinutes + 1;
      throw ApiError(409, 'Ainda é cedo: tire a foto "depois" em $wait min.');
    }
    if (elapsed > maxWaterInterval) {
      await _repo.setVerdict(postId, 'recusado', 'regra', null, 'O prazo de 6 horas para a foto "depois" acabou.', null);
      throw ApiError(409, 'O prazo de 6 horas acabou. Comece uma nova prova.');
    }
    final (mime, sha, hash) = await _checkImage(userId, photo, strictOwn: false);
    final before = await _repo.image(postId, 'antes');
    await _repo.addImage(postId, 'depois', photo, mime, sha, hash);
    final cap = _caption(caption);
    if (cap.isNotEmpty) await _repo.setCaption(postId, cap);
    await _repo.setStatus(postId, 'verificando');
    unawaited(_run(postId, () => _verify.verifyWater(before!['image'] as List<int>, photo, mime, elapsed: elapsed)));
    return (await _repo.post(postId))!;
  }

  Future<void> _run(String postId, Future<(Decision, Map<String, dynamic>?)> Function() check) async {
    try {
      final (decision, verdict) = await check();
      await apply(postId, decision, by: verdict == null ? 'fila' : 'ia', verdict: verdict);
    } catch (e) {
      stderr.writeln('[comunidade] verificação de $postId falhou: $e');
      await apply(postId, VerificationService.pendingReview, by: 'fila');
    }
  }

  /// Aplica uma decisão (da IA ou da equipe) e paga as gotas se aprovado.
  /// Idempotente: um post aprovado não paga duas vezes.
  Future<Map<String, dynamic>?> apply(String postId, Decision d, {required String by, Map<String, dynamic>? verdict}) async {
    final p = await _repo.post(postId);
    if (p == null) return null;
    final wasApproved = p['status'] == 'aprovado';
    await _repo.setVerdict(postId, d.status, by, verdict, d.reason, d.ml);
    if (!d.approved || wasApproved) return null;
    final user = await _users.byId(p['user_id'] as String);
    if (user == null) return null;
    final city = cityById(user['city_id'] as String?);
    final plus = user['plan'] == 'plus';
    if (p['category'] == 'agua') {
      return _rewards.awardVerifiedWater(user['id'] as String, d.ml ?? 0, city, plus: plus, ref: postId);
    }
    return _rewards.award(user['id'] as String, 'post_verificado', city, plus: plus, ref: postId);
  }

  // ---------- selos da semana ----------

  /// Segunda-feira 0h (hora local) da semana de [t], como "dia" (UTC 0h).
  static DateTime weekStart(City city, DateTime t) {
    final local = city.localWallClock(t);
    final day = DateTime.utc(local.year, local.month, local.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  static const tripsCategory = ('rota_fresca', '+ Rotas Frescas');

  static List<(String, String)> get badgeCategories =>
      [for (final c in postCategories) (c.id, c.badge), tripsCategory];

  Future<List<Map<String, dynamic>>> _leaders(City city, DateTime week) async {
    final startUtc = week.subtract(city.utcOffset);
    final endUtc = startUtc.add(const Duration(days: 7));
    final out = <Map<String, dynamic>>[];
    for (final (id, badge) in badgeCategories) {
      final rows = id == tripsCategory.$1
          ? await _repo.weekTrips(week, week.add(const Duration(days: 7)))
          : await _repo.weekScores(id, startUtc, endUtc);
      // Precisa de um mínimo de interações para valer selo.
      final valid = rows.where((r) => (r['score'] as num) >= 3).toList();
      out.add({
        'category': id,
        'badge': badge,
        'leaders': [
          for (final r in valid)
            {
              'userId': r['user_id'],
              'name': _firstName(r['name']),
              'avatarUpdatedAt': r['avatar_updated_at'],
              'score': r['score'],
            }
        ],
      });
    }
    return out;
  }

  /// Fecha a semana anterior (uma vez): grava os vencedores e paga +50 gotas.
  Future<void> _closeWeek(City city, DateTime week) async {
    if (await _repo.weekClosed(week)) return;
    for (final cat in await _leaders(city, week)) {
      final leaders = cat['leaders'] as List;
      if (leaders.isEmpty) continue;
      final w = leaders.first as Map<String, dynamic>;
      if (await _repo.saveBadge(week, cat['category'] as String, w['userId'] as String, w['score'] as int)) {
        final user = await _users.byId(w['userId'] as String);
        await _rewards.award(w['userId'] as String, 'selo', city,
            plus: user?['plan'] == 'plus', ref: '${RewardRepo.day(week)}:${cat['category']}');
      }
    }
  }

  /// Selos em vigor (vencedores da semana passada) e a disputa desta semana.
  Future<Map<String, dynamic>> badges(City city) async {
    final current = weekStart(city, DateTime.now());
    final last = current.subtract(const Duration(days: 7));
    await _closeWeek(city, last);
    final holders = await _repo.badgesOf(last);
    return {
      'week': RewardRepo.day(current),
      'holders': [
        for (final h in holders)
          {
            'category': h['category'],
            'badge': badgeCategories.firstWhere((b) => b.$1 == h['category']).$2,
            'userId': h['user_id'],
            'name': _firstName(h['name']),
            'avatarUpdatedAt': h['avatar_updated_at'],
            'score': h['score'],
          }
      ],
      'race': await _leaders(city, current),
    };
  }

  /// Selos em vigor por pessoa (para mostrar junto do nome nos posts).
  Future<Map<String, List<String>>> badgesByUser(City city) async {
    final last = weekStart(city, DateTime.now()).subtract(const Duration(days: 7));
    final out = <String, List<String>>{};
    for (final h in await _repo.badgesOf(last)) {
      final badge = badgeCategories.firstWhere((b) => b.$1 == h['category']).$2;
      (out[h['user_id'] as String] ??= []).add(badge);
    }
    return out;
  }

  static String _firstName(Object? name) {
    final n = '${name ?? ''}'.trim();
    return n.isEmpty ? 'Alguém' : n.split(' ').first;
  }
}

/// Confere a assinatura do arquivo, não a extensão nem o cabeçalho.
String? imageMime(List<int> b) {
  if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'image/jpeg';
  if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'image/png';
  return null;
}
