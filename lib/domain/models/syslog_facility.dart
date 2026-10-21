enum SyslogFacility {
  kern(0, 'kern', 'Kernel messages'),
  user(1, 'user', 'User-level messages'),
  mail(2, 'mail', 'Mail system'),
  daemon(3, 'daemon', 'System daemons'),
  auth(4, 'auth', 'Security/authorization'),
  syslog(5, 'syslog', 'Messages generated internally by syslogd'),
  lpr(6, 'lpr', 'Line printer subsystem'),
  news(7, 'news', 'Network news subsystem'),
  uucp(8, 'uucp', 'UUCP subsystem'),
  cron(9, 'cron', 'Clock daemon'),
  authpriv(10, 'authpriv', 'Security/authorization (private)'),
  ftp(11, 'ftp', 'FTP daemon'),
  ntp(12, 'ntp', 'NTP subsystem'),
  security(13, 'security', 'Log audit'),
  console(14, 'console', 'Log alert'),
  solarisCron(15, 'cron2', 'Clock daemon (Solaris)'),
  local0(16, 'local0', 'Local use 0'),
  local1(17, 'local1', 'Local use 1'),
  local2(18, 'local2', 'Local use 2'),
  local3(19, 'local3', 'Local use 3'),
  local4(20, 'local4', 'Local use 4'),
  local5(21, 'local5', 'Local use 5'),
  local6(22, 'local6', 'Local use 6'),
  local7(23, 'local7', 'Local use 7');

  const SyslogFacility(this.code, this.nameStr, this.description);

  final int code;
  final String nameStr;
  final String description;

  static SyslogFacility fromCode(int code) {
    if (code >= 0 && code < SyslogFacility.values.length) {
      return SyslogFacility.values[code];
    }
    return SyslogFacility.user;
  }
}
