import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../rewards/rewards_controller.dart';

class HydrationState {
  const HydrationState({required this.day, required this.totalMl, required this.entries});
  final String day;
  final int totalMl;
  final List<(DateTime, int)> entries;

  DateTime? get lastDrink => entries.isEmpty ? null : entries.last.$1;
}

/// Registro de água do dia. Funciona offline; envia ao servidor quando possível.
class HydrationController extends Notifier<HydrationState> {
  String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
  }

  String get _key => 'hydration_${_today()}';

  @override
  HydrationState build() {
    final list = ref.read(localStoreProvider).readList(_key);
    final entries = list
        .map((e) => (DateTime.parse((e as Map)['at'] as String).toLocal(), (e['ml'] as num).toInt()))
        .toList();
    return HydrationState(
      day: _today(),
      totalMl: entries.fold(0, (a, e) => a + e.$2),
      entries: entries,
    );
  }

  /// Recarrega se o dia virou com o app aberto.
  void ensureToday() {
    if (state.day != _today()) state = build();
  }

  Future<void> add(int ml) async {
    ensureToday();
    final now = DateTime.now();
    final entries = [...state.entries, (now, ml)];
    state = HydrationState(day: state.day, totalMl: state.totalMl + ml, entries: entries);
    await ref.read(localStoreProvider).writeList(
          _key,
          entries.map((e) => {'at': e.$1.toUtc().toIso8601String(), 'ml': e.$2}).toList(),
        );
    try {
      final res = await ref.read(apiClientProvider).post('/hydration', {
        'amountMl': ml,
        'loggedAt': now.toUtc().toIso8601String(),
      });
      ref.read(rewardsProvider.notifier).announceFrom(res);
    } catch (_) {}
  }

  Future<void> undoLast() async {
    if (state.entries.isEmpty) return;
    final entries = [...state.entries]..removeLast();
    state = HydrationState(day: state.day, totalMl: entries.fold(0, (a, e) => a + e.$2), entries: entries);
    await ref.read(localStoreProvider).writeList(
          _key,
          entries.map((e) => {'at': e.$1.toUtc().toIso8601String(), 'ml': e.$2}).toList(),
        );
  }
}

final hydrationProvider = NotifierProvider<HydrationController, HydrationState>(HydrationController.new);
