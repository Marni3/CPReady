/// Tab 3 — History: every saved practice session, newest first.
///
/// Mirrors the other tabs' chrome (the shared [ScreenHeader] on top and the
/// shared bottom nav underneath) and lists one row per session showing the
/// trainee name, the date and time, and the duration. Each row carries a
/// "See more" action that opens the session summary and a three-dot action that
/// deletes just that session after confirmation; the whole list can be cleared
/// from the gradient button at the bottom.
///
/// All persistence goes through [SessionRepository] (`AppScope.history`); every
/// visual value comes from `lib/src/config/`.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/config.dart';
import '../../core/app_scope.dart';
import '../../core/history/history_format.dart';
import '../../core/history/history_revision.dart';
import '../../core/history/session_record.dart';
import '../../core/history/session_repository.dart';
import '../../widgets/widgets.dart';

/// History tab screen.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  SessionRepository? _repository;
  bool _initialized = false;
  bool _loading = true;
  List<SessionRecord> _sessions = const <SessionRecord>[];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _repository = AppScope.history(context);
    // The list is kept alive by the tab shell's IndexedStack, so reload when a
    // session is saved elsewhere instead of relying on a rebuild.
    historyRevisionNotifier.addListener(_onHistoryChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    historyRevisionNotifier.removeListener(_onHistoryChanged);
    super.dispose();
  }

  void _onHistoryChanged() {
    if (!mounted) return;
    unawaited(_load());
  }

  /// Reads every saved session, newest first.
  Future<void> _load() async {
    final repository = _repository;
    if (repository == null) return;

    if (mounted) {
      setState(() => _loading = true);
    }

    List<SessionRecord> sessions = const <SessionRecord>[];
    try {
      sessions = await repository.listSessions();
    } catch (error) {
      debugPrint('History load failed: $error');
    }

    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _loading = false;
    });
  }

  /// Removes a session, once its deletion has been confirmed.
  Future<void> _delete(SessionRecord record) async {
    final repository = _repository;
    final id = record.id;
    if (repository == null || id == null) return;

    setState(() {
      _sessions = _sessions
          .where((session) => session.id != id)
          .toList(growable: false);
    });

    try {
      await repository.deleteSession(id);
    } catch (error) {
      debugPrint('History delete failed: $error');
      await _load();
    }
  }

  /// Asks before deleting one session's row.
  Future<void> _confirmDelete(SessionRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStrings.historyDeleteOneTitle),
        content: const Text(AppStrings.historyDeleteOneBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(AppStrings.historyClearAllCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(AppStrings.historyDeleteOneConfirm),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _delete(record);
  }

  /// Deletes every session, after confirmation.
  Future<void> _clearAll() async {
    final repository = _repository;
    if (repository == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStrings.historyClearAllTitle),
        content: const Text(AppStrings.historyClearAllBody),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(AppStrings.historyClearAllCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(AppStrings.historyClearAllConfirm),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await repository.deleteAllSessions();
    } catch (error) {
      debugPrint('History clear failed: $error');
    }

    await _load();
  }

  /// Opens one session's summary.
  Future<void> _open(SessionRecord record) async {
    final id = record.id;
    if (id == null) return;

    await context.pushNamed(
      AppRoutes.historyDetail,
      pathParameters: <String, String>{'id': '$id'},
    );

    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final double page = AppLayout.pagePaddingFor(
      MediaQuery.sizeOf(context).width,
    );

    return SafeArea(
      bottom: false,
      child: Column(
        children: <Widget>[
          ScreenHeader(pageLabel: AppStrings.historyHeaderPage),
          Expanded(
            child: ContentBounds(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: page),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SizedBox(height: AppSpacing.historyTopPadding),
                    Text(
                      AppStrings.historyTitle,
                      style: AppTypography.style(
                        size: AppTypography.historyTitleSize,
                        weight: AppTypography.headingWeight,
                        color: AppColors.historyTitleText,
                      ),
                    ),
                    SizedBox(height: AppSpacing.historyTitleGap),
                    Expanded(child: _list()),
                    if (_sessions.isNotEmpty) ...<Widget>[
                      SizedBox(
                        height: AppSpacing.historyClearButtonTopGap,
                      ),
                      _ClearHistoryButton(
                        onPressed: () => unawaited(_clearAll()),
                      ),
                      SizedBox(
                        height: AppSpacing.historyClearButtonBottomGap,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The list itself, or whatever stands in for it while it is unavailable.
  Widget _list() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_sessions.isEmpty) {
      return const _EmptyHistory();
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _sessions.length,
      separatorBuilder: (_, __) =>
          SizedBox(height: AppSpacing.historyRowGap),
      itemBuilder: (context, index) {
        final record = _sessions[index];
        return _SessionRow(
          record: record,
          onOpen: () => unawaited(_open(record)),
          onDelete: () => unawaited(_confirmDelete(record)),
        );
      },
    );
  }
}

/// Bottom "Clear History" button: the brand gradient with a centred white
/// label, spanning the content width above the nav bar.
class _ClearHistoryButton extends StatelessWidget {
  const _ClearHistoryButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        minHeight: AppSizes.historyClearButtonHeight,
      ),
      decoration: BoxDecoration(
        gradient: AppGradients.brandVertical,
        borderRadius: BorderRadius.circular(AppSizes.historyClearButtonRadius),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(
            AppSizes.historyClearButtonRadius,
          ),
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppSpacing.homeButtonLabelInsetH,
              vertical: AppSpacing.flowActionLabelInsetV,
            ),
            child: Center(
              child: Text(
                AppStrings.historyClearButton,
                textAlign: TextAlign.center,
                style: AppTypography.style(
                  size: AppTypography.historyClearButtonSize,
                  weight: AppTypography.headingWeight,
                  color: AppColors.historyClearButtonText,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One session: the trainee name with the duration right-aligned over the
/// three-dot button, then a line carrying the timestamp alongside the row's own
/// actions ("See more" to open the summary, three dots to delete just this
/// session).
class _SessionRow extends StatelessWidget {
  const _SessionRow({
    required this.record,
    required this.onOpen,
    required this.onDelete,
  });

  final SessionRecord record;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onOpen,
      child: Container(
        padding: EdgeInsets.all(AppSpacing.historyRowPadding),
        decoration: BoxDecoration(
          color: AppColors.historyRowBackground,
          borderRadius: BorderRadius.circular(AppSizes.historyRowRadius),
          border: Border.all(
            color: AppColors.historyRowBorder,
            width: AppSizes.historyRowBorderWidth,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _HeaderLine(record: record),
            SizedBox(height: AppSpacing.historyRowTextGap),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    formatHistoryTimestamp(record.startedAt),
                    style: AppTypography.style(
                      size: AppTypography.historyRowMetaSize,
                      weight: FontWeight.bold,
                      color: AppColors.historyRowDateText,
                    ),
                  ),
                ),
                SizedBox(width: AppSpacing.historyRowActionsGap),
                _SeeMoreButton(onPressed: onOpen),
                SizedBox(width: AppSpacing.historyRowDotsGap),
                InkWell(
                  onTap: onDelete,
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: AppSizes.historyMoreTapSize,
                    height: AppSizes.historyMoreTapSize,
                    child: Icon(
                      Icons.more_vert,
                      size: AppSizes.historyMoreIconSize,
                      color: AppColors.historyRowActionsText,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Outlined "See more" capsule: a thin black edge, no fill, with the label
/// centred inside it. Tapping it opens the session summary.
class _SeeMoreButton extends StatelessWidget {
  const _SeeMoreButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Container(
        constraints: BoxConstraints(
          minHeight: AppSizes.historySeeMoreMinHeight,
        ),
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(
          horizontal: AppSpacing.historySeeMorePaddingH,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSizes.historySeeMoreRadius),
          border: Border.all(
            color: AppColors.historySeeMoreBorder,
            width: AppSizes.historySeeMoreBorderWidth,
          ),
        ),
        child: Text(
          AppStrings.historySeeMore,
          style: AppTypography.style(
            size: AppTypography.historySeeMoreSize,
            weight: FontWeight.bold,
            color: AppColors.historyRowActionsText,
          ),
        ),
      ),
    );
  }
}

/// Small marker on a session that ended before its summary arrived.
class _InterruptedLabel extends StatelessWidget {
  const _InterruptedLabel();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: AppSpacing.historyInterruptedPaddingH,
        vertical: AppSpacing.historyInterruptedPaddingV,
      ),
      decoration: BoxDecoration(
        color: AppColors.historyInterruptedBackground,
        borderRadius: BorderRadius.circular(
          AppSizes.historyInterruptedLabelRadius,
        ),
      ),
      child: Text(
        AppStrings.historyInterruptedLabel,
        style: AppTypography.style(
          size: AppTypography.historyInterruptedSize,
          weight: FontWeight.bold,
          color: AppColors.historyInterruptedText,
        ),
      ),
    );
  }
}

/// Shown before the first session has been saved.
class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(AppSpacing.page),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            Icons.history,
            size: AppSizes.iconLarge,
            color: AppColors.navUnselected,
          ),
          SizedBox(height: AppSpacing.item),
          Text(
            AppStrings.historyEmptyTitle,
            style: AppTypography.style(
              size: AppTypography.historyRowTitleSize,
              weight: FontWeight.bold,
              color: AppColors.historyRowTitleText,
            ),
          ),
          SizedBox(height: AppSpacing.small),
          Text(
            AppStrings.historyEmptyBody,
            textAlign: TextAlign.center,
            style: AppTypography.style(
              size: AppTypography.historyRowMetaSize,
              weight: FontWeight.normal,
              color: AppColors.historyRowMetaText,
            ),
          ),
        ],
      ),
    );
  }
}

