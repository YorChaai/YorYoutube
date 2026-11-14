from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import re
import time
from typing import Callable
from datetime import datetime, timedelta, timezone
import httpx
import db

YT_API_BASE = "https://www.googleapis.com/youtube/v3"


def parse_iso_duration(iso_dur: str) -> str:
    if not iso_dur:
        return ""
    m = re.match(r"^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$", iso_dur.strip())
    if not m or not any(m.groups()):
        return ""
    d, h, mins, s = (int(x) if x else 0 for x in m.groups())
    total_h = d * 24 + h
    if total_h > 0:
        return f"{total_h}:{mins:02d}:{s:02d}"
    return f"{mins}:{s:02d}"


def _auth_params_headers(api_key: str, oauth_token: str) -> tuple[dict, dict]:
    params = {}
    headers = {}
    clean_key = (api_key or "").strip()
    clean_tok = (oauth_token or "").strip()
    if clean_key:
        params["key"] = clean_key
    elif clean_tok:
        headers["Authorization"] = f"Bearer {clean_tok}"
    return params, headers


def _safe_json(resp: httpx.Response) -> dict:
    try:
        parsed = resp.json()
        return parsed if isinstance(parsed, dict) else {}
    except (ValueError, json.JSONDecodeError):
        return {}


def resolve_and_add_channel(identifier: str, api_key: str = "", oauth_token: str = "") -> dict:
    raw = identifier.strip()
    if not raw:
        raise ValueError("Masukkan @handle, URL channel, atau Channel ID (UC...)")

    # Extract @handle, UC..., or custom/user slug from full youtube URL if pasted
    if "youtube.com/" in raw:
        no_frag = raw.split("#")[0]
        if "/@" in no_frag:
            raw = "@" + no_frag.split("/@")[1].split("/")[0].split("?")[0]
        elif "/channel/" in no_frag:
            raw = no_frag.split("/channel/")[1].split("/")[0].split("?")[0]
        elif "/c/" in no_frag:
            raw = no_frag.split("/c/")[1].split("/")[0].split("?")[0]
        elif "/user/" in no_frag:
            raw = no_frag.split("/user/")[1].split("/")[0].split("?")[0]

    params, headers = _auth_params_headers(api_key, oauth_token)
    if not params and not headers:
        raise ValueError("Masukkan YouTube API Key terlebih dahulu di menu Pengaturan API.")

    with httpx.Client(timeout=20.0) as client:
        req_params = {**params, "part": "snippet,contentDetails"}
        if raw.startswith("@"):
            req_params["forHandle"] = raw
        elif raw.startswith("UC") and len(raw) >= 20:
            req_params["id"] = raw
        else:
            req_params["forHandle"] = "@" + raw.lstrip("@")

        resp = client.get(f"{YT_API_BASE}/channels", params=req_params, headers=headers)
        data = _safe_json(resp)
        if resp.status_code != 200 or "error" in data:
            err_msg = data.get("error", {}).get("message", f"YouTube API error ({resp.status_code})")
            raise ValueError(err_msg)
        items = data.get("items", [])

        # Fallback: search channel by name if handle not found
        if not items and not (raw.startswith("UC") and len(raw) >= 20):
            s_resp = client.get(
                f"{YT_API_BASE}/search",
                params={**params, "part": "snippet", "q": raw, "type": "channel", "maxResults": 1},
                headers=headers,
            )
            s_data = _safe_json(s_resp)
            if s_resp.status_code != 200 or "error" in s_data:
                err_msg = s_data.get("error", {}).get("message", f"YouTube search error ({s_resp.status_code})")
                raise ValueError(err_msg)
            s_items = s_data.get("items", [])
            if s_items:
                cid = s_items[0].get("snippet", {}).get("channelId", "")
                if cid:
                    c_resp = client.get(
                        f"{YT_API_BASE}/channels",
                        params={**params, "part": "snippet,contentDetails", "id": cid},
                        headers=headers,
                    )
                    c_data = _safe_json(c_resp)
                    items = c_data.get("items", [])

        if not items:
            err_msg = data.get("error", {}).get("message", f"Channel '{identifier}' tidak ditemukan.")
            raise ValueError(err_msg)

        ch = items[0]
        cid = ch["id"]
        snippet = ch.get("snippet", {})
        title = snippet.get("title") or raw
        handle = snippet.get("customUrl") or (raw if raw.startswith("@") else "")
        thumbs = snippet.get("thumbnails", {})
        thumb_url = (thumbs.get("medium") or thumbs.get("default") or {}).get("url", "")
        uploads_pid = (
            ch.get("contentDetails", {}).get("relatedPlaylists", {}).get("uploads")
            or ("UU" + cid[2:] if cid.startswith("UC") else cid)
        )

        db.upsert_channel(
            channel_id=cid,
            title=title,
            handle=handle,
            thumbnail_url=thumb_url,
            uploads_playlist_id=uploads_pid,
            source="manual",
            status="subscribed",
            force_subscribe=True,
        )
        return {"channel_id": cid, "title": title, "handle": handle, "uploads_playlist_id": uploads_pid}


