# Graph Report - youtube  (2026-11-14)

## Corpus Check
- 49 files · ~126,665 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 29 file(s) not represented in the graph (top: .xml 7, (none) 6, .bat 6)

## Summary
- 676 nodes · 1044 edges · 34 communities (19 shown, 15 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 23 edges (avg confidence: 0.85)
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
- Community 26
- Community 27
- Community 28

## God Nodes (most connected - your core abstractions)
1. `get_conn()` - 29 edges
2. `sync_channel_videos()` - 21 edges
3. `Win32Window` - 21 edges
4. `list_channels()` - 17 edges
5. `refresh_all_channels_comprehensive()` - 15 edges
6. `upsert_channel()` - 14 edges
7. `get_setting()` - 13 edges
8. `query_videos()` - 13 edges
9. `_run_background_refresh()` - 13 edges
10. `test_init_db_drops_legacy_region_and_refresh_scans_hidden_channels()` - 12 edges

## Surprising Connections (you probably didn't know these)
- `test_default_state_limit_and_hide_filter()` --calls--> `get_conn()`  [EXTRACTED]
  backend/test_app.py → backend/db.py
- `wWinMain()` --calls--> `CreateAndAttachConsole()`  [INFERRED]
  frontend/windows/runner/main.cpp → frontend/windows/runner/utils.cpp
- `get_settings()` --calls--> `get_setting()`  [EXTRACTED]
  backend/main.py → backend/db.py
- `import_channels_csv()` --calls--> `get_setting()`  [EXTRACTED]
  backend/main.py → backend/db.py
- `refresh_youtube()` --calls--> `get_setting()`  [EXTRACTED]
  backend/main.py → backend/db.py

## Import Cycles
- None detected.

## Communities (34 total, 15 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.01
Nodes (245): accentColor, activeBgColor, _activeDayFocusListener, _activeDurationThumb, apiKeyPreview, _applyLocalFilterAndPagination, _applyPeriodChoice, _applySyncDataString (+237 more)

### Community 1 - "Community 1"
Cohesion: 0.06
Nodes (46): _apply_hide_filter_clause(), apply_short_check_batch(), duration_to_seconds(), get_conn(), get_setting(), init_db(), _is_newer_or_equal_ts(), list_channels() (+38 more)

### Community 2 - "Community 2"
Cohesion: 0.04
Nodes (26): add, addStream, bufferOutput, _bytes, close, compressionState, contentLength, encoding (+18 more)

### Community 3 - "Community 3"
Cohesion: 0.05
Nodes (7): isolated_client(), test_default_state_limit_and_hide_filter(), test_fallback_refresh_fails_closed_when_short_probe_errors(), test_live_streaming_detection_and_refresh_cleanup(), test_live_uulv_xml_parses_real_updated_tag_and_zero_duration_transition(), test_shorts_excluded_by_format_and_under_60s_regular_kept(), test_sync_channel_videos_custom_range_cap_100_and_preserves_old()

### Community 4 - "Community 4"
Cohesion: 0.14
Nodes (4): wWinMain(), CreateAndAttachConsole(), GetCommandLineArguments(), Utf8FromUtf16()

### Community 5 - "Community 5"
Cohesion: 0.15
Nodes (9): set_setting(), disable_frontend_cache(), _get_permanent_limits(), get_settings(), _save_permanent_limit(), save_settings(), SettingsPayload, UiStatePayload (+1 more)

### Community 6 - "Community 6"
Cohesion: 0.18
Nodes (5): Scale(), Win32Window::Win32Window(), WindowClassRegistrar, class_registered_, instance_

### Community 7 - "Community 7"
Cohesion: 0.12
Nodes (4): FlutterWindow, flutter_controller_, FlutterWindow::FlutterWindow(), project_

### Community 8 - "Community 8"
Cohesion: 0.20
Nodes (12): _CustomCalendarDialog, _CustomCalendarDialogState, _DisposeOnUnmount, _DisposeOnUnmountState, _HoldToActionMenuItem, _HoldToActionMenuItemState, _HomeScrollWithBar, _HomeScrollWithBarState (+4 more)

### Community 9 - "Community 9"
Cohesion: 0.18
Nodes (9): _safe_nonneg_int(), sync_device_data(), DeviceSyncPayload, export_sync_bundle_endpoint(), import_sync_bundle_endpoint(), refresh_youtube_consume(), subscribe_channel_endpoint(), sync_exchange_device() (+1 more)

### Community 10 - "Community 10"
Cohesion: 0.19
Nodes (9): get_channel_reload_status(), get_channels_list(), purge_shorts_status(), refresh_youtube_status(), serve_flutter_bootstrap(), serve_versioned_web_asset(), serve_web_index(), unregister_legacy_service_worker() (+1 more)

### Community 11 - "Community 11"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 12 - "Community 12"
Cohesion: 0.24
Nodes (4): Win32Window, child_content_, quit_on_close_, window_handle_

### Community 13 - "Community 13"
Cohesion: 0.24
Nodes (7): clear_demo_data(), delete_channel(), _read_unsub_map(), subscribe_channel(), remove_channel(), remove_demo(), restore_demo()

### Community 15 - "Community 15"
Cohesion: 0.25
Nodes (6): purge_shorts_endpoint(), refresh_youtube(), RefreshYouTubePayload, _run_short_purge_bg(), _on_prog(), _start_short_purge_bg()

### Community 16 - "Community 16"
Cohesion: 0.21
Nodes (6): Point, x, y, Size, height, width

### Community 17 - "Community 17"
Cohesion: 0.29
Nodes (6): set_channel_hidden(), AddChannelPayload, HidePayload, ImportCsvPayload, SyncPayload, update_channel_hide()

### Community 18 - "Community 18"
Cohesion: 0.33
Nodes (3): ChannelReloadPayload, reload_single_channel(), _sync_live_snapshot_in_place()

### Community 20 - "Community 20"
Cohesion: 0.50
Nodes (5): increment_channel_watched(), record_watch(), watch_channel(), watch_video(), WatchPayload

## Knowledge Gaps
- **282 isolated node(s):** `baseUrl`, `sidebarMode`, `filterMinimized`, `loading`, `refreshingYouTube` (+277 more)
  These have ≤1 connection - possible missing edges. (Counts symbols only; 449 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **15 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Win32Window` connect `Community 12` to `Community 4`, `Community 6`, `Community 7`, `Community 14`, `Community 16`?**
  _High betweenness centrality (0.015) - this node is a cross-community bridge._
- **What connects `baseUrl`, `sidebarMode`, `filterMinimized` to the rest of the system?**
  _282 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.007380073800738007 - nodes in this community are weakly interconnected._
- **Why does `upsert_channel()` connect `Community 1` to `Community 3`, `Community 21`?**
  _High betweenness centrality (0.013) - this node is a cross-community bridge._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.05742296918767507 - nodes in this community are weakly interconnected._
- **Why does `list_channels()` connect `Community 1` to `Community 3`, `Community 10`, `Community 18`, `Community 21`?**
  _High betweenness centrality (0.012) - this node is a cross-community bridge._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.0425531914893617 - nodes in this community are weakly interconnected._