import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'ui/features/server/view_models/syslog_view_model.dart';
import 'ui/features/server/views/syslog_screen.dart';
import 'ui/theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SyslogServerApp());
}

class SyslogServerApp extends StatelessWidget {
  const SyslogServerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SyslogViewModel(),
      child: MaterialApp(
        title: 'Syslog Server',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme(),
        home: const SyslogScreen(),
      ),
    );
  }
}
