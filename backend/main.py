from concurrent.futures import ThreadPoolExecutor, as_completed
from contextlib import asynccontextmanager
import csv
import io
import json
from pathlib import Path
import re
import threading
from urllib.parse import parse_qs, urlparse
import httpx
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, Response
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

import db
import youtube_sync


@asynccontextmanager
async def lifespan(_app: FastAPI):
    db.init_db()
    db.seed_demo_if_empty()
    yield


app = FastAPI(title="Personal YouTube Subscriptions Hub", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def disable_frontend_cache(request, call_next):
    response = await call_next(request)
    if not request.url.path.startswith("/api/"):
        response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate, max-age=0"
        response.headers["Pragma"] = "no-cache"
        response.headers["Expires"] = "0"
    return response

# State sementara sesi berjalan: bertahan saat Refresh halaman (F5),
# dan otomatis kembali ke default saat aplikasi di-restart.
SESSION_UI_STATE: dict = {
    "sort_by": "time",
    "period": "all",
    "custom_date": "",
    "range_start": "",
    "range_end": "",
    "start_at": "",
    "end_at": "",
    "hide_filter": "unhide",  # 'unhide' | 'hide' | 'both'
    "channel_id": "",
    "q": "",
    "page": 1,
    "min_minutes": 0,
    "max_minutes": 120,
    "sidebar_mode": "full",  # 'full' | 'mini' | 'hidden'
    "filter_minimized": False,
}

# Status sinkronisasi background (0%..100% + indikator Merah/Hijau)
REFRESH_STATE: dict = {
    "running": False,
    "progress": 0,          # 0 .. 100
    "done_ready": False,    # True jika sudah 100% selesai dan siap ditampilkan saat tombol Hijau diklik
    "done_channels": 0,
    "total_channels": 0,
    "new_videos": 0,
    "total_videos": 0,
    "error": "",
    "rotation_offset": 0,
}

_STATE_LOCK = threading.Lock()


def _extract_yt_video_id(raw_value: str) -> str:
    val = (raw_value or "").strip()
    if val.startswith("demo_") and val.count("_") >= 2:
        val = val.split("_", 2)[2].strip()
    if not val:
        return ""
    if "://" in val or "youtube.com" in val or "youtu.be" in val:
        url = val if "://" in val else f"https://{val}"
        parsed = urlparse(url)
        host = (parsed.hostname or "").lower()
        if host in ("youtu.be", "www.youtu.be"):
            cand = parsed.path.strip("/").split("/")[0]
            if cand:
                val = cand
        elif "youtube.com" in host:
            if parsed.path == "/watch":
                cand = (parse_qs(parsed.query).get("v") or [""])[0]
                if cand:
                    val = cand
            else:
                parts = [p for p in parsed.path.strip("/").split("/") if p]
                if len(parts) >= 2 and parts[0] in ("shorts", "embed", "live"):
                    val = parts[1]
    val = val.split("?")[0].split("&")[0].split("#")[0].strip()
    m = re.match(r"^[A-Za-z0-9_-]{11}$", val)
    return m.group(0) if m else val


def _get_permanent_limits() -> tuple[int, dict[str, int]]:
    return 50, {}


def _save_permanent_limit(tab_key: str, limit_val: int) -> None:
    if limit_val not in (25, 50, 100):
        return
    _, tab_limits = _get_permanent_limits()
    tab_limits[tab_key or "home"] = limit_val
    db.set_setting("default_limit", str(limit_val))
    db.set_setting("tab_limits_json", json.dumps(tab_limits))


class SettingsPayload(BaseModel):
    api_key: str = ""
    oauth_token: str = ""


class AddChannelPayload(BaseModel):
    identifier: str


class ImportCsvPayload(BaseModel):
    csv_text: str


class SyncPayload(BaseModel):
    import_mode: str = "none"
    years_back: int = 4


class RefreshYouTubePayload(BaseModel):
    channel_id: str = ""
    start_date: str = ""
    end_date: str = ""
    max_videos: int = 100


class ChannelReloadPayload(BaseModel):
    start_date: str = ""
    end_date: str = ""
    max_videos: int = 100


class UiStatePayload(BaseModel):
    sort_by: str | None = None
    period: str | None = None
    custom_date: str | None = None
    range_start: str | None = None
    range_end: str | None = None
    start_at: str | None = None
    end_at: str | None = None
    hide_filter: str | None = None
    channel_id: str | None = None
    q: str | None = None
    page: int | None = None
    min_minutes: int | None = None
    max_minutes: int | None = None
    limit: int | None = None
    sidebar_mode: str | None = None
    filter_minimized: bool | None = None


class WatchPayload(BaseModel):
    video_id: str = ""
    channel_id: str = ""
    device: str = "laptop"


class HidePayload(BaseModel):
    hidden: bool = True


class DeviceSyncPayload(BaseModel):
    device: str = "hp"
    videos: list[dict] = []
    channels: list[dict] = []


@app.get("/api/state")
def get_state() -> dict:
    channels = db.list_channels()
    api_key = db.get_setting("api_key", "")
    oauth_token = db.get_setting("oauth_token", "")
    default_limit, tab_limits = _get_permanent_limits()
    with _STATE_LOCK:
        session_copy = dict(SESSION_UI_STATE)
        refresh_copy = dict(REFRESH_STATE)
    current_tab_key = session_copy.get("channel_id") or "home"
    active_limit = tab_limits.get(current_tab_key, default_limit)
    return {
        "channels": channels,
        "live_streams": db.list_live_videos(hide_filter="both"),
        "has_api_key": bool(api_key),
        "api_key_preview": (api_key[:6] + "..." + api_key[-4:]) if len(api_key) > 10 else ("Terpasang" if api_key else ""),
        "has_oauth_token": bool(oauth_token),
        "session_state": session_copy,
        "default_limit": default_limit,
        "tab_limits": tab_limits,
        "active_limit": active_limit,
        "refresh_state": refresh_copy,
    }


@app.post("/api/ui-state")
def update_ui_state(payload: UiStatePayload) -> dict:
    with _STATE_LOCK:
        if payload.sort_by is not None:
            SESSION_UI_STATE["sort_by"] = payload.sort_by
        if payload.period is not None:
            SESSION_UI_STATE["period"] = payload.period
        if payload.custom_date is not None:
            SESSION_UI_STATE["custom_date"] = payload.custom_date
        if payload.range_start is not None:
            SESSION_UI_STATE["range_start"] = payload.range_start
        if payload.range_end is not None:
            SESSION_UI_STATE["range_end"] = payload.range_end
        if payload.start_at is not None:
            SESSION_UI_STATE["start_at"] = payload.start_at
        if payload.end_at is not None:
            SESSION_UI_STATE["end_at"] = payload.end_at
        if payload.hide_filter is not None and payload.hide_filter in ("unhide", "hide", "both"):
            SESSION_UI_STATE["hide_filter"] = payload.hide_filter
        if payload.channel_id is not None:
            SESSION_UI_STATE["channel_id"] = payload.channel_id
        if payload.q is not None:
            SESSION_UI_STATE["q"] = payload.q
        if payload.page is not None:
            SESSION_UI_STATE["page"] = max(1, payload.page)
        if payload.min_minutes is not None:
            SESSION_UI_STATE["min_minutes"] = payload.min_minutes
        if payload.max_minutes is not None:
            SESSION_UI_STATE["max_minutes"] = payload.max_minutes
        if payload.sidebar_mode is not None:
            SESSION_UI_STATE["sidebar_mode"] = payload.sidebar_mode
        if payload.filter_minimized is not None:
            SESSION_UI_STATE["filter_minimized"] = payload.filter_minimized
        if payload.limit is not None and payload.limit in (25, 50, 100):
            tab_key = SESSION_UI_STATE.get("channel_id") or "home"
            _save_permanent_limit(tab_key, payload.limit)
        session_copy = dict(SESSION_UI_STATE)

    default_limit, tab_limits = _get_permanent_limits()
    current_tab_key = session_copy.get("channel_id") or "home"
    return {
        "status": "ok",
        "session_state": session_copy,
        "default_limit": default_limit,
        "tab_limits": tab_limits,
        "active_limit": tab_limits.get(current_tab_key, default_limit),
    }


@app.get("/api/videos")
def get_videos(
    sort_by: str = "time",
    period: str = "all",
    hide_filter: str = "unhide",
    channel_id: str = "",
    q: str = "",
    limit: int = 50,
    page: int = 1,
    min_minutes: int = 0,
    max_minutes: int = 120,
    start_at: str = "",
    end_at: str = "",
    custom_date: str = "",
    range_start: str = "",
    range_end: str = "",
) -> dict:
    norm_hide = hide_filter if hide_filter in ("unhide", "hide", "both") else "unhide"
    # Simpan kondisi terakhir ke SESSION_UI_STATE agar saat Refresh halaman (F5) tidak hilang
    with _STATE_LOCK:
        SESSION_UI_STATE["sort_by"] = sort_by
        SESSION_UI_STATE["period"] = period
        SESSION_UI_STATE["start_at"] = start_at
        SESSION_UI_STATE["end_at"] = end_at
        SESSION_UI_STATE["custom_date"] = custom_date if period == "custom_date" else ""
        SESSION_UI_STATE["range_start"] = range_start if period == "custom_range" else ""
        SESSION_UI_STATE["range_end"] = range_end if period == "custom_range" else ""
        SESSION_UI_STATE["hide_filter"] = norm_hide
        SESSION_UI_STATE["channel_id"] = channel_id
        SESSION_UI_STATE["q"] = q
        SESSION_UI_STATE["page"] = max(1, page)
        SESSION_UI_STATE["min_minutes"] = min_minutes
        SESSION_UI_STATE["max_minutes"] = max_minutes

    res = db.query_videos(
        sort_by=sort_by,
        period=period,
        hide_filter=norm_hide,
        channel_id=channel_id,
        q=q,
        limit=limit,
        page=page,
        min_minutes=min_minutes,
        max_minutes=max_minutes,
        start_at=start_at,
        end_at=end_at,
    )
    # Jika user mengetik pencarian (misal 'saat stop') untuk video lama yang belum ada di cache lokal,
    # cari di YouTube khusus dari daftar 927 channel yang di-subscribe user
    if q.strip() and res["total"] < 3 and page == 1:
        api_key = db.get_setting("api_key", "")
        oauth_token = db.get_setting("oauth_token", "")
        if api_key or oauth_token:
            youtube_sync.search_and_cache_subscribed_videos(
                q=q,
                channel_id=channel_id,
                api_key=api_key,
                oauth_token=oauth_token,
            )
            res = db.query_videos(
                sort_by=sort_by,
                period=period,
                hide_filter=norm_hide,
                channel_id=channel_id,
                q=q,
                limit=limit,
                page=page,
                min_minutes=min_minutes,
                max_minutes=max_minutes,
                start_at=start_at,
                end_at=end_at,
            )

    # Jika user klik salah satu dari 930 channel di sidebar yang videonya belum pernah ditarik sama sekali (0 video), tarik 1x
    if channel_id and res["total"] == 0 and period == "all" and not q and page == 1 and min_minutes == 0 and max_minutes >= 120:
        api_key = db.get_setting("api_key", "")
        oauth_token = db.get_setting("oauth_token", "")
        if api_key or oauth_token:
            chs = [c for c in db.list_channels() if c["channel_id"] == channel_id]
            if chs and chs[0].get("synced_video_count", 0) == 0:
                try:
                    youtube_sync.sync_channel_videos(chs[0], api_key=api_key, oauth_token=oauth_token, max_videos=150)
                    res = db.query_videos(
                        sort_by=sort_by,
                        period=period,
                        hide_filter=norm_hide,
                        channel_id=channel_id,
                        q=q,
                        limit=limit,
                        page=page,
                        min_minutes=min_minutes,
                        max_minutes=max_minutes,
                    )
                except Exception:
                    pass
    res["live_streams"] = db.list_live_videos(hide_filter=norm_hide, channel_id=channel_id)
    return res


def _sync_live_snapshot_in_place() -> None:
    """Perbarui file snapshot aplikasi secara in-place tanpa menyimpan file cadangan lama."""
    try:
        live_db_path = (Path(__file__).resolve().parent / "youtube_personal.db").resolve()
        if Path(db.DB_PATH).resolve() != live_db_path:
            return
        snapshot_path = (Path(__file__).resolve().parent.parent / "frontend" / "assets" / "initial_data.json").resolve()
        if not snapshot_path.parent.exists():
            return
        bundle = db.sync_device_data({"device": "bundle", "videos": [], "channels": []})
        bundle["api_key"] = db.get_setting("api_key", "")
        bundle["my_channel_id"] = db.get_setting("my_channel_id", "")
        tmp_path = snapshot_path.with_suffix(".tmp")
        tmp_path.write_text(json.dumps(bundle, ensure_ascii=False), encoding="utf-8")
        tmp_path.replace(snapshot_path)
    except Exception:
        pass


def _run_background_refresh(
    channel_id: str,
    api_key: str,
    oauth_token: str,
    start_date: str = "",
    end_date: str = "",
    max_videos: int = 100,
) -> None:
    try:
        before_total = db.query_videos(limit=25, page=1)["total"]
        # 1. Tarik daftar channel Subscriptions terbaru secara PERMANEN via Channel ID user + API Key (aktif selamanya!)
        my_cid = db.get_setting("my_channel_id", "")
        if my_cid and api_key and not channel_id:
            try:
                youtube_sync.sync_public_subscriptions_by_channel(my_cid, api_key=api_key)
            except Exception:
                pass
        elif oauth_token and not channel_id:
            try:
                youtube_sync.import_oauth_subscriptions(oauth_token, mode="subscriptions")
            except Exception:
                pass
        # Proses seluruh channel aktif baik yang normal (unhide) maupun yang tersembunyi (hide)
        all_chs = [c for c in db.list_channels(hide_filter="both") if not c["channel_id"].startswith("UC_demo_")]

        if channel_id:
            target_chs = [c for c in all_chs if c["channel_id"] == channel_id]
            eff_cap = max(1, min(int(max_videos or 100), 500))
            with _STATE_LOCK:
                REFRESH_STATE["total_channels"] = len(target_chs)
                REFRESH_STATE["done_channels"] = 0
                REFRESH_STATE["progress"] = 10
            for idx, ch in enumerate(target_chs):
                youtube_sync.sync_channel_videos(
                    ch,
                    api_key=api_key,
                    oauth_token=oauth_token,
                    max_videos=eff_cap,
                    start_date=start_date,
                    end_date=end_date,
                )
                with _STATE_LOCK:
                    REFRESH_STATE["done_channels"] = idx + 1
                    REFRESH_STATE["progress"] = min(99, int((idx + 1) * 100 / max(1, len(target_chs))))
        else:
            # Cek 100% SELURUH channel (semua 927+ channel tanpa terkecuali, termasuk yang jarang upload 1 bulan/tahun sekali!)
            with _STATE_LOCK:
                REFRESH_STATE["total_channels"] = len(all_chs)
                REFRESH_STATE["done_channels"] = 0
                REFRESH_STATE["progress"] = 5

            def _on_prog(done: int, total: int) -> None:
                with _STATE_LOCK:
                    REFRESH_STATE["done_channels"] = done
                    REFRESH_STATE["progress"] = min(99, max(5, int(done * 95 / max(1, total))))

            added_new = youtube_sync.refresh_all_channels_comprehensive(
                all_chs,
                api_key=api_key,
                oauth_token=oauth_token,
                on_progress=_on_prog,
            )

        _sync_live_snapshot_in_place()
        after_total = db.query_videos(limit=25, page=1)["total"]
        with _STATE_LOCK:
            REFRESH_STATE["new_videos"] = max(0, after_total - before_total) if channel_id else max(added_new, after_total - before_total)
            REFRESH_STATE["total_videos"] = after_total
            REFRESH_STATE["progress"] = 100
            REFRESH_STATE["done_ready"] = True
            REFRESH_STATE["running"] = False
    except Exception as e:
        with _STATE_LOCK:
            REFRESH_STATE["error"] = str(e)
            REFRESH_STATE["running"] = False
            REFRESH_STATE["done_ready"] = False


@app.post("/api/refresh-youtube")
def refresh_youtube(payload: RefreshYouTubePayload) -> dict:
    """Mulai sinkronisasi YouTube di background (0%..100%) tanpa menghentikan aktivitas user."""
    api_key = db.get_setting("api_key", "")
    oauth_token = db.get_setting("oauth_token", "")
    if not api_key and not oauth_token:
        raise HTTPException(status_code=400, detail="API Key belum terpasang.")

    with _STATE_LOCK:
        if REFRESH_STATE["running"]:
            return {"status": "running", **REFRESH_STATE}

        REFRESH_STATE["running"] = True
        REFRESH_STATE["progress"] = 2
        REFRESH_STATE["done_ready"] = False
        REFRESH_STATE["done_channels"] = 0
        REFRESH_STATE["total_channels"] = 0
        REFRESH_STATE["new_videos"] = 0
        REFRESH_STATE["error"] = ""
        snapshot = dict(REFRESH_STATE)

    t = threading.Thread(
        target=_run_background_refresh,
        args=(payload.channel_id, api_key, oauth_token, payload.start_date, payload.end_date, payload.max_videos),
        daemon=True,
    )
    t.start()
    return {"status": "started", **snapshot}


@app.get("/api/refresh-youtube/status")
def refresh_youtube_status() -> dict:
    with _STATE_LOCK:
        return dict(REFRESH_STATE)


@app.post("/api/refresh-youtube/consume")
def refresh_youtube_consume() -> dict:
    """Dipanggil ketika tombol Refresh warna HIJAU (100%) ditekan untuk menampilkan video baru."""
    with _STATE_LOCK:
        summary = dict(REFRESH_STATE)
        REFRESH_STATE["done_ready"] = False
        REFRESH_STATE["progress"] = 0
    return {"status": "ok", **summary}


@app.get("/api/settings")
def get_settings() -> dict:
    api_key = db.get_setting("api_key", "")
    oauth_token = db.get_setting("oauth_token", "")
    default_limit, tab_limits = _get_permanent_limits()
    return {
        "status": "ok",
        "has_api_key": bool(api_key),
        "api_key_preview": (api_key[:6] + "..." + api_key[-4:]) if len(api_key) > 10 else ("Terpasang" if api_key else ""),
        "has_oauth_token": bool(oauth_token),
        "default_limit": default_limit,
        "tab_limits": tab_limits,
    }


@app.post("/api/settings")
def save_settings(payload: SettingsPayload) -> dict:
    if payload.api_key and payload.api_key.strip():
        db.set_setting("api_key", payload.api_key.strip())
    if payload.oauth_token and payload.oauth_token.strip():
        db.set_setting("oauth_token", payload.oauth_token.strip())
    return {"status": "ok", **get_state()}


@app.get("/api/channels")
def get_channels_list(hide_filter: str = "both") -> dict:
    channels = db.list_channels(hide_filter=hide_filter)
    return {"status": "ok", "channels": channels, "hide_filter": hide_filter}


@app.post("/api/channels")
def add_channel(payload: AddChannelPayload) -> dict:
    api_key = db.get_setting("api_key", "")
    oauth_token = db.get_setting("oauth_token", "")
    try:
        ch = youtube_sync.resolve_and_add_channel(payload.identifier, api_key=api_key, oauth_token=oauth_token)
        synced = youtube_sync.sync_channel_videos(ch, api_key=api_key, oauth_token=oauth_token)
        return {"status": "ok", "channel": ch, "videos_synced": synced}
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except (httpx.HTTPError, json.JSONDecodeError) as e:
        raise HTTPException(status_code=502, detail=f"Gagal menghubungi YouTube: {e}")


@app.post("/api/channels/{channel_id}/reload")
def reload_single_channel(channel_id: str, payload: ChannelReloadPayload | None = None) -> dict:
    """Muat ulang / tarik video 1 creator (mendukung Custom Date Range & batas maksimal 100 video tanpa menghapus video lama)."""
    api_key = db.get_setting("api_key", "")
    oauth_token = db.get_setting("oauth_token", "")
    if not api_key and not oauth_token:
        raise HTTPException(status_code=400, detail="API Key belum terpasang.")

    chs = [c for c in db.list_channels(hide_filter="both") if c["channel_id"] == channel_id]
    if not chs:
        raise HTTPException(status_code=404, detail="Channel tidak ditemukan.")
    ch = chs[0]

    start_date = (payload.start_date if payload else "").strip()
    end_date = (payload.end_date if payload else "").strip()
    max_videos = max(1, min(int((payload.max_videos if payload else 100) or 100), 500))

    try:
        synced = youtube_sync.sync_channel_videos(
            ch,
            api_key=api_key,
            oauth_token=oauth_token,
            max_videos=max_videos,
            start_date=start_date,
            end_date=end_date,
        )
        _sync_live_snapshot_in_place()
        total_now = db.query_videos(channel_id=channel_id, hide_filter="both", limit=25, page=1)["total"]
        return {
            "status": "ok",
            "channel_id": channel_id,
            "videos_synced": synced,
            "total_channel_videos": total_now,
        }
    except RuntimeError as e:
        raise HTTPException(status_code=502, detail=str(e))
    except (httpx.HTTPError, json.JSONDecodeError) as e:
        raise HTTPException(status_code=502, detail=f"Gagal menghubungi YouTube: {e}")


@app.post("/api/videos/{video_id}/watch")
def watch_video(video_id: str, payload: WatchPayload | None = None) -> dict:
    dev = payload.device if payload and payload.device else "laptop"
    cid = payload.channel_id if payload else ""
    res = db.record_watch(channel_id=cid, video_id=video_id, device=dev)
    return {"status": "ok", **res}


@app.get("/api/videos/{video_id}/transcript")
def get_video_transcript(video_id: str) -> dict:
    clean_id = _extract_yt_video_id(video_id)
    if not clean_id:
        raise HTTPException(status_code=400, detail="Video ID tidak valid.")
    try:
        from youtube_transcript_api import YouTubeTranscriptApi
        from youtube_transcript_api import _errors as yt_errors
        import requests
    except ImportError:
        raise HTTPException(status_code=500, detail="Paket youtube-transcript-api belum terpasang di backend.")

    def _rows_to_segments(fetched_rows) -> list[str]:
        segs = [str(row.text).replace("\n", " ").strip() for row in fetched_rows]
        return [s for s in segs if s]

    def _pick_ordered_tracks(track_list) -> list:
        all_tracks = list(track_list)
        if not all_tracks:
            return []
        ordered = []
        used = set()
        for pref in ("id", "en"):
            for tr in all_tracks:
                code = (getattr(tr, "language_code", "") or "").lower()
                if (code == pref or code.startswith(f"{pref}-")) and id(tr) not in used:
                    ordered.append(tr)
                    used.add(id(tr))
        for tr in all_tracks:
            if id(tr) not in used:
                ordered.append(tr)
        return ordered

    segments: list[str] = []
    with requests.Session() as sess:
        api = YouTubeTranscriptApi(http_client=sess)
        try:
            transcript_list = api.list(clean_id)
            ordered_tracks = _pick_ordered_tracks(transcript_list)
            if not ordered_tracks:
                raise HTTPException(status_code=404, detail="Video tidak memiliki subtitle/transkrip.")
            last_exc: Exception | None = None
            for tr in ordered_tracks:
                try:
                    segments = _rows_to_segments(tr.fetch())
                    if segments:
                        break
                except (yt_errors.IpBlocked, yt_errors.RequestBlocked):
                    raise
                except Exception as exc:
                    last_exc = exc
            if not segments and last_exc is not None:
                raise last_exc
        except HTTPException:
            raise
        except Exception as exc:
            msg = str(exc)
            err_name = type(exc).__name__
            if (
                "IpBlocked" in err_name
                or "RequestBlocked" in err_name
                or "blocking requests from your IP" in msg
            ):
                raise HTTPException(
                    status_code=429,
                    detail="IP internet saat ini sedang dibatasi sementara oleh YouTube. Centang TubeTranscript.com untuk mengambil transkrip lewat browser.",
                )
            raise HTTPException(status_code=404, detail=f"Gagal mengambil transkrip: {exc}")

    if not segments:
        raise HTTPException(status_code=404, detail="Video tidak memiliki teks transkrip.")
    return {
        "video_id": clean_id,
        "text": " ; ".join(segments),
        "segments_count": len(segments),
    }


@app.post("/api/channels/{channel_id}/watch")
def watch_channel(channel_id: str, payload: WatchPayload | None = None) -> dict:
    dev = payload.device if payload and payload.device else "laptop"
    vid = payload.video_id if payload else ""
    res = db.record_watch(channel_id=channel_id, video_id=vid, device=dev)
    return {"status": "ok", **res}


@app.post("/api/channels/{channel_id}/hide")
def update_channel_hide(channel_id: str, payload: HidePayload) -> dict:
    res = db.set_channel_hidden(channel_id, payload.hidden)
    with _STATE_LOCK:
        if payload.hidden and SESSION_UI_STATE.get("channel_id") == channel_id and SESSION_UI_STATE.get("hide_filter", "unhide") == "unhide":
            SESSION_UI_STATE["channel_id"] = ""
    return {"status": "ok", **res}


@app.post("/api/channels/{channel_id}/subscribe")
def subscribe_channel_endpoint(channel_id: str) -> dict:
    db.subscribe_channel(channel_id)
    return {"ok": True, "channel_id": channel_id, "status": "subscribed"}


@app.post("/api/channels/{channel_id}/unfollow")
def unfollow_channel_endpoint(channel_id: str) -> dict:
    db.delete_channel(channel_id)
    with _STATE_LOCK:
        if SESSION_UI_STATE.get("channel_id") == channel_id:
            SESSION_UI_STATE["channel_id"] = ""
    return {"ok": True, "channel_id": channel_id, "status": "unfollowed"}


@app.delete("/api/channels/{channel_id}")
def remove_channel(channel_id: str) -> dict:
    db.delete_channel(channel_id)
    with _STATE_LOCK:
        if SESSION_UI_STATE.get("channel_id") == channel_id:
            SESSION_UI_STATE["channel_id"] = ""
    return {"status": "ok"}


@app.post("/api/sync/exchange")
def sync_exchange_device(payload: DeviceSyncPayload) -> dict:
    """Sinkronisasi langsung HP ⇄ Laptop via Kabel USB / Jaringan Lokal."""
    return db.sync_device_data(payload.model_dump())


@app.get("/api/sync/export-bundle")
def export_sync_bundle_endpoint() -> Response:
    bundle = db.sync_device_data({"device": "bundle", "videos": [], "channels": []})
    bundle_json = json.dumps(bundle, indent=2, ensure_ascii=False)
    return Response(
        content=bundle_json,
        media_type="application/json; charset=utf-8",
        headers={"Content-Disposition": 'attachment; filename="youtube_sync_bundle.json"'},
    )


@app.post("/api/sync/import-bundle")
def import_sync_bundle_endpoint(payload: DeviceSyncPayload) -> dict:
    return db.sync_device_data(payload.model_dump())


@app.delete("/api/demo")
def remove_demo() -> dict:
    db.clear_demo_data()
    return {"status": "ok"}


@app.post("/api/demo")
def restore_demo() -> dict:
    db.clear_demo_data()
    db.seed_demo_if_empty()
    return {"status": "ok"}


@app.post("/api/sync")
def sync_all(payload: SyncPayload) -> dict:
    api_key = db.get_setting("api_key", "")
    oauth_token = db.get_setting("oauth_token", "")
    if not api_key and not oauth_token:
        raise HTTPException(status_code=400, detail="API Key atau OAuth Token belum terpasang.")
    imported_channels = 0

    try:
        if payload.import_mode in ("subscriptions", "subscribers") and oauth_token:
            imported_channels = youtube_sync.import_oauth_subscriptions(oauth_token, mode=payload.import_mode)

        started = False
        with _STATE_LOCK:
            if not REFRESH_STATE["running"]:
                started = True
                REFRESH_STATE["running"] = True
                REFRESH_STATE["progress"] = 2
                REFRESH_STATE["done_ready"] = False
                REFRESH_STATE["done_channels"] = 0
                REFRESH_STATE["total_channels"] = 0
                REFRESH_STATE["new_videos"] = 0
                REFRESH_STATE["error"] = ""
            snapshot = dict(REFRESH_STATE)

        if started:
            t = threading.Thread(
                target=_run_background_refresh,
                args=("", api_key, oauth_token),
                daemon=True,
            )
            t.start()

        return {
            "status": "started" if started else "running",
            "imported_channels": imported_channels,
            "synced_videos": 0,
            **snapshot,
        }
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except (httpx.HTTPError, json.JSONDecodeError) as e:
        raise HTTPException(status_code=502, detail=f"Gagal menghubungi YouTube: {e}")


@app.get("/api/channels/export-csv")
def export_channels_csv() -> Response:
    channels = db.list_channels()
    buf = io.StringIO()
    buf.write("\ufeff")
    writer = csv.writer(buf)
    writer.writerow(["Channel ID", "Nama Channel", "Handle", "URL Channel", "Total Video di YouTube", "Jumlah Subscriber", "Sumber"])
    for c in channels:
        cid = c["channel_id"]
        handle = c.get("handle", "")
        url = f"https://www.youtube.com/{handle}" if handle else f"https://www.youtube.com/channel/{cid}"
        writer.writerow([
            cid,
            c["title"],
            handle,
            url,
            c.get("video_count", 0),
            c.get("subscriber_count", 0),
            c.get("source", ""),
        ])

    return Response(
        content=buf.getvalue(),
        media_type="text/csv; charset=utf-8",
        headers={"Content-Disposition": 'attachment; filename="daftar_channel_youtube.csv"'},
    )


@app.post("/api/channels/import-csv")
def import_channels_csv(payload: ImportCsvPayload) -> dict:
    api_key = db.get_setting("api_key", "")
    oauth_token = db.get_setting("oauth_token", "")
    text = payload.csv_text.strip()
    if not text:
        raise HTTPException(status_code=400, detail="Teks CSV / daftar channel kosong.")

    reader = csv.reader(io.StringIO(text))
    added = 0
    for row in reader:
        if not row:
            continue
        first = row[0].strip()
        if not first or first.lower() in ("channel id", "channel_id", "id", "nama channel"):
            continue
        if first.startswith("UC") and len(row) >= 2:
            cid = first
            col1 = row[1].strip()
            col2 = row[2].strip() if len(row) >= 3 else ""
            # Google Takeout format: [Channel Id, Channel Url, Channel Title]
            # App CSV export format: [Channel ID, Nama Channel, Handle, URL Channel, ...]
            if col1.startswith("http"):
                title = col2 or cid
                handle = ""
            else:
                title = col1 or col2 or cid
                handle = col2 if col2.startswith("@") else ""
            db.upsert_channel(
                channel_id=cid,
                title=title,
                handle=handle,
                uploads_playlist_id="UU" + cid[2:],
                source="csv",
            )
            added += 1
        elif api_key or oauth_token:
            try:
                youtube_sync.resolve_and_add_channel(first, api_key=api_key, oauth_token=oauth_token)
                added += 1
            except (ValueError, httpx.HTTPError, json.JSONDecodeError):
                pass
    return {"status": "ok", "added": added}


@app.get("/flutter_service_worker.js")
def unregister_legacy_service_worker() -> Response:
    js = (
        "self.addEventListener('install', () => self.skipWaiting());\n"
        "self.addEventListener('activate', (event) => {\n"
        "  event.waitUntil((async () => {\n"
        "    const keys = await caches.keys();\n"
        "    await Promise.all(keys.map((k) => caches.delete(k)));\n"
        "    await self.registration.unregister();\n"
        "    const clients = await self.clients.matchAll({ type: 'window' });\n"
        "    clients.forEach((c) => c.navigate(c.url));\n"
        "  })());\n"
        "});\n"
    )
    return Response(content=js, media_type="application/javascript")


WEB_BUILD_DIR = Path(__file__).parent.parent / "frontend" / "build" / "web"


def _web_build_version() -> str:
    main_js = WEB_BUILD_DIR / "main.dart.js"
    if main_js.exists():
        return str(main_js.stat().st_mtime_ns)
    return "1"


@app.get("/")
@app.get("/index.html")
def serve_web_index() -> Response:
    index_path = WEB_BUILD_DIR / "index.html"
    if not index_path.exists():
        raise HTTPException(status_code=404, detail="Web build belum tersedia.")
    html = index_path.read_text(encoding="utf-8")
    version = _web_build_version()
    html = html.replace('src="flutter_bootstrap.js"', f'src="flutter_bootstrap.js?v={version}"')
    return Response(content=html, media_type="text/html; charset=utf-8")


@app.get("/flutter_bootstrap.js")
def serve_flutter_bootstrap() -> Response:
    bootstrap_path = WEB_BUILD_DIR / "flutter_bootstrap.js"
    if not bootstrap_path.exists():
        raise HTTPException(status_code=404, detail="flutter_bootstrap.js belum tersedia.")
    js = bootstrap_path.read_text(encoding="utf-8")
    version = _web_build_version()
    js = js.replace('"main.dart.js"', f'"main.dart.js?v={version}"')
    js = js.replace(
        "_flutter.loader.load({",
        f'_flutter.loader.load({{\n  config: {{ assetBase: "/web_v/{version}/" }},',
    )
    return Response(content=js, media_type="application/javascript; charset=utf-8")


@app.get("/web_v/{version}/{subpath:path}")
def serve_versioned_web_asset(version: str, subpath: str) -> FileResponse:
    root = WEB_BUILD_DIR.resolve()
    target = (root / subpath).resolve()
    if not target.is_relative_to(root) or not target.is_file():
        raise HTTPException(status_code=404, detail="Asset tidak ditemukan.")
    return FileResponse(target)


if WEB_BUILD_DIR.exists():
    app.mount("/", StaticFiles(directory=str(WEB_BUILD_DIR), html=True), name="web")
