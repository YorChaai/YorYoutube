import pytest
from fastapi.testclient import TestClient

import db
import main


@pytest.fixture()
def isolated_client(tmp_path, monkeypatch):
    test_db = tmp_path / "test_youtube.db"
    monkeypatch.setattr(db, "DB_PATH", test_db)
    # Reset mutable in-memory session state per test
    main.SESSION_UI_STATE.update(
        {
            "sort_by": "time",
            "period": "all",
            "custom_date": "",
            "range_start": "",
            "range_end": "",
            "start_at": "",
            "end_at": "",
            "hide_filter": "unhide",
            "channel_id": "",
            "q": "",
            "page": 1,
            "min_minutes": 0,
            "max_minutes": 120,
            "sidebar_mode": "full",
            "filter_minimized": False,
        }
    )
    with TestClient(main.app) as client:
        yield client


def test_default_state_limit_and_hide_filter(isolated_client):
    res = isolated_client.get("/api/state")
    assert res.status_code == 200
    data = res.json()
    assert data["default_limit"] == 50
    assert data["active_limit"] == 50
    assert data["session_state"]["hide_filter"] == "unhide"
    assert "region" not in data["session_state"]
    assert len(data["channels"]) == 6
    assert all(ch["is_hidden"] == 0 for ch in data["channels"])
    assert all("region" not in ch for ch in data["channels"])

    with db.get_conn() as conn:
        ch_cols = {r[1] for r in conn.execute("PRAGMA table_info(channels)").fetchall()}
        v_cols = {r[1] for r in conn.execute("PRAGMA table_info(videos)").fetchall()}
        assert "region" not in ch_cols
        assert "region" not in v_cols


def test_hide_unhide_filter_and_video_visibility(isolated_client):
    # Initially 36 demo videos (6 per channel * 6 channels)
    r_init = isolated_client.get("/api/videos?hide_filter=unhide&limit=50")
    assert r_init.status_code == 200
    assert r_init.json()["total"] == 36

    # Hide one channel
    r_hide = isolated_client.post("/api/channels/UC_demo_fajrul/hide", json={"hidden": True})
    assert r_hide.status_code == 200
    assert r_hide.json()["is_hidden"] == 1

    # unhide: excludes hidden channel -> 30 videos
    r_unhide = isolated_client.get("/api/videos?hide_filter=unhide&limit=50")
    assert r_unhide.json()["total"] == 30
    assert all(v["channel_id"] != "UC_demo_fajrul" for v in r_unhide.json()["items"])

    # hide: only hidden channel -> 6 videos with channel_is_hidden=1
    r_only_hide = isolated_client.get("/api/videos?hide_filter=hide&limit=50")
    assert r_only_hide.json()["total"] == 6
    assert all(v["channel_id"] == "UC_demo_fajrul" for v in r_only_hide.json()["items"])
    assert all(v["channel_is_hidden"] == 1 for v in r_only_hide.json()["items"])

    # both: all 36 videos returned
    r_both = isolated_client.get("/api/videos?hide_filter=both&limit=50")
    assert r_both.json()["total"] == 36

    # /api/channels filterable too
    assert len(isolated_client.get("/api/channels?hide_filter=unhide").json()["channels"]) == 5
    assert len(isolated_client.get("/api/channels?hide_filter=hide").json()["channels"]) == 1
    assert len(isolated_client.get("/api/channels?hide_filter=both").json()["channels"]) == 6

    # Unhide immediately restores 36
    r_un = isolated_client.post("/api/channels/UC_demo_fajrul/hide", json={"hidden": False})
    assert r_un.status_code == 200
    assert r_un.json()["is_hidden"] == 0
    assert isolated_client.get("/api/videos?hide_filter=unhide&limit=50").json()["total"] == 36


def test_sync_reconciles_hidden_unfollow_and_device_views(isolated_client):
    # Watch once on laptop
    w = isolated_client.post(
        "/api/channels/UC_demo_malaka/watch",
        json={"video_id": "demo_03_jNQXAC9IVRw", "channel_id": "UC_demo_malaka", "device": "laptop"},
    )
    assert w.status_code == 200

    # Phone sends newer timestamp hiding channel and adding HP watch views
    future_ts = "2099-01-01T00:00:00+00:00"
    sync_res = isolated_client.post(
        "/api/sync/exchange",
        json={
            "device": "hp",
            "videos": [
                {
                    "video_id": "demo_03_jNQXAC9IVRw",
                    "views_hp": 3,
                    "views_laptop": 0,
                    "updated_at": future_ts,
                }
            ],
            "channels": [
                {
                    "channel_id": "UC_demo_malaka",
                    "title": "MALAKA",
                    "views_hp": 3,
                    "views_laptop": 0,
                    "status": "subscribed",
                    "is_hidden": 1,
                    "updated_at": future_ts,
                },
                {
                    "channel_id": "UC_demo_anim",
                    "title": "Animated History",
                    "views_hp": 0,
                    "views_laptop": 0,
                    "status": "unfollowed",
                    "is_hidden": 0,
                    "updated_at": future_ts,
                },
            ],
        },
    )
    assert sync_res.status_code == 200
    out_chs = {c["channel_id"]: c for c in sync_res.json()["channels"]}
    assert out_chs["UC_demo_malaka"]["is_hidden"] == 1
    assert out_chs["UC_demo_malaka"]["views_hp"] == 3
    assert out_chs["UC_demo_malaka"]["views_laptop"] == 1
    assert out_chs["UC_demo_anim"]["status"] == "unfollowed"

    # unhide mode hides UC_demo_malaka AND excludes unfollowed UC_demo_anim => 4*6 = 24 videos
    assert isolated_client.get("/api/videos?hide_filter=unhide&limit=50").json()["total"] == 24
    # hide mode only UC_demo_malaka => 6 videos
    assert isolated_client.get("/api/videos?hide_filter=hide&limit=50").json()["total"] == 6


