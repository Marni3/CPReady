import 'package:flutter/material.dart';

import '../main.dart';
import '../shared_widgets.dart';
import 'calibration_screen.dart';

/// Tab 1 — Home: CPReady overview, connection status, connect button.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text(
              'CPReady Overview',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            const Text(
              'Lorem ipsum dolor sit amet, consectetur adipiscing elit. '
              'Sed do eiusmod tempor incididunt ut labore et dolore magna '
              'aliqua. Ut enim ad minim veniam, quis nostrud exercitation '
              'ullamco laboris nisi ut aliquip ex ea commodo consequat. '
              'Duis aute irure dolor in reprehenderit in voluptate velit '
              'esse cillum dolore eu fugiat nulla pariatur. '
              'Lorem ipsum dolor sit amet, consectetur adipiscing elit. '
              'Sed do eiusmod tempor incididunt ut labore et dolore magna '
              'aliqua. Ut enim ad minim veniam, quis nostrud exercitation '
              'ullamco laboris nisi ut aliquip ex ea commodo consequat. '
              'Duis aute irure dolor in reprehenderit in voluptate velit '
              'esse cillum dolore eu fugiat nulla pariatur. ',
            ),
            const SizedBox(height: 24),
            Text(
              'Device Connection',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ConnectionStatusChip(controller: controller),
            const SizedBox(height: 12),
            ConnectButton(controller: controller),
          ],
        ),
      ),
    );
  }
}

/// Tab 2 — Practice: entry point to the guide and the practice flow.
class PracticeScreen extends StatelessWidget {
  const PracticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text('Practice', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            const Text('Choose an option below.'),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.menu_book),
              label: const Text('Step-by-Step Guide'),
              onPressed: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const GuideScreen())),
            ),
            const SizedBox(height: 16),
            const _StartPracticeButton(),
          ],
        ),
      ),
    );
  }
}

/// "Start Practice": checks BLE connection, connects if needed,
/// then enters the practice setup flow.
class _StartPracticeButton extends StatefulWidget {
  const _StartPracticeButton();

  @override
  State<_StartPracticeButton> createState() => _StartPracticeButtonState();
}

class _StartPracticeButtonState extends State<_StartPracticeButton> {
  bool _busy = false;
  String? _error;

  Future<void> _onPressed() async {
    final controller = AppScope.of(context);

    if (controller.isConnected) {
      _openSetup();
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final ok = await controller.connect();

    if (!mounted) return;
    setState(() => _busy = false);

    if (ok) {
      _openSetup();
    } else {
      setState(() {
        _error = controller.lastError.isEmpty
            ? 'Could not connect to CPReady.'
            : controller.lastError;
      });
    }
  }

  void _openSetup() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const PracticeSetupScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow),
          label: Text(_busy ? 'Connecting\u2026' : 'Start Practice'),
          onPressed: _busy ? null : _onPressed,
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}

/// Tab 3 — History: work-in-progress placeholder.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text('History', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(Icons.construction, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      'Work in Progress',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Saved practice sessions will appear here soon.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Full-screen guide shown from Practice; returns to Practice on back.
class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Step-by-Step Guide')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              Text('Guide', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              const Text(
                'Lorem ipsum dolor sit amet, consectetur adipiscing elit. '
                'Sed do eiusmod tempor incididunt ut labore et dolore magna '
                'aliqua. Ut enim ad minim veniam, quis nostrud exercitation '
                'ullamco laboris nisi ut aliquip ex ea commodo consequat. '
                'Lorem ipsum dolor sit amet, consectetur adipiscing elit. '
                'Sed do eiusmod tempor incididunt ut labore et dolore magna '
                'aliqua. Ut enim ad minim veniam, quis nostrud exercitation '
                'ullamco laboris nisi ut aliquip ex ea commodo consequat. ',
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to Practice'),
          ),
        ),
      ),
    );
  }
}

/// Practice setup: required trainee name before continuing.
class PracticeSetupScreen extends StatefulWidget {
  const PracticeSetupScreen({super.key});

  @override
  State<PracticeSetupScreen> createState() => _PracticeSetupScreenState();
}

class _PracticeSetupScreenState extends State<PracticeSetupScreen> {
  final _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _valid => _nameController.text.trim().isNotEmpty;

  void _continue() {
    if (!_valid) return;
    final name = _nameController.text.trim();
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => HandPlacementScreen(traineeName: name)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Practice Setup')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Trainee Name',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Trainee Name *',
                  border: OutlineInputBorder(),
                  hintText: 'Enter trainee name',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              const Text(
                'A unique ID will be assigned to this trainee for History '
                '(coming soon).',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _valid ? _continue : null,
                child: const Text('Continue'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Visual hand placement instruction + instructor verification.
class HandPlacementScreen extends StatelessWidget {
  final String traineeName;

  const HandPlacementScreen({super.key, required this.traineeName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hand Placement')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Icon(Icons.back_hand, size: 64),
                      const SizedBox(height: 12),
                      Text(
                        'Place both hands on the chest',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Lorem ipsum dolor sit amet, consectetur adipiscing elit. '
                        'Sed do eiusmod tempor incididunt ut labore et dolore '
                        'magna aliqua. Ut enim ad minim veniam.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              const Text(
                'Instructor: verify hand placement before continuing.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CalibrationScreen(traineeName: traineeName),
                  ),
                ),
                child: const Text('Yes (All Good)'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
