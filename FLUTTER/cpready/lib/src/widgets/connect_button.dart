/// Connect / reconnect button with busy states, styled from config.

import 'package:flutter/material.dart';

import '../config/config.dart';
import '../core/ble/ble_controller.dart';
import 'base/app_button.dart';

/// Connect / reconnect button driven by [BleController].
class ConnectButton extends StatelessWidget {
  final BleController controller;

  const ConnectButton({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final busy = controller.isBusy;
        final connected = controller.status == BleStatus.connected;

        final String label;
        if (busy) {
          label = controller.status == BleStatus.scanning
              ? AppStrings.statusScanning
              : AppStrings.statusConnecting;
        } else if (connected) {
          label = 'Connected \u2713 \u2014 Tap to reconnect';
        } else {
          label = AppStrings.buttonConnect;
        }

        return AppButton(
          label: label,
          variant: AppButtonVariant.filled,
          onPressed: busy ? null : controller.connect,
          isBusy: busy,
        );
      },
    );
  }
}
