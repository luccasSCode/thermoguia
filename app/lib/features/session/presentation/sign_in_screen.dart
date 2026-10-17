import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thermo_core/thermo_core.dart';

import '../../../core/widgets/common.dart';
import 'persona_picker.dart';
import 'session_controller.dart';
import '../../../core/widgets/thermo_loader.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _register = false;
  bool _busy = false;
  Persona _persona = Persona.pedestre;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final s = ref.read(sessionProvider);
    try {
      if (_register) {
        await s.register(_name.text.trim(), _email.text.trim(), _password.text, _persona);
      } else {
        await s.login(_email.text.trim(), _password.text);
      }
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Voltar',
          onPressed: () => context.go('/boas-vindas'),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            children: [
              Text(_register ? 'Criar conta' : 'Entrar', style: t.headlineMedium),
              const SizedBox(height: 24),
              if (_register) ...[
                TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nome'),
                ),
                const SizedBox(height: 16),
              ],
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: 'E-mail'),
                validator: (v) => (v ?? '').contains('@') ? null : 'Informe um e-mail válido.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _password,
                obscureText: true,
                autofillHints: const [AutofillHints.password],
                decoration: const InputDecoration(labelText: 'Senha'),
                validator: (v) => (v ?? '').length >= 8 ? null : 'Use pelo menos 8 caracteres.',
              ),
              if (_register) ...[
                const SizedBox(height: 24),
                Text('Seu perfil de deslocamento', style: t.titleMedium),
                const SizedBox(height: 12),
                PersonaPicker(value: _persona, onChanged: (p) => setState(() => _persona = p)),
              ],
              const SizedBox(height: 32),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const ThermoLoader.inline()
                    : Text(_register ? 'Criar conta' : 'Entrar'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _register = !_register),
                child: Text(_register ? 'Já tenho conta' : 'Criar uma conta com e-mail'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
