import 'package:flutter/material.dart';

import 'native.dart';
import 'now_playing_model.dart';
import 'onboarding.dart';
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
                  Expanded(
                    child: Row(
                      children: [
                        Image.asset(
                          'assets/vybe_logo.png',
                          height: 34,
                          errorBuilder: (context, error, stack) =>
                              const SizedBox.shrink(),
                        ),
                        const SizedBox(width: 18),
                        const Text('Settings',
                            style: TextStyle(
                                fontSize: 28, fontWeight: FontWeight.w300)),
                      ],
                    ),
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
                      children: _items(context),
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

  List<Widget> _items(BuildContext context) {
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
      _switch('VHS uses vaporwave colors',
          'Pink and cyan instead of colors from the album art',
          s.vhsVaporwave, (v) => s.update(() => s.vhsVaporwave = v)),
      _section('Effects'),
      _slider(
        'VHS effect strength',
        '${(s.vhsEffects * 100).round()}%',
        s.vhsEffects,
        0.0,
        1.0,
        (v) => s.update(() => s.vhsEffects = v, persist: false),
        s.save,
      ),
      _slider(
        'Other effects strength',
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
      _switch('Breathing glow',
          'Soft blobs in the album colors drift and swell behind everything',
          s.fxGlow, (v) => s.update(() => s.fxGlow = v)),
      _switch('Aurora sweep',
          'Slow bands of the album colors roll across the screen',
          s.fxSweep, (v) => s.update(() => s.fxSweep = v)),
      _switch('Light rays',
          'Beams fan out from behind the cover and brighten on bass',
          s.fxRays, (v) => s.update(() => s.fxRays = v)),
      _switch('Beat ripples',
          'Rings spread out from the cover on each beat',
          s.fxRipples, (v) => s.update(() => s.fxRipples = v)),
      _switch('Water shimmer',
          'Light glints on the lower part of the screen, like a lake',
          s.fxWater, (v) => s.update(() => s.fxWater = v)),
      _switch('Soft bloom on the cover',
          'A blurred glow around the album art',
          s.fxBloom, (v) => s.update(() => s.fxBloom = v)),
      _switch('Performance mode',
          'For slower units: turns off all effects above, plus grain, glitch bands, drift and particles',
          s.performance, (v) => s.update(() => s.performance = v)),
      _section('Online (needs an internet connection)'),
      _switch('Find missing album art',
          'Searches online when a player does not send a cover',
          s.artLookup, (v) => s.update(() => s.artLookup = v)),
      _switch('Synced lyrics',
          'Shows the current line as it is sung, when the song has lyrics',
          s.lyrics, (v) => s.update(() => s.lyrics = v)),
      _section('Launch'),
      _switch('Open when the unit starts',
          'Some units have their own auto-start manager that must also allow this app',
          s.bootStart, (v) => s.update(() => s.bootStart = v)),
      _switch('Open when music starts',
          'Brings the app forward when a player begins playing',
          s.musicStart, (v) => s.update(() => s.musicStart = v)),
      _choices(
        'A pause of this long starts a new session',
        const ['30 seconds', '1 minute', '5 minutes'],
        const [30, 60, 300].indexOf(s.graceSec).clamp(0, 2).toInt(),
        (i) => s.update(() => s.graceSec = const [30, 60, 300][i]),
      ),
      _switch("Don't open while navigation is guiding",
          'Looks for the navigation notification, so VYBE never covers your map',
          s.avoidNav, (v) => s.update(() => s.avoidNav = v)),
      _switch('Also open for video apps',
          'Off by default: only music players open VYBE',
          s.allowVideo, (v) => s.update(() => s.allowVideo = v)),
      _switch('Also open for navigation audio',
          'Off by default: voice prompts from a map never open VYBE',
          s.allowNavAudio, (v) => s.update(() => s.allowNavAudio = v)),
      _action(
        'Players that may open VYBE',
        'Every player VYBE has seen, with a switch for each',
        'Manage',
        () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const PlayersScreen(),
        )),
      ),
      _section('Navigation and Drive theme'),
      _action(
        'Navigation app',
        s.navLabel.isEmpty
            ? 'Automatic: the first known navigation app found'
            : s.navLabel,
        'Choose',
        () => _pickNavApp(context),
      ),
      _switch('Swap sides in the Drive theme',
          'Navigation card on the left and music on the right',
          s.driveSwap, (v) => s.update(() => s.driveSwap = v)),
      _slider(
        'Navigation card width',
        '${(s.driveCardWidth * 100).round()}%',
        s.driveCardWidth,
        0.35,
        0.65,
        (v) => s.update(() => s.driveCardWidth = v, persist: false),
        s.save,
      ),
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
      _section('Permissions and privacy'),
      const _PermissionsPanel(),
      _action(
        'Welcome tour',
        'Replay the explanation of each permission',
        'Replay',
        () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (ctx) => OnboardingScreen(
            settings: settings,
            onDone: () => Navigator.of(ctx).pop(),
          ),
        )),
      ),
    ];
  }

  Widget _action(
          String title, String sub, String button, VoidCallback onPressed) =>
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        title: Text(title, style: const TextStyle(fontSize: 20)),
        subtitle: Text(sub,
            style: const TextStyle(fontSize: 15, color: Colors.white60)),
        trailing: ElevatedButton(
          onPressed: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Text(button, style: const TextStyle(fontSize: 16)),
          ),
        ),
      );

  Future<void> _pickNavApp(BuildContext context) async {
    final apps = await Native.getInstalledApps();
    if (!context.mounted) return;
    final choice = await showDialog<AppInfo>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Navigation app'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, const AppInfo('', '')),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Automatic', style: TextStyle(fontSize: 20)),
            ),
          ),
          for (final a in apps)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, a),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(a.label, style: const TextStyle(fontSize: 20)),
              ),
            ),
        ],
      ),
    );
    if (choice == null) return;
    settings.update(() {
      settings.navPkg = choice.pkg;
      settings.navLabel = choice.label;
    });
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

