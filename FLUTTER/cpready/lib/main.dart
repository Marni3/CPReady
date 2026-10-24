import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'src/config/config.dart';
import 'src/core/app_scope.dart';
import 'src/core/ble/ble_controller.dart';
import 'src/core/history/session_repository.dart';
import 'src/core/metrics/cpr_metrics.dart';
import 'src/core/navigation.dart';
import 'src/core/tab_state.dart';
import 'src/theme/app_theme.dart';
import 'src/widgets/app_asset_icon.dart';
import 'src/widgets/flow_connection_guard.dart';
import 'src/screens/splash/splash_screen.dart';
import 'src/screens/home/home_screen.dart';
import 'src/screens/practice/practice_screen.dart';
import 'src/screens/history/history_screen.dart';
import 'src/screens/history/history_detail_screen.dart';
import 'src/screens/guide/guide_screen.dart';
import 'src/screens/setup/practice_setup_screen.dart';
import 'src/screens/hand_placement/hand_placement_screen.dart';
import 'src/screens/calibration/calibration_screen.dart';
import 'src/screens/begin_compression/begin_compression_screen.dart';
import 'src/screens/live_practice/live_practice_screen.dart';
import 'src/screens/session_complete/session_complete_screen.dart';

/// Trainee name carried through the practice flow in GoRouter's `extra`.
String _traineeName(BuildContext context) =>
    GoRouterState.of(context).extra as String? ?? '';

void main() {
  runApp(const CpReadyApp());
}

/// Root widget: owns the shared [BleController] and provides it via [AppScope].
class CpReadyApp extends StatefulWidget {
  const CpReadyApp({super.key});

  @override
  State<CpReadyApp> createState() => _CpReadyAppState();
}

class _CpReadyAppState extends State<CpReadyApp> {
  final BleController _controller = BleController();
  final SessionRepository _repository = SessionRepository();
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = buildRouter(
      initialRoute: AppRoutes.splash,
      routeBuilder: {
        AppRoutes.splash: (_) => const SplashScreen(),
        AppRoutes.home: (_) => const MainShell(),
        AppRoutes.historyDetail: (context) {
          final rawId = GoRouterState.of(context).pathParameters['id'];
          return HistoryDetailScreen(
            sessionId: int.tryParse(rawId ?? '') ?? -1,
          );
        },
        AppRoutes.guide: (_) => const GuideScreen(),
        AppRoutes.setup: (_) =>
            const FlowConnectionGuard(child: PracticeSetupScreen()),
        AppRoutes.handPlacement: (context) => FlowConnectionGuard(
          child: HandPlacementScreen(traineeName: _traineeName(context)),
        ),
        AppRoutes.calibration: (context) => FlowConnectionGuard(
          child: CalibrationScreen(traineeName: _traineeName(context)),
        ),
        AppRoutes.beginCompression: (context) => FlowConnectionGuard(
          child: BeginCompressionScreen(traineeName: _traineeName(context)),
        ),
        AppRoutes.livePractice: (context) =>
            LivePracticeScreen(traineeName: _traineeName(context)),
        AppRoutes.sessionComplete: (context) {
          final extra = GoRouterState.of(context).extra as Map? ?? {};
          return SessionCompleteScreen(
            traineeName: extra['traineeName'] as String? ?? '',
            saved: extra['saved'] as bool? ?? false,
            summary: extra['summary'] as CprMetrics?,
            durationSeconds: extra['durationSeconds'] as int? ?? 0,
            historySaved: extra['historySaved'] as bool? ?? true,
          );
        },
      },
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _repository.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: _controller,
      repository: _repository,
      child: CpReadyTheme(
        data: appThemeData(),
        child: MaterialApp.router(
          title: AppIdentity.name,
          theme: appThemeData().theme,
          routerConfig: _router,
          debugShowCheckedModeBanner: false,
          builder: (BuildContext context, Widget? child) {
            return MediaQuery.withClampedTextScaling(
              maxScaleFactor: AppLayout.maxTextScale,
              child: child ?? const SizedBox.shrink(),
            );
          },
        ),
      ),
    );
  }
}

/// Root shell with the 3-tab bottom navigation (Home / Practice / History).
///
/// The active tab is synced to [selectedTabNotifier] so screens that leave the
/// shell — the Session Complete screen, for instance — can choose the tab that
/// is showing when they return.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const List<Widget> _screens = <Widget>[
    HomeScreen(),
    PracticeScreen(),
    HistoryScreen(),
  ];

  int _index = 0;

  @override
  void initState() {
    super.initState();
    _index = selectedTabNotifier.value.clamp(0, _screens.length - 1);
    selectedTabNotifier.addListener(_onNotifierChanged);
  }

  void _onNotifierChanged() {
    if (!mounted) return;
    setState(() {
      _index = selectedTabNotifier.value.clamp(0, _screens.length - 1);
    });
  }

  void _onTabTapped(int index) {
    selectedTabNotifier.value = index;
    setState(() => _index = index);
  }

  @override
  void dispose() {
    selectedTabNotifier.removeListener(_onNotifierChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppLayout.pagePaddingFor(
                MediaQuery.sizeOf(context).width,
              ),
            ),
            child: Container(
              height: AppSizes.dividerThickness,
              color: AppColors.divider,
            ),
          ),
          const SizedBox(height: AppSpacing.dividerGap),
          SafeArea(
            top: false,
            child: _BottomNavBar(currentIndex: _index, onTap: _onTabTapped),
          ),
        ],
      ),
    );
  }
}

/// One bottom-navigation destination.
class _NavDestination {
  const _NavDestination({required this.iconAsset, required this.label});

  final String iconAsset;
  final String label;
}

/// Tap-to-switch bottom navigation with no tap animation (no ink splash or
/// highlight). Items are packed together rather than spread edge to edge.
class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  static const List<_NavDestination> _destinations = <_NavDestination>[
    _NavDestination(iconAsset: AppAssets.iconHome, label: AppStrings.navHome),
    _NavDestination(
      iconAsset: AppAssets.iconHeartbeat,
      label: AppStrings.navPractice,
    ),
    _NavDestination(
      iconAsset: AppAssets.iconClock,
      label: AppStrings.navHistory,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final bool compact = AppLayout.isCompact(MediaQuery.sizeOf(context).width);
    final double gap = compact
        ? AppSpacing.navItemGapCompact
        : AppSpacing.navItemGap;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (int i = 0; i < _destinations.length; i++) ...<Widget>[
          if (i > 0) SizedBox(width: gap),
          _NavButton(
            destination: _destinations[i],
            selected: i == currentIndex,
            onTap: () => onTap(i),
          ),
        ],
      ],
    );
  }
}

/// A single nav item: icon + label, colored by selection, with no ripple.
class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = selected
        ? AppColors.navSelected
        : AppColors.navUnselected;

    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppLayout.isCompact(MediaQuery.sizeOf(context).width)
                ? AppSpacing.navItemPaddingCompact
                : AppSpacing.navItemPadding,
            vertical: AppSpacing.item,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppAssetIcon(
                asset: destination.iconAsset,
                size: AppSizes.navIconSize,
                color: color,
              ),
              const SizedBox(height: AppSpacing.tiny),
              Text(
                destination.label,
                style: AppTypography.style(
                  size: AppTypography.homePageSize,
                  weight: selected ? FontWeight.bold : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
