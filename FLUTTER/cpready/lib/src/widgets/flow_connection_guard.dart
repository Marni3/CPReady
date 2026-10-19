/// BLE guard for the practice flow.
///
/// Every step up to the countdown is wrapped in [FlowConnectionGuard]: while the
/// link is not connected — including a drop after the flow has started — the app
/// shows the "connection lost" notice and returns to the Home tab, so a session
/// can never carry on against a board that is not there.
///
/// Live Practice is not wrapped: a running session has state of its own to shut
/// down, so it calls [abortFlowToHome] itself.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/config.dart';
import '../core/app_scope.dart';
import '../core/ble/ble_controller.dart';

/// Shows the link-lost notice, then closes the flow and returns to Home.
Future<void> abortFlowToHome(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text(AppStrings.flowLinkLostTitle),
      content: const Text(AppStrings.flowLinkLostBody),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text(AppStrings.flowLinkLostAction),
        ),
      ],
    ),
  );

  if (!context.mounted) return;
  context.go(AppRoutes.home);
}

/// Returns to Home as soon as the BLE link is gone.
class FlowConnectionGuard extends StatefulWidget {
  const FlowConnectionGuard({super.key, required this.child});

  /// The flow screen being guarded.
  final Widget child;

  @override
  State<FlowConnectionGuard> createState() => _FlowConnectionGuardState();
}

class _FlowConnectionGuardState extends State<FlowConnectionGuard> {
  BleController? _controller;
  bool _initialized = false;
  bool _aborted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;

    final controller = AppScope.of(context);
    _controller = controller;
    controller.addListener(_check);
    // The screen may also open on an already-dropped link.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (_aborted || !mounted) return;
    final controller = _controller;
    if (controller == null || controller.isConnected) return;
    _aborted = true;
    unawaited(abortFlowToHome(context));
  }

  @override
  void dispose() {
    _controller?.removeListener(_check);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