def import_oauth_subscriptions(oauth_token: str, mode: str = "subscriptions") -> int:
    """
    mode='subscriptions' -> channel yang kamu subscribe (mine=true)
    mode='subscribers'   -> subscriber publik yang subscribe ke kamu (mySubscribers=true)
    """
    if not oauth_token.strip():
        raise ValueError("OAuth Access Token diperlukan untuk menarik daftar Subscriptions otomatis.")

    unfollowed_map: dict[str, str] = {}
    with db.get_conn() as conn:
        for r in conn.execute("SELECT channel_id, COALESCE(updated_at, '') AS updated_at FROM channels WHERE status = 'unfollowed'").fetchall():
            unfollowed_map[r["channel_id"]] = r["updated_at"]

    headers = {"Authorization": f"Bearer {oauth_token.strip()}"}
    added = 0
    page_token = None

    with httpx.Client(timeout=20.0) as client:
        while True:
            params = {"part": "snippet", "maxResults": 50}
            if mode == "subscribers":
                params["mySubscribers"] = "true"
            else:
                params["mine"] = "true"
            if page_token:
                params["pageToken"] = page_token

            resp = client.get(f"{YT_API_BASE}/subscriptions", params=params, headers=headers)
            data = _safe_json(resp)
            if resp.status_code != 200 or "error" in data:
                raise ValueError(data.get("error", {}).get("message", f"Gagal mengambil subscriptions via OAuth ({resp.status_code})."))

            for item in data.get("items", []):
                snippet = item.get("snippet", {})
                sub_pub = snippet.get("publishedAt", "")
                if mode == "subscribers":
                    sub_snip = item.get("subscriberSnippet", snippet)
                    cid = sub_snip.get("channelId", "")
                    title = sub_snip.get("title", "")
                    thumbs = sub_snip.get("thumbnails", {})
                else:
                    res_id = snippet.get("resourceId", {})
                    cid = res_id.get("channelId", "")
                    title = snippet.get("title", "")
                    thumbs = snippet.get("thumbnails", {})

                if cid and title:
                    # Filter Masuk (Ingress Gate): buang jika berstatus unfollowed di lokal
                    if cid in unfollowed_map:
                        unsub_at = unfollowed_map[cid]
                        if not sub_pub or (unsub_at and not db._is_newer_or_equal_ts(sub_pub, unsub_at)):
                            continue
                    thumb_url = (thumbs.get("medium") or thumbs.get("default") or {}).get("url", "")
                    db.upsert_channel(
                        channel_id=cid,
                        title=title,
                        thumbnail_url=thumb_url,
                        uploads_playlist_id="UU" + cid[2:] if cid.startswith("UC") else cid,
                        source=mode,
                        force_subscribe=True,
                    )
                    added += 1

            page_token = data.get("nextPageToken")
            if not page_token:
                break

    return added


def sync_public_subscriptions_by_channel(my_channel_id: str, api_key: str = "") -> int:
    """
    Tarik daftar Subscriptions terbaru milik user secara PERMANEN (selamanya tanpa batas 1 jam OAuth)
    menggunakan Channel ID user + API Key yang tersimpan di database lokal.
    Otomatis mendeteksi kreator baru yang baru di-subscribe di YouTube asli dan langsung mengambil videonya!
    """
    import json
    if not my_channel_id.strip() or not api_key.strip():
        return 0

    existing_cids = {c["channel_id"] for c in db.list_channels(include_unfollowed=False)}
    unfollowed_db_map: dict[str, str] = {}
    with db.get_conn() as conn:
        for r in conn.execute("SELECT channel_id, COALESCE(updated_at, '') AS updated_at FROM channels WHERE status = 'unfollowed'").fetchall():
            unfollowed_db_map[r["channel_id"]] = r["updated_at"]

    raw_unsub = db.get_setting("unsubscribed_map_json", "{}")
    try:
        unsub_map = json.loads(raw_unsub)
        if not isinstance(unsub_map, dict):
            unsub_map = {}
    except Exception:
        unsub_map = {}

    newly_added_channels: list[dict] = []
    page_token = None

    with httpx.Client(timeout=20.0) as client:
        while True:
            params = {
                "part": "snippet",
                "channelId": my_channel_id.strip(),
                "maxResults": 50,
                "key": api_key.strip(),
            }
            if page_token:
                params["pageToken"] = page_token

            resp = client.get(f"{YT_API_BASE}/subscriptions", params=params)
            data = _safe_json(resp)
            if resp.status_code != 200 or "error" in data:
                raise ValueError(data.get("error", {}).get("message", f"Gagal mengambil daftar subscriptions ({resp.status_code})."))

            for item in data.get("items", []):
                snippet = item.get("snippet", {})
                res_id = snippet.get("resourceId", {})
                cid = res_id.get("channelId", "")
                title = snippet.get("title", "")
                sub_pub = snippet.get("publishedAt", "")
                thumbs = snippet.get("thumbnails", {})

                if not cid or not title:
                    continue

                if cid not in existing_cids:
                    # Filter Masuk (Ingress Gate): jika di lokal berstatus unfollowed, lewati kecuali baru di-subscribe ulang di YouTube
                    unsub_at = unfollowed_db_map.get(cid) or unsub_map.get(cid, "")
                    if unsub_at and (not sub_pub or not db._is_newer_or_equal_ts(sub_pub, unsub_at)):
                        continue
                    thumb_url = (thumbs.get("medium") or thumbs.get("default") or {}).get("url", "")
                    uploads_pid = "UU" + cid[2:] if cid.startswith("UC") else cid
                    db.upsert_channel(
                        channel_id=cid,
                        title=title,
                        thumbnail_url=thumb_url,
                        uploads_playlist_id=uploads_pid,
                        source="subscriptions",
                        force_subscribe=True,
                    )
                    existing_cids.add(cid)
                    newly_added_channels.append(
                        {
                            "channel_id": cid,
                            "title": title,
                            "thumbnail_url": thumb_url,
                            "uploads_playlist_id": uploads_pid,
                        }
                    )

            page_token = data.get("nextPageToken")
            if not page_token:
                break

    # Langsung tarik video untuk setiap channel baru yang baru saja di-subscribe di YouTube (maks 100)!
    for new_ch in newly_added_channels:
        try:
            sync_channel_videos(new_ch, api_key=api_key, max_videos=100)
        except Exception:
            pass

    return len(newly_added_channels)


