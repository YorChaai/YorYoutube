# Graph Report - youtube  (2026-11-15)

## Corpus Check
- 30 files · ~129,033 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 29 file(s) not represented in the graph (top: .xml 7, (none) 6, .bat 6)

## Summary
- 769 nodes · 1142 edges · 48 communities (23 shown, 25 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 26 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `f1fd85fa`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Flutter App UI Core
- test_app.py
- SQLite DB & Sync Logic
- db.py
- json
- Flutter Windows Host View
- 🏛️ ARSITEKTUR ISI SETIAP MODUL (STRUKTUR 5 PILAR ADAPTIF)
- main.py
- Win32 Window Lifecycle
- Custom Dialogs & Hold Menus
- get_setting
- Win32 Geometry Primitives
- Flutter Plugin Registrant
- Project Documentation
- Android MainActivity Host
- Frontend Docs Stub
- BaseModel
- YouTube Handle Metadata
- 3. Urutan Pengujian Lintas Tool (General Checklist)
- Android Root Gradle Build
- Android Gradle Settings
- Nullable DateTime Type
- sync_device_data
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

## God Nodes (most connected - your core abstractions)
1. `get_conn()` - 30 edges
2. `sync_channel_videos()` - 21 edges
3. `Win32Window` - 21 edges
4. `upsert_channel()` - 17 edges
5. `list_channels()` - 17 edges
6. `refresh_all_channels_comprehensive()` - 15 edges
7. `get_setting()` - 13 edges
8. `query_videos()` - 13 edges
9. `_run_background_refresh()` - 13 edges
10. `search_and_cache_subscribed_videos()` - 13 edges

## Surprising Connections (you probably didn't know these)
- `Tahap 2 — Unit & Backend API Test (`pytest` / `unittest` / `vitest`)` --references--> `lifespan()`  [INFERRED]
  DEBUG_AND_AUDIT_PLAYBOOK.md → backend/main.py
- `test_default_state_limit_and_hide_filter()` --calls--> `get_conn()`  [EXTRACTED]
  backend/test_app.py → backend/db.py
- `wWinMain()` --calls--> `CreateAndAttachConsole()`  [INFERRED]
  frontend/windows/runner/main.cpp → frontend/windows/runner/utils.cpp
- `test_search_and_cache_marks_failed_short_probe_unchecked()` --calls--> `get_conn()`  [EXTRACTED]
  backend/test_app.py → backend/db.py
- `lifespan()` --calls--> `init_db()`  [EXTRACTED]
  backend/main.py → backend/db.py

## Import Cycles
- None detected.

## Communities (48 total, 25 thin omitted)

### Community 0 - "Flutter App UI Core"
Cohesion: 0.01
Nodes (266): accentColor, activeBgColor, _activeDayFocusListener, _activeDurationThumb, apiKeyPreview, _applyLocalFilterAndPagination, _applyPeriodChoice, _applySyncDataString (+258 more)

### Community 2 - "SQLite DB & Sync Logic"
Cohesion: 0.04
Nodes (26): add, addStream, bufferOutput, _bytes, close, compressionState, contentLength, encoding (+18 more)

### Community 3 - "db.py"
Cohesion: 0.06
Nodes (46): _apply_hide_filter_clause(), apply_short_check_batch(), clear_demo_data(), duration_to_seconds(), get_conn(), init_db(), _is_newer_or_equal_ts(), list_channels() (+38 more)

### Community 4 - "json"
Cohesion: 0.28
Nodes (6): delete_channel(), _read_unsub_map(), subscribe_channel(), remove_channel(), remove_demo(), unfollow_channel_endpoint()

### Community 5 - "Flutter Windows Host View"
Cohesion: 0.14
Nodes (4): wWinMain(), CreateAndAttachConsole(), GetCommandLineArguments(), Utf8FromUtf16()

### Community 6 - "🏛️ ARSITEKTUR ISI SETIAP MODUL (STRUKTUR 5 PILAR ADAPTIF)"
Cohesion: 0.14
Nodes (13): 1. Banner & Navigasi Modul, 2. Teks Narasi Lengkap (Penulisan Ulang Utuh & Mengalir), 3. Poin-Poin Analisis Mendalam & Terstruktur, 4. Prosedur, Visualisasi Alur, & Diagram Logika, 5. Toolkit Aksi, Template Siap Pakai, & Glosarium, 🏛️ ARSITEKTUR ISI SETIAP MODUL (STRUKTUR 5 PILAR ADAPTIF), Informasi tambahan yang tersirat dalam teks (OPSIONAL, pisahkan dari hasil utama, dan WAJIB tetap berbasis kutipan jika digunakan), MASTER PROMPT 2.0: TRANSFORMASI NASKAH & REKONSTRUKSI MODULAR DINAMIS (+5 more)

### Community 7 - "main.py"
Cohesion: 0.13
Nodes (4): disable_frontend_cache(), export_channels_csv(), import_channels_csv(), prepare_usb_sync_bridge()

### Community 8 - "Win32 Window Lifecycle"
Cohesion: 0.18
Nodes (5): Scale(), Win32Window::Win32Window(), WindowClassRegistrar, class_registered_, instance_

### Community 9 - "Custom Dialogs & Hold Menus"
Cohesion: 0.12
Nodes (4): FlutterWindow, flutter_controller_, FlutterWindow::FlutterWindow(), project_

### Community 10 - "get_setting"
Cohesion: 0.17
Nodes (10): get_setting(), ChannelReloadPayload, get_settings(), refresh_youtube(), RefreshYouTubePayload, reload_single_channel(), _run_background_refresh(), sync_all() (+2 more)

### Community 11 - "Win32 Geometry Primitives"
Cohesion: 0.24
Nodes (8): increment_channel_watched(), record_watch(), refresh_youtube_consume(), restore_demo(), subscribe_channel_endpoint(), watch_channel(), watch_video(), WatchPayload

### Community 12 - "Flutter Plugin Registrant"
Cohesion: 0.14
Nodes (11): _extract_yt_video_id(), get_channel_reload_status(), get_channels_list(), get_video_transcript(), purge_shorts_status(), refresh_youtube_status(), serve_flutter_bootstrap(), serve_versioned_web_asset() (+3 more)

### Community 13 - "Project Documentation"
Cohesion: 0.20
Nodes (12): _CustomCalendarDialog, _CustomCalendarDialogState, _DisposeOnUnmount, _DisposeOnUnmountState, _HoldToActionMenuItem, _HoldToActionMenuItemState, _HomeScrollWithBar, _HomeScrollWithBarState (+4 more)

### Community 14 - "Android MainActivity Host"
Cohesion: 0.18
Nodes (10): background_color, description, display, icons, name, orientation, prefer_related_applications, short_name (+2 more)

### Community 15 - "Frontend Docs Stub"
Cohesion: 0.24
Nodes (4): Win32Window, child_content_, quit_on_close_, window_handle_

### Community 16 - "BaseModel"
Cohesion: 0.18
Nodes (12): add_channel(), AddChannelPayload, _get_permanent_limits(), get_state(), HidePayload, ImportCsvPayload, _save_permanent_limit(), save_settings() (+4 more)

### Community 18 - "3. Urutan Pengujian Lintas Tool (General Checklist)"
Cohesion: 0.17
Nodes (11): 1. Petakan Arsitektur Dulu dengan Graphify, 2. Cara Mengaktifkan & Mengatur Subagent Audit Paralel, 3. Urutan Pengujian Lintas Tool (General Checklist), 4. Checklist Cepat Bug yang Paling Sering Terjadi, A. Lewat Prompt Langsung ke Agent Utama, B. Tips Agar Subagent Tidak Boros Token, Playbook Debug & Audit Aplikasi (Multi-Tool + Subagent), Tahap 1 — Static & Syntax Check (Detik Pertama) (+3 more)

### Community 19 - "Android Root Gradle Build"
Cohesion: 0.29
Nodes (5): lifespan(), purge_shorts_endpoint(), _run_short_purge_bg(), _on_prog(), _start_short_purge_bg()

### Community 20 - "Android Gradle Settings"
Cohesion: 0.21
Nodes (6): Point, x, y, Size, height, width

### Community 22 - "sync_device_data"
Cohesion: 0.29
Nodes (6): _safe_nonneg_int(), sync_device_data(), DeviceSyncPayload, export_sync_bundle_endpoint(), import_sync_bundle_endpoint(), sync_exchange_device()

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
- **303 isolated node(s):** `s`, `inTrim`, `exTrim`, `inDt`, `exDt` (+298 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 521 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **25 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `upsert_channel()` connect `db.py` to `test_sync_channel_videos_custom_range_cap_100_and_preserves_old`, `test_live_streaming_detection_and_refresh_cleanup`, `test_live_uulv_xml_parses_real_updated_tag_and_zero_duration_transition`, `main.py`, `test_search_and_cache_marks_failed_short_probe_unchecked`, `test_shorts_excluded_by_format_and_under_60s_regular_kept`, `test_fallback_refresh_fails_closed_when_short_probe_errors`?**
  _High betweenness centrality (0.015) - this node is a cross-community bridge._
- **What connects `s`, `inTrim`, `exTrim` to the rest of the system?**
  _303 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Flutter App UI Core` be split into smaller, more focused modules?**
  _Cohesion score 0.006802721088435374 - nodes in this community are weakly interconnected._
- **Why does `lifespan()` connect `Android Root Gradle Build` to `3. Urutan Pengujian Lintas Tool (General Checklist)`, `db.py`, `main.py`?**
  _High betweenness centrality (0.015) - this node is a cross-community bridge._
- **Should `SQLite DB & Sync Logic` be split into smaller, more focused modules?**
  _Cohesion score 0.0425531914893617 - nodes in this community are weakly interconnected._
- **Why does `Win32Window` connect `Frontend Docs Stub` to `Flutter Windows Host View`, `Win32 Window Lifecycle`, `Custom Dialogs & Hold Menus`, `YouTube Handle Metadata`, `Android Gradle Settings`?**
  _High betweenness centrality (0.013) - this node is a cross-community bridge._
- **Should `db.py` be split into smaller, more focused modules?**
  _Cohesion score 0.05593803786574871 - nodes in this community are weakly interconnected._