# Graph Report - youtube  (2026-11-14)

## Corpus Check
- 46 files · ~111,228 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 486 nodes · 766 edges · 22 communities (11 shown, 11 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 18 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Flutter App UI Core
- FastAPI Backend Endpoints
- SQLite DB & Sync Logic
- Windows Native Runner Entry
- Win32 Window Management
- Flutter Windows Host View
- Flutter Widget Tests
- PWA Web Manifest
- Win32 Window Lifecycle
- Custom Dialogs & Hold Menus
- Windows DPI & Msg Dispatch
- Win32 Geometry Primitives
- Flutter Plugin Registrant
- Project Documentation
- Android MainActivity Host
- Frontend Docs Stub
- Flutter Root Widget

## God Nodes (most connected - your core abstractions)
1. `get_conn()` - 23 edges
2. `Win32Window` - 21 edges
3. `sync_public_subscriptions_by_channel()` - 13 edges
4. `_run_background_refresh()` - 12 edges
5. `sync_channel_videos()` - 12 edges
6. `get_setting()` - 11 edges
7. `list_channels()` - 11 edges
8. `refresh_all_channels_comprehensive()` - 11 edges
9. `search_and_cache_subscribed_videos()` - 11 edges
10. `FlutterWindow` - 10 edges

## Surprising Connections (you probably didn't know these)
- `wWinMain()` --calls--> `CreateAndAttachConsole()`  [INFERRED]
  frontend/windows/runner/main.cpp → frontend/windows/runner/utils.cpp
- `get_settings()` --calls--> `get_setting()`  [EXTRACTED]
  backend/main.py → backend/db.py
- `import_channels_csv()` --calls--> `get_setting()`  [EXTRACTED]
  backend/main.py → backend/db.py
- `refresh_youtube()` --calls--> `get_setting()`  [EXTRACTED]
  backend/main.py → backend/db.py
- `import_channels_csv()` --calls--> `upsert_channel()`  [EXTRACTED]
  backend/main.py → backend/db.py

## Import Cycles
- None detected.

## Communities (22 total, 11 thin omitted)

### Community 0 - "Flutter App UI Core"
Cohesion: 0.01
Nodes (185): accentColor, activeBgColor, _activeDurationThumb, apiKeyPreview, _applyLocalFilterAndPagination, _applyPeriodChoice, _applySyncDataString, baseUrl (+177 more)

### Community 1 - "FastAPI Backend Endpoints"
Cohesion: 0.05
Nodes (46): clear_demo_data(), increment_channel_watched(), record_watch(), set_channel_hidden(), set_setting(), AddChannelPayload, DeviceSyncPayload, disable_frontend_cache() (+38 more)

### Community 2 - "SQLite DB & Sync Logic"
Cohesion: 0.09
Nodes (38): _apply_hide_filter_clause(), classify_region(), delete_channel(), duration_to_seconds(), get_conn(), get_setting(), init_db(), _is_newer_or_equal_ts() (+30 more)

### Community 3 - "Windows Native Runner Entry"
Cohesion: 0.14
Nodes (4): wWinMain(), CreateAndAttachConsole(), GetCommandLineArguments(), Utf8FromUtf16()

### Community 4 - "Win32 Window Management"
Cohesion: 0.18
Nodes (5): Scale(), Win32Window::Win32Window(), WindowClassRegistrar, class_registered_, instance_

### Community 5 - "Flutter Windows Host View"
Cohesion: 0.12
Nodes (4): FlutterWindow, flutter_controller_, FlutterWindow::FlutterWindow(), project_

### Community 7 - "PWA Web Manifest"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 8 - "Win32 Window Lifecycle"
Cohesion: 0.24
Nodes (4): Win32Window, child_content_, quit_on_close_, window_handle_

### Community 9 - "Custom Dialogs & Hold Menus"
Cohesion: 0.27
Nodes (8): _CustomCalendarDialog, _CustomCalendarDialogState, _HoldToActionMenuItem, _HoldToActionMenuItemState, TabPickerDialog, _TabPickerDialogState, YouTubeHomeScreen, _YouTubeHomeScreenState

### Community 11 - "Win32 Geometry Primitives"
Cohesion: 0.21
Nodes (6): Point, x, y, Size, height, width

### Community 13 - "Project Documentation"
Cohesion: 0.50
Nodes (3): Cara Menjalankan, Fitur Utama, Yorpersonal YouTube Subscriptions Hub

## Knowledge Gaps
- **197 isolated node(s):** `baseUrl`, `sidebarMode`, `filterMinimized`, `loading`, `refreshingYouTube` (+192 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 305 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **11 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Win32Window` connect `Win32 Window Lifecycle` to `Windows Native Runner Entry`, `Win32 Window Management`, `Flutter Windows Host View`, `Windows DPI & Msg Dispatch`, `Win32 Geometry Primitives`?**
  _High betweenness centrality (0.041) - this node is a cross-community bridge._
- **What connects `baseUrl`, `sidebarMode`, `filterMinimized` to the rest of the system?**
  _197 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Flutter App UI Core` be split into smaller, more focused modules?**
  _Cohesion score 0.009478672985781991 - nodes in this community are weakly interconnected._
- **Why does `FlutterWindow` connect `Flutter Windows Host View` to `Win32 Window Lifecycle`, `Windows Native Runner Entry`?**
  _High betweenness centrality (0.022) - this node is a cross-community bridge._
- **Should `FastAPI Backend Endpoints` be split into smaller, more focused modules?**
  _Cohesion score 0.053830227743271224 - nodes in this community are weakly interconnected._
- **Should `SQLite DB & Sync Logic` be split into smaller, more focused modules?**
  _Cohesion score 0.08672659968270756 - nodes in this community are weakly interconnected._
- **Should `Windows Native Runner Entry` be split into smaller, more focused modules?**
  _Cohesion score 0.14285714285714285 - nodes in this community are weakly interconnected._