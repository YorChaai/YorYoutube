# Graph Report - youtube  (2026-11-16)

## Corpus Check
- 30 files · ~132,802 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 29 file(s) not represented in the graph (top: .xml 7, (none) 6, .bat 6)

## Summary
- 790 nodes · 1179 edges · 49 communities (22 shown, 27 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 26 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `ff5fd163`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Flutter App UI Core
- test_app.py
- SQLite DB & Sync Logic
- db.py
- youtube_sync.py
- Flutter Windows Host View
- 🏛️ ARSITEKTUR ISI SETIAP MODUL (STRUKTUR 5 PILAR ADAPTIF)
- main.py
- Win32 Window Lifecycle
- Custom Dialogs & Hold Menus
- get_setting
- post
- Flutter Plugin Registrant
- Project Documentation
- Android MainActivity Host
- Frontend Docs Stub
- set_setting
- YouTube Handle Metadata
- 3. Urutan Pengujian Lintas Tool (General Checklist)
- Android Root Gradle Build
- Android Gradle Settings
- Nullable DateTime Type
- test_refresh_falls_back_to_web_tabs_when_rss_returns_404
- test_search_and_cache_marks_failed_short_probe_unchecked
- test_shorts_excluded_by_format_and_under_60s_regular_kept
- test_fallback_refresh_fails_closed_when_short_probe_errors
- _TestHttpResponse
- FlutterActivity
- _FastScrollbarTrack
- _TestBackendHttpClient
- _TestHttpHeaders
- _TestHttpRequest
- test_sync_channel_videos_custom_range_cap_100_and_preserves_old
- test_live_streaming_detection_and_refresh_cleanup
- test_live_uulv_xml_parses_real_updated_tag_and_zero_duration_transition
- perbandingan_notion_vs_yor_follower_8456c823.md
- promt kutip.md
- test_usb_prepare_endpoint_sets_adb_reverse
- Yorpersonal YouTube Subscriptions Hub
- frontend
- Aturan Kerja Proyek YorYoutube
- import_channels_csv

## God Nodes (most connected - your core abstractions)
1. `get_conn()` - 30 edges
2. `sync_channel_videos()` - 21 edges
3. `Win32Window` - 21 edges
4. `upsert_channel()` - 18 edges
5. `list_channels()` - 18 edges
6. `refresh_all_channels_comprehensive()` - 16 edges
7. `query_videos()` - 14 edges
8. `get_setting()` - 13 edges
9. `_run_background_refresh()` - 13 edges
10. `search_and_cache_subscribed_videos()` - 13 edges

## Surprising Connections (you probably didn't know these)
- `Tahap 2 — Unit & Backend API Test (`pytest` / `unittest` / `vitest`)` --references--> `lifespan()`  [INFERRED]
  DEBUG_AND_AUDIT_PLAYBOOK.md → backend/main.py
- `test_default_state_limit_and_hide_filter()` --calls--> `get_conn()`  [EXTRACTED]
  backend/test_app.py → backend/db.py
- `_fake_sync_channel()` --calls--> `upsert_videos()`  [EXTRACTED]
  backend/test_app.py → backend/db.py
- `wWinMain()` --calls--> `CreateAndAttachConsole()`  [INFERRED]
  frontend/windows/runner/main.cpp → frontend/windows/runner/utils.cpp
- `test_search_and_cache_marks_failed_short_probe_unchecked()` --calls--> `get_conn()`  [EXTRACTED]
  backend/test_app.py → backend/db.py

## Import Cycles
- None detected.

## Communities (49 total, 27 thin omitted)

### Community 0 - "Flutter App UI Core"
Cohesion: 0.01
Nodes (269): accentColor, activeBgColor, _activeDayFocusListener, _activeDurationThumb, apiKeyPreview, _applyLocalFilterAndPagination, _applyPeriodChoice, _applySyncDataString (+261 more)

### Community 2 - "SQLite DB & Sync Logic"
Cohesion: 0.04
Nodes (27): add, addStream, bufferOutput, _bytes, close, compressionState, contentLength, encoding (+19 more)

### Community 3 - "db.py"
Cohesion: 0.06
Nodes (32): apply_short_check_batch(), clear_demo_data(), delete_channel(), get_conn(), init_db(), _is_newer_or_equal_ts(), list_channels_for_refresh(), list_unchecked_short_candidates() (+24 more)

### Community 4 - "youtube_sync.py"
Cohesion: 0.10
Nodes (24): duration_to_seconds(), mark_videos_not_live(), upsert_videos(), _auth_params_headers(), _extract_web_tab_videos(), _extract_yt_initial_data(), _fetch_playlist_items_ids(), _fetch_web_tab_videos() (+16 more)

### Community 5 - "Flutter Windows Host View"
Cohesion: 0.14
Nodes (4): wWinMain(), CreateAndAttachConsole(), GetCommandLineArguments(), Utf8FromUtf16()

### Community 6 - "🏛️ ARSITEKTUR ISI SETIAP MODUL (STRUKTUR 5 PILAR ADAPTIF)"
Cohesion: 0.14
Nodes (13): 1. Banner & Navigasi Modul, 2. Teks Narasi Lengkap (Penulisan Ulang Utuh & Mengalir), 3. Poin-Poin Analisis Mendalam & Terstruktur, 4. Prosedur, Visualisasi Alur, & Diagram Logika, 5. Toolkit Aksi, Template Siap Pakai, & Glosarium, 🏛️ ARSITEKTUR ISI SETIAP MODUL (STRUKTUR 5 PILAR ADAPTIF), Informasi tambahan yang tersirat dalam teks (OPSIONAL, pisahkan dari hasil utama, dan WAJIB tetap berbasis kutipan jika digunakan), MASTER PROMPT 2.0: TRANSFORMASI NASKAH & REKONSTRUKSI MODULAR DINAMIS (+5 more)

### Community 7 - "main.py"
Cohesion: 0.12
Nodes (4): disable_frontend_cache(), _extract_yt_video_id(), get_video_transcript(), prepare_usb_sync_bridge()

### Community 8 - "Win32 Window Lifecycle"
Cohesion: 0.18
Nodes (5): Scale(), Win32Window::Win32Window(), WindowClassRegistrar, class_registered_, instance_

### Community 9 - "Custom Dialogs & Hold Menus"
Cohesion: 0.12
Nodes (4): FlutterWindow, flutter_controller_, FlutterWindow::FlutterWindow(), project_

### Community 10 - "get_setting"
Cohesion: 0.18
Nodes (13): _apply_hide_filter_clause(), get_setting(), list_channels(), list_live_videos(), ChannelReloadPayload, get_channels_list(), get_state(), get_videos() (+5 more)

### Community 11 - "post"
Cohesion: 0.14
Nodes (15): increment_channel_watched(), record_watch(), add_channel(), AddChannelPayload, DeviceSyncPayload, HidePayload, import_sync_bundle_endpoint(), ImportCsvPayload (+7 more)

### Community 12 - "Flutter Plugin Registrant"
Cohesion: 0.21
Nodes (9): export_sync_bundle_endpoint(), get_channel_reload_status(), purge_shorts_status(), refresh_youtube_status(), serve_flutter_bootstrap(), serve_versioned_web_asset(), serve_web_index(), unregister_legacy_service_worker() (+1 more)

### Community 13 - "Project Documentation"
Cohesion: 0.20
Nodes (12): _CustomCalendarDialog, _CustomCalendarDialogState, _DisposeOnUnmount, _DisposeOnUnmountState, _HoldToActionMenuItem, _HoldToActionMenuItemState, _HomeScrollWithBar, _HomeScrollWithBarState (+4 more)

### Community 14 - "Android MainActivity Host"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 15 - "Frontend Docs Stub"
Cohesion: 0.24
Nodes (4): Win32Window, child_content_, quit_on_close_, window_handle_

### Community 16 - "set_setting"
Cohesion: 0.29
Nodes (8): set_setting(), _get_permanent_limits(), get_settings(), _save_permanent_limit(), save_settings(), SettingsPayload, UiStatePayload, update_ui_state()

### Community 18 - "3. Urutan Pengujian Lintas Tool (General Checklist)"
Cohesion: 0.17
Nodes (11): 1. Petakan Arsitektur Dulu dengan Graphify, 2. Cara Mengaktifkan & Mengatur Subagent Audit Paralel, 3. Urutan Pengujian Lintas Tool (General Checklist), 4. Checklist Cepat Bug yang Paling Sering Terjadi, A. Lewat Prompt Langsung ke Agent Utama, B. Tips Agar Subagent Tidak Boros Token, Playbook Debug & Audit Aplikasi (Multi-Tool + Subagent), Tahap 1 — Static & Syntax Check (Detik Pertama) (+3 more)

### Community 19 - "Android Root Gradle Build"
Cohesion: 0.25
Nodes (6): purge_shorts_endpoint(), refresh_youtube(), RefreshYouTubePayload, _run_short_purge_bg(), _on_prog(), _start_short_purge_bg()

### Community 20 - "Android Gradle Settings"
Cohesion: 0.21
Nodes (6): Point, x, y, Size, height, width

### Community 40 - "perbandingan_notion_vs_yor_follower_8456c823.md"
Cohesion: 0.33
Nodes (5): Sheet: Belum Ada di Yor (Unik), Sheet: Hanya di Yor (Belum Notion), Sheet: Notion Semua Link, Sheet: Ringkasan, Sheet: Sudah Ada di Yor (Unik)

### Community 41 - "promt kutip.md"
Cohesion: 0.40
Nodes (4): Daftar topik yang dibahas, Informasi tambahan yang tersirat dalam teks (OPSIONAL, pisahkan dari hasil utama, dan WAJIB tetap berbasis kutipan jika digunakan), Penjelasan detail untuk setiap topik, Ringkasan isi teks (Gambaran umum, tanpa menghilangkan konteks utama, maksimal 3–5 kalimat, tanpa interpretasi tambahan)

### Community 43 - "Yorpersonal YouTube Subscriptions Hub"
Cohesion: 0.50
Nodes (3): Cara Menjalankan, Fitur Utama, Yorpersonal YouTube Subscriptions Hub

## Knowledge Gaps
- **307 isolated node(s):** `s`, `inTrim`, `exTrim`, `inDt`, `exDt` (+302 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 537 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **27 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `upsert_channel()` connect `db.py` to `youtube_sync.py`, `test_sync_channel_videos_custom_range_cap_100_and_preserves_old`, `test_live_streaming_detection_and_refresh_cleanup`, `test_live_uulv_xml_parses_real_updated_tag_and_zero_duration_transition`, `get_setting`, `import_channels_csv`, `test_refresh_falls_back_to_web_tabs_when_rss_returns_404`, `test_search_and_cache_marks_failed_short_probe_unchecked`, `test_shorts_excluded_by_format_and_under_60s_regular_kept`, `test_fallback_refresh_fails_closed_when_short_probe_errors`?**
  _High betweenness centrality (0.017) - this node is a cross-community bridge._
- **What connects `s`, `inTrim`, `exTrim` to the rest of the system?**
  _307 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Flutter App UI Core` be split into smaller, more focused modules?**
  _Cohesion score 0.006711409395973154 - nodes in this community are weakly interconnected._
- **Why does `lifespan()` connect `db.py` to `3. Urutan Pengujian Lintas Tool (General Checklist)`, `Android Root Gradle Build`, `main.py`?**
  _High betweenness centrality (0.014) - this node is a cross-community bridge._
- **Should `SQLite DB & Sync Logic` be split into smaller, more focused modules?**
  _Cohesion score 0.04081632653061224 - nodes in this community are weakly interconnected._
- **Why does `Win32Window` connect `Frontend Docs Stub` to `Flutter Windows Host View`, `Win32 Window Lifecycle`, `Custom Dialogs & Hold Menus`, `YouTube Handle Metadata`, `Android Gradle Settings`?**
  _High betweenness centrality (0.013) - this node is a cross-community bridge._
- **Should `db.py` be split into smaller, more focused modules?**
  _Cohesion score 0.06140350877192982 - nodes in this community are weakly interconnected._