/// Trainee name on the left, then the "Interrupted" badge and the duration.
///
/// The three share one line while the name's rendered width leaves room for
/// the rest. When they no longer fit, the badge and the duration move to a
/// second line instead of squeezing the name.
class _HeaderLine extends StatelessWidget {
  const _HeaderLine({required this.record});

  final SessionRecord record;

  @override
  Widget build(BuildContext context) {
    final TextStyle nameStyle = AppTypography.style(
      size: AppTypography.historyRowTitleSize,
      weight: AppTypography.headingWeight,
      color: AppColors.historyRowTitleText,
    );
    final TextStyle metaStyle = AppTypography.style(
      size: AppTypography.historyRowMetaSize,
      weight: AppTypography.headingWeight,
      color: AppColors.historyRowDateText,
    );
    final TextStyle badgeStyle = AppTypography.style(
      size: AppTypography.historyInterruptedSize,
      weight: FontWeight.bold,
    );
    final String duration = formatHistoryDuration(record.durationSeconds);

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double nameWidth = measureTextWidth(
          context,
          record.traineeName,
          nameStyle,
        );
        final double badgeWidth = record.isCompleted
            ? 0
            : measureTextWidth(
                    context,
                    AppStrings.historyInterruptedLabel,
                    badgeStyle,
                  ) +
                  (2 * AppSpacing.historyInterruptedPaddingH);
        final double metaWidth =
            badgeWidth +
            (record.isCompleted ? 0 : AppSpacing.small) +
            AppSpacing.historyRowActionsGap +
            measureTextWidth(context, duration, metaStyle) +
            AppSpacing.historyDurationRightPad;

        if (nameWidth + metaWidth <= constraints.maxWidth) {
          return Row(
            children: <Widget>[
              Expanded(child: Text(record.traineeName, style: nameStyle)),
              if (!record.isCompleted) ...<Widget>[
                SizedBox(width: AppSpacing.small),
                const _InterruptedLabel(),
              ],
              SizedBox(width: AppSpacing.historyRowActionsGap),
              _DurationLabel(text: duration),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(record.traineeName, style: nameStyle),
            SizedBox(height: AppSpacing.small),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                if (!record.isCompleted) ...<Widget>[
                  const _InterruptedLabel(),
                  SizedBox(width: AppSpacing.small),
                ],
                Flexible(child: _DurationLabel(text: duration)),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Session duration as shown on a History row.
class _DurationLabel extends StatelessWidget {
  const _DurationLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(right: AppSpacing.historyDurationRightPad),
      child: Text(
        text,
        style: AppTypography.style(
          size: AppTypography.historyRowMetaSize,
          weight: AppTypography.headingWeight,
          color: AppColors.historyRowDateText,
        ),
      ),
    );
  }
}
