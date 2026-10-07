import 'dart:async';

import 'package:flutter/material.dart';

import 'ble_controller.dart';
import 'screens/root_screens.dart';

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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: _controller,
      child: MaterialApp(
        title: 'CPReady',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}

/// Simple InheritedWidget exposing the app-level [BleController].
class AppScope extends InheritedWidget {
  final BleController controller;

  const AppScope({
    super.key,
    required this.controller,
    required super.child,
  });

  static BleController of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppScope>()!
      .controller;

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      controller != oldWidget.controller;
}

/// Launch screen: plain "CPReady" text, no logo, 1.5 s then Home.
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
    _timer = Timer(const Duration(milliseconds: 1500), _goHome);
  }

  void _goHome() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainShell()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('CPReady', style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            Text('Loading\u2026'),
          ],
        ),
      ),
    );
  }
}

/// Root shell with the 3-tab bottom navigation (Home / Practice / History).
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  static const _screens = <Widget>[
    HomeScreen(),
    PracticeScreen(),
    HistoryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Icon(Icons.monitor_heart),
            label: 'Practice',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
        ],
      ),
    );
  }
}
