/// Confirmation shown before SET_PROFILE.
///
/// Each kinematic profile has its own calibrated depth scalar (K), so a switch
/// changes the depth readings; the app never switches modes silently.

import 'package:flutter/material.dart';

import '../config/config.dart';

/// Returns true when the user confirms the mode change.
Future<bool> confirmProfileChange(BuildContext context) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text(AppStrings.profileSwitchWarningTitle),
      content: const Text(AppStrings.profileSwitchWarningBody),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text(AppStrings.actionCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text(AppStrings.profileSwitchConfirm),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