def refresh_all_channel_statistics(api_key: str = "", oauth_token: str = "") -> int:
    """Ambil total video asli di YouTube, jumlah subscriber, dan @handle untuk seluruh channel."""
    params, headers = _auth_params_headers(api_key, oauth_token)
    if not params and not headers:
        return 0
    channels = [c for c in db.list_channels() if not c["channel_id"].startswith("UC_demo_")]
    updated = 0
    with httpx.Client(timeout=25.0) as client:
        for i in range(0, len(channels), 50):
            batch = channels[i : i + 50]
            cids = [c["channel_id"] for c in batch]
            resp = client.get(
                f"{YT_API_BASE}/channels",
                params={**params, "part": "snippet,statistics,contentDetails", "id": ",".join(cids)},
                headers=headers,
            )
            r_data = resp.json()
            if resp.status_code != 200 or "error" in r_data:
                continue
            items = r_data.get("items", [])
            with db.get_conn() as conn:
                for ch in items:
                    cid = ch["id"]
                    snip = ch.get("snippet", {})
                    stats = ch.get("statistics", {})
                    handle = snip.get("customUrl", "")
                    v_count = int(stats.get("videoCount", 0))
                    sub_count = int(stats.get("subscriberCount", 0))
                    conn.execute(
                        """
                        UPDATE channels
                        SET yt_video_count=?,
                            subscriber_count=?,
                            handle=CASE WHEN ? != '' THEN ? ELSE handle END
                        WHERE channel_id=?
                        """,
                        (v_count, sub_count, handle, handle, cid),
                    )
                    updated += 1
    return updated


def _youtube_longform_playlist_id(cid: str, uploads_pid: str = "") -> str:
    """Playlist resmi YouTube berisi video reguler saja (UULF...), mengecualikan Shorts dan Live."""
    if cid.startswith("UC") and len(cid) > 2:
        return "UULF" + cid[2:]
    return uploads_pid


def _youtube_shorts_playlist_id(cid: str) -> str:
    if cid.startswith("UC") and len(cid) > 2:
        return "UUSH" + cid[2:]
    return ""


def _probe_short_kind(video_id: str, client: httpx.Client | None = None) -> str:
    """
    Mendeteksi jenis URL video ('short', 'regular', atau 'unknown' saat error jaringan/rate-limit):
    - Shorts -> HTTP 200 di /shorts/{id} (walaupun durasi > 60 detik) -> 'short'
    - Video reguler -> HTTP 301-308 redirect ke /watch?v={id} atau 404 -> 'regular'
    - Gagal jaringan / 429 / 5xx -> 'unknown' (jangan diam-diam dianggap reguler pada jalur fallback)
    """
    if not video_id:
        return "regular"

    def _once(hc: httpx.Client) -> str:
        head_fn = getattr(hc, "head", None)
        if not callable(head_fn):
            return "unknown"
        try:
            resp = head_fn(
                f"https://www.youtube.com/shorts/{video_id}",
                follow_redirects=False,
            )
        except TypeError:
            resp = head_fn(f"https://www.youtube.com/shorts/{video_id}")
        code = getattr(resp, "status_code", 0)
        if code in (301, 302, 303, 307, 308, 404):
            return "regular"
        if code == 200:
            final_url = str(getattr(resp, "url", "") or "")
            if final_url and "/watch" in final_url:
                return "regular"
            return "short"
        return "unknown"

    for attempt in range(2):
        try:
            if client is not None:
                kind = _once(client)
            else:
                with httpx.Client(timeout=6.0, follow_redirects=False) as hc:
                    kind = _once(hc)
            if kind != "unknown":
                return kind
        except Exception:
            pass
        if attempt == 0:
            time.sleep(0.15)
    return "unknown"


