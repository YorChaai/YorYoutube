# Graph Report - youtube  (2026-11-14)

## Corpus Check
- 49 files · ~122,167 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 29 file(s) not represented in the graph (top: .xml 7, (none) 6, .bat 6)

## Summary
- 611 nodes · 934 edges · 25 communities (12 shown, 13 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 18 edges (avg confidence: 0.85)
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

## God Nodes (most connected - your core abstractions)
1. `get_conn()` - 27 edges
2. `Win32Window` - 21 edges
3. `list_channels()` - 15 edges
4. `sync_channel_videos()` - 15 edges
5. `get_setting()` - 13 edges
6. `refresh_all_channels_comprehensive()` - 13 edges
7. `_run_background_refresh()` - 12 edges
8. `test_init_db_drops_legacy_region_and_refresh_scans_hidden_channels()` - 12 edges
9. `upsert_channel()` - 11 edges
10. `sync_public_subscriptions_by_channel()` - 11 edges

## Surprising Connections (you probably didn't know these)
- `test_default_state_limit_and_hide_filter()` --calls--> `get_conn()`  [EXTRACTED]
  backend/test_app.py → backend/db.py
- `wWinMain()` --calls--> `CreateAndAttachConsole()`  [INFERRED]
  frontend/windows/runner/main.cpp → frontend/windows/runner/utils.cpp
- `lifespan()` --calls--> `init_db()`  [EXTRACTED]
  backend/main.py → backend/db.py
- `get_settings()` --calls--> `get_setting()`  [EXTRACTED]
  backend/main.py → backend/db.py
- `get_state()` --calls--> `get_setting()`  [EXTRACTED]
  backend/main.py → backend/db.py

## Import Cycles
- None detected.

## Communities (25 total, 13 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.01
Nodes (229): accentColor, activeBgColor, _activeDayFocusListener, _activeDurationThumb, apiKeyPreview, _applyLocalFilterAndPagination, _applyPeriodChoice, _applySyncDataString (+221 more)

### Community 1 - "Community 1"
Cohesion: 0.07
Nodes (42): _apply_hide_filter_clause(), delete_channel(), duration_to_seconds(), get_conn(), get_setting(), init_db(), _is_newer_or_equal_ts(), list_channels() (+34 more)

### Community 2 - "Community 2"
Cohesion: 0.05
Nodes (47): clear_demo_data(), increment_channel_watched(), record_watch(), set_channel_hidden(), set_setting(), AddChannelPayload, ChannelReloadPayload, DeviceSyncPayload (+39 more)

### Community 3 - "Community 3"
Cohesion: 0.04
Nodes (26): add, addStream, bufferOutput, _bytes, close, compressionState, contentLength, encoding (+18 more)

### Community 4 - "Community 4"
Cohesion: 0.07
Nodes (5): isolated_client(), test_default_state_limit_and_hide_filter(), test_live_streaming_detection_and_refresh_cleanup(), test_live_uulv_xml_parses_real_updated_tag_and_zero_duration_transition(), test_sync_channel_videos_custom_range_cap_100_and_preserves_old()

### Community 5 - "Community 5"
Cohesion: 0.14
Nodes (4): wWinMain(), CreateAndAttachConsole(), GetCommandLineArguments(), Utf8FromUtf16()

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
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 10 - "Community 10"
Cohesion: 0.24
Nodes (4): Win32Window, child_content_, quit_on_close_, window_handle_

### Community 12 - "Community 12"
Cohesion: 0.21
Nodes (6): Point, x, y, Size, height, width

## Knowledge Gaps
- **266 isolated node(s):** `baseUrl`, `sidebarMode`, `filterMinimized`, `loading`, `refreshingYouTube` (+261 more)
  These have ≤1 connection - possible missing edges. (Counts symbols only; 403 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **13 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Win32Window` connect `Community 10` to `Community 5`, `Community 6`, `Community 7`, `Community 11`, `Community 12`?**
  _High betweenness centrality (0.016) - this node is a cross-community bridge._
- **What connects `baseUrl`, `sidebarMode`, `filterMinimized` to the rest of the system?**
  _266 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.00784313725490196 - nodes in this community are weakly interconnected._
- **Why does `import_channels_csv()` connect `Community 2` to `Community 1`?**
  _High betweenness centrality (0.010) - this node is a cross-community bridge._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.0715962441314554 - nodes in this community are weakly interconnected._
- **Why does `FlutterWindow` connect `Community 7` to `Community 10`, `Community 5`?**
  _High betweenness centrality (0.009) - this node is a cross-community bridge._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.0546583850931677 - nodes in this community are weakly interconnected._