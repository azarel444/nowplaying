import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'now_playing_screen.dart';

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
      home: const NowPlayingScreen(),
    );
  }
}
