/// Color-coded BLE connection status chip using config colors/sizes/strings.

import 'package:flutter/material.dart';

import '../config/config.dart';
import '../core/ble/ble_controller.dart';

/// Status dot + label driven by [BleController]. Colors come from config.
class ConnectionStatusChip extends StatelessWidget {
  final BleController controller;

  const ConnectionStatusChip({super.key, required this.controller});

  static const double _dotSize = 12.0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final (label, color) = switch (controller.status) {
          BleStatus.disconnected => (AppStrings.statusDisconnected,
              AppColors.statusDisconnected),
          BleStatus.scanning => (AppStrings.statusScanning,
              AppColors.statusScanning),
          BleStatus.connecting => (AppStrings.statusConnecting,
              AppColors.statusConnecting),
          BleStatus.connected => (AppStrings.statusConnected,
              AppColors.statusConnected),
          BleStatus.error => (
              '${AppStrings.statusErrorPrefix}${controller.lastError}',
              AppColors.statusError,
            ),
        };

        return Row(
          children: [
            Container(
              width: _dotSize,
              height: _dotSize,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: color, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        );
      },
    );
  }
}
