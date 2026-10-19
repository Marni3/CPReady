/// Shared tab selection state so the bottom-nav shell can remember which
/// tab was active across pushed/popped routes (e.g. returning to Practice
/// from the Session Complete screen).

import 'package:flutter/material.dart';

/// Index of the active bottom-nav tab: 0 = Home, 1 = Practice, 2 = History.
final ValueNotifier<int> selectedTabNotifier = ValueNotifier<int>(0);