/// Live status of each permission, with a button to change it.
class _PermissionsPanel extends StatefulWidget {
  const _PermissionsPanel();

  @override
  State<_PermissionsPanel> createState() => _PermissionsPanelState();
}

class _PermissionsPanelState extends State<_PermissionsPanel>
    with WidgetsBindingObserver {
  Map<String, bool> _p = const {
    'notification': false,
    'audio': false,
    'overlay': false,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final r = await Native.permissionStatus();
    if (mounted) setState(() => _p = r);
  }

  Widget _row(String title, String why, bool on, String button,
      Future<void> Function() act) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      leading: Icon(on ? Icons.check_circle : Icons.radio_button_unchecked,
          color: on ? Colors.greenAccent : Colors.white38),
      title: Text(title, style: const TextStyle(fontSize: 20)),
      subtitle: Text(why,
          style: const TextStyle(fontSize: 15, color: Colors.white60)),
      trailing: on
          ? null
          : ElevatedButton(
              onPressed: () async {
                await act();
                _refresh();
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                child: Text(button, style: const TextStyle(fontSize: 16)),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _row(
          'Notification access',
          'Reads the title, artist, album and cover of what is playing, and '
              'checks whether navigation is guiding. Required.',
          _p['notification'] == true,
          'Open settings',
          Native.openAccessSettings,
        ),
        _row(
          'Audio access',
          'Only for the live visualizer. VYBE does not use the microphone or '
              'record anything.',
          _p['audio'] == true,
          'Allow',
          () async {
            await Native.requestAudio();
          },
        ),
        _row(
          'Display over other apps',
          'Lets Android allow VYBE to open itself when music starts. VYBE '
              'draws nothing over other apps.',
          _p['overlay'] == true,
          'Open settings',
          Native.openOverlaySettings,
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Text(
            'The internet is used only if album art search or lyrics are on, '
            'and sends just the song title and artist. Everything else stays '
            'on this device.',
            style: TextStyle(fontSize: 15, color: Colors.white54, height: 1.4),
          ),
        ),
      ],
    );
  }
}

/// Which players may open VYBE: Auto follows the rules, or force it.
class PlayersScreen extends StatefulWidget {
  const PlayersScreen({super.key});

  @override
  State<PlayersScreen> createState() => _PlayersScreenState();
}

class _PlayersScreenState extends State<PlayersScreen> {
  List<PlayerInfo>? _players;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await Native.getPlayers();
    if (mounted) setState(() => _players = r);
  }

  Future<void> _set(PlayerInfo p, String mode) async {
    await Native.setPlayerOverride(p.pkg, mode);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _players;
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
                    child: Text('Players that may open VYBE',
                        style:
                            TextStyle(fontSize: 26, fontWeight: FontWeight.w300)),
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
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: list == null
                      ? const Center(child: CircularProgressIndicator())
                      : list.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.all(32),
                              child: Text(
                                'No players seen yet. Start music in a player '
                                'app and it will appear here.',
                                style: TextStyle(
                                    fontSize: 19, color: Colors.white70),
                              ),
                            )
                          : ListView(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                              children: [
                                const Padding(
                                  padding: EdgeInsets.fromLTRB(8, 4, 8, 8),
                                  child: Text(
                                    'Auto lets music players open VYBE and keeps '
                                    'video and navigation apps out. Allow or '
                                    'Block overrides that for one app.',
                                    style: TextStyle(
                                        fontSize: 15, color: Colors.white60),
                                  ),
                                ),
                                for (final p in list) _playerRow(p),
                              ],
                            ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playerRow(PlayerInfo p) {
    const modes = ['auto', 'allow', 'block'];
    const names = ['Auto', 'Allow', 'Block'];
    final sel = modes.indexOf(p.override).clamp(0, 2).toInt();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.label, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 2),
          Text(
            p.kindLabel + (p.allowed ? ' · can open VYBE' : ' · will not open VYBE'),
            style: TextStyle(
                fontSize: 15,
                color: p.allowed ? Colors.greenAccent : Colors.white54),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            children: List<Widget>.generate(
              3,
              (i) => ChoiceChip(
                label: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Text(names[i], style: const TextStyle(fontSize: 17)),
                ),
                selected: i == sel,
                onSelected: (_) => _set(p, modes[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
