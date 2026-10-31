import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';

/// Renders an AsyncValue: data as soon as any is available (cached data
/// stays on screen while refreshing or if the refresh fails), a spinner on
/// a cold start, an error with retry otherwise.
class AsyncView<T> extends StatelessWidget {
  const AsyncView(this.value, {super.key, required this.builder, this.onRetry});

  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (value.hasValue) return builder(value.requireValue);
    if (value.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 40),
              const SizedBox(height: 12),
              Text(errorMessage(value.error!), textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 12),
                FilledButton.tonal(onPressed: onRetry, child: const Text('Réessayer')),
              ],
            ],
          ),
        ),
      );
    }
    return const Center(child: CircularProgressIndicator());
  }
}

/// Shows a short message at the bottom of the screen.
void toast(BuildContext context, String msg) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
}

/// Runs an action and reports failures as a toast.
Future<void> guard(BuildContext context, Future<void> Function() action, {String? success}) async {
  try {
    await action();
    if (success != null && context.mounted) toast(context, success);
  } catch (e) {
    if (context.mounted) toast(context, errorMessage(e));
  }
}