def test_sorting_duration_search_and_pagination_limits(isolated_client):
    # Invalid limit falls back to 50
    r_bad_lim = isolated_client.get("/api/videos?limit=999")
    assert r_bad_lim.json()["limit"] == 50

    # Pagination 25 per page
    p1 = isolated_client.get("/api/videos?limit=25&page=1").json()
    p2 = isolated_client.get("/api/videos?limit=25&page=2").json()
    assert len(p1["items"]) == 25
    assert len(p2["items"]) == 11
    assert p1["total_pages"] == 2

    # Sort views descending vs oldest ascending
    v_items = isolated_client.get("/api/videos?sort_by=views&limit=50").json()["items"]
    view_counts = [v["view_count"] for v in v_items]
    assert view_counts == sorted(view_counts, reverse=True)

    o_items = isolated_client.get("/api/videos?sort_by=oldest&limit=50").json()["items"]
    pub_dates = [v["published_at"] for v in o_items]
    assert pub_dates == sorted(pub_dates)

    # Duration filter (e.g. 20..30 minutes)
    d_items = isolated_client.get("/api/videos?min_minutes=20&max_minutes=30&limit=50").json()["items"]
    assert len(d_items) > 0
    assert all(1200 <= v["duration_seconds"] <= 1800 for v in d_items)

    # Search q filter
    q_res = isolated_client.get("/api/videos?q=Majapahit&limit=50").json()
    assert q_res["total"] == 1
    assert "Majapahit" in q_res["items"][0]["title"]


