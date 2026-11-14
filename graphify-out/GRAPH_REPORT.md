# Graph Report - youtube  (2026-11-14)

## Corpus Check
- 49 files · ~125,007 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 29 file(s) not represented in the graph (top: .xml 7, (none) 6, .bat 6)

## Summary
- 656 nodes · 1012 edges · 31 communities (17 shown, 14 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 21 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Community 0
- Community 1
- Community 2
- Community 3
- Community 4
- Community 5
- Community 6
- Community 7
- Community 8
- Community 9
- Community 10
- Community 11
- Community 12
- Community 13
- Community 14
- Community 15
- Community 16
- Community 17
- Community 18
- Community 19
- Community 20
- Community 21
- Community 22
- Community 23
- Community 24
- Community 25

## God Nodes (most connected - your core abstractions)
1. `get_conn()` - 29 edges
2. `Win32Window` - 21 edges
3. `sync_channel_videos()` - 19 edges
4. `list_channels()` - 16 edges
5. `get_setting()` - 13 edges
6. `upsert_channel()` - 13 edges
7. `_run_background_refresh()` - 13 edges
8. `refresh_all_channels_comprehensive()` - 13 edges
9. `query_videos()` - 12 edges
10. `test_init_db_drops_legacy_region_and_refresh_scans_hidden_channels()` - 12 edges

## Surprising Connections (you probably didn't know these)
- `test_default_state_limit_and_hide_filter()` --calls--> `get_conn()`  [EXTRACTED]
  backend/test_app.py → backend/db.py
- `wWinMain()` --calls--> `CreateAndAttachConsole()`  [INFERRED]
  frontend/windows/runner/main.cpp → frontend/windows/runner/utils.cpp
- `lifespan()` --calls--> `init_db()`  [EXTRACTED]
  backend/main.py → backend/db.py
- `add_channel()` --calls--> `get_setting()`  [EXTRACTED]
  backend/main.py → backend/db.py
- `get_settings()` --calls--> `get_setting()`  [EXTRACTED]
  backend/main.py → backend/db.py

## Import Cycles
- None detected.

## Communities (31 total, 14 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.01
Nodes (239): accentColor, activeBgColor, _activeDayFocusListener, _activeDurationThumb, apiKeyPreview, _applyLocalFilterAndPagination, _applyPeriodChoice, _applySyncDataString (+231 more)

### Community 1 - "Community 1"
Cohesion: 0.05
Nodes (43): apply_short_check_batch(), clear_demo_data(), delete_channel(), duration_to_seconds(), get_conn(), init_db(), _is_newer_or_equal_ts(), list_channels_for_refresh() (+35 more)

### Community 2 - "Community 2"
Cohesion: 0.04
Nodes (26): add, addStream, bufferOutput, _bytes, close, compressionState, contentLength, encoding (+18 more)

### Community 3 - "Community 3"
Cohesion: 0.06
Nodes (6): isolated_client(), test_default_state_limit_and_hide_filter(), test_live_streaming_detection_and_refresh_cleanup(), test_live_uulv_xml_parses_real_updated_tag_and_zero_duration_transition(), test_shorts_excluded_by_format_and_under_60s_regular_kept(), test_sync_channel_videos_custom_range_cap_100_and_preserves_old()

### Community 4 - "Community 4"
Cohesion: 0.14
Nodes (4): wWinMain(), CreateAndAttachConsole(), GetCommandLineArguments(), Utf8FromUtf16()

### Community 5 - "Community 5"
Cohesion: 0.14
Nodes (7): set_channel_hidden(), disable_frontend_cache(), export_channels_csv(), HidePayload, import_channels_csv(), lifespan(), update_channel_hide()

### Community 6 - "Community 6"
Cohesion: 0.16
Nodes (12): get_setting(), ChannelReloadPayload, purge_shorts_endpoint(), refresh_youtube(), RefreshYouTubePayload, reload_single_channel(), _run_background_refresh(), _run_short_purge_bg() (+4 more)

### Community 7 - "Community 7"
Cohesion: 0.18
Nodes (5): Scale(), Win32Window::Win32Window(), WindowClassRegistrar, class_registered_, instance_

### Community 8 - "Community 8"
Cohesion: 0.12
Nodes (4): FlutterWindow, flutter_controller_, FlutterWindow::FlutterWindow(), project_

### Community 9 - "Community 9"
Cohesion: 0.18
Nodes (13): _apply_hide_filter_clause(), list_channels(), list_live_videos(), get_channels_list(), get_state(), get_videos(), purge_shorts_status(), refresh_youtube_status() (+5 more)

### Community 10 - "Community 10"
Cohesion: 0.20
Nodes (12): _CustomCalendarDialog, _CustomCalendarDialogState, _DisposeOnUnmount, _DisposeOnUnmountState, _HoldToActionMenuItem, _HoldToActionMenuItemState, _HomeScrollWithBar, _HomeScrollWithBarState (+4 more)

### Community 11 - "Community 11"
Cohesion: 0.18
Nodes (9): _safe_nonneg_int(), sync_device_data(), DeviceSyncPayload, export_sync_bundle_endpoint(), import_sync_bundle_endpoint(), refresh_youtube_consume(), subscribe_channel_endpoint(), sync_exchange_device() (+1 more)

### Community 12 - "Community 12"
Cohesion: 0.20
Nodes (11): set_setting(), AddChannelPayload, _get_permanent_limits(), get_settings(), ImportCsvPayload, _save_permanent_limit(), save_settings(), SettingsPayload (+3 more)

### Community 13 - "Community 13"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 14 - "Community 14"
Cohesion: 0.24
Nodes (4): Win32Window, child_content_, quit_on_close_, window_handle_

### Community 16 - "Community 16"
Cohesion: 0.21
Nodes (6): Point, x, y, Size, height, width

### Community 18 - "Community 18"
Cohesion: 0.50
Nodes (5): increment_channel_watched(), record_watch(), watch_channel(), watch_video(), WatchPayload

## Knowledge Gaps
- **276 isolated node(s):** `baseUrl`, `sidebarMode`, `filterMinimized`, `loading`, `refreshingYouTube` (+271 more)
  These have ≤1 connection - possible missing edges. (Counts symbols only; 433 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **14 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Win32Window` connect `Community 14` to `Community 4`, `Community 7`, `Community 8`, `Community 15`, `Community 16`?**
  _High betweenness centrality (0.015) - this node is a cross-community bridge._
- **What connects `baseUrl`, `sidebarMode`, `filterMinimized` to the rest of the system?**
  _276 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.007547169811320755 - nodes in this community are weakly interconnected._
- **Why does `upsert_channel()` connect `Community 1` to `Community 3`, `Community 5`?**
  _High betweenness centrality (0.012) - this node is a cross-community bridge._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.05389942788316772 - nodes in this community are weakly interconnected._
- **Why does `import_channels_csv()` connect `Community 5` to `Community 1`, `Community 11`, `Community 12`, `Community 6`?**
  _High betweenness centrality (0.011) - this node is a cross-community bridge._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.0425531914893617 - nodes in this community are weakly interconnected._