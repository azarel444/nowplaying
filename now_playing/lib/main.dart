import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'now_playing_screen.dart';
import 'onboarding.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const NowPlayingApp());
}

class NowPlayingApp extends StatelessWidget {
  const NowPlayingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VYBE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: false,
      ),
      home: const _Root(),
    );
  }
}

/// Splash first, then the first-launch tour (once), then the player.
class _Root extends StatefulWidget {
  const _Root();

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool? _onboarded; // null while the splash is showing

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    var done = false;
    try {
      final p = await SharedPreferences.getInstance();
      done = p.getBool('onboarded') ?? false;
    } catch (_) {}
    // Keep the splash up for a moment so the logo can be seen.
    await Future<void>.delayed(const Duration(milliseconds: 1800));
    if (!mounted) return;
    setState(() => _onboarded = done);
  }

  Future<void> _finish() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('onboarded', true);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _onboarded = true);
  }

  @override
  Widget build(BuildContext context) {
    final o = _onboarded;
    if (o == null) return const SplashScreen();
    if (!o) return OnboardingScreen(onDone: _finish);
    return const NowPlayingScreen();
  }
}