def _is_youtube_short(video_id: str, client: httpx.Client | None = None) -> bool:
    """True jika YouTube menyajikan video tersebut pada endpoint format /shorts/{id}."""
    return _probe_short_kind(video_id, client=client) == "short"


def _rss_playlist_has_entries(client: httpx.Client, playlist_id: str) -> bool:
    if not playlist_id:
        return False
    try:
        resp = client.get(f"https://www.youtube.com/feeds/videos.xml?playlist_id={playlist_id}")
        return getattr(resp, "status_code", 0) == 200 and "<yt:videoId>" in (getattr(resp, "text", "") or "")
    except Exception:
        return False


def _parse_sync_bound(date_str: str, is_end: bool = False) -> datetime | None:
    raw = (date_str or "").strip()
    if not raw:
        return None
    if len(raw) == 10 and raw[4] == "-" and raw[7] == "-":
        try:
            dt = datetime.fromisoformat(raw + ("T23:59:59+00:00" if is_end else "T00:00:00+00:00"))
            return dt
        except ValueError:
            return None
    try:
        dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt
    except ValueError:
        return None


def sync_channel_videos(
    channel: dict,
    api_key: str = "",
    oauth_token: str = "",
    years_back: int = 10,
    max_videos: int = 100,
    start_date: str = "",
    end_date: str = "",
    on_progress: Callable[[int], None] | None = None,
) -> int:
    cid = channel["channel_id"]
    if cid.startswith("UC_demo_"):
        return 0

    params, headers = _auth_params_headers(api_key, oauth_token)
    if not params and not headers:
        return 0

    uploads_pid = channel.get("uploads_playlist_id") or ("UU" + cid[2:] if cid.startswith("UC") else "")
    target_pid = _youtube_longform_playlist_id(cid, uploads_pid)
    if not target_pid:
        return 0
    using_fallback_uploads = target_pid == uploads_pid

    max_videos = max(1, min(int(max_videos or 100), 10000))
    start_dt = _parse_sync_bound(start_date, is_end=False)
    end_dt = _parse_sync_bound(end_date, is_end=True)
    if start_dt and end_dt and start_dt > end_dt:
        start_dt, end_dt = end_dt, start_dt

    cutoff = start_dt if start_dt is not None else (datetime.now(timezone.utc) - timedelta(days=365 * years_back + 30))
    video_ids: list[str] = []
    page_token = None
    pages_scanned = 0
    max_pages = 250 if (start_dt is not None or end_dt is not None or max_videos > 1000) else 25
    with db.get_conn() as conn:
        existing_live_ids = {
            r["video_id"]
            for r in conn.execute(
                "SELECT video_id FROM videos WHERE channel_id = ? AND COALESCE(is_live, 0) = 1",
                (cid,),
            ).fetchall()
        }

    with httpx.Client(timeout=25.0, follow_redirects=False) as client:
        if on_progress:
            on_progress(5)
        while len(video_ids) < max_videos and pages_scanned < max_pages:
            req_params = {
                **params,
                "part": "contentDetails,snippet",
                "playlistId": target_pid,
                "maxResults": 50,
            }
            if page_token:
                req_params["pageToken"] = page_token

            resp = client.get(f"{YT_API_BASE}/playlistItems", params=req_params, headers=headers)
            data = _safe_json(resp)
            if pages_scanned == 0 and resp.status_code == 404 and not using_fallback_uploads:
                # UULF tidak ada (mis. channel khusus Shorts saja -> UUSH ada -> 0 video reguler, atau channel khusus tanpa UULF)
                uush_pid = _youtube_shorts_playlist_id(cid)
                if uush_pid and _rss_playlist_has_entries(client, uush_pid):
                    break
                if uploads_pid:
                    target_pid = uploads_pid
                    using_fallback_uploads = True
                    continue
            if resp.status_code != 200 or "error" in data:
                err_msg = data.get("error", {}).get("message", f"YouTube playlist API error ({resp.status_code})")
                if not video_ids:
                    raise RuntimeError(err_msg)
                break
            pages_scanned += 1
            items = data.get("items", [])
            if not items:
                break

            reached_cutoff = False
            for it in items:
                if len(video_ids) >= max_videos:
                    break
                vid = it.get("contentDetails", {}).get("videoId")
                pub_str = it.get("contentDetails", {}).get("videoPublishedAt") or it.get("snippet", {}).get("publishedAt", "")
                pub_dt: datetime | None = None
                if pub_str:
                    try:
                        pub_dt = datetime.fromisoformat(pub_str.replace("Z", "+00:00"))
                        if pub_dt.tzinfo is None:
                            pub_dt = pub_dt.replace(tzinfo=timezone.utc)
                    except (ValueError, TypeError):
                        pub_dt = None

                if end_dt is not None and pub_dt is not None and pub_dt > end_dt:
                    continue

                if pub_dt is not None and pub_dt < cutoff and (start_dt is not None or len(video_ids) >= 50):
                    reached_cutoff = True
                    break

                if vid:
                    if using_fallback_uploads and _is_youtube_short(vid, client):
                        continue
                    video_ids.append(vid)

            page_token = data.get("nextPageToken")
            if on_progress:
                on_progress(min(55, max(8, int(len(video_ids) * 50 / max_videos) + 5)))
            if reached_cutoff or not page_token or len(video_ids) >= max_videos:
                break

        if existing_live_ids:
            seen_v = set(video_ids)
            for lvid in existing_live_ids:
                if lvid not in seen_v:
                    video_ids.append(lvid)
                    seen_v.add(lvid)

        if on_progress:
            on_progress(55)

        # Batch fetch statistics (viewCount, likeCount) & duration in chunks of 50 (only 1 unit per 50 videos!)
        rows_to_save: list[dict] = []
        still_live_ids: set[str] = set()
        checked_vids: set[str] = set()
        for i in range(0, len(video_ids), 50):
            chunk = video_ids[i : i + 50]
            v_resp = client.get(
                f"{YT_API_BASE}/videos",
                params={
                    **params,
                    "part": "snippet,statistics,contentDetails",
                    "id": ",".join(chunk),
                },
                headers=headers,
            )
            v_data = _safe_json(v_resp)
            if v_resp.status_code != 200 or "error" in v_data:
                if rows_to_save:
                    break
                err_msg = v_data.get("error", {}).get("message", f"YouTube videos API error ({v_resp.status_code})")
                raise RuntimeError(err_msg)
            checked_vids.update(chunk)
            for v_item in v_data.get("items", []):
                vid = v_item["id"]
                snip = v_item.get("snippet", {})
                stats = v_item.get("statistics", {})
                cdet = v_item.get("contentDetails", {})
                dur_str = parse_iso_duration(cdet.get("duration", ""))
                dur_sec = db.duration_to_seconds(dur_str)
                is_live_val = 1 if snip.get("liveBroadcastContent") == "live" else 0
                fmt_checked = 1
                if is_live_val == 0 and 0 < dur_sec <= 185:
                    kind = _probe_short_kind(vid, client)
                    if kind == "short":
                        continue
                    if kind == "unknown" and using_fallback_uploads:
                        continue
                    fmt_checked = 1 if kind == "regular" else 0
                thumbs = snip.get("thumbnails", {})
                thumb_url = (
                    (thumbs.get("high") or thumbs.get("medium") or thumbs.get("default") or {}).get("url")
                    or f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg"
                )
                if is_live_val:
                    still_live_ids.add(vid)
                rows_to_save.append(
                    {
                        "video_id": vid,
                        "channel_id": cid,
                        "channel_title": channel["title"],
                        "channel_thumbnail": channel.get("thumbnail_url", ""),
                        "title": snip.get("title", "Untitled"),
                        "thumbnail_url": thumb_url,
                        "published_at": snip.get("publishedAt", datetime.now(timezone.utc).isoformat()),
                        "view_count": int(stats.get("viewCount", 0)),
                        "like_count": int(stats.get("likeCount", 0)),
                        "duration": dur_str,
                        "is_demo": 0,
                        "is_live": is_live_val,
                        "format_checked": fmt_checked,
                    }
                )
            if on_progress and video_ids:
                on_progress(min(96, 55 + int((i + len(chunk)) * 41 / len(video_ids))))

    saved_count = db.upsert_videos(rows_to_save)
    ended_live = [lvid for lvid in existing_live_ids if lvid in checked_vids and lvid not in still_live_ids]
    if ended_live:
        db.mark_videos_not_live(ended_live)
    if on_progress:
        on_progress(100)
    return saved_count


