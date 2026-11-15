import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:network_suite_shared/network_suite_shared.dart';
import 'package:provider/provider.dart';

import 'domain/models/launch_adapter_config.dart';
import 'ui/features/server/view_models/syslog_view_model.dart';
import 'ui/features/server/views/syslog_screen.dart';
import 'ui/theme/app_theme.dart';

Future<void> main([List<String> args = const []]) async {
  WidgetsFlutterBinding.ensureInitialized();
  final launchAdapterConfig = LaunchAdapterConfig.fromArgs(args);

  // Safely initialize shared device database (standalone resilient).
  try {
    await SharedDeviceDatabase.instance.init();
    final mode = await SharedDeviceDatabase.instance.getThemeMode();
    AppTheme.applyThemeMode(mode);
  } catch (e) {
    debugPrint('Shared device database fallback: $e');
  }

  runApp(SyslogServerApp(launchAdapterConfig: launchAdapterConfig));
}

class SyslogServerApp extends StatefulWidget {
  const SyslogServerApp({
    super.key,
    this.launchAdapterConfig,
    this.viewModel,
    this.database,
  });

  final LaunchAdapterConfig? launchAdapterConfig;
  final SyslogViewModel? viewModel;
  final SharedDeviceDatabase? database;

  @override
  State<SyslogServerApp> createState() => _SyslogServerAppState();
}

class _SyslogServerAppState extends State<SyslogServerApp> {
  late ThemeMode _themeMode;
  StreamSubscription<void>? _dbSubscription;
  Timer? _pollTimer;

  SharedDeviceDatabase get _db =>
      widget.database ?? SharedDeviceDatabase.instance;

  ThemeMode get _currentThemeMode =>
      AppTheme.isDark ? ThemeMode.dark : ThemeMode.light;

  @override
  void initState() {
    super.initState();
    _themeMode = _currentThemeMode;
    _syncTheme();
    _dbSubscription = _db.onDatabaseChanged.listen((_) => _syncTheme());
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      _pollTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _syncTheme(),
      );
    }
  }

  Future<void> _syncTheme() async {
    try {
      final modeStr = await _db.getThemeMode();
      AppTheme.applyThemeMode(modeStr);
      final nextMode = _currentThemeMode;
      if (mounted && _themeMode != nextMode) {
        setState(() {
          _themeMode = nextMode;
        });
      }
    } catch (_) {
      // Ignore if shared database is unavailable during initialization.
    }
  }

  @override
  void dispose() {
    _dbSubscription?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp(
      title: 'Syslog Server',
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      theme: AppTheme.lightTheme(),
      darkTheme: AppTheme.darkTheme(),
      home: KeyedSubtree(
        key: ValueKey(_themeMode),
        child: const SyslogScreen(),
      ),
    );

    if (widget.viewModel != null) {
      return ChangeNotifierProvider<SyslogViewModel>.value(
        value: widget.viewModel!,
        child: app,
      );
    }

    return ChangeNotifierProvider<SyslogViewModel>(
      create: (_) => SyslogViewModel(
        initialAdapterConfig: widget.launchAdapterConfig,
      ),
      child: app,
    );
  }
}
