# Graph Report - youtube  (2026-11-14)

## Corpus Check
- 49 files · ~121,782 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 29 file(s) not represented in the graph (top: .xml 7, (none) 6, .bat 6)

## Summary
- 613 nodes · 919 edges · 25 communities (12 shown, 13 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 18 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Cluster 0
- Cluster 1
- Cluster 2
- Cluster 3
- Cluster 4
- Cluster 5
- Cluster 6
- Cluster 7
- Cluster 8
- Cluster 9
- Cluster 10
- Cluster 11
- Cluster 12
- Cluster 13
- Cluster 14
- Cluster 15
- Cluster 16
- Cluster 17
- Cluster 18
- Cluster 19

## God Nodes (most connected - your core abstractions)
1. `get_conn()` - 27 edges
2. `Win32Window` - 21 edges
3. `list_channels()` - 15 edges
4. `get_setting()` - 13 edges
5. `test_init_db_drops_legacy_region_and_refresh_scans_hidden_channels()` - 12 edges
6. `refresh_all_channels_comprehensive()` - 12 edges
7. `upsert_channel()` - 11 edges
8. `sync_channel_videos()` - 11 edges
9. `upsert_videos()` - 10 edges
10. `query_videos()` - 10 edges

## Surprising Connections (you probably didn't know these)
- `test_default_state_limit_and_hide_filter()` --calls--> `get_conn()`  [EXTRACTED]
  backend/test_app.py → backend/db.py
- `wWinMain()` --calls--> `CreateAndAttachConsole()`  [INFERRED]
  frontend/windows/runner/main.cpp → frontend/windows/runner/utils.cpp
- `sync_public_subscriptions_by_channel()` --calls--> `get_setting()`  [EXTRACTED]
  backend/youtube_sync.py → backend/db.py
- `test_sync_channel_videos_custom_range_cap_100_and_preserves_old()` --calls--> `set_setting()`  [EXTRACTED]
  backend/test_app.py → backend/db.py
- `import_channels_csv()` --calls--> `upsert_channel()`  [EXTRACTED]
  backend/main.py → backend/db.py

## Import Cycles
- None detected.

## Communities (25 total, 13 thin omitted)

### Community 0 - "Cluster 0"
Cohesion: 0.01
Nodes (229): accentColor, activeBgColor, _activeDayFocusListener, _activeDurationThumb, apiKeyPreview, _applyLocalFilterAndPagination, _applyPeriodChoice, _applySyncDataString (+221 more)

### Community 1 - "Cluster 1"
Cohesion: 0.05
Nodes (51): _apply_hide_filter_clause(), get_setting(), increment_channel_watched(), list_channels(), list_live_videos(), record_watch(), set_channel_hidden(), set_setting() (+43 more)

### Community 2 - "Cluster 2"
Cohesion: 0.07
Nodes (38): clear_demo_data(), delete_channel(), duration_to_seconds(), get_conn(), init_db(), _is_newer_or_equal_ts(), list_channels_for_refresh(), mark_videos_not_live() (+30 more)

### Community 3 - "Cluster 3"
Cohesion: 0.04
Nodes (26): add, addStream, bufferOutput, _bytes, close, compressionState, contentLength, encoding (+18 more)

### Community 4 - "Cluster 4"
Cohesion: 0.07
Nodes (5): isolated_client(), test_default_state_limit_and_hide_filter(), test_live_streaming_detection_and_refresh_cleanup(), test_live_uulv_xml_parses_real_updated_tag_and_zero_duration_transition(), test_sync_channel_videos_custom_range_cap_100_and_preserves_old()

### Community 5 - "Cluster 5"
Cohesion: 0.13
Nodes (4): wWinMain(), CreateAndAttachConsole(), GetCommandLineArguments(), Utf8FromUtf16()

### Community 6 - "Cluster 6"
Cohesion: 0.18
Nodes (5): Scale(), Win32Window::Win32Window(), WindowClassRegistrar, class_registered_, instance_

### Community 7 - "Cluster 7"
Cohesion: 0.12
Nodes (4): FlutterWindow, flutter_controller_, FlutterWindow::FlutterWindow(), project_

### Community 8 - "Cluster 8"
Cohesion: 0.20
Nodes (12): _CustomCalendarDialog, _CustomCalendarDialogState, _DisposeOnUnmount, _DisposeOnUnmountState, _HoldToActionMenuItem, _HoldToActionMenuItemState, _HomeScrollWithBar, _HomeScrollWithBarState (+4 more)

### Community 9 - "Cluster 9"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 10 - "Cluster 10"
Cohesion: 0.24
Nodes (4): Win32Window, child_content_, quit_on_close_, window_handle_

### Community 12 - "Cluster 12"
Cohesion: 0.21
Nodes (6): Point, x, y, Size, height, width

## Knowledge Gaps
- **266 isolated node(s):** `baseUrl`, `sidebarMode`, `filterMinimized`, `loading`, `refreshingYouTube` (+261 more)
  These have ≤1 connection - possible missing edges. (Counts symbols only; 406 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **13 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Win32Window` connect `Cluster 10` to `Cluster 5`, `Cluster 6`, `Cluster 7`, `Cluster 11`, `Cluster 12`?**
  _High betweenness centrality (0.016) - this node is a cross-community bridge._
- **What connects `baseUrl`, `sidebarMode`, `filterMinimized` to the rest of the system?**
  _266 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Cluster 0` be split into smaller, more focused modules?**
  _Cohesion score 0.00784313725490196 - nodes in this community are weakly interconnected._
- **Why does `list_channels()` connect `Cluster 1` to `Cluster 2`, `Cluster 4`?**
  _High betweenness centrality (0.013) - this node is a cross-community bridge._
- **Should `Cluster 1` be split into smaller, more focused modules?**
  _Cohesion score 0.054385964912280704 - nodes in this community are weakly interconnected._
- **Why does `FlutterWindow` connect `Cluster 7` to `Cluster 10`, `Cluster 5`?**
  _High betweenness centrality (0.009) - this node is a cross-community bridge._
- **Should `Cluster 2` be split into smaller, more focused modules?**
  _Cohesion score 0.06946386946386947 - nodes in this community are weakly interconnected._