def refresh_all_channels_comprehensive(
    channels: list[dict],
    api_key: str = "",
    oauth_token: str = "",
    on_progress: Callable[[int, int], None] | None = None,
) -> int:
    """
    Mengecek SELURUH channel (baik unhide maupun hide, termasuk channel yang belum punya cache):
    Seluruh channel dicek 15 item RSS terbarunya secara paralel berkecepatan tinggi (0 kuota API),
    lalu seluruh video baru & video 48 jam terakhir diambil statistik lengkapnya via batch videos.list (50 video/request).
    """
    params, headers = _auth_params_headers(api_key, oauth_token)
    if not params and not headers:
        return 0

    real_chs = [c for c in channels if not c["channel_id"].startswith("UC_demo_")]
    total_chs = len(real_chs)
    if total_chs == 0:
        return 0

    ch_map = {c["channel_id"]: c for c in real_chs}

    # Ambil daftar video_id yang sudah ada di database (kecuali yang baru diupload 48 jam terakhir agar views/likes ikut ter-update)
    # Serta video berdurasi 0 / upcoming dan seluruh video yang sebelumnya berstatus live (is_live=1) agar status live akurat!
    recent_cutoff = (datetime.now(timezone.utc) - timedelta(hours=48)).isoformat()
    live_rss_cutoff = (datetime.now(timezone.utc) - timedelta(days=14)).strftime("%Y-%m-%dT%H:%M:%S")
    with db.get_conn() as conn:
        rows = conn.execute(
            "SELECT video_id, channel_id, published_at, COALESCE(duration_seconds, 0) AS dur_sec, COALESCE(is_live, 0) AS is_live FROM videos"
        ).fetchall()
        all_existing_vids = {r["video_id"] for r in rows}
        known_old_vids = {
            r["video_id"]
            for r in rows
            if (r["published_at"] or "") < recent_cutoff
            and int(r["dur_sec"] or 0) > 0
            and int(r["is_live"] or 0) == 0
        }
        existing_live_map = {r["video_id"]: r["channel_id"] for r in rows if int(r["is_live"] or 0) == 1 and r["channel_id"] in ch_map}
        zero_dur_vids = {r["video_id"] for r in rows if int(r["dur_sec"] or 0) == 0}

    done_count = 0
    newly_inserted_count = 0

    entry_block_re = re.compile(r"<entry>(.*?)</entry>", re.DOTALL)
    vid_tag_re = re.compile(r"<yt:videoId>([^<]+)</yt:videoId>")
    upd_tag_re = re.compile(r"<updated>([^<]+)</updated>")
    pub_tag_re = re.compile(r"<published>([^<]+)</published>")

    # Cek 15 item RSS terbaru + feed live UULV untuk seluruh channel sekaligus via pool 40 worker & keep-alive connection
    vid_to_cid: dict[str, str] = {}
    fallback_vids: set[str] = set()
    uulv_vids: set[str] = set()
    limits = httpx.Limits(max_connections=60, max_keepalive_connections=40)
    with httpx.Client(timeout=6.0, limits=limits, follow_redirects=True) as rss_client:
        def _fetch_rss(url: str) -> str:
            for attempt in range(3):
                try:
                    r = rss_client.get(url)
                    if r.status_code == 200:
                        return r.text
                    if r.status_code in (429, 500, 502, 503, 504) and attempt < 2:
                        time.sleep(0.2 * (attempt + 1))
                        continue
                    return ""
                except Exception:
                    if attempt < 2:
                        time.sleep(0.2 * (attempt + 1))
            return ""

        def _check_channel(ch: dict) -> list[tuple[str, str, bool, bool]]:
            cid = ch["channel_id"]
            found: list[tuple[str, str, bool, bool]] = []
            seen_local: set[str] = set()
            uulf_pid = _youtube_longform_playlist_id(cid)
            xml_main = _fetch_rss(f"https://www.youtube.com/feeds/videos.xml?playlist_id={uulf_pid}") if uulf_pid else ""
            used_channel_fallback = False
            if not xml_main:
                xml_main = _fetch_rss(f"https://www.youtube.com/feeds/videos.xml?channel_id={cid}")
                used_channel_fallback = True
            if xml_main:
                for v in vid_tag_re.findall(xml_main):
                    v = v.strip()
                    if v and v not in known_old_vids and v not in seen_local:
                        if used_channel_fallback and _probe_short_kind(v, rss_client) == "short":
                            continue
                        seen_local.add(v)
                        found.append((v, cid, used_channel_fallback, False))
            if cid.startswith("UC") and len(cid) > 2:
                xml_live = _fetch_rss(f"https://www.youtube.com/feeds/videos.xml?playlist_id=UULV{cid[2:]}")
                if xml_live:
                    blocks = entry_block_re.findall(xml_live)
                    for block in blocks:
                        vm = vid_tag_re.search(block)
                        if not vm:
                            continue
                        v = vm.group(1).strip()
                        um = upd_tag_re.search(block)
                        pm = pub_tag_re.search(block)
                        upd = (um.group(1).strip() if um else "") or (pm.group(1).strip() if pm else "")
                        if v and v not in seen_local and (
                            (upd and upd >= live_rss_cutoff)
                            or v not in known_old_vids
                            or v in zero_dur_vids
                        ):
                            seen_local.add(v)
                            found.append((v, cid, False, True))
            return found

        with ThreadPoolExecutor(max_workers=40) as pool:
            futures = [pool.submit(_check_channel, ch) for ch in real_chs]
            for fut in as_completed(futures):
                done_count += 1
                if on_progress and (done_count % 10 == 0 or done_count == total_chs):
                    on_progress(done_count, total_chs)
                for vid, cid, is_fb, is_uulv in fut.result():
                    vid_to_cid[vid] = cid
                    if is_fb:
                        fallback_vids.add(vid)
                    if is_uulv:
                        uulv_vids.add(vid)

    for lvid, lcid in existing_live_map.items():
        vid_to_cid.setdefault(lvid, lcid)

    if not vid_to_cid:
        return 0

    still_live_vids: set[str] = set()
    checked_vids: set[str] = set()
    all_vids = list(vid_to_cid.keys())
    with httpx.Client(timeout=25.0) as client:
        for i in range(0, len(all_vids), 50):
            chunk = all_vids[i : i + 50]
            v_resp = client.get(
                f"{YT_API_BASE}/videos",
                params={
                    **params,
                    "part": "snippet,statistics,contentDetails",
                    "id": ",".join(chunk),
                },
                headers=headers,
            )
            v_data = _safe_json(v_resp)
            if v_resp.status_code != 200 or "error" in v_data:
                err_msg = v_data.get("error", {}).get("message", f"YouTube API error ({v_resp.status_code})")
                raise RuntimeError(err_msg)
            checked_vids.update(chunk)
            raw_items = v_data.get("items", [])
            need_probe: list[str] = []
            for v_item in raw_items:
                vid = v_item["id"]
                snip = v_item.get("snippet", {})
                cdet = v_item.get("contentDetails", {})
                dur_sec = db.duration_to_seconds(parse_iso_duration(cdet.get("duration", "")))
                is_live_val = 1 if snip.get("liveBroadcastContent") == "live" else 0
                if is_live_val == 0 and 0 < dur_sec <= 185:
                    need_probe.append(vid)

            probe_results: dict[str, str] = {}
            if len(need_probe) > 3 and isinstance(client, httpx.Client):
                with httpx.Client(timeout=6.0, follow_redirects=False) as probe_hc:
                    with ThreadPoolExecutor(max_workers=10) as p_pool:
                        futs = {p_pool.submit(_probe_short_kind, pvid, probe_hc): pvid for pvid in need_probe}
                        for pfut in as_completed(futs):
                            probe_results[futs[pfut]] = pfut.result()
            else:
                for pvid in need_probe:
                    probe_results[pvid] = _probe_short_kind(pvid, client)

            chunk_rows: list[dict] = []
            for v_item in raw_items:
                vid = v_item["id"]
                snip = v_item.get("snippet", {})
                stats = v_item.get("statistics", {})
                cdet = v_item.get("contentDetails", {})
                dur_str = parse_iso_duration(cdet.get("duration", ""))
                dur_sec = db.duration_to_seconds(dur_str)
                is_live_val = 1 if snip.get("liveBroadcastContent") == "live" else 0
                fmt_checked = 1
                if is_live_val == 0 and 0 < dur_sec <= 185:
                    kind = probe_results.get(vid, "unknown")
                    if kind == "short":
                        continue
                    if kind == "unknown" and (vid in fallback_vids or vid in uulv_vids):
                        continue
                    fmt_checked = 1 if kind == "regular" else 0
                cid = snip.get("channelId") or vid_to_cid.get(vid, "")
                ch_obj = ch_map.get(cid, {})
                thumbs = snip.get("thumbnails", {})
                thumb_url = (
                    (thumbs.get("high") or thumbs.get("medium") or thumbs.get("default") or {}).get("url")
                    or f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg"
                )
                if is_live_val:
                    still_live_vids.add(vid)
                if vid not in all_existing_vids:
                    newly_inserted_count += 1
                    all_existing_vids.add(vid)
                chunk_rows.append(
                    {
                        "video_id": vid,
                        "channel_id": cid,
                        "channel_title": ch_obj.get("title") or snip.get("channelTitle", "YouTube"),
                        "channel_thumbnail": ch_obj.get("thumbnail_url", ""),
                        "title": snip.get("title", "Untitled"),
                        "thumbnail_url": thumb_url,
                        "published_at": snip.get("publishedAt", datetime.now(timezone.utc).isoformat()),
                        "view_count": int(stats.get("viewCount", 0)),
                        "like_count": int(stats.get("likeCount", 0)),
                        "duration": dur_str,
                        "is_demo": 0,
                        "is_live": is_live_val,
                        "format_checked": fmt_checked,
                    }
                )
            db.upsert_videos(chunk_rows)

    ended_live = [lvid for lvid in existing_live_map if lvid in checked_vids and lvid not in still_live_vids]
    if ended_live:
        db.mark_videos_not_live(ended_live)

    return newly_inserted_count


