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
        country = snippet.get("country", "")
        default_lang = snippet.get("defaultLanguage", "")
        region = db.classify_region(title, handle, country=country, default_lang=default_lang)
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
            region=region,
            country=country,
            status="subscribed",
            force_subscribe=True,
        )
        return {"channel_id": cid, "title": title, "handle": handle, "uploads_playlist_id": uploads_pid, "region": region}


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

        # Cek negara asli (snippet.country) untuk channel yang baru ditambahkan
        if newly_added_channels:
            new_cids = [c["channel_id"] for c in newly_added_channels]
            for i in range(0, len(new_cids), 50):
                chunk = new_cids[i : i + 50]
                try:
                    c_resp = client.get(
                        f"{YT_API_BASE}/channels",
                        params={"part": "snippet", "id": ",".join(chunk), "key": api_key.strip()},
                    )
                    for ch_it in c_resp.json().get("items", []):
                        cid = ch_it["id"]
                        csnip = ch_it.get("snippet", {})
                        reg = db.classify_region(
                            csnip.get("title", ""),
                            csnip.get("customUrl", ""),
                            country=csnip.get("country", ""),
                            default_lang=csnip.get("defaultLanguage", ""),
                        )
                        db.set_channel_region(cid, reg)
                except Exception:
                    pass

    # Langsung tarik video untuk setiap channel baru yang baru saja di-subscribe di YouTube!
    for new_ch in newly_added_channels:
        try:
            sync_channel_videos(new_ch, api_key=api_key, max_videos=50)
        except Exception:
            pass

    return len(newly_added_channels)


def refresh_all_channel_statistics(api_key: str = "", oauth_token: str = "") -> int:
    """Ambil total video asli di YouTube (bisa ribuan video), jumlah subscriber, @handle, dan negara/region untuk seluruh channel."""
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
                    country = snip.get("country", "")
                    default_lang = snip.get("defaultLanguage", "")
                    reg = db.classify_region(snip.get("title", ""), handle, country=country, default_lang=default_lang)
                    v_count = int(stats.get("videoCount", 0))
                    sub_count = int(stats.get("subscriberCount", 0))
                    conn.execute(
                        """
                        UPDATE channels
                        SET yt_video_count=?,
                            subscriber_count=?,
                            region=CASE WHEN ? != 'Belum diketahui' AND COALESCE(region, 'Belum diketahui') = 'Belum diketahui' THEN ? ELSE region END,
                            handle=CASE WHEN ? != '' THEN ? ELSE handle END
                        WHERE channel_id=?
                        """,
                        (v_count, sub_count, reg, reg, handle, handle, cid),
                    )
                    conn.execute(
                        """
                        UPDATE videos
                        SET region=CASE WHEN ? != 'Belum diketahui' AND COALESCE(region, 'Belum diketahui') = 'Belum diketahui' THEN ? ELSE region END
                        WHERE channel_id=?
                        """,
                        (reg, reg, cid),
                    )
                    updated += 1
    return updated


def sync_channel_videos(
    channel: dict,
    api_key: str = "",
    oauth_token: str = "",
    years_back: int = 10,
    max_videos: int = 250,
) -> int:
    cid = channel["channel_id"]
    if cid.startswith("UC_demo_"):
        return 0

    params, headers = _auth_params_headers(api_key, oauth_token)
    if not params and not headers:
        return 0

    uploads_pid = channel.get("uploads_playlist_id") or ("UU" + cid[2:] if cid.startswith("UC") else "")
    if not uploads_pid:
        return 0

    cutoff = datetime.now(timezone.utc) - timedelta(days=365 * years_back + 30)
    video_ids: list[str] = []
    page_token = None

    with httpx.Client(timeout=25.0) as client:
        while len(video_ids) < max_videos:
            req_params = {
                **params,
                "part": "contentDetails,snippet",
                "playlistId": uploads_pid,
                "maxResults": 50,
            }
            if page_token:
                req_params["pageToken"] = page_token

            resp = client.get(f"{YT_API_BASE}/playlistItems", params=req_params, headers=headers)
            data = _safe_json(resp)
            if resp.status_code != 200 or "error" in data:
                err_msg = data.get("error", {}).get("message", f"YouTube playlist API error ({resp.status_code})")
                if not video_ids:
                    raise RuntimeError(err_msg)
                break
            items = data.get("items", [])
            if not items:
                break

            reached_cutoff = False
            for it in items:
                if len(video_ids) >= max_videos:
                    break
                vid = it.get("contentDetails", {}).get("videoId")
                pub_str = it.get("contentDetails", {}).get("videoPublishedAt") or it.get("snippet", {}).get("publishedAt", "")
                if pub_str and len(video_ids) >= 50:
                    try:
                        pub_dt = datetime.fromisoformat(pub_str.replace("Z", "+00:00"))
                        if pub_dt.tzinfo is None:
                            pub_dt = pub_dt.replace(tzinfo=timezone.utc)
                        if pub_dt < cutoff:
                            reached_cutoff = True
                            break
                    except (ValueError, TypeError):
                        pass
                if vid:
                    video_ids.append(vid)

            page_token = data.get("nextPageToken")
            if reached_cutoff or not page_token or len(video_ids) >= max_videos:
                break

        # Batch fetch statistics (viewCount, likeCount) & duration in chunks of 50 (only 1 unit per 50 videos!)
        rows_to_save: list[dict] = []
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
            for v_item in v_data.get("items", []):
                vid = v_item["id"]
                snip = v_item.get("snippet", {})
                stats = v_item.get("statistics", {})
                cdet = v_item.get("contentDetails", {})
                thumbs = snip.get("thumbnails", {})
                thumb_url = (
                    (thumbs.get("high") or thumbs.get("medium") or thumbs.get("default") or {}).get("url")
                    or f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg"
                )
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
                        "duration": parse_iso_duration(cdet.get("duration", "")),
                        "is_demo": 0,
                    }
                )

    return db.upsert_videos(rows_to_save)


