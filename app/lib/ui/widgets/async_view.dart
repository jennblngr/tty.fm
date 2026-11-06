import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../theme.dart';

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

/// Toast for a reversible action: 5 s with "[annuler]", no confirmation
/// (Menus-Contextuels, fiche 01 « retour · archiver »): surface background,
/// 8 px corners, 12 × 16 px padding, 420 px at most, "[annuler]" in bold
/// green on the right.
void toastUndo(BuildContext context, String msg, VoidCallback undo) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final c = Tty.of(context);
  final width = MediaQuery.sizeOf(context).width - 32;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        width: width < 420 ? width : 420,
        backgroundColor: c.surface,
        elevation: 0,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        content: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(msg, style: TextStyle(color: c.text, fontSize: 13, height: 1.5)),
              ),
              InkWell(
                onTap: () {
                  messenger.hideCurrentSnackBar();
                  undo();
                },
                child: Padding(
                  // 12 px above and below, 16 px on the right: the toast's
                  // padding, made part of the tap target.
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Text(
                    '[annuler]',
                    style: TextStyle(color: c.green, fontWeight: FontWeight.w700, fontSize: 13, height: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
