import 'package:flutter/material.dart';

import 'screens/home.dart';
import 'screens/library.dart';
import 'screens/playlists.dart';
import 'screens/search.dart';
import 'widgets/mini_player.dart';

class _Tab {
  const _Tab(this.label, this.icon, this.selectedIcon, this.root);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget root;
}

const _tabs = [
  _Tab('Accueil', Icons.home_outlined, Icons.home, HomeScreen()),
  _Tab('Bibliothèque', Icons.library_music_outlined, Icons.library_music, LibraryScreen()),
  _Tab('Recherche', Icons.search, Icons.search, SearchScreen()),
  _Tab('Playlists', Icons.queue_music_outlined, Icons.queue_music, PlaylistsScreen()),
];

/// Top-level layout: one nested navigator per tab (each keeps its own
/// history), a navigation bar or rail depending on width, and the mini
/// player always visible.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  final _keys = List.generate(_tabs.length, (_) => GlobalKey<NavigatorState>());

  void _select(int i) {
    if (i == _index) {
      // Tapping the active tab pops back to its root.
      _keys[i].currentState?.popUntil((r) => r.isFirst);
    } else {
      setState(() => _index = i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final body = IndexedStack(
      index: _index,
      children: [
        for (var i = 0; i < _tabs.length; i++)
          Navigator(
            key: _keys[i],
            onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => _tabs[i].root),
          ),
      ],
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = _keys[_index].currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
        } else if (_index != 0) {
          setState(() => _index = 0);
        }
      },
      child: Scaffold(
        body: Column(
          children: [
            Expanded(
              child: wide
                  ? Row(children: [
                      NavigationRail(
                        selectedIndex: _index,
                        onDestinationSelected: _select,
                        labelType: NavigationRailLabelType.all,
                        destinations: [
                          for (final t in _tabs)
                            NavigationRailDestination(
                                icon: Icon(t.icon), selectedIcon: Icon(t.selectedIcon), label: Text(t.label)),
                        ],
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: body),
                    ])
                  : body,
            ),
            const MiniPlayer(),
          ],
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: _select,
                height: 64,
                destinations: [
                  for (final t in _tabs)
                    NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selectedIcon), label: t.label),
                ],
              ),
      ),
    );
  }
}
