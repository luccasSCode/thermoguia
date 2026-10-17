import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/common.dart';
import '../data/route_models.dart';
import 'routes_controller.dart';
import '../../../core/widgets/thermo_loader.dart';

Future<Place?> showSearchSheet(BuildContext context) => showModalBottomSheet<Place>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _SearchSheet(),
    );

class _SearchSheet extends ConsumerStatefulWidget {
  const _SearchSheet();

  @override
  ConsumerState<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends ConsumerState<_SearchSheet> {
  final _q = TextEditingController();
  Timer? _debounce;
  List<Place> _results = const [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    // A política do Nominatim pede no máximo 1 busca por segundo.
    _debounce = Timer(const Duration(milliseconds: 600), () => _search(text));
  }

  Future<void> _search(String text) async {
    if (text.trim().length < 3) {
      setState(() => _results = const []);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await ref.read(routesRepositoryProvider).search(text.trim());
      if (mounted) setState(() => _results = r);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(Place p) async {
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Salvar como'),
        children: [
          for (final l in const ['Casa', 'Trabalho', 'Faculdade', 'Outro'])
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, l), child: Text(l)),
        ],
      ),
    );
    if (label == null) return;
    await ref.read(routesRepositoryProvider).savePlace(p, label);
    if (mounted) {
      setState(() {});
      showMessage(context, '${p.name} salvo como $label.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = ref.read(routesRepositoryProvider).savedPlaces;
    final showSaved = _q.text.trim().length < 3;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: TextField(
                controller: _q,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                onSubmitted: _search,
                decoration: InputDecoration(
                  hintText: 'Para onde você vai?',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _loading
                      ? const Padding(
                          padding: EdgeInsets.all(14),
                          child: ThermoLoader.inline(size: 18),
                        )
                      : null,
                ),
              ),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
            Expanded(
              child: ListView(
                children: [
                  if (showSaved && saved.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Busque um endereço, bairro ou lugar. Você pode salvar Casa e Trabalho para ir mais rápido.'),
                    ),
                  if (showSaved)
                    for (final p in saved)
                      ListTile(
                        leading: Icon(p.savedAs == 'Casa' ? Icons.home_outlined : Icons.bookmark_outline),
                        title: Text(p.savedAs!),
                        subtitle: Text(p.name),
                        onTap: () => Navigator.pop(context, p),
                        trailing: IconButton(
                          tooltip: 'Remover',
                          icon: const Icon(Icons.close),
                          onPressed: () async {
                            await ref.read(routesRepositoryProvider).removePlace(p.savedAs!);
                            setState(() {});
                          },
                        ),
                      ),
                  if (!showSaved && !_loading && _results.isEmpty && _error == null)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Nenhum lugar encontrado em Manaus com esse nome. Tente o nome da rua ou do bairro.'),
                    ),
                  for (final p in _results)
                    ListTile(
                      leading: const Icon(Icons.place_outlined),
                      title: Text(p.name),
                      subtitle: p.address.isEmpty ? null : Text(p.address, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.pop(context, p),
                      trailing: IconButton(
                        tooltip: 'Salvar lugar',
                        icon: const Icon(Icons.bookmark_add_outlined),
                        onPressed: () => _save(p),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