def refresh_all_channels_comprehensive(
    channels: list[dict],
    api_key: str = "",
    oauth_token: str = "",
    on_progress: Callable[[int, int], None] | None = None,
) -> int:
    """
    Mengecek SELURUH channel (100% semua 927+ channel, termasuk YouTuber yang jarang upload 1 bulan/tahun sekali):
    1. Channel yang belum pernah tersinkronisasi sama sekali ditarik via API.
    2. Seluruh channel lainnya dicek feed video terbarunya secara paralel (0 kuota API untuk cek daftar ID video terbaru),
       lalu seluruh video baru & video 48 jam terakhir diambil statistik lengkapnya (views, likes, durasi) via batch videos.list (50 video/request).
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
    recent_cutoff = (datetime.now(timezone.utc) - timedelta(hours=48)).isoformat()
    with db.get_conn() as conn:
        rows = conn.execute(
            "SELECT video_id, published_at FROM videos"
        ).fetchall()
        all_existing_vids = {r["video_id"] for r in rows}
        known_old_vids = {r["video_id"] for r in rows if (r["published_at"] or "") < recent_cutoff}

    unsynced_chs = [c for c in real_chs if c.get("synced_video_count", 0) == 0]
    rss_chs = [c for c in real_chs if c.get("synced_video_count", 0) > 0]

    done_count = 0
    newly_inserted_count = 0

    # 1. Sync channel baru secara berurutan agar tidak terjadi race condition / lock di SQLite
    for ch in unsynced_chs:
        try:
            sync_channel_videos(ch, api_key=api_key, oauth_token=oauth_token, max_videos=50)
        except Exception:
            pass
        done_count += 1
        if on_progress:
            on_progress(done_count, total_chs)

    # 2. Cek seluruh 15 item RSS terbaru untuk channel lainnya (dengan koneksi pool & retry jika kena timeout/429)
    vid_to_cid: dict[str, str] = {}

    if rss_chs:
        with httpx.Client(timeout=10.0, follow_redirects=True) as rss_client:
            def _check_channel(ch: dict) -> list[tuple[str, str]]:
                cid = ch["channel_id"]
                found: list[tuple[str, str]] = []
                url = f"https://www.youtube.com/feeds/videos.xml?channel_id={cid}"
                for attempt in range(2):
                    try:
                        r = rss_client.get(url)
                        if r.status_code == 200:
                            vids = re.findall(r"<yt:videoId>([^<]+)</yt:videoId>", r.text)
                            for v in vids:
                                if v not in known_old_vids:
                                    found.append((v, cid))
                            return found
                        if r.status_code in (429, 500, 502, 503, 504) and attempt == 0:
                            time.sleep(0.4)
                            continue
                        return found
                    except Exception:
                        if attempt == 0:
                            time.sleep(0.4)
                return found

            with ThreadPoolExecutor(max_workers=20) as pool:
                futures = [pool.submit(_check_channel, ch) for ch in rss_chs]
                for fut in as_completed(futures):
                    done_count += 1
                    if on_progress:
                        on_progress(done_count, total_chs)
                    for vid, cid in fut.result():
                        vid_to_cid[vid] = cid

    if not vid_to_cid:
        if unsynced_chs:
            with db.get_conn() as conn:
                after_count = conn.execute("SELECT COUNT(*) FROM videos").fetchone()[0]
                return max(0, after_count - len(all_existing_vids))
        return 0

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
            chunk_rows: list[dict] = []
            for v_item in v_data.get("items", []):
                vid = v_item["id"]
                snip = v_item.get("snippet", {})
                stats = v_item.get("statistics", {})
                cdet = v_item.get("contentDetails", {})
                cid = snip.get("channelId") or vid_to_cid.get(vid, "")
                ch_obj = ch_map.get(cid, {})
                thumbs = snip.get("thumbnails", {})
                thumb_url = (
                    (thumbs.get("high") or thumbs.get("medium") or thumbs.get("default") or {}).get("url")
                    or f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg"
                )
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
                        "duration": parse_iso_duration(cdet.get("duration", "")),
                        "is_demo": 0,
                    }
                )
            db.upsert_videos(chunk_rows)

    if unsynced_chs:
        with db.get_conn() as conn:
            after_count = conn.execute("SELECT COUNT(*) FROM videos").fetchone()[0]
            return max(newly_inserted_count, after_count - len(all_existing_vids))
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
                    }
                )
            return db.upsert_videos(rows_to_save)
    except Exception:
        return 0



