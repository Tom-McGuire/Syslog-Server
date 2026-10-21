# Syslog Server

A portable, cross-platform Syslog server desktop application built with **Flutter Desktop** (Windows, macOS, Linux) and powered by an embedded **SQLite** engine.

Designed for network engineers, system administrators, and developers who need a lightweight, self-contained Syslog server to capture, inspect, and analyze logs sent from network devices (firewalls, switches, routers, Linux/Windows servers, ESXi hosts) in real-time.

---

## ✨ Features

- **Cross-Platform Desktop**: Native support for **Windows**, **macOS**, and **Linux**.
- **Dual Protocol Ingestion**: Simultaneous **UDP** and **TCP** socket listeners with configurable port (standard `514`, `1514`, `5140`, or custom).
- **Standards Compliant**:
  - **RFC 5424** (Modern IETF Syslog with structured headers, app names, PIDs, message IDs).
  - **RFC 3164** (BSD legacy format with hostname and tag parsing).
  - Resilient fallback for unstructured and device-specific logs (e.g., Cisco ASA, switches).
- **SQLite Storage & Query Engine**:
  - Embedded `sqlite3` database with Write-Ahead Logging (WAL) for high-throughput packet ingestion without UI stutter.
  - Micro-batch buffering (50ms) to easily absorb sudden network log storms.
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
- **Log Inspection & Export**:
  - Bottom collapsible inspection panel with formatted metadata and raw packet viewer.
  - Right-click context menu (copy message, copy raw packet, quick filter by IP or host).
  - One-click export to **CSV** and **JSON**.
  - Built-in **Demo Logs** generator to test the interface without external hardware.

---

## 🛠️ Architecture

```
lib/
├── domain/                     # Pure domain logic and models
│   └── models/
│       ├── syslog_record.dart       # Syslog entry entity
│       ├── syslog_severity.dart     # Severity levels & color coding
│       ├── syslog_facility.dart     # Syslog facilities (0-23)
│       ├── syslog_filter.dart       # Filter & search criteria
│       └── server_status.dart       # Ingestion statistics
│
├── data/                       # Data services & repositories
│   ├── repositories/
│   │   └── syslog_repository.dart   # Coordinates sockets and SQLite
│   └── services/
│       ├── parser/
│       │   └── syslog_parser.dart   # RFC 5424 & RFC 3164 parser
│       ├── database/
│       │   └── syslog_database_service.dart # SQLite batching & queries
│       ├── listener/
│       │   └── syslog_listener_service.dart # UDP & TCP sockets
│       ├── export/
│       │   └── export_service.dart  # CSV & JSON export
│       └── generator/
│           └── demo_syslog_generator.dart   # Sample device logs
│
└── ui/                         # Presentation Layer
    ├── theme/
    │   └── app_theme.dart           # Desktop dark theme
    └── features/
        └── server/
            ├── view_models/
            │   └── syslog_view_model.dart   # Provider ChangeNotifier
            └── views/
                ├── syslog_screen.dart       # Main scaffold
                ├── syslog_control_bar.dart  # Server start/stop & port configuration
                ├── syslog_filter_bar.dart   # Search & severity chips
                ├── syslog_table_view.dart   # Virtualized resizable table
                └── syslog_detail_panel.dart # Raw packet inspector
```

---

## 🚀 Getting Started

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

## 🔒 Port 514 & Platform Permissions

- **Windows**: Standard users can bind UDP sockets, but Windows Defender Firewall will prompt to allow incoming network traffic on first run.
- **macOS & Linux**: Standard Syslog port `514` is a privileged port (`< 1024`).
  - To listen on `514`, run the app with elevated permissions (e.g. `sudo`), or
  - Configure the server port to an unprivileged port such as **`1514`** or **`5140`** (using the preset dropdown in the toolbar) and configure your sending devices to forward to that port.

---

## 🧪 Testing

Run the automated test suite:
```bash
flutter test
```

Includes unit tests for RFC 5424 / RFC 3164 parsing, SQLite batch ingestion & SQL queries, live loopback UDP socket ingestion, and widget UI smoke tests.

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
