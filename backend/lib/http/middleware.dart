import 'dart:io';

import 'package:shelf/shelf.dart';

import '../services/auth_service.dart';
import 'http_utils.dart';

const _corsHeaders = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
  'access-control-allow-headers': 'authorization, content-type',
};

Middleware cors() => (inner) => (req) async {
      if (req.method == 'OPTIONS') return Response.ok('', headers: _corsHeaders);
      final res = await inner(req);
      return res.change(headers: _corsHeaders);
    };

Middleware errorHandler() => (inner) => (req) async {
      try {
        return await inner(req);
      } on ApiError catch (e) {
        return jsonResponse({'error': e.message}, status: e.status);
      } catch (e, st) {
        stderr.writeln('[erro] ${req.method} ${req.requestedUri}: $e\n$st');
        return jsonResponse({'error': 'Erro interno. Tente novamente em instantes.'}, status: 500);
      }
    };

const _publicPaths = {'health', 'cities', 'plans', 'plans/compare'};

Middleware authGuard(AuthService auth) => (inner) => (req) {
      final path = req.url.path;
      // admin/ tem chave própria (ADMIN_TOKEN), conferida nas rotas.
      // acompanhar/ é a página do responsável: o token secreto do link é a chave.
      if (_publicPaths.contains(path) ||
          path.startsWith('auth/') ||
          path.startsWith('admin/') ||
          path.startsWith('acompanhar/')) {
        return inner(req);
      }
      final header = req.headers['authorization'];
      if (header == null || !header.startsWith('Bearer ')) {
        throw ApiError(401, 'Sessão expirada. Entre novamente.');
      }
      final userId = auth.verifyToken(header.substring(7));
      return inner(req.change(context: {'userId': userId}));
    };
