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

    # 4. Day period filter (2d / 3d) matches exact calendar day slice
    r_2d = isolated_client.get("/api/videos?period=2d&limit=50")
    assert r_2d.status_code == 200
    assert r_2d.json()["total"] == 1
    assert "Tubuh Saat Makan Sekali Sehari" in r_2d.json()["items"][0]["title"]

    r_3d = isolated_client.get("/api/videos?period=3d&limit=50")
    assert r_3d.status_code == 200
    assert r_3d.json()["total"] == 1
    assert "Cara Berpikir Kritis" in r_3d.json()["items"][0]["title"]


