import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import '../../../widgets/guided_tour_overlay.dart';
import '../view_models/syslog_view_model.dart';
import 'syslog_control_bar.dart';
import 'syslog_detail_panel.dart';
import 'syslog_filter_bar.dart';
import 'syslog_table_view.dart';

class SyslogScreen extends StatefulWidget {
  const SyslogScreen({super.key});

  @override
  State<SyslogScreen> createState() => _SyslogScreenState();
}

class _SyslogScreenState extends State<SyslogScreen> {
  final GlobalKey _zone2Key = GlobalKey();
  final GlobalKey _zone3Key = GlobalKey();
  final GlobalKey _filterBarKey = GlobalKey();
  final GlobalKey _tableViewKey = GlobalKey();
  final GlobalKey _detailPanelKey = GlobalKey();

  List<GuidedTourStep> _buildTourSteps(SyslogViewModel vm) {
    return [
      GuidedTourStep(
        targetKey: _zone2Key,
        title: 'Zone 2: Bind Interface, Protocol & Port',
        description:
            'Select the network adapter to bind (or 0.0.0.0 for all interfaces), configure the listener port (default 514), and toggle UDP/TCP ingestion protocols.',
      ),
      GuidedTourStep(
        targetKey: _zone3Key,
        title: 'Zone 3: Start / Pause Listener',
        description:
            'Start the RFC 3164/5424 syslog receiver socket to capture live device logs in real time, or stop the listener at any time.',
      ),
      GuidedTourStep(
        targetKey: _filterBarKey,
        title: 'Severity & Facility Filter Bar',
        description:
            'Search messages, filter by RFC syslog severity levels or facility codes, and toggle visibility for named or auto-detected network devices.',
      ),
      GuidedTourStep(
        targetKey: _tableViewKey,
        title: 'Real-Time Syslog Stream Table',
        description:
            'Inspect incoming and demo syslog events sorted by timestamp, severity, host, or facility. Click any row to open full packet details.',
        onStepEnter: () {
          if (vm.selectedRecord == null && vm.logs.isNotEmpty) {
            vm.selectRecord(vm.logs.first);
          }
        },
      ),
      GuidedTourStep(
        targetKey: _detailPanelKey,
        title: 'Message Inspector & Shared Device Naming',
        description:
            'Examine parsed syslog fields, raw payloads, and detected MAC addresses. Assign custom names here to share device identities across Network Suite.',
        onStepEnter: () {
          if (vm.selectedRecord == null && vm.logs.isNotEmpty) {
            vm.selectRecord(vm.logs.first);
          }
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.read<SyslogViewModel>();
    final hasSelection = context.select<SyslogViewModel, bool>(
      (model) => model.selectedRecord != null,
    );
    final isDemoMode = context.select<SyslogViewModel, bool>(
      (model) => model.isDemoMode,
    );

    return Scaffold(
      body: GuidedTourOverlay(
        isActive: isDemoMode,
        steps: _buildTourSteps(vm),
        onFinish: () => vm.endDemoWalkthrough(),
        child: Column(
          children: [
            // Top Control Toolbar
            SyslogControlBar(
              zone2Key: _zone2Key,
              zone3Key: _zone3Key,
            ),

            // Filter bar
            SyslogFilterBar(key: _filterBarKey),

            // Main Log Table
            Expanded(
              child: SyslogTableView(key: _tableViewKey),
            ),

            // Detail inspector (collapsible)
            if (hasSelection) SyslogDetailPanel(key: _detailPanelKey),
          ],
        ),
      ),
    );
  }
}
