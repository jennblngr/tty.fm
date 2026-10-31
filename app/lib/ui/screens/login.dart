import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_info.dart';
import '../../core/api_client.dart';
import '../../core/session.dart';
import '../../core/settings.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  late final _remote = TextEditingController(text: ref.read(settingsProvider).remoteUrl);
  late final _lan = TextEditingController(text: ref.read(settingsProvider).lanUrl);
  final _user = TextEditingController(text: 'admin');
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_remote.text.trim().isEmpty) {
      setState(() => _error = 'Adresse du serveur requise');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .login(remoteUrl: _remote.text, lanUrl: _lan.text, username: _user.text.trim(), password: _pass.text);
    } catch (e) {
      setState(() => _error = errorMessage(e) == 'bad credentials' ? 'Identifiants incorrects' : errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.graphic_eq, size: 56, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 8),
                  Text(appDisplayName, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _remote,
                    decoration: const InputDecoration(
                      labelText: 'Adresse du serveur',
                      hintText: 'nas.tailnet.ts.net:4533',
                      helperText: 'Adresse Tailscale, utilisée partout',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _lan,
                    decoration: const InputDecoration(
                      labelText: 'Adresse locale (optionnelle)',
                      hintText: '192.168.1.20:4533',
                      helperText: 'Préférée à la maison : qualité originale',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _user,
                    decoration: const InputDecoration(labelText: 'Utilisateur', border: OutlineInputBorder()),
                    autofillHints: const [AutofillHints.username],
                    autocorrect: false,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pass,
                    decoration: const InputDecoration(labelText: 'Mot de passe', border: OutlineInputBorder()),
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _busy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Se connecter'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
