import 'package:flutter/material.dart';

import 'now_playing_model.dart';
import 'settings.dart';

const _cyan = Color(0xFF00E5FF);

/// Full-screen settings page with large touch targets for head units.
class SettingsScreen extends StatelessWidget {
  final AppSettings settings;
  final NowPlayingModel model;

  const SettingsScreen({super.key, required this.settings, required this.model});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070D),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 12, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Settings',
                        style:
                            TextStyle(fontSize: 28, fontWeight: FontWeight.w300)),
                  ),
                  IconButton(
                    iconSize: 38,
                    padding: const EdgeInsets.all(12),
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedBuilder(
                animation: Listenable.merge([settings, model]),
                builder: (context, _) => Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                      children: _items(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _items() {
    final s = settings;
    return [
      _section('Access'),
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        title: const Text('Notification access',
            style: TextStyle(fontSize: 20)),
        subtitle: Text(
          model.accessGranted
              ? 'Granted'
              : 'Not granted. Needed to see what is playing.',
          style: TextStyle(
              fontSize: 15,
              color: model.accessGranted ? Colors.white60 : Colors.orangeAccent),
        ),
        trailing: ElevatedButton(
          onPressed: model.openAccessSettings,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Text('Open settings', style: TextStyle(fontSize: 16)),
          ),
        ),
      ),
      _section('Visualizer'),
      _switch('Show visualizer', 'Turn the bars and ring off completely',
          s.visualizer, (v) => s.update(() => s.visualizer = v)),
      _slider(
        'Sensitivity',
        '${(s.sensitivity * 100).round()}%',
        s.sensitivity,
        0.5,
        1.5,
        (v) => s.update(() => s.sensitivity = v, persist: false),
        s.save,
      ),
      _choices(
        'Style in the Focused theme',
        const ['Ring', 'Bars'],
        s.vizStyle,
        (i) => s.update(() => s.vizStyle = i),
      ),
      _choices(
        'Number of bars',
        AppSettings.barCounts.map((e) => '$e').toList(),
        AppSettings.barCounts.indexOf(s.barCount),
        (i) => s.update(() => s.barCount = AppSettings.barCounts[i]),
      ),
      _section('Look'),
      _choices(
        'Accent colors',
        AppSettings.accentNames,
        s.accent,
        (i) => s.update(() => s.accent = i),
      ),
      _choices(
        'Theme',
        AppSettings.themeNames,
        s.theme,
        (i) => s.update(() => s.theme = i),
      ),
      _section('Effects'),
      _slider(
        'VHS effect strength',
        '${(s.effects * 100).round()}%',
        s.effects,
        0.0,
        1.0,
        (v) => s.update(() => s.effects = v, persist: false),
        s.save,
      ),
      _switch('Background drift and beat pulse',
          'Slow motion behind the art, and a small pulse on bass hits',
          s.bgEffects, (v) => s.update(() => s.bgEffects = v)),
      _switch('Floating particles', 'Glowing embers drifting upward',
          s.particles, (v) => s.update(() => s.particles = v)),
      _switch('Performance mode',
          'For slower units: turns off grain, glitch bands, drift and particles',
          s.performance, (v) => s.update(() => s.performance = v)),
      _section('Screen care'),
      _choices(
        'Night mode',
        const ['Off', 'Auto (8pm to 6am)', 'Always on'],
        s.night,
        (i) => s.update(() => s.night = i),
      ),
      _switch('Burn-in protection',
          'Moves the layout a few pixels over time',
          s.burnIn, (v) => s.update(() => s.burnIn = v)),
    ];
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 28, 8, 6),
        child: Text(
          t.toUpperCase(),
          style: const TextStyle(fontSize: 14, letterSpacing: 2, color: _cyan),
        ),
      );

  Widget _switch(String title, String sub, bool value, ValueChanged<bool> on) =>
      SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        title: Text(title, style: const TextStyle(fontSize: 20)),
        subtitle: Text(sub,
            style: const TextStyle(fontSize: 15, color: Colors.white60)),
        value: value,
        onChanged: on,
      );

  Widget _slider(String title, String label, double value, double min,
          double max, ValueChanged<double> onChanged, VoidCallback onEnd) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(fontSize: 20)),
                Text(label,
                    style:
                        const TextStyle(fontSize: 18, color: Colors.white70)),
              ],
            ),
            Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              activeColor: _cyan,
              onChanged: onChanged,
              onChangeEnd: (_) => onEnd(),
            ),
          ],
        ),
      );

  Widget _choices(String title, List<String> labels, int selected,
          ValueChanged<int> onSelect) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: List<Widget>.generate(
                labels.length,
                (i) => ChoiceChip(
                  label: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Text(labels[i], style: const TextStyle(fontSize: 18)),
                  ),
                  selected: i == selected,
                  onSelected: (_) => onSelect(i),
                ),
              ),
            ),
          ],
        ),
      );
}
