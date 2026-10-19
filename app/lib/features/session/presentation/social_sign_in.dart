import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:thermo_core/thermo_core.dart';

import '../../../core/widgets/common.dart';
import '../../../core/widgets/thermo_loader.dart';
import 'session_controller.dart';

/// Provedores de login social mostrados na tela de boas-vindas.
enum SocialProvider {
  google('Google', 'Entrar com uma conta Google'),
  facebook('Facebook', 'Entrar com o Facebook');

  const SocialProvider(this.brand, this.label);
  final String brand;
  final String label;
}

/// Logos oficiais, sem fundo. O "G" do Google mantém as quatro cores nos dois
/// temas (exigência da marca); o Facebook usa o azul da marca no tema
/// claro e branco no escuro, como pede o guia de marca para fundos escuros.
class SocialLogo extends StatelessWidget {
  const SocialLogo(this.provider, {super.key, this.size = 22});
  final SocialProvider provider;
  final double size;

  static const _google = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
<path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>
<path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>
<path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/>
<path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>
</svg>''';

  static const _facebook = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
<path d="M9.101 23.691v-7.98H6.627v-3.667h2.474v-1.58c0-4.085 1.848-5.978 5.858-5.978.401 0 .955.042 1.468.103a8.68 8.68 0 0 1 1.141.195v3.325a8.623 8.623 0 0 0-.653-.036 26.805 26.805 0 0 0-.733-.009c-.707 0-1.259.096-1.675.309a1.686 1.686 0 0 0-.679.622c-.258.42-.374.995-.374 1.752v1.297h3.919l-.386 2.103-.287 1.564h-3.246v8.245C19.396 23.238 24 18.179 24 12.044c0-6.627-5.373-12-12-12s-12 5.373-12 12c0 5.628 3.874 10.35 9.101 11.647Z"/>
</svg>''';


  static const facebookBlue = Color(0xFF0866FF);

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final (svg, color) = switch (provider) {
      SocialProvider.google => (_google, null),
      SocialProvider.facebook => (_facebook, dark ? Colors.white : facebookBlue),
    };
    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      colorFilter: color == null ? null : ColorFilter.mode(color, BlendMode.srcIn),
      excludeFromSemantics: true,
    );
  }
}

/// Os botões de login social, um embaixo do outro. Entram de verdade pelo
/// Google ou Facebook (o servidor conduz o login pelo navegador), a menos que
/// [onPressed] seja dado: aí são só visuais e chamam [onPressed].
class SocialSignInButtons extends ConsumerStatefulWidget {
  const SocialSignInButtons({super.key, this.persona, this.onPressed});

  /// Perfil escolhido no cadastro, usado se a conta for nova.
  final Persona? persona;

  /// Substitui o login social por esta ação.
  final VoidCallback? onPressed;

  @override
  ConsumerState<SocialSignInButtons> createState() => _SocialSignInButtonsState();
}

class _SocialSignInButtonsState extends ConsumerState<SocialSignInButtons> {
  SocialProvider? _busy;

  Future<void> _login(SocialProvider p) async {
    setState(() => _busy = p);
    try {
      await ref.read(sessionProvider).socialLogin(p.name, p.brand, persona: widget.persona);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final p in SocialProvider.values) ...[
            OutlinedButton(
              onPressed: widget.onPressed ?? (_busy == null ? () => _login(p) : null),
              child: Row(children: [
                if (_busy == p) const ThermoLoader.inline() else SocialLogo(p),
                const SizedBox(width: 12),
                Expanded(child: Text(p.label, textAlign: TextAlign.center)),
                // Mantém o texto centralizado em relação ao botão.
                const SizedBox(width: 34),
              ]),
            ),
            if (p != SocialProvider.values.last) const SizedBox(height: 10),
          ],
        ],
      );
}
