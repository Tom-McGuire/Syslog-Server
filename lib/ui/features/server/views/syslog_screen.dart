import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../view_models/syslog_view_model.dart';
import 'syslog_control_bar.dart';
import 'syslog_detail_panel.dart';
import 'syslog_filter_bar.dart';
import 'syslog_table_view.dart';

class SyslogScreen extends StatelessWidget {
  const SyslogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final hasSelection = context.select<SyslogViewModel, bool>(
      (vm) => vm.selectedRecord != null,
    );

    return Scaffold(
      body: Column(
        children: [
          // Top Control Toolbar
          const SyslogControlBar(),

          // Filter bar
          const SyslogFilterBar(),

          // Main Log Table
          const Expanded(
            child: SyslogTableView(),
          ),

          // Detail inspector (collapsible)
          if (hasSelection) const SyslogDetailPanel(),
        ],
      ),
    );
  }
}
