import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_info.dart';
import 'network.dart';
import 'session.dart';

/// Persistent WebSocket to the server's live hub (`/ws`): change
/// notifications, other devices' playback state and remote commands.
/// Reconnects with backoff, and whenever the server address or the token
/// changes. Messages are JSON objects with a "type" field.
class LiveConnection {
  LiveConnection(this._url, this._token) {
    if (_token.isNotEmpty) _connect();
  }

  final String _url;
  final String _token;
  final _messages = StreamController<Map<String, dynamic>>.broadcast();
  final _connected = StreamController<bool>.broadcast();
  WebSocket? _ws;
  Timer? _retry;
  var _attempt = 0;
  var _closed = false;

  Stream<Map<String, dynamic>> get messages => _messages.stream;
  Stream<bool> get connectedChanges => _connected.stream;
  bool get isConnected => _ws != null;

  static const _backoff = [1, 2, 5, 10, 30];

  Future<void> _connect() async {
    if (_closed) return;
    try {
      final ws = await WebSocket.connect(
        _url,
        headers: {'Authorization': 'Bearer $_token'},
      ).timeout(const Duration(seconds: 8));
      if (_closed) {
        ws.close();
        return;
      }
      ws.pingInterval = const Duration(seconds: 25);
      _ws = ws;
      _attempt = 0;
      _connected.add(true);
      ws.listen(
        (data) {
          if (data is! String) return;
          try {
            final m = jsonDecode(data);
            if (m is Map<String, dynamic>) _messages.add(m);
          } catch (_) {}
        },
        onDone: _lost,
        onError: (_) => _lost(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _lost() {
    if (_ws == null) return;
    _ws = null;
    if (!_connected.isClosed) _connected.add(false);
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_closed) return;
    _retry?.cancel();
    _retry = Timer(Duration(seconds: _backoff[_attempt.clamp(0, _backoff.length - 1)]), _connect);
    _attempt++;
  }

  /// Sends a message if connected; returns false otherwise.
  bool send(Map<String, dynamic> msg) {
    final ws = _ws;
    if (ws == null) return false;
    ws.add(jsonEncode(msg));
    return true;
  }

  void dispose() {
    _closed = true;
    _retry?.cancel();
    _ws?.close();
    _ws = null;
    _messages.close();
    _connected.close();
  }
}

final liveConnectionProvider = Provider<LiveConnection>((ref) {
  final base = ref.watch(routeProvider.select((r) => r.baseUrl));
  final token = ref.watch(tokenProvider);
  final url = '${base.replaceFirst(RegExp('^http'), 'ws')}$apiPrefix/ws';
  final c = LiveConnection(url, token);
  ref.onDispose(c.dispose);
  return c;
});
