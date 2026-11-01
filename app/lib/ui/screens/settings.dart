import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_info.dart';
import '../../core/json_cache.dart';
import '../../core/network.dart';
import '../../core/session.dart';
import '../../core/settings.dart';
import '../../data/library_repository.dart';
import '../../offline/downloads.dart';
import '../dialogs.dart';
import '../widgets/async_view.dart';
import 'offline.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final route = ref.watch(routeProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final quality = ref.watch(streamQualityProvider);

    Widget qualityTile(String title, StreamQuality value, Settings Function(StreamQuality) apply) => ListTile(
      title: Text(title),
      trailing: DropdownButton<StreamQuality>(
        value: value,
        underline: const SizedBox(),
        items: [for (final q in StreamQuality.values) DropdownMenuItem(value: q, child: Text(q.label))],
        onChanged: (q) => q == null ? null : notifier.update(apply(q)),
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('réglages')),
      body: ListView(
        children: [
          _Header('Serveur', action: 'éditer', onAction: () => _editAddresses(context)),
          ListTile(
            leading: Icon(route.link == LinkType.local ? Icons.home_outlined : Icons.public),
            title: Text(route.baseUrl),
            subtitle: Text(
              '${switch (route.link) {
                LinkType.local => 'Réseau local',
                LinkType.remoteWifi => 'À distance (Wi-Fi)',
                LinkType.cellular => 'Réseau mobile',
              }} · ${quality.label}',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Re-détecter le réseau',
              onPressed: () => ref.read(routeProvider.notifier).refresh(),
            ),
          ),
          ListTile(
            dense: true,
            title: const Text('Adresse distante'),
            subtitle: Text(s.remoteUrl),
          ),
          ListTile(
            dense: true,
            title: const Text('Adresse locale'),
            subtitle: Text(s.lanUrl.isEmpty ? 'Aucune' : s.lanUrl),
          ),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Rescanner la bibliothèque'),
            onTap: () => guard(context, () => ref.read(libraryProvider).startScan(), success: 'Scan lancé'),
          ),
          const _Header('Qualité de lecture'),
          qualityTile('Réseau local', s.qualityLocal, (q) => s.copyWith(qualityLocal: q)),
          qualityTile('À distance (Wi-Fi)', s.qualityRemoteWifi, (q) => s.copyWith(qualityRemoteWifi: q)),
          qualityTile('Réseau mobile', s.qualityCellular, (q) => s.copyWith(qualityCellular: q)),
          const _Header('Hors ligne'),
          qualityTile('Qualité des téléchargements', s.downloadQuality, (q) => s.copyWith(downloadQuality: q)),
          SwitchListTile(
            title: const Text('Télécharger en Wi-Fi uniquement'),
            subtitle: const Text('Les téléchargements attendent hors du réseau mobile'),
            value: s.downloadWifiOnly,
            onChanged: (v) => notifier.update(s.copyWith(downloadWifiOnly: v)),
          ),
          const OfflineStatusTile(),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Supprimer tous les téléchargements'),
            onTap: () async {
              if (await confirm(
                context,
                'Supprimer tous les téléchargements ?',
                'Les fichiers seront effacés de cet appareil.',
              )) {
                ref.read(downloadsProvider.notifier).removeAll();
              }
            },
          ),
          const _Header('Apparence'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('Système')),
                ButtonSegment(value: ThemeMode.light, label: Text('Clair')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Sombre')),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (m) => notifier.update(s.copyWith(themeMode: m.first)),
            ),
          ),
          const _Header('Compte'),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('Vider le cache local'),
            onTap: () async {
              await ref.read(jsonCacheProvider).clear();
              if (context.mounted) toast(context, 'Cache vidé');
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Se déconnecter'),
            onTap: () async {
              final lib = ref.read(libraryProvider);
              Navigator.of(context).popUntil((r) => r.isFirst);
              await ref.read(sessionProvider.notifier).logout(revoke: lib.logout);
            },
          ),
          const SizedBox(height: 24),
          Center(child: Text(appDisplayName, style: Theme.of(context).textTheme.labelSmall)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

Future<void> _editAddresses(BuildContext context) async {
  final saved = await showDialog<bool>(context: context, builder: (_) => const _AddressDialog());
  if (saved == true && context.mounted) toast(context, 'Adresses enregistrées');
}

/// Edits the remote and LAN addresses without logging out. Both are probed
/// before saving; if neither answers, the user can still save (e.g. when
/// fixing the remote address from home while Tailscale is off).
class _AddressDialog extends ConsumerStatefulWidget {
  const _AddressDialog();

  @override
  ConsumerState<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends ConsumerState<_AddressDialog> {
  late final _remote = TextEditingController(text: ref.read(settingsProvider).remoteUrl);
  late final _lan = TextEditingController(text: ref.read(settingsProvider).lanUrl);
  final _probe = Dio(
    BaseOptions(connectTimeout: const Duration(seconds: 5), receiveTimeout: const Duration(seconds: 5)),
  );
  bool _busy = false;
  bool _force = false;
  String? _error;

  @override
  void dispose() {
    _remote.dispose();
    _lan.dispose();
    _probe.close();
    super.dispose();
  }

  Future<bool> _answers(String base) async {
    if (base.isEmpty) return false;
    try {
      final r = await _probe.get('$base$apiPrefix/health');
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> _save() async {
    final remote = normalizeUrl(_remote.text);
    final lan = normalizeUrl(_lan.text);
    if (remote.isEmpty) {
      setState(() => _error = 'Adresse distante requise');
      return;
    }
    if (!_force) {
      setState(() {
        _busy = true;
        _error = null;
      });
      final ok = await Future.wait([_answers(remote), _answers(lan)]);
      if (!mounted) return;
      if (!ok[0] && !ok[1]) {
        setState(() {
          _busy = false;
          _force = true;
          _error = 'Aucune adresse ne répond. Vérifie la saisie, ou enregistre quand même.';
        });
        return;
      }
    }
    final s = ref.read(settingsProvider);
    await ref.read(settingsProvider.notifier).update(s.copyWith(remoteUrl: remote, lanUrl: lan));
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    // Editing an address again means it should be probed again.
    void edited(String _) {
      if (_force || _error != null) {
        setState(() {
          _force = false;
          _error = null;
        });
      }
    }

    return AlertDialog(
      title: const Text('Adresses du serveur'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _remote,
              decoration: const InputDecoration(
                labelText: 'Adresse distante',
                hintText: 'nas.tailnet.ts.net:4533',
                helperText: 'Adresse Tailscale, utilisée partout',
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              onChanged: edited,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _lan,
              decoration: const InputDecoration(
                labelText: 'Adresse locale (optionnelle)',
                hintText: '192.168.1.20:4533',
                helperText: 'Préférée à la maison',
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              onChanged: edited,
              onSubmitted: (_) {
                if (!_busy) _save();
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_force ? 'Enregistrer quand même' : 'Enregistrer'),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title, {this.action, this.onAction});
  final String title;

  /// Optional action shown as `[action]` at the end of the line.
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: _title(context),
    );
    if (action == null) return header;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: header),
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: TextButton(onPressed: onAction, child: Text('[$action]')),
        ),
      ],
    );
  }

  Widget _title(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: '\$ ',
          style: TextStyle(color: Theme.of(context).colorScheme.primary),
        ),
        TextSpan(text: title.toLowerCase()),
      ],
    ),
    style: const TextStyle(fontWeight: FontWeight.w700),
  );
}