def search_and_cache_subscribed_videos(
    q: str,
    channel_id: str = "",
    api_key: str = "",
    oauth_token: str = "",
) -> int:
    """
    Jika user mencari kata kunci (misal 'saat stop') untuk video lama yang belum masuk ke 50 video terbaru di cache,
    cari di YouTube API dan HANYA simpan video yang berasal dari daftar channel yang di-subscribe user (927 channel).
    """
    q_clean = q.strip()
    if not q_clean:
        return 0
    params, headers = _auth_params_headers(api_key, oauth_token)
    if not params and not headers:
        return 0

    all_chs = [c for c in db.list_channels() if not c["channel_id"].startswith("UC_demo_")]
    ch_map = {c["channel_id"]: c for c in all_chs}
    if not ch_map:
        return 0

    search_params = {
        **params,
        "part": "snippet",
        "q": q_clean,
        "type": "video",
        "maxResults": 35,
    }
    if channel_id and channel_id in ch_map:
        search_params["channelId"] = channel_id

    vid_to_cid: dict[str, str] = {}
    try:
        with httpx.Client(timeout=15.0) as client:
            resp = client.get(f"{YT_API_BASE}/search", params=search_params, headers=headers)
            data = _safe_json(resp)
            if resp.status_code != 200 or "error" in data:
                return 0
            items = data.get("items", [])
            for it in items:
                vid = it.get("id", {}).get("videoId", "")
                cid = it.get("snippet", {}).get("channelId", "")
                # Hanya ambil jika channel tersebut memang ada di daftar Subscriptions user!
                if vid and cid in ch_map:
                    vid_to_cid[vid] = cid

            is_explicit_channel = (
                q_clean.startswith("@")
                or (q_clean.startswith("UC") and len(q_clean) >= 20)
                or "youtube.com/" in q_clean
            )
            if not vid_to_cid and not channel_id and is_explicit_channel:
                # Jika user mencari langsung dengan @handle / UC... / URL channel baru, tambahkan & sync videonya.
                try:
                    new_ch = resolve_and_add_channel(q_clean, api_key=api_key, oauth_token=oauth_token)
                    return sync_channel_videos(new_ch, api_key=api_key, oauth_token=oauth_token, max_videos=100)
                except Exception:
                    return 0

            vid_to_cid = {
                vid: cid
                for vid, cid in vid_to_cid.items()
                if not _is_youtube_short(vid, client)
            }
            if not vid_to_cid:
                return 0

            v_resp = client.get(
                f"{YT_API_BASE}/videos",
                params={
                    **params,
                    "part": "snippet,statistics,contentDetails",
                    "id": ",".join(vid_to_cid.keys()),
                },
                headers=headers,
            )
            v_data = _safe_json(v_resp)
            if v_resp.status_code != 200 or "error" in v_data:
                return 0
            rows_to_save: list[dict] = []
            for v_item in v_data.get("items", []):
                vid = v_item["id"]
                snip = v_item.get("snippet", {})
                stats = v_item.get("statistics", {})
                cdet = v_item.get("contentDetails", {})
                cid = snip.get("channelId") or vid_to_cid.get(vid, "")
                if cid not in ch_map:
                    continue
                ch_obj = ch_map[cid]
                thumbs = snip.get("thumbnails", {})
                thumb_url = (
                    (thumbs.get("high") or thumbs.get("medium") or thumbs.get("default") or {}).get("url")
                    or f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg"
                )
                rows_to_save.append(
                    {
                        "video_id": vid,
                        "channel_id": cid,
                        "channel_title": ch_obj.get("title") or snip.get("channelTitle", "YouTube"),
                        "channel_thumbnail": ch_obj.get("thumbnail_url", ""),
                        "title": snip.get("title", "Untitled"),
                        "thumbnail_url": thumb_url,
                        "published_at": snip.get("publishedAt", datetime.now(timezone.utc).isoformat()),
                        "view_count": int(stats.get("viewCount", 0)),
                        "like_count": int(stats.get("likeCount", 0)),
                        "duration": parse_iso_duration(cdet.get("duration", "")),
                        "is_demo": 0,
                        "is_live": 1 if snip.get("liveBroadcastContent") == "live" else 0,
                    }
                )
            return db.upsert_videos(rows_to_save)
    except Exception:
        return 0


