import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_info.dart';
import '../../core/json_cache.dart';
import '../../core/network.dart';
import '../../core/session.dart';
import '../../core/settings.dart';
import '../../data/library_repository.dart';
import '../widgets/async_view.dart';

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
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(children: [
        const _Header('Serveur'),
        ListTile(
          leading: Icon(route.link == LinkType.local ? Icons.home_outlined : Icons.public),
          title: Text(route.baseUrl),
          subtitle: Text('${switch (route.link) {
            LinkType.local => 'Réseau local',
            LinkType.remoteWifi => 'À distance (Wi-Fi)',
            LinkType.cellular => 'Réseau mobile',
          }} · ${quality.label}'),
          trailing: IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Re-détecter le réseau',
            onPressed: () => ref.read(routeProvider.notifier).refresh(),
          ),
        ),
        if (s.lanUrl.isNotEmpty) ListTile(dense: true, title: const Text('Adresse locale'), subtitle: Text(s.lanUrl)),
        ListTile(dense: true, title: const Text('Adresse distante'), subtitle: Text(s.remoteUrl)),
        ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('Rescanner la bibliothèque'),
          onTap: () => guard(context, () => ref.read(libraryProvider).startScan(), success: 'Scan lancé'),
        ),
        const _Header('Qualité de lecture'),
        qualityTile('Réseau local', s.qualityLocal, (q) => s.copyWith(qualityLocal: q)),
        qualityTile('À distance (Wi-Fi)', s.qualityRemoteWifi, (q) => s.copyWith(qualityRemoteWifi: q)),
        qualityTile('Réseau mobile', s.qualityCellular, (q) => s.copyWith(qualityCellular: q)),
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
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(title, style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
      );
}
