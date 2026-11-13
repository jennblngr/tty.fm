import 'dart:io';

import 'package:material_ui/material_ui.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../playback/audio_engine.dart';
import '../../state/playback.dart';
import '../../state/remote.dart';
import '../format.dart';
import '../widgets/async_view.dart';
import '../widgets/cover.dart';

IconData platformIcon(String platform) => switch (platform) {
  'android' || 'ios' => Icons.smartphone,
  'macos' || 'windows' || 'linux' => Icons.laptop_mac,
  _ => Icons.devices_other,
};

void openRemotePlayer(BuildContext context, int deviceId) => Navigator.of(
  context,
  rootNavigator: true,
).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => RemotePlayerScreen(deviceId)));

/// Lists this account's online devices: see what each plays, control it,
/// or move playback between devices.
Future<void> showDevicesSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  useRootNavigator: true,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => const _DevicesSheet(),
);

class _DevicesSheet extends ConsumerWidget {
  const _DevicesSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remote = ref.watch(remoteDevicesProvider);
    final local = ref.watch(playbackStateProvider);
    final rc = ref.read(remoteControlProvider);
    final scheme = Theme.of(context).colorScheme;
    final selfId = remote.selfId;

    Widget nowLine(String? title, String? artist, bool playing) => Text(
      title == null ? 'Inactif' : '${playing ? '▶︎ ' : '❙❙ '}$title · $artist',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Appareils', style: Theme.of(context).textTheme.titleLarge),
          ),
          ListTile(
            leading: Icon(
              Platform.isAndroid || Platform.isIOS ? Icons.smartphone : Icons.laptop_mac,
              color: scheme.primary,
            ),
            title: const Text('Cet appareil'),
            subtitle: nowLine(local.current?.title, local.current?.artist, local.playing),
          ),
          if (!remote.connected)
            const ListTile(leading: Icon(Icons.cloud_off), title: Text('Connexion en direct indisponible'))
          else if (remote.devices.isEmpty)
            const ListTile(
              leading: Icon(Icons.devices_other),
              title: Text('Aucun autre appareil connecté'),
              subtitle: Text('Ouvrez l\'app sur un autre appareil pour le voir ici.'),
            ),
          for (final d in remote.devices.values)
            ListTile(
              leading: Icon(platformIcon(d.platform)),
              title: Text(d.name),
              subtitle: nowLine(d.state?.track?.title, d.state?.track?.artist, d.state?.playing ?? false),
              onTap: () {
                Navigator.pop(context);
                openRemotePlayer(context, d.id);
              },
              trailing: PopupMenuButton<VoidCallback>(
                tooltip: 'Transférer',
                icon: const Icon(Icons.swap_horiz),
                onSelected: (f) => f(),
                itemBuilder: (_) => [
                  if (d.state?.track != null && selfId != null)
                    PopupMenuItem(
                      value: () {
                        rc.transfer(from: d.id, to: selfId);
                        Navigator.pop(context);
                      },
                      child: const ListTile(leading: Icon(Icons.download), title: Text('Écouter ici'), dense: true),
                    ),
                  if (local.current != null && selfId != null)
                    PopupMenuItem(
                      value: () {
                        rc.transfer(from: selfId, to: d.id);
                        Navigator.pop(context);
                        toast(context, 'Lecture envoyée vers ${d.name}');
                      },
                      child: ListTile(
                        leading: const Icon(Icons.upload),
                        title: Text('Envoyer vers ${d.name}'),
                        dense: true,
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Full player controlling another device.
class RemotePlayerScreen extends ConsumerWidget {
  const RemotePlayerScreen(this.deviceId, {super.key});
  final int deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remote = ref.watch(remoteDevicesProvider);
    final d = remote.devices[deviceId];
    final rc = ref.read(remoteControlProvider);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    void cmd(String action, [Map<String, dynamic>? args]) => rc.send(deviceId, action, args);

    final s = d?.state;
    final track = s?.track;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.keyboard_arrow_down), onPressed: () => Navigator.pop(context)),
        title: Text(d == null ? 'Appareil déconnecté' : 'Sur ${d.name}'),
        actions: [
          if (d != null && track != null && remote.selfId != null)
            TextButton.icon(
              icon: const Icon(Icons.download),
              label: const Text('Écouter ici'),
              onPressed: () {
                rc.transfer(from: deviceId, to: remote.selfId!);
                Navigator.pop(context);
              },
            ),
        ],
      ),
      body: d == null
          ? const Center(child: Text('Cet appareil n\'est plus connecté.'))
          : track == null
          ? const Center(child: Text('Rien en lecture sur cet appareil.'))
          : LayoutBuilder(
              builder: (context, box) {
                final wide = box.maxWidth >= 900;
                final player = Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 520),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CoverImage(
                            track.coverId,
                            size: (box.maxWidth - 48).clamp(120.0, (box.maxHeight - 340).clamp(120.0, 420.0)),
                            radius: 12,
                          ),
                          const SizedBox(height: 20),
                          Text(track.title, style: text.titleLarge, textAlign: TextAlign.center),
                          Text(track.artist, style: text.titleMedium?.copyWith(color: scheme.primary)),
                          const SizedBox(height: 8),
                          _RemoteSeekBar(state: s!, onSeek: (ms) => cmd('seek', {'ms': ms})),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              IconButton(
                                icon: Icon(Icons.shuffle, color: s.shuffle ? scheme.primary : null),
                                onPressed: () => cmd('shuffle', {'on': !s.shuffle}),
                              ),
                              IconButton(
                                iconSize: 36,
                                icon: const Icon(Icons.skip_previous),
                                onPressed: () => cmd('previous'),
                              ),
                              IconButton.filled(
                                iconSize: 44,
                                icon: Icon(s.playing ? Icons.pause : Icons.play_arrow),
                                onPressed: () => cmd(s.playing ? 'pause' : 'play'),
                              ),
                              IconButton(iconSize: 36, icon: const Icon(Icons.skip_next), onPressed: () => cmd('next')),
                              IconButton(
                                icon: Icon(
                                  s.repeat == RepeatMode.one ? Icons.repeat_one : Icons.repeat,
                                  color: s.repeat != RepeatMode.off ? scheme.primary : null,
                                ),
                                onPressed: () => cmd('repeat', {
                                  'mode': RepeatMode.values[(s.repeat.index + 1) % RepeatMode.values.length].name,
                                }),
                              ),
                            ],
                          ),
                          _RemoteVolume(value: s.volume, onChanged: (v) => cmd('volume', {'value': v})),
                        ],
                      ),
                    ),
                  ),
                );
                final queue = _RemoteQueue(
                  state: s,
                  onJump: (i) => cmd('jump', {'index': i}),
                  onRemove: (i) => cmd('remove', {'index': i}),
                );
                return wide
                    ? Row(
                        children: [
                          Expanded(child: player),
                          const VerticalDivider(width: 1),
                          SizedBox(width: 420, child: queue),
                        ],
                      )
                    : DefaultTabController(
                        length: 2,
                        child: Column(
                          children: [
                            const TabBar(
                              tabs: [
                                Tab(text: 'Lecture'),
                                Tab(text: 'File d\'attente'),
                              ],
                            ),
                            Expanded(child: TabBarView(children: [player, queue])),
                          ],
                        ),
                      );
              },
            ),
    );
  }
}

