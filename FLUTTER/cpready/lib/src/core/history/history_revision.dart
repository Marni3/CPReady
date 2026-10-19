/// Change signal for the saved-session set.
///
/// The History list lives inside the tab shell's `IndexedStack`, so its state is
/// kept alive and it does not rebuild when the tab is shown. Bumping this
/// notifier whenever a session is written or removed lets the list reload
/// without polling or re-reading the database on every frame.

import 'package:flutter/foundation.dart';

/// Incremented whenever the set of saved sessions changes.
final ValueNotifier<int> historyRevisionNotifier = ValueNotifier<int>(0);

/// Announces that the saved sessions changed.
void markHistoryChanged() {
  historyRevisionNotifier.value++;
}
