/// One saved session, opened from the History list.
///
/// Renders the same screen a session ends with ([SessionCompleteScreen]),
/// filled from the stored row rather than from the live controller.
///
/// When opened from History, the screen displays "Session Details"
/// with a back arrow instead of the post-practice navigation.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/config.dart';
import '../../core/app_scope.dart';
import '../../core/history/session_record.dart';
import '../../core/history/session_repository.dart';
import '../session_complete/session_complete_screen.dart';

/// Detail view for a single saved session.
class HistoryDetailScreen extends StatefulWidget {
  /// Row id of the session to show.
  final int sessionId;

  const HistoryDetailScreen({
    super.key,
    required this.sessionId,
  });

  @override
  State<HistoryDetailScreen> createState() =>
      _HistoryDetailScreenState();
}

class _HistoryDetailScreenState extends State<HistoryDetailScreen> {
  SessionRepository? _repository;
  SessionRecord? _record;

  bool _initialized = false;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_initialized) return;

    _initialized = true;
    _repository = AppScope.history(context);

    unawaited(_load());
  }

  Future<void> _load() async {
    final repository = _repository;

    if (repository == null) return;

    SessionRecord? record;

    try {
      record = await repository.getSession(widget.sessionId);
    } catch (error) {
      debugPrint('History detail load failed: $error');
    }

    if (!mounted) return;

    setState(() {
      _record = record;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final record = _record;

    if (record == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Session Details'),
        ),
        body: Center(
          child: _loaded
              ? const Text(AppStrings.historyMissing)
              : const CircularProgressIndicator(),
        ),
      );
    }

    return SessionCompleteScreen(
      traineeName: record.traineeName,
      reason: record.isCompleted
          ? SessionEndReason.completed
          : SessionEndReason.interrupted,
      summary: record.summary,
      durationSeconds: record.durationSeconds,
      historySaved: true,

      // Tells SessionCompleteScreen it was opened from History.
      fromHistory: true,
    );
  }
}