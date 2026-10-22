import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/audio/synth_engine.dart';
import 'services/settings_store.dart';
import 'state/audio_monitor.dart';
import 'state/synth_state.dart';
import 'ui/screens/synth_screen.dart';
import 'ui/theme.dart';

class SynthApp extends StatelessWidget {
  // ignore: prefer_initializing_formals
  // ignore: prefer_initializing_formals
  const SynthApp({super.key, SynthEngine? engine, SettingsStore? store})
      // ignore: prefer_initializing_formals
      : _engine = engine,
        // ignore: prefer_initializing_formals
        _store = store;
  final SynthEngine? _engine;

  /// Where the settings live (null = the app's documents folder).
  final SettingsStore? _store;

  @override
  Widget build(BuildContext context) {
    final engine = _engine ?? NativeSynthEngine();
    return MultiProvider(
      providers: [
        Provider<SynthEngine>.value(value: engine),
        ChangeNotifierProvider(create: (_) => AudioMonitor(engine)),
        ChangeNotifierProvider(
          create: (_) {
            final state = SynthState(engine, _store ?? SettingsStore());
            // Open the audio stream once the first frame is up: on recent
            // Android versions a stream opened before the app is in the
            // foreground can be muted.
            WidgetsBinding.instance.addPostFrameCallback((_) => state.start());
            return state;
          },
        ),
      ],
      child: MaterialApp(
        title: 'Twin Sound',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const _SaveOnBackground(child: SynthScreen()),
      ),
    );
  }
}

/// Flushes the settings when the app leaves the foreground, so nothing is lost
/// if the system kills it afterwards.
class _SaveOnBackground extends StatefulWidget {
  const _SaveOnBackground({required this.child});
  final Widget child;

  @override
  State<_SaveOnBackground> createState() => _SaveOnBackgroundState();
}

class _SaveOnBackgroundState extends State<_SaveOnBackground> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) context.read<SynthState>().flush();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
