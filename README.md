# Syslog Server

A portable, cross-platform Syslog server desktop application built with **Flutter Desktop** (Windows, macOS, Linux) and powered by an embedded **SQLite** engine.

Designed for network engineers, system administrators, and developers who need a lightweight, self-contained Syslog server to capture, inspect, and analyze logs sent from network devices (firewalls, switches, routers, Linux/Windows servers, ESXi hosts) in real-time or offline via CSV imports.

---

## Features

- **Cross-Platform Desktop**: Native support for **Windows**, **macOS**, and **Linux**.
- **Dual Protocol Ingestion**: Simultaneous **UDP** and **TCP** socket listeners with configurable port (standard `514`, `1514`, `5140`, or custom).
- **Network Interface Selector**: Detects active network adapters (Ethernet, Wi-Fi, Loopback, or All Interfaces `0.0.0.0`) with a one-click "Copy IP" helper for quick device configuration.
- **Standards Compliant**:
  - **RFC 5424** (Modern IETF Syslog with structured headers, app names, PIDs, message IDs).
  - **RFC 3164** (BSD legacy format with hostname and tag parsing).
  - Resilient fallback for unstructured and device-specific logs (e.g., Cisco ASA, switches).
- **SQLite Storage & Query Engine**:
  - Embedded `sqlite3` database with indexed queries for high-throughput packet ingestion without UI stutter.
  - Micro-batch buffering (50ms) to easily absorb sudden network log storms.
  - Automatic retention limit (oldest records pruned beyond maximum row limit).
- **Virtualized High-Performance Table View**:
  - Modeled after [Packet Inspector](https://github.com/Tom-McGuire/packet-inspector)'s high-density desktop table.
  - **Dynamic resizable columns** with drag handles.
  - **Column sorting** (ID, Time, Severity, Facility, Source IP, Host, App).
  - **Infinite scrolling pagination** (1,000 logs per batch).
- **Interactive Multi-Level Filtering**:
  - Instant full-text search across messages, hostnames, applications, and IPs.
  - Color-coded severity chips with live message counts (Emergency, Alert, Critical, Error, Warning, Notice, Info, Debug).
  - Facility multi-select dropdown (kern, user, auth, daemon, local0..local7, etc.).
  - Dedicated source IP filter input.
- **Offline Investigation (CSV Import & Export)**:
  - **CSV Import**: Load CSV logs exported from this application, Kiwi Syslog, Splunk, Graylog, or raw syslog text files.
  - **Export**: One-click export to sanitized **CSV** (formula injection protected) and **JSON**.
  - **Demo Logs**: Built-in sample log generator to test the interface without external hardware.
- **Shared Device Library Integration (Network Suite)**:
  - Dissects hardware MAC addresses in log payloads (common in DHCP snooping, 802.1X, and firewall logs).
  - Resolves MAC addresses to friendly custom names and IEEE OUI manufacturers via `network_suite_shared`.
  - Interactive chips with single-click and right-click "Rename Device" dialog that syncs device identities across all suite applications via SQLite WAL.
  - Fully resilient standalone operation: local socket and database operations run independently of shared library availability.
- **Log Inspection & Utilities**:
  - Bottom collapsible inspection panel with formatted metadata and raw packet viewer.
  - Right-click context menu (copy message, copy raw packet, quick filter by IP or host).

---

## Architecture

```
lib/
|-- domain/                     # Pure domain logic and models
|   `-- models/
|       |-- syslog_record.dart       # Syslog entry entity
|       |-- syslog_severity.dart     # Severity levels & color coding
|       |-- syslog_facility.dart     # Syslog facilities (0-23)
|       |-- syslog_filter.dart       # Filter & search criteria
|       |-- server_status.dart       # Ingestion statistics
|       `-- network_adapter_info.dart # Detected network interfaces
|
|-- data/                       # Data services & repositories
|   |-- repositories/
|   |   `-- syslog_repository.dart   # Coordinates sockets and SQLite
|   `-- services/
|       |-- parser/
|       |   `-- syslog_parser.dart   # RFC 5424 & RFC 3164 parser
|       |-- database/
|       |   `-- syslog_database_service.dart # SQLite batching & queries
|       |-- listener/
|       |   `-- syslog_listener_service.dart # UDP & TCP sockets
|       |-- import/
|       |   `-- csv_import_service.dart # CSV & raw log importer
|       |-- export/
|       |   `-- export_service.dart  # CSV & JSON export
|       |-- network/
|       |   `-- network_adapter_service.dart # Adapter enumeration
|       `-- generator/
|           `-- demo_syslog_generator.dart   # Sample device logs
|
`-- ui/                         # Presentation Layer
    |-- theme/
    |   `-- app_theme.dart           # Desktop dark theme
    `-- features/
        `-- server/
            |-- view_models/
            |   `-- syslog_view_model.dart   # Provider ChangeNotifier
            `-- views/
                |-- syslog_screen.dart       # Main scaffold
                |-- syslog_control_bar.dart  # Controls, interface, & port
                |-- syslog_filter_bar.dart   # Search & severity chips
                |-- syslog_table_view.dart   # Virtualized resizable table
                `-- syslog_detail_panel.dart # Raw packet inspector
```

---

## ⚠️ Note on Windows / macOS Security Prompts

These tools are free and independent projects and are not yet code-signed with expensive commercial certificates:

- **Windows**: If SmartScreen appears, click **"More info"** → **"Run anyway"**.
- **macOS**: Right-click the `.app` file, select **Open**, and confirm the prompt (or run `xattr -c <AppName>.app` in Terminal).

---

## Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.24+ recommended)
- Desktop build toolchains:
  - **Windows**: Visual Studio 2022 with "Desktop development with C++"
  - **macOS**: Xcode & Command Line Tools
  - **Linux**: `clang`, `cmake`, `ninja-build`, `pkg-config`, `libgtk-3-dev`

### Running the Application

1. Clone the repository:
   ```bash
   git clone https://github.com/Tom-McGuire/Syslog-Server.git
   cd Syslog-Server
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run on your desktop platform:
   ```bash
   # Windows
   flutter run -d windows

   # macOS
   flutter run -d macos

   # Linux
   flutter run -d linux
   ```

---

## Port 514 & Platform Permissions

- **Windows**: Standard users can bind UDP sockets, but Windows Defender Firewall will prompt to allow incoming network traffic on first run.
- **macOS & Linux**: Standard Syslog port `514` is a privileged port (`< 1024`).
  - To listen on `514`, run the app with elevated permissions (e.g. `sudo`), or
  - Configure the server port to an unprivileged port such as **`1514`** or **`5140`** (using the preset dropdown in the toolbar) and configure your sending devices to forward to that port.

---

## Testing

Run the automated test suite:
```bash
flutter test
```

Includes unit tests for RFC 5424 / RFC 3164 parsing, SQLite batch ingestion & SQL queries, live loopback UDP socket ingestion, CSV import/export, and widget UI smoke tests.

---

## License

MIT License. See [LICENSE](LICENSE) for details.
