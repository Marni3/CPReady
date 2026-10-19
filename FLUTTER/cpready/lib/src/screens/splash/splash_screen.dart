/// Launch screen: gradient background, CPReady logo, "CPReady" wordmark, and a
/// tiny loading line. All visual values come from config (no hardcoded
/// literals), so the look can be changed without touching this file.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../config/config.dart';

/// Splash screen shown on cold start, then navigates to home.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (!AppFeatures.showSplash) {
      _goHome();
      return;
    }
    _timer = Timer(AppDurations.splash, _goHome);
  }

  void _goHome() {
    if (!mounted) return;
    context.go(AppRoutes.home);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.splash),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  AppAssets.logoWhite,
                  width: AppSizes.splashLogoWidth,
                ),
                const SizedBox(height: AppSpacing.splashLogoGap),
                Text(
                  AppStrings.splashTitle,
                  style: AppTypography.style(
                    size: AppTypography.splashTitleSize,
                    weight: AppTypography.splashTitleWeight,
                    color: AppColors.splashForeground,
                    letterSpacing: AppTypography.splashTitleLetterSpacing,
                  ),
                ),
                const SizedBox(height: AppSpacing.splashLoaderGap),
                const _SplashLoader(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A very tiny loading line that fills left→right under the wordmark:
/// a white fill growing over the #A6A6A6 track.
class _SplashLoader extends StatefulWidget {
  const _SplashLoader();

  @override
  State<_SplashLoader> createState() => _SplashLoaderState();
}

class _SplashLoaderState extends State<_SplashLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppDurations.splashLoader,
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = AppSizes.splashLoaderHeight;
    return SizedBox(
      width: AppSizes.splashLoaderWidth,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => LinearProgressIndicator(
            value: _controller.value,
            minHeight: height,
            color: AppColors.splashLoaderFill,
            backgroundColor: AppColors.splashLoaderTrack,
          ),
        ),
      ),
    );
  }
}