/// Seek bar whose position is extrapolated between state reports.
class _RemoteSeekBar extends StatefulWidget {
  const _RemoteSeekBar({required this.state, required this.onSeek});
  final RemoteState state;
  final void Function(int ms) onSeek;

  @override
  State<_RemoteSeekBar> createState() => _RemoteSeekBarState();
}

class _RemoteSeekBarState extends State<_RemoteSeekBar> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: Stream.periodic(const Duration(milliseconds: 500)),
      builder: (context, _) {
        final s = widget.state;
        final max = s.duration.inMilliseconds.toDouble().clamp(1.0, double.infinity);
        final value = (_drag ?? s.positionNow().inMilliseconds.toDouble()).clamp(0.0, max);
        final style = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12);
        return Column(
          children: [
            Slider(
              value: value,
              max: max,
              onChanged: (v) => setState(() => _drag = v),
              onChangeEnd: (v) {
                widget.onSeek(v.round());
                setState(() => _drag = null);
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(formatDuration(Duration(milliseconds: value.round())), style: style),
                  Text(formatDuration(s.duration), style: style),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Volume slider that only sends the final value (and a few while dragging).
class _RemoteVolume extends StatefulWidget {
  const _RemoteVolume({required this.value, required this.onChanged});
  final double value;
  final void Function(double) onChanged;

  @override
  State<_RemoteVolume> createState() => _RemoteVolumeState();
}

class _RemoteVolumeState extends State<_RemoteVolume> {
  double? _drag;
  DateTime _lastSent = DateTime(0);

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.volume_down, size: 20),
      Expanded(
        child: Slider(
          value: (_drag ?? widget.value).clamp(0.0, 1.0),
          onChanged: (v) {
            setState(() => _drag = v);
            if (DateTime.now().difference(_lastSent) > const Duration(milliseconds: 150)) {
              _lastSent = DateTime.now();
              widget.onChanged(v);
            }
          },
          onChangeEnd: (v) {
            widget.onChanged(v);
            setState(() => _drag = null);
          },
        ),
      ),
      const Icon(Icons.volume_up, size: 20),
    ],
  );
}

class _RemoteQueue extends StatelessWidget {
  const _RemoteQueue({required this.state, required this.onJump, required this.onRemove});
  final RemoteState state;
  final void Function(int index) onJump;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final scheme = Theme.of(context).colorScheme;
    final hidden = s.queueLength - s.queueOffset - s.queue.length;
    return ListView(
      children: [
        if (s.queueOffset > 0)
          ListTile(
            dense: true,
            title: Text('${s.queueOffset} titre(s) déjà joué(s)', style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
        for (var k = 0; k < s.queue.length; k++)
          () {
            final i = s.queueOffset + k;
            final t = s.queue[k];
            final current = i == s.index;
            return Dismissible(
              key: ValueKey('remote-$i-${t.id}'),
              direction: current ? DismissDirection.none : DismissDirection.endToStart,
              background: Container(
                color: scheme.errorContainer,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 16),
                child: const Icon(Icons.delete_outline),
              ),
              onDismissed: (_) => onRemove(i),
              child: ListTile(
                dense: true,
                selected: current,
                leading: CoverImage(t.coverId, size: 40),
                title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                onTap: () => onJump(i),
              ),
            );
          }(),
        if (hidden > 0)
          ListTile(
            dense: true,
            title: Text('… et $hidden autre(s)', style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
      ],
    );
  }
}

/// Shown instead of the mini player when nothing plays here but another
/// device is playing: tap to control it.
class RemoteMiniBar extends ConsumerWidget {
  const RemoteMiniBar(this.device, {super.key});
  final RemoteDevice device;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = device.state!;
    final t = s.track!;
    final scheme = Theme.of(context).colorScheme;
    final rc = ref.read(remoteControlProvider);
    return Material(
      color: scheme.secondaryContainer,
      child: InkWell(
        onTap: () => openRemotePlayer(context, device.id),
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              const SizedBox(width: 10),
              CoverImage(t.coverId, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Row(
                      children: [
                        Icon(platformIcon(device.platform), size: 14, color: scheme.onSecondaryContainer),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Sur ${device.name}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(s.playing ? Icons.pause : Icons.play_arrow),
                onPressed: () => rc.send(device.id, s.playing ? 'pause' : 'play'),
              ),
              IconButton(
                icon: const Icon(Icons.devices),
                tooltip: 'Appareils',
                onPressed: () => showDevicesSheet(context),
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}