def purge_existing_shorts(
    on_progress: Callable[[int, int, int], None] | None = None,
) -> dict:
    """
    Verifikasi dan hapus video Shorts lama yang sudah terlanjur tersimpan menggunakan endpoint format
    HEAD /shorts/{id} (200 = Shorts -> hapus, 303 redirect = video reguler -> pertahankan).
    Video reguler berdurasi < 1 menit TIDAK akan dihapus.
    """
    candidates = db.list_unchecked_short_candidates()
    total = len(candidates)
    if total == 0:
        return {"total": 0, "checked": 0, "deleted": 0, "kept_regular": 0}

    checked = 0
    deleted = 0
    kept_regular = 0
    short_buf: list[str] = []
    reg_buf: list[str] = []

    limits = httpx.Limits(max_connections=60, max_keepalive_connections=40)
    with httpx.Client(timeout=6.0, limits=limits, follow_redirects=False) as client:
        head_fn = getattr(client, "head", None)

        def _probe(vid: str) -> tuple[str, str]:
            if not callable(head_fn):
                return vid, "skip"
            try:
                try:
                    r = head_fn(f"https://www.youtube.com/shorts/{vid}", follow_redirects=False)
                except TypeError:
                    r = head_fn(f"https://www.youtube.com/shorts/{vid}")
                code = getattr(r, "status_code", 0)
                if code in (301, 302, 303, 307, 308):
                    return vid, "regular"
                if code == 200:
                    final_url = str(getattr(r, "url", "") or "")
                    if final_url and "/watch" in final_url:
                        return vid, "regular"
                    return vid, "short"
                if code == 404:
                    return vid, "regular"
            except Exception:
                pass
            return vid, "skip"

        with ThreadPoolExecutor(max_workers=40) as pool:
            futures = [pool.submit(_probe, vid) for vid in candidates]
            for fut in as_completed(futures):
                vid, kind = fut.result()
                checked += 1
                if kind == "short":
                    short_buf.append(vid)
                elif kind == "regular":
                    reg_buf.append(vid)
                    kept_regular += 1
                if len(short_buf) + len(reg_buf) >= 200:
                    deleted += db.apply_short_check_batch(short_buf, reg_buf)
                    short_buf.clear()
                    reg_buf.clear()
                    if on_progress:
                        on_progress(checked, total, deleted)

    if short_buf or reg_buf:
        deleted += db.apply_short_check_batch(short_buf, reg_buf)
    if on_progress:
        on_progress(checked, total, deleted)
    return {
        "total": total,
        "checked": checked,
        "deleted": deleted,
        "kept_regular": kept_regular,
    }



