import 'syslog_facility.dart';
import 'syslog_severity.dart';

class SyslogFilterCriteria {
  const SyslogFilterCriteria({
    this.searchQuery = '',
    this.selectedSeverities = const {},
    this.selectedFacilities = const {},
    this.remoteIp = '',
    this.hostname = '',
    this.appName = '',
    this.timeStartMs,
    this.timeEndMs,
    this.sortColumn = 'id',
    this.sortAscending = false,
  });

  final String searchQuery;
  final Set<SyslogSeverity> selectedSeverities;
  final Set<SyslogFacility> selectedFacilities;
  final String remoteIp;
  final String hostname;
  final String appName;
  final int? timeStartMs;
  final int? timeEndMs;
  final String sortColumn;
  final bool sortAscending;

  bool get hasActiveFilter =>
      searchQuery.trim().isNotEmpty ||
      selectedSeverities.isNotEmpty ||
      selectedFacilities.isNotEmpty ||
      remoteIp.trim().isNotEmpty ||
      hostname.trim().isNotEmpty ||
      appName.trim().isNotEmpty ||
      timeStartMs != null ||
      timeEndMs != null;

  SyslogFilterCriteria copyWith({
    String? searchQuery,
    Set<SyslogSeverity>? selectedSeverities,
    Set<SyslogFacility>? selectedFacilities,
    String? remoteIp,
    String? hostname,
    String? appName,
    int? timeStartMs,
    int? timeEndMs,
    String? sortColumn,
    bool? sortAscending,
  }) {
    return SyslogFilterCriteria(
      searchQuery: searchQuery ?? this.searchQuery,
      selectedSeverities: selectedSeverities ?? this.selectedSeverities,
      selectedFacilities: selectedFacilities ?? this.selectedFacilities,
      remoteIp: remoteIp ?? this.remoteIp,
      hostname: hostname ?? this.hostname,
      appName: appName ?? this.appName,
      timeStartMs: timeStartMs ?? this.timeStartMs,
      timeEndMs: timeEndMs ?? this.timeEndMs,
      sortColumn: sortColumn ?? this.sortColumn,
      sortAscending: sortAscending ?? this.sortAscending,
    );
  }
}
