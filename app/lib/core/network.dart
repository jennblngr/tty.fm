import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_info.dart';
import 'settings.dart';

enum LinkType { local, remoteWifi, cellular }

/// Which server address to use right now and how we reach it.
@immutable
class ServerRoute {
  const ServerRoute(this.baseUrl, this.link);
  final String baseUrl;
  final LinkType link;

  @override
  bool operator ==(Object other) => other is ServerRoute && other.baseUrl == baseUrl && other.link == link;
  @override
  int get hashCode => Object.hash(baseUrl, link);
}

/// Resolves the route: the LAN address if it answers quickly on Wi-Fi or
/// Ethernet, otherwise the remote (Tailscale) address. Re-evaluated on
/// connectivity changes.
class RouteNotifier extends Notifier<ServerRoute> {
  final _probe = Dio(
    BaseOptions(connectTimeout: const Duration(milliseconds: 600), receiveTimeout: const Duration(milliseconds: 600)),
  );
  StreamSubscription<List<ConnectivityResult>>? _sub;
  List<ConnectivityResult> _conn = const [ConnectivityResult.wifi];

  @override
  ServerRoute build() {
    final s = ref.watch(settingsProvider);
    _sub ??= Connectivity().onConnectivityChanged.listen((c) {
      _conn = c;
      refresh();
    });
    ref.onDispose(() {
      _sub?.cancel();
      _sub = null;
    });
    Connectivity().checkConnectivity().then((c) {
      _conn = c;
      refresh();
    });
    return ServerRoute(s.remoteUrl, s.lanUrl.isEmpty ? LinkType.local : LinkType.remoteWifi);
  }

  bool get _cellularOnly =>
      _conn.contains(ConnectivityResult.mobile) &&
      !_conn.contains(ConnectivityResult.wifi) &&
      !_conn.contains(ConnectivityResult.ethernet);

  Future<void> refresh() async {
    final s = ref.read(settingsProvider);
    if (_cellularOnly) {
      state = ServerRoute(s.remoteUrl, LinkType.cellular);
      return;
    }
    if (s.lanUrl.isEmpty) {
      // Single address: treat Wi-Fi/Ethernet as local.
      state = ServerRoute(s.remoteUrl, LinkType.local);
      return;
    }
    try {
      final r = await _probe.get('${s.lanUrl}$apiPrefix/health');
      if (r.statusCode == 200) {
        state = ServerRoute(s.lanUrl, LinkType.local);
        return;
      }
    } catch (_) {}
    state = ServerRoute(s.remoteUrl, LinkType.remoteWifi);
  }
}

final routeProvider = NotifierProvider<RouteNotifier, ServerRoute>(RouteNotifier.new);

/// Quality to request for the current route.
final streamQualityProvider = Provider<StreamQuality>((ref) {
  final s = ref.watch(settingsProvider);
  return switch (ref.watch(routeProvider).link) {
    LinkType.local => s.qualityLocal,
    LinkType.remoteWifi => s.qualityRemoteWifi,
    LinkType.cellular => s.qualityCellular,
  };
});
