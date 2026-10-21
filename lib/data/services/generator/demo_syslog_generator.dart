import '../../../domain/models/syslog_record.dart';
import '../parser/syslog_parser.dart';

class DemoSyslogGenerator {
  static final List<({String ip, int port, String raw})> _samples = [
    (
      ip: '192.168.1.1',
      port: 514,
      raw: '<189>1 2026-10-21T19:30:00.123Z fw01.corp.local cisco-asa 412001 - - %ASA-5-111008: User \'admin\' executed the \'show running-config\' command.',
    ),
    (
      ip: '192.168.1.254',
      port: 514,
      raw: '<187>Oct 21 19:30:02 sw-core-01 %LINK-3-UPDOWN: Interface GigabitEthernet1/0/24, changed state to down',
    ),
    (
      ip: '192.168.1.254',
      port: 514,
      raw: '<186>Oct 21 19:30:04 sw-core-01 %SPANTREE-2-BLOCK_BPDUGUARD: Received BPDU on port Gi1/0/24 with BPDU Guard enabled. Disabling port.',
    ),
    (
      ip: '10.0.0.15',
      port: 514,
      raw: '<34>1 2026-10-21T19:30:07.450Z srv-auth01.internal sshd 18942 ID47 - Failed password for invalid user root from 203.0.113.88 port 48212 ssh2',
    ),
    (
      ip: '10.0.0.15',
      port: 514,
      raw: '<38>Oct 21 19:30:08 srv-auth01 sudo[19012]: pam_unix(sudo:auth): authentication failure; logname=alice uid=1000 euid=0 tty=/dev/pts/2 ruser=alice rhost= user=alice',
    ),
    (
      ip: '10.0.0.20',
      port: 514,
      raw: '<13>1 2026-10-21T19:30:10.001Z web-lb-01 nginx 8200 - - 203.0.113.45 - - [21/Oct/2026:19:30:10 +0000] "GET /api/v1/health HTTP/1.1" 200 15 "-" "kube-probe/1.28"',
    ),
    (
      ip: '10.0.0.20',
      port: 514,
      raw: '<11>1 2026-10-21T19:30:12.782Z web-lb-01 nginx 8200 - - 198.51.100.12 - - [21/Oct/2026:19:30:12 +0000] "POST /api/v1/checkout HTTP/1.1" 500 241 "https://store.local/" "Mozilla/5.0"',
    ),
    (
      ip: '192.168.10.1',
      port: 514,
      raw: '<130>Oct 21 19:30:15 edge-rtr-01 %BGP-2-NEIGHBOR_RESET: Neighbor 198.51.100.1 active reset (Peer closed TCP connection)',
    ),
    (
      ip: '10.0.0.5',
      port: 514,
      raw: '<27>1 2026-10-21T19:30:18.010Z db-cluster-primary postgres 4512 - - [3-1] LOG: checkpoint starting: time',
    ),
    (
      ip: '10.0.0.5',
      port: 514,
      raw: '<27>1 2026-10-21T19:30:21.340Z db-cluster-primary postgres 4512 - - [4-1] LOG: checkpoint complete: wrote 428 buffers (2.6%); 0 WAL file(s) added, 0 removed, 1 recycled',
    ),
    (
      ip: '192.168.1.50',
      port: 514,
      raw: '<190>Oct 21 19:30:25 esxi-host-04 hostd[100234]: [Originator@6876 sub=Vmsvc.vm:/vmfs/volumes/datastore1/vm-win10/vm-win10.vmx] State Change event: poweredOn',
    ),
    (
      ip: '192.168.1.1',
      port: 514,
      raw: '<188>1 2026-10-21T19:30:28.910Z fw01.corp.local cisco-asa 106023 - - %ASA-4-106023: Deny tcp src outside:198.51.100.22/55123 dst inside:10.0.0.20/443 by access-group "OUTSIDE-IN"',
    ),
    (
      ip: '10.0.0.12',
      port: 514,
      raw: '<86>Oct 21 19:30:30 storage-san-01 storage-daemon: Volume [datastore-nvme-01] capacity utilization reached 88%',
    ),
    (
      ip: '10.0.0.15',
      port: 514,
      raw: '<38>1 2026-10-21T19:30:33.200Z srv-auth01.internal systemd 1 - - systemd-journald.service: Failed with result \'exit-code\'.',
    ),
    (
      ip: '192.168.1.1',
      port: 514,
      raw: '<185>Oct 21 19:30:35 fw01 %ASA-1-105001: ARN duplicate IP address 192.168.1.100 detected on interface inside',
    ),
  ];

  static List<SyslogRecord> generateDemoLogs() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final records = <SyslogRecord>[];

    for (int i = 0; i < _samples.length; i++) {
      final sample = _samples[i];
      final record = SyslogParser.parse(
        raw: sample.raw,
        remoteIp: sample.ip,
        remotePort: sample.port,
        transport: 'UDP',
        receivedAtMs: now - ((_samples.length - i) * 1200),
      );
      records.add(record);
    }

    return records;
  }
}