def test_init_db_drops_legacy_region_and_refresh_scans_hidden_channels(tmp_path, monkeypatch):
    import sqlite3
    import httpx
    import youtube_sync

    legacy_db = tmp_path / "legacy_region.db"
    monkeypatch.setattr(db, "DB_PATH", legacy_db)

    conn = sqlite3.connect(legacy_db)
    conn.executescript(
        """
        CREATE TABLE channels (
            channel_id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            handle TEXT DEFAULT '',
            thumbnail_url TEXT DEFAULT '',
            uploads_playlist_id TEXT NOT NULL,
            source TEXT DEFAULT 'manual',
            added_at TEXT NOT NULL,
            region TEXT DEFAULT 'Belum diketahui',
            status TEXT DEFAULT 'subscribed',
            is_hidden INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE videos (
            video_id TEXT PRIMARY KEY,
            channel_id TEXT NOT NULL,
            channel_title TEXT NOT NULL,
            channel_thumbnail TEXT DEFAULT '',
            title TEXT NOT NULL,
            thumbnail_url TEXT NOT NULL,
            published_at TEXT NOT NULL,
            view_count INTEGER DEFAULT 0,
            like_count INTEGER DEFAULT 0,
            duration TEXT DEFAULT '',
            duration_seconds INTEGER DEFAULT 0,
            is_demo INTEGER DEFAULT 0,
            region TEXT DEFAULT 'Belum diketahui'
        );
        CREATE INDEX idx_videos_region ON videos(region);
        CREATE INDEX idx_channels_region ON channels(region);
        """
    )
    conn.commit()
    conn.close()

    # init_db() must drop both legacy indexes & columns without error
    db.init_db()
    with db.get_conn() as c:
        ch_cols = {r[1] for r in c.execute("PRAGMA table_info(channels)").fetchall()}
        v_cols = {r[1] for r in c.execute("PRAGMA table_info(videos)").fetchall()}
        assert "region" not in ch_cols
        assert "region" not in v_cols

    # Both normal (unhide) and hidden (hide) channels must be refreshed
    db.upsert_channel(channel_id="UC_norm_1", title="Normal Creator")
    db.upsert_channel(channel_id="UC_hide_1", title="Hidden Creator")
    db.set_channel_hidden("UC_hide_1", True)
    all_chs = db.list_channels(hide_filter="both")
    assert {c["channel_id"] for c in all_chs} == {"UC_norm_1", "UC_hide_1"}

    requested_urls: list[str] = []

    class FakeResp:
        def __init__(self, status_code: int, text: str = "", json_data: dict | None = None):
            self.status_code = status_code
            self.text = text
            self._json = json_data or {}

        def json(self):
            return self._json

    class FakeClient:
        def __init__(self, *args, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

        def get(self, url, params=None, headers=None):
            requested_urls.append(str(url))
            if "feeds/videos.xml?channel_id=UC_norm_1" in str(url):
                return FakeResp(200, text="<feed><yt:videoId>vid_norm_1</yt:videoId></feed>")
            if "feeds/videos.xml?channel_id=UC_hide_1" in str(url):
                return FakeResp(200, text="<feed><yt:videoId>vid_hide_1</yt:videoId></feed>")
            if "videos" in str(url):
                return FakeResp(
                    200,
                    json_data={
                        "items": [
                            {
                                "id": "vid_norm_1",
                                "snippet": {"channelId": "UC_norm_1", "channelTitle": "Normal Creator", "title": "Normal Video", "publishedAt": "2026-11-14T10:00:00Z"},
                                "statistics": {"viewCount": "100", "likeCount": "10"},
                                "contentDetails": {"duration": "PT5M"},
                            },
                            {
                                "id": "vid_hide_1",
                                "snippet": {"channelId": "UC_hide_1", "channelTitle": "Hidden Creator", "title": "Hidden Video", "publishedAt": "2026-11-14T11:00:00Z"},
                                "statistics": {"viewCount": "200", "likeCount": "20"},
                                "contentDetails": {"duration": "PT6M"},
                            },
                        ]
                    },
                )
            return FakeResp(404)

    monkeypatch.setattr(httpx, "Client", FakeClient)
    added = youtube_sync.refresh_all_channels_comprehensive(all_chs, api_key="fake_key")
    assert added == 2
    assert any("channel_id=UC_norm_1" in u for u in requested_urls)
    assert any("channel_id=UC_hide_1" in u for u in requested_urls)
    assert db.query_videos(hide_filter="unhide", limit=50)["total"] == 1
    assert db.query_videos(hide_filter="hide", limit=50)["total"] == 1
    assert db.query_videos(hide_filter="both", limit=50)["total"] == 2


def test_hidden_timestamp_isolated_from_watch_and_day_period_filter(isolated_client):
    # 1. Hide channel on PC -> records hidden_updated_at
    r_hide = isolated_client.post("/api/channels/UC_demo_ferry/hide", json={"hidden": True})
    assert r_hide.status_code == 200
    hid_ts = r_hide.json()["hidden_updated_at"]
    assert hid_ts

    # 2. Phone watched a video AFTER hide (newer updated_at), WITHOUT newer hidden_updated_at
    sync_res = isolated_client.post(
        "/api/sync/exchange",
        json={
            "device": "hp",
            "videos": [],
            "channels": [
                {
                    "channel_id": "UC_demo_ferry",
                    "title": "Ferry Irwandi",
                    "views_hp": 4,
                    "views_laptop": 0,
                    "status": "subscribed",
                    "is_hidden": 0,
                    "hidden_updated_at": "",
                    "updated_at": "2099-12-31T23:59:59+00:00",
                }
            ],
        },
    )
    assert sync_res.status_code == 200
    out_ferry = next(c for c in sync_res.json()["channels"] if c["channel_id"] == "UC_demo_ferry")
    # Watch view incremented, yet PC's newer hide status stayed intact!
    assert out_ferry["views_hp"] == 4
    assert out_ferry["is_hidden"] == 1
    assert out_ferry["hidden_updated_at"] == hid_ts

    # 3. Later, Phone explicitly unhides -> newer hidden_updated_at wins cleanly
    sync_res2 = isolated_client.post(
        "/api/sync/exchange",
        json={
            "device": "hp",
            "videos": [],
            "channels": [
                {
                    "channel_id": "UC_demo_ferry",
                    "title": "Ferry Irwandi",
                    "views_hp": 4,
                    "views_laptop": 0,
                    "status": "subscribed",
                    "is_hidden": 0,
                    "hidden_updated_at": "2099-12-31T23:59:59+00:00",
                    "updated_at": "2099-12-31T23:59:59+00:00",
                }
            ],
        },
    )
    assert sync_res2.status_code == 200
    out_ferry2 = next(c for c in sync_res2.json()["channels"] if c["channel_id"] == "UC_demo_ferry")
    assert out_ferry2["is_hidden"] == 0

    # 4. Day period filter (Nd) includes all videos from N days ago up to today (day 0..N)
    r_2d = isolated_client.get("/api/videos?period=2d&limit=50")
    assert r_2d.status_code == 200
    assert r_2d.json()["total"] == 2
    titles_2d = [it["title"] for it in r_2d.json()["items"]]
    assert any("Kasus Ueno" in t for t in titles_2d)
    assert any("Tubuh Saat Makan Sekali Sehari" in t for t in titles_2d)

    r_3d = isolated_client.get("/api/videos?period=3d&limit=50")
    assert r_3d.status_code == 200
    assert r_3d.json()["total"] == 3
    titles_3d = [it["title"] for it in r_3d.json()["items"]]
    assert any("Cara Berpikir Kritis" in t for t in titles_3d)

    r_40d = isolated_client.get("/api/videos?period=40d&limit=50")
    assert r_40d.status_code == 200
    assert r_40d.json()["total"] == 12
    titles_40d = [it["title"] for it in r_40d.json()["items"]]
    assert any("Perang Dunia II" in t for t in titles_40d)
    assert not any("Tur Rumah Baru" in t for t in titles_40d)


def test_live_streaming_detection_and_refresh_cleanup(isolated_client, monkeypatch):
    from datetime import datetime, timezone
    import youtube_sync

    db.upsert_channel(
        channel_id="UC_live_streamer",
        title="Live Gamer",
        handle="@livegamer",
        uploads_playlist_id="UU_live_streamer",
        source="manual",
    )
    now_iso = datetime.now(timezone.utc).isoformat()
    db.upsert_videos(
        [
            {
                "video_id": "vid_live_1",
                "channel_id": "UC_live_streamer",
                "channel_title": "Live Gamer",
                "channel_thumbnail": "",
                "title": "Live Malam Ini!",
                "thumbnail_url": "https://i.ytimg.com/vi/vid_live_1/hqdefault.jpg",
                "published_at": now_iso,
                "view_count": 100,
                "like_count": 20,
                "duration": "0:00",
                "is_demo": 0,
                "is_live": 1,
            }
        ]
    )

    state_data = isolated_client.get("/api/state").json()
    assert len(state_data["live_streams"]) == 1
    assert state_data["live_streams"][0]["channel_id"] == "UC_live_streamer"
    assert state_data["live_streams"][0]["video_id"] == "vid_live_1"

    vid_data = isolated_client.get("/api/videos?hide_filter=unhide").json()
    assert len(vid_data["live_streams"]) == 1

    # Hidden channel must follow hide_filter on live_streams
    isolated_client.post("/api/channels/UC_live_streamer/hide", json={"hidden": True})
    vid_unhide = isolated_client.get("/api/videos?hide_filter=unhide").json()
    assert vid_unhide["live_streams"] == []
    vid_hide = isolated_client.get("/api/videos?hide_filter=hide").json()
    assert len(vid_hide["live_streams"]) == 1
    isolated_client.post("/api/channels/UC_live_streamer/hide", json={"hidden": False})

    # Verify comprehensive refresh calls videos.list for previously-live video IDs
    # and clears is_live=0 when YouTube returns liveBroadcastContent == "none"
    class _FakeResp:
        def __init__(self, status_code, payload):
            self.status_code = status_code
            self._payload = payload
            self.text = ""

        def json(self):
            return self._payload

    class _FakeClient:
        def __init__(self, *args, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

        def get(self, url, params=None, headers=None):
            if "feeds/videos.xml" in url:
                return _FakeResp(404, {})
            if url.endswith("/videos"):
                return _FakeResp(
                    200,
                    {
                        "items": [
                            {
                                "id": "vid_live_1",
                                "snippet": {
                                    "channelId": "UC_live_streamer",
                                    "channelTitle": "Live Gamer",
                                    "title": "Live Malam Ini! (VOD)",
                                    "publishedAt": now_iso,
                                    "liveBroadcastContent": "none",
                                    "thumbnails": {},
                                },
                                "statistics": {"viewCount": "500", "likeCount": "50"},
                                "contentDetails": {"duration": "PT1H10M"},
                            }
                        ]
                    },
                )
            return _FakeResp(404, {})

    monkeypatch.setattr(youtube_sync.httpx, "Client", _FakeClient)
    youtube_sync.refresh_all_channels_comprehensive(db.list_channels(), api_key="FAKE_KEY")

    after_state = isolated_client.get("/api/state").json()
    assert after_state["live_streams"] == []


def test_live_uulv_xml_parses_real_updated_tag_and_zero_duration_transition(isolated_client, monkeypatch):
    from datetime import datetime, timedelta, timezone
    import youtube_sync

    db.upsert_channel(
        channel_id="UC_uulv_test",
        title="24x7 Radio",
        handle="@radio247",
        uploads_playlist_id="UU_uulv_test",
        source="manual",
    )
    old_iso = (datetime.now(timezone.utc) - timedelta(days=20)).strftime("%Y-%m-%dT%H:%M:%SZ")
    upd_iso = (datetime.now(timezone.utc) - timedelta(days=2)).strftime("%Y-%m-%dT%H:%M:%S+00:00")
    db.upsert_videos(
        [
            {
                "video_id": "vid_uulv_live",
                "channel_id": "UC_uulv_test",
                "channel_title": "24x7 Radio",
                "channel_thumbnail": "",
                "title": "Upcoming 24/7 Stream",
                "thumbnail_url": "https://i.ytimg.com/vi/vid_uulv_live/hqdefault.jpg",
                "published_at": old_iso,
                "view_count": 0,
                "like_count": 0,
                "duration": "",
                "duration_seconds": 0,
                "is_demo": 0,
                "is_live": 0,
            }
        ]
    )

    class _FakeResp:
        def __init__(self, status_code, text="", payload=None):
            self.status_code = status_code
            self.text = text
            self._payload = payload or {}

        def json(self):
            return self._payload

    class _FakeClient:
        def __init__(self, *args, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

        def get(self, url, params=None, headers=None):
            if "playlist_id=UULV_uulv_test" in str(url):
                return _FakeResp(
                    200,
                    text=(
                        "<feed>"
                        "<entry>"
                        "<yt:videoId>vid_uulv_live</yt:videoId>"
                        "<title>Live 24/7</title>"
                        "<author><name>24x7 Radio</name></author>"
                        f"<published>{old_iso}</published>"
                        f"<updated>{upd_iso}</updated>"
                        "</entry>"
                        "</feed>"
                    ),
                )
            if "feeds/videos.xml" in str(url):
                return _FakeResp(200, text="<feed></feed>")
            if str(url).endswith("/videos"):
                return _FakeResp(
                    200,
                    payload={
                        "items": [
                            {
                                "id": "vid_uulv_live",
                                "snippet": {
                                    "channelId": "UC_uulv_test",
                                    "channelTitle": "24x7 Radio",
                                    "title": "Live 24/7 Now",
                                    "publishedAt": old_iso,
                                    "liveBroadcastContent": "live",
                                    "thumbnails": {},
                                },
                                "statistics": {"viewCount": "900", "likeCount": "80"},
                                "contentDetails": {"duration": "P0D"},
                            }
                        ]
                    },
                )
            return _FakeResp(404)

    monkeypatch.setattr(youtube_sync.httpx, "Client", _FakeClient)
    youtube_sync.refresh_all_channels_comprehensive(db.list_channels(), api_key="FAKE_KEY")
    st = isolated_client.get("/api/state").json()
    assert len(st["live_streams"]) == 1
    assert st["live_streams"][0]["video_id"] == "vid_uulv_live"
    assert st["live_streams"][0]["title"] == "Live 24/7 Now"


def test_sync_channel_videos_custom_range_cap_100_and_preserves_old(isolated_client, monkeypatch):
    import youtube_sync

    db.set_setting("api_key", "FAKE_KEY")
    db.upsert_channel(
        channel_id="UC_eno_test",
        title="Eno Bening",
        handle="@enobening",
        uploads_playlist_id="UU_eno_test",
    )
    # Seed 1 very old saved video from 2022 that must NEVER be deleted unless Unsubscribed
    db.upsert_videos(
        [
            {
                "video_id": "vid_old_2022",
                "channel_id": "UC_eno_test",
                "channel_title": "Eno Bening",
                "channel_thumbnail": "",
                "title": "Video Lama 2022",
                "thumbnail_url": "https://i.ytimg.com/vi/vid_old_2022/hqdefault.jpg",
                "published_at": "2022-03-10T10:00:00Z",
                "view_count": 5000,
                "like_count": 300,
                "duration": "12:00",
                "duration_seconds": 720,
                "is_demo": 0,
                "is_live": 0,
            }
        ]
    )

    # Mock 140 videos across pages: 10 newest in 2026-11, 120 inside 2025-05, 10 older in 2024-01
    all_playlist_items = []
    video_meta = {}
    for i in range(10):
        vid = f"vid_2026_{i}"
        pub = f"2026-11-{10 - i:02d}T12:00:00Z"
        all_playlist_items.append({"contentDetails": {"videoId": vid, "videoPublishedAt": pub}})
        video_meta[vid] = pub
    for i in range(120):
        vid = f"vid_2025_{i}"
        day = 28 - (i // 5)
        hr = 20 - (i % 5)
        pub = f"2025-05-{day:02d}T{hr:02d}:00:00Z"
        all_playlist_items.append({"contentDetails": {"videoId": vid, "videoPublishedAt": pub}})
        video_meta[vid] = pub
    for i in range(10):
        vid = f"vid_2024_{i}"
        pub = f"2024-01-{10 - i:02d}T12:00:00Z"
        all_playlist_items.append({"contentDetails": {"videoId": vid, "videoPublishedAt": pub}})
        video_meta[vid] = pub

    class _FakeResp:
        def __init__(self, status_code, payload=None):
            self.status_code = status_code
            self._payload = payload or {}

        def json(self):
            return self._payload

    class _FakeClient:
        def __init__(self, *args, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

        def get(self, url, params=None, headers=None):
            params = params or {}
            if str(url).endswith("/playlistItems"):
                offset = int(params.get("pageToken", "0") or "0")
                chunk = all_playlist_items[offset : offset + 50]
                next_tok = str(offset + 50) if offset + 50 < len(all_playlist_items) else None
                payload = {"items": chunk}
                if next_tok:
                    payload["nextPageToken"] = next_tok
                return _FakeResp(200, payload)
            if str(url).endswith("/videos"):
                ids = [x for x in str(params.get("id", "")).split(",") if x]
                items = [
                    {
                        "id": vid,
                        "snippet": {
                            "channelId": "UC_eno_test",
                            "channelTitle": "Eno Bening",
                            "title": f"Video {vid}",
                            "publishedAt": video_meta.get(vid, "2025-05-01T00:00:00Z"),
                            "liveBroadcastContent": "none",
                            "thumbnails": {},
                        },
                        "statistics": {"viewCount": "100", "likeCount": "10"},
                        "contentDetails": {"duration": "PT10M"},
                    }
                    for vid in ids
                ]
                return _FakeResp(200, {"items": items})
            return _FakeResp(404)

    monkeypatch.setattr(youtube_sync.httpx, "Client", _FakeClient)

    res = isolated_client.post(
        "/api/channels/UC_eno_test/reload",
        json={"start_date": "2025-05-01", "end_date": "2025-05-31", "max_videos": 100},
    )
    assert res.status_code == 200
    body = res.json()
    assert body["videos_synced"] == 100
    assert body["total_channel_videos"] == 101  # 100 from 2025-05 + 1 preserved 2022 video

    vids = isolated_client.get("/api/videos?channel_id=UC_eno_test&limit=100&page=1").json()
    all_ids = {v["video_id"] for v in vids["items"]}
    vids_p2 = isolated_client.get("/api/videos?channel_id=UC_eno_test&limit=100&page=2").json()
    all_ids |= {v["video_id"] for v in vids_p2["items"]}
    assert "vid_old_2022" in all_ids
    assert "vid_2026_0" not in all_ids
    assert "vid_2024_0" not in all_ids
    assert len([x for x in all_ids if x.startswith("vid_2025_")]) == 100

    st_res = isolated_client.get("/api/channels/UC_eno_test/reload-status")
    assert st_res.status_code == 200
    st_body = st_res.json()
    assert st_body["running"] is False
    assert st_body["progress"] == 100


def test_shorts_excluded_by_format_and_under_60s_regular_kept(isolated_client, monkeypatch):
    """Shorts (>60s atau <60s) wajib dikecualikan lewat UULF & HEAD /shorts, sedangkan video reguler <60s tetap disimpan."""
    import youtube_sync

    db.set_setting("api_key", "FAKE_KEY")
    db.upsert_channel(
        channel_id="UC_mixed_fmt",
        title="Mixed Channel",
        uploads_playlist_id="UU_mixed_fmt",
    )
    db.upsert_channel(
        channel_id="UC_shorts_only",
        title="Shorts Only",
        uploads_playlist_id="UU_shorts_only",
    )
    db.upsert_channel(
        channel_id="UC_fallback_fmt",
        title="Fallback Format",
        uploads_playlist_id="UU_fallback_fmt",
    )

    class _Resp:
        def __init__(self, status_code, payload=None, text="", url=""):
            self.status_code = status_code
            self._payload = payload or {}
            self.text = text
            self.url = url

        def json(self):
            return self._payload

    requested_playlists: list[str] = []

    class _FakeClient:
        def __init__(self, *args, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

        def head(self, url, follow_redirects=False):
            # vid_short_over60 adalah Short > 1 menit -> 200; vid_reg_shortdur adalah reguler 15 detik -> 303 redirect
            if url.endswith("/shorts/vid_short_over60") or url.endswith("/shorts/vid_short_search"):
                return _Resp(200, url=url)
            return _Resp(303, url="https://www.youtube.com/watch?v=regular")

        def get(self, url, params=None, headers=None):
            params = params or {}
            if str(url).endswith("/playlistItems"):
                pid = params.get("playlistId", "")
                requested_playlists.append(pid)
                if pid == "UULF_mixed_fmt":
                    return _Resp(
                        200,
                        {
                            "items": [
                                {"contentDetails": {"videoId": "vid_reg_25s", "videoPublishedAt": "2026-11-14T10:00:00Z"}},
                                {"contentDetails": {"videoId": "vid_reg_long", "videoPublishedAt": "2026-11-13T10:00:00Z"}},
                            ]
                        },
                    )
                if pid == "UULF_shorts_only":
                    return _Resp(404, {"error": {"message": "Not found"}})
                if pid == "UULF_fallback_fmt":
                    return _Resp(404, {"error": {"message": "Not found"}})
                if pid == "UU_fallback_fmt":
                    return _Resp(
                        200,
                        {
                            "items": [
                                {"contentDetails": {"videoId": "vid_short_over60", "videoPublishedAt": "2026-11-14T12:00:00Z"}},
                                {"contentDetails": {"videoId": "vid_reg_shortdur", "videoPublishedAt": "2026-11-14T11:00:00Z"}},
                            ]
                        },
                    )
                return _Resp(404)

            if "feeds/videos.xml?playlist_id=UUSH_shorts_only" in str(url):
                return _Resp(200, text="<feed><yt:videoId>vid_only_short_1</yt:videoId></feed>")
            if "feeds/videos.xml?playlist_id=UULF_mixed_fmt" in str(url):
                return _Resp(200, text="<feed><yt:videoId>vid_rss_reg_12s</yt:videoId></feed>")
            if "feeds/videos.xml?playlist_id=UULF" in str(url) or "feeds/videos.xml?playlist_id=UUSH" in str(url):
                return _Resp(404)
            if "feeds/videos.xml" in str(url):
                return _Resp(200, text="<feed></feed>")

            if str(url).endswith("/search"):
                return _Resp(
                    200,
                    {
                        "items": [
                            {"id": {"videoId": "vid_short_search"}, "snippet": {"channelId": "UC_mixed_fmt"}},
                            {"id": {"videoId": "vid_reg_search_10s"}, "snippet": {"channelId": "UC_mixed_fmt"}},
                        ]
                    },
                )

            if str(url).endswith("/videos"):
                ids = [x for x in str(params.get("id", "")).split(",") if x]
                durations = {
                    "vid_reg_25s": "PT25S",
                    "vid_reg_long": "PT15M",
                    "vid_short_over60": "PT1M10S",
                    "vid_reg_shortdur": "PT15S",
                    "vid_rss_reg_12s": "PT12S",
                    "vid_reg_search_10s": "PT10S",
                }
                return _Resp(
                    200,
                    {
                        "items": [
                            {
                                "id": vid,
                                "snippet": {
                                    "channelId": "UC_fallback_fmt" if vid == "vid_reg_shortdur" else "UC_mixed_fmt",
                                    "channelTitle": "Test Creator",
                                    "title": f"Title {vid}",
                                    "publishedAt": "2026-11-14T10:00:00Z",
                                    "liveBroadcastContent": "none",
                                    "thumbnails": {},
                                },
                                "statistics": {"viewCount": "50", "likeCount": "5"},
                                "contentDetails": {"duration": durations.get(vid, "PT1M")},
                            }
                            for vid in ids
                        ]
                    },
                )
            return _Resp(404)

    monkeypatch.setattr(youtube_sync.httpx, "Client", _FakeClient)

    # 1. Mixed channel -> uses UULF_mixed_fmt, keeps 25s regular video
    chs = {c["channel_id"]: c for c in db.list_channels()}
    assert youtube_sync.sync_channel_videos(chs["UC_mixed_fmt"], api_key="FAKE_KEY", max_videos=100) == 2
    assert "UULF_mixed_fmt" in requested_playlists

    # 2. Shorts-only channel -> UULF 404 + UUSH exists -> 0 videos saved & no UU burn
    assert youtube_sync.sync_channel_videos(chs["UC_shorts_only"], api_key="FAKE_KEY", max_videos=100) == 0
    assert "UU_shorts_only" not in requested_playlists

    # 3. Fallback UU channel -> filters out Short >60s (200), keeps regular 15s (303)
    assert youtube_sync.sync_channel_videos(chs["UC_fallback_fmt"], api_key="FAKE_KEY", max_videos=100) == 1
    saved_ids = {v["video_id"] for v in db.query_videos(limit=100)["items"]}
    assert "vid_reg_25s" in saved_ids
    assert "vid_reg_long" in saved_ids
    assert "vid_reg_shortdur" in saved_ids
    assert "vid_short_over60" not in saved_ids

    # 4. Fast Refresh RSS prefers UULF and keeps 12s regular video
    assert youtube_sync.refresh_all_channels_comprehensive([chs["UC_mixed_fmt"]], api_key="FAKE_KEY") == 1
    saved_ids = {v["video_id"] for v in db.query_videos(limit=100)["items"]}
    assert "vid_rss_reg_12s" in saved_ids

    # 5. Search cache drops Shorts (200) and keeps 10s regular video (303)
    assert youtube_sync.search_and_cache_subscribed_videos("test", api_key="FAKE_KEY") == 1
    saved_ids = {v["video_id"] for v in db.query_videos(limit=100)["items"]}
    assert "vid_reg_search_10s" in saved_ids
    assert "vid_short_search" not in saved_ids


def test_purge_existing_shorts_endpoint_preserves_regular_short_videos(isolated_client, monkeypatch):
    """Pembersihan Shorts lama wajib menghapus Shorts (200 di /shorts) tetapi tetap mempertahankan video reguler < 1 menit (303)."""
    import youtube_sync

    db.upsert_channel(channel_id="UC_purge_test", title="Purge Creator", uploads_playlist_id="UU_purge_test")
    db.upsert_videos(
        [
            {
                "video_id": "vid_old_short_1",
                "channel_id": "UC_purge_test",
                "channel_title": "Purge Creator",
                "channel_thumbnail": "",
                "title": "Old Short 45s",
                "thumbnail_url": "https://i.ytimg.com/vi/vid_old_short_1/hqdefault.jpg",
                "published_at": "2026-11-10T10:00:00Z",
                "view_count": 100,
                "like_count": 10,
                "duration": "0:45",
                "duration_seconds": 45,
                "is_demo": 0,
                "is_live": 0,
                "format_checked": 0,
            },
            {
                "video_id": "vid_old_reg_under1m",
                "channel_id": "UC_purge_test",
                "channel_title": "Purge Creator",
                "channel_thumbnail": "",
                "title": "Regular 20s Video",
                "thumbnail_url": "https://i.ytimg.com/vi/vid_old_reg_under1m/hqdefault.jpg",
                "published_at": "2026-11-09T10:00:00Z",
                "view_count": 200,
                "like_count": 20,
                "duration": "0:20",
                "duration_seconds": 20,
                "is_demo": 0,
                "is_live": 0,
                "format_checked": 0,
            },
        ]
    )

    class _HeadResp:
        def __init__(self, status_code, url=""):
            self.status_code = status_code
            self.url = url

    class _FakeHeadClient:
        def __init__(self, *args, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

        def head(self, url, follow_redirects=False):
            if url.endswith("/shorts/vid_old_short_1"):
                return _HeadResp(200, url=url)
            return _HeadResp(303, url="https://www.youtube.com/watch?v=vid_old_reg_under1m")

    monkeypatch.setattr(youtube_sync.httpx, "Client", _FakeHeadClient)
    res = isolated_client.post("/api/videos/purge-shorts?sync=true")
    assert res.status_code == 200
    body = res.json()
    assert body["deleted"] == 1
    assert body["kept_regular"] == 1

    remaining_ids = {v["video_id"] for v in db.query_videos(channel_id="UC_purge_test", limit=50)["items"]}
    assert "vid_old_short_1" not in remaining_ids
    assert "vid_old_reg_under1m" in remaining_ids
    # Re-running finds 0 unchecked candidates
    assert db.list_unchecked_short_candidates() == []


def test_fallback_refresh_fails_closed_when_short_probe_errors(isolated_client, monkeypatch):
    """Jika RSS UULF gagal sementara lalu fallback ke channel_id & HEAD /shorts error/429, video <=3m tidak boleh lolos (fail-closed)."""
    import youtube_sync

    db.set_setting("api_key", "FAKE_KEY")
    db.upsert_channel(channel_id="UC_flaky", title="Flaky Channel", uploads_playlist_id="UU_flaky")

    class _Resp:
        def __init__(self, status_code, payload=None, text="", url=""):
            self.status_code = status_code
            self._payload = payload or {}
            self.text = text
            self.url = url

        def json(self):
            return self._payload

    class _FlakyClient:
        def __init__(self, *args, **kwargs):
            pass

        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

        def head(self, url, follow_redirects=False):
            if url.endswith("/shorts/vid_short_err"):
                raise RuntimeError("Simulated 429/timeout on HEAD")
            return _Resp(303, url="https://www.youtube.com/watch?v=vid_reg_ok_35s")

        def get(self, url, params=None, headers=None):
            params = params or {}
            if "playlist_id=UULF_flaky" in str(url):
                return _Resp(429, text="")
            if "channel_id=UC_flaky" in str(url):
                return _Resp(
                    200,
                    text="<feed><yt:videoId>vid_short_err</yt:videoId><yt:videoId>vid_reg_ok_35s</yt:videoId></feed>",
                )
            if "playlist_id=UULV_flaky" in str(url):
                return _Resp(404, text="")
            if str(url).endswith("/videos"):
                return _Resp(
                    200,
                    {
                        "items": [
                            {
                                "id": "vid_short_err",
                                "snippet": {
                                    "channelId": "UC_flaky",
                                    "channelTitle": "Flaky Channel",
                                    "title": "Short Leaked On Timeout",
                                    "publishedAt": "2026-11-14T14:45:00Z",
                                    "liveBroadcastContent": "none",
                                    "thumbnails": {},
                                },
                                "statistics": {"viewCount": "10", "likeCount": "1"},
                                "contentDetails": {"duration": "PT34S"},
                            },
                            {
                                "id": "vid_reg_ok_35s",
                                "snippet": {
                                    "channelId": "UC_flaky",
                                    "channelTitle": "Flaky Channel",
                                    "title": "Regular 35s Clip",
                                    "publishedAt": "2026-11-14T14:40:00Z",
                                    "liveBroadcastContent": "none",
                                    "thumbnails": {},
                                },
                                "statistics": {"viewCount": "20", "likeCount": "2"},
                                "contentDetails": {"duration": "PT35S"},
                            },
                        ]
                    },
                )
            return _Resp(404)

    monkeypatch.setattr(youtube_sync.httpx, "Client", _FlakyClient)
    inserted = youtube_sync.refresh_all_channels_comprehensive(db.list_channels(), api_key="FAKE_KEY")
    assert inserted == 1
    ids = {v["video_id"] for v in db.query_videos(channel_id="UC_flaky", limit=50)["items"]}
    assert "vid_reg_ok_35s" in ids
    assert "vid_short_err" not in ids


def test_sync_device_data_reconciles_hidden_state_with_legacy_and_timestamps(isolated_client):
    """Hide dari HP (baik timestamp lebih baru maupun legacy kosong) tidak boleh kalah oleh default Unhide kosong di Laptop."""
    db.upsert_channel(channel_id="UC_luxxy", title="Luxxy Gaming", uploads_playlist_id="UU_luxxy")
    db.upsert_channel(channel_id="UC_unhid_new", title="Explicit Unhid", uploads_playlist_id="UU_unhid_new")
    db.set_channel_hidden("UC_unhid_new", False)  # sets non-empty hidden_updated_at

    # 1. HP punya legacy pre-timestamp Hide ('') vs Laptop default Unhide ('') -> Hide menang
    # 2. HP punya legacy pre-timestamp Hide ('') vs Laptop explicit Unhide (non-empty) -> Unhide baru di Laptop menang
    # 3. HP punya timestamp Hide lebih baru terhadap channel baru/unhid -> Hide HP menang
    db.upsert_channel(channel_id="UC_hid_new", title="Timestamped Hide", uploads_playlist_id="UU_hid_new")
    res = isolated_client.post(
        "/api/sync/exchange",
        json={
            "device": "hp",
            "videos": [],
            "channels": [
                {
                    "channel_id": "UC_luxxy",
                    "title": "Luxxy Gaming",
                    "is_hidden": 1,
                    "hidden_updated_at": "",
                    "updated_at": "2026-11-14T10:00:00Z",
                },
                {
                    "channel_id": "UC_unhid_new",
                    "title": "Explicit Unhid",
                    "is_hidden": 1,
                    "hidden_updated_at": "",
                    "updated_at": "2026-11-14T10:00:00Z",
                },
                {
                    "channel_id": "UC_hid_new",
                    "title": "Timestamped Hide",
                    "is_hidden": 1,
                    "hidden_updated_at": "2099-01-01T00:00:00Z",
                    "updated_at": "2099-01-01T00:00:00Z",
                },
            ],
        },
    )
    assert res.status_code == 200
    by_id = {c["channel_id"]: c for c in res.json()["channels"]}
    assert by_id["UC_luxxy"]["is_hidden"] == 1
    assert by_id["UC_unhid_new"]["is_hidden"] == 0
    assert by_id["UC_hid_new"]["is_hidden"] == 1
    assert by_id["UC_hid_new"]["hidden_updated_at"] == "2099-01-01T00:00:00Z"


def test_usb_prepare_endpoint_sets_adb_reverse(isolated_client, monkeypatch):
    """Endpoint /api/sync/usb-prepare menjalankan adb reverse tcp:8000 bila HP terhubung."""
    import main as app_main

    monkeypatch.setattr(app_main.shutil, "which", lambda name: "adb" if name == "adb" else None)

    class _Proc:
        def __init__(self, returncode=0, stdout=""):
            self.returncode = returncode
            self.stdout = stdout

    calls = []

    def _fake_run(cmd, **kwargs):
        calls.append(cmd)
        if cmd[:2] == ["adb", "devices"]:
            return _Proc(0, "List of devices attached\nSERIAL123\tdevice\n")
        if cmd[:4] == ["adb", "-s", "SERIAL123", "reverse"]:
            return _Proc(0, "")
        return _Proc(1, "")

    monkeypatch.setattr(app_main.subprocess, "run", _fake_run)
    resp = isolated_client.post("/api/sync/usb-prepare")
    assert resp.status_code == 200
    body = resp.json()
    assert body["connected"] is True
    assert body["reverse_ok"] is True
    assert body["devices"] == ["SERIAL123"]
    assert ["adb", "-s", "SERIAL123", "reverse", "tcp:8000", "tcp:8000"] in calls





