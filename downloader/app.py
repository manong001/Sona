from __future__ import annotations

import hmac
import json
import multiprocessing
import os
import queue
import re
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import dataclass
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlencode, urlparse
from urllib.request import Request, urlopen


DEFAULT_SOURCES = (
    "MiguMusicClient",
    "NeteaseMusicClient",
    "QQMusicClient",
    "KuwoMusicClient",
    "QianqianMusicClient",
)
SOURCE_LABELS = {
    "MiguMusicClient": "咪咕音乐",
    "NeteaseMusicClient": "网易云音乐",
    "QQMusicClient": "QQ音乐",
    "KuwoMusicClient": "酷我音乐",
    "QianqianMusicClient": "千千音乐",
    "KugouMusicClient": "酷狗音乐",
    "BilibiliMusicClient": "哔哩哔哩",
    "AppleMusicClient": "Apple Music",
    "SpotifyMusicClient": "Spotify",
    "YouTubeMusicClient": "YouTube",
    "JooxMusicClient": "JOOX",
    "SoundCloudMusicClient": "SoundCloud",
    "DeezerMusicClient": "Deezer",
    "QobuzMusicClient": "Qobuz",
    "TIDALMusicClient": "TIDAL",
}
MAX_QUERY_LENGTH = 120
MAX_BODY_BYTES = 64 * 1024
MAX_PLAYLIST_URL_LENGTH = 2_048
MAX_CANDIDATES = 1_000
CANDIDATE_TTL_SECONDS = 30 * 60
PLAYLIST_CANDIDATE_TTL_SECONDS = 72 * 60 * 60
PLAYBACK_URL_TTL_SECONDS = 30 * 60
DOWNLOAD_TIMEOUT_SECONDS = 10 * 60
SUPPORTED_AUDIO_EXTENSIONS = frozenset(
    {"mp3", "m4a", "aac", "flac", "alac", "wav", "aiff", "aif", "ogg", "opus", "ape", "wv", "tta"}
)
PLAYLIST_HOSTS = frozenset({
    "kuwo.cn", "music.migu.cn", "migu.cn", "music.163.com", "163cn.tv",
    "y.qq.com", "music.qq.com", "music.91q.com", "music.taihe.com", "music.baidu.com",
    "open.spotify.com",
})


def source_label(source: str) -> str:
    """Return a stable display name for every musicdl source.

    musicdl exposes many more clients than Sona's conservative default list.
    Keeping a fallback here means enabling one through ``SONA_DOWNLOAD_SOURCES``
    does not make /health or search fail with a KeyError.
    """
    return SOURCE_LABELS.get(source, source.removesuffix("MusicClient") or source)


@dataclass(frozen=True)
class BackendCandidate:
    source: str
    title: str
    artist: str
    album: str
    extension: str
    duration_ms: int | None
    file_size_bytes: int | None
    bitrate: int | None
    sample_rate: int | None
    artwork_url: str | None
    lyrics: str | None
    opaque: Any


@dataclass(frozen=True)
class SpotifyPlaylistItem:
    uri: str


@dataclass(frozen=True)
class PublicPlaylistItem:
    source: str
    identifier: str


@dataclass
class CachedCandidate:
    candidate: BackendCandidate
    created_at: float
    expires_at: float


class CandidateCache:
    def __init__(self, clock=time.monotonic):
        self._clock = clock
        self._items: dict[str, CachedCandidate] = {}
        self._lock = threading.Lock()

    def add(self, candidate: BackendCandidate, ttl_seconds: int = CANDIDATE_TTL_SECONDS) -> str:
        with self._lock:
            self._purge_locked()
            if len(self._items) >= MAX_CANDIDATES:
                oldest = min(self._items, key=lambda key: self._items[key].created_at)
                self._items.pop(oldest, None)
            candidate_id = str(uuid.uuid4())
            now = self._clock()
            self._items[candidate_id] = CachedCandidate(candidate, now, now + ttl_seconds)
            return candidate_id

    def get(self, candidate_id: str) -> BackendCandidate | None:
        with self._lock:
            self._purge_locked()
            cached = self._items.get(candidate_id)
            return cached.candidate if cached else None

    def _purge_locked(self) -> None:
        expired = [
            candidate_id
            for candidate_id, cached in self._items.items()
            if cached.expires_at <= self._clock()
        ]
        for candidate_id in expired:
            self._items.pop(candidate_id, None)


def _run_download_process(action: Any, arguments: tuple[Any, ...], result_queue: Any) -> None:
    try:
        result_queue.put((True, action(*arguments)))
    except BaseException as exception:
        result_queue.put((False, str(exception) or exception.__class__.__name__))


class DownloadProcessRunner:
    def __init__(self, timeout_seconds: float = DOWNLOAD_TIMEOUT_SECONDS):
        self._timeout_seconds = timeout_seconds
        self._context = multiprocessing.get_context("spawn")
        self._processes: dict[str, Any] = {}
        self._cancelled: set[str] = set()
        self._lock = threading.Lock()

    def run(self, task_id: str, action: Any, *arguments: Any) -> list[str]:
        result_queue = self._context.Queue(maxsize=1)
        process = self._context.Process(
            target=_run_download_process,
            args=(action, arguments, result_queue),
            daemon=True,
        )
        with self._lock:
            if task_id in self._processes:
                raise RuntimeError("下载任务正在运行")
            if task_id in self._cancelled:
                self._cancelled.remove(task_id)
                raise RuntimeError("下载已取消")
            self._processes[task_id] = process
            process.start()
        deadline = time.monotonic() + self._timeout_seconds
        try:
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    self._terminate(process)
                    raise TimeoutError(f"下载超时（超过 {self._timeout_seconds:g} 秒）")
                try:
                    succeeded, value = result_queue.get(timeout=min(0.1, remaining))
                    if succeeded:
                        return value
                    raise RuntimeError(value)
                except queue.Empty:
                    if process.is_alive():
                        continue
                    with self._lock:
                        cancelled = task_id in self._cancelled
                    if cancelled:
                        raise RuntimeError("下载已取消")
                    raise RuntimeError("下载进程异常退出")
        finally:
            self._terminate(process)
            with self._lock:
                self._processes.pop(task_id, None)
                self._cancelled.discard(task_id)
            result_queue.close()

    def cancel(self, task_id: str) -> None:
        with self._lock:
            self._cancelled.add(task_id)
            process = self._processes.get(task_id)
        if process is not None:
            self._terminate(process)

    def _terminate(self, process: Any) -> None:
        if process.is_alive():
            process.terminate()
            process.join(timeout=1)


def _download_musicdl_candidate(
    music_dir_value: str,
    state_dir_value: str,
    source: str,
    opaque: Any,
) -> list[str]:
    from musicdl import musicdl

    music_dir = Path(music_dir_value).resolve()
    config = {
        source: {
            "work_dir": state_dir_value,
            "search_size_per_source": 8,
            "search_size_per_page": 8,
            "strict_limit_search_size_per_page": True,
            "disable_print": True,
        }
    }
    client = musicdl.MusicClient(
        music_sources=[source],
        init_music_clients_cfg=config,
        clients_threadings={source: 2},
    )
    downloaded = client.download(song_infos=[opaque])
    files: list[str] = []
    for song in downloaded:
        raw_path = getattr(song, "_save_path", None) or getattr(song, "save_path", None)
        if not raw_path:
            continue
        resolved = Path(raw_path).resolve()
        try:
            relative = resolved.relative_to(music_dir)
        except ValueError as exception:
            raise RuntimeError("musicdl returned a path outside /music") from exception
        if resolved.is_file() and resolved.suffix.removeprefix(".").lower() in SUPPORTED_AUDIO_EXTENSIONS:
            files.append(relative.as_posix())
    if not files:
        raise RuntimeError("musicdl did not produce an audio file")
    return files


class MusicDlBackend:
    def __init__(
        self,
        music_dir: Path,
        allowed_sources: tuple[str, ...],
        state_dir: Path = Path("/tmp/sona-downloader"),
    ):
        from musicdl import musicdl
        from musicdl.modules import MusicClientBuilder

        self._musicdl = musicdl
        self._music_dir = music_dir.resolve()
        self._output_dir = self._music_dir / "download"
        self._output_dir.mkdir(parents=True, exist_ok=True)
        self._state_dir = state_dir.resolve()
        self._state_dir.mkdir(parents=True, exist_ok=True)
        self._allowed_sources = allowed_sources
        self._registered_sources = frozenset(MusicClientBuilder.REGISTERED_MODULES)
        self._clients: dict[tuple[str, ...], Any] = {}
        self._source_locks: dict[tuple[str, ...], threading.Lock] = {}
        self._lock = threading.Lock()
        self._download_runner = DownloadProcessRunner()

    @property
    def registered_sources(self) -> frozenset[str]:
        return self._registered_sources

    def search(self, query: str, sources: tuple[str, ...]) -> list[BackendCandidate]:
        with self._lock_for(sources):
            client = self._client(sources)
            results = client.search(keyword=query)
        candidates: list[BackendCandidate] = []
        for source in sources:
            for song in results.get(source, []):
                song.work_dir = str(self._output_dir / source_label(source))
                candidates.append(
                    BackendCandidate(
                        source=source,
                        title=_text(song.song_name),
                        artist=_text(song.singers),
                        album=_text(song.album),
                        extension=_text(song.ext).removeprefix(".").lower(),
                        duration_ms=_duration_ms(song.duration_s, song.duration),
                        file_size_bytes=_positive_int(song.file_size_bytes),
                        bitrate=_positive_int(song.bitrate),
                        sample_rate=_positive_int(song.samplerate),
                        artwork_url=_optional_text(song.cover_url),
                        lyrics=_optional_text(song.lyric),
                        opaque=song,
                    )
                )
        return candidates

    def parse_playlist(self, url: str) -> tuple[str, str | None, list[BackendCandidate]]:
        hostname = (urlparse(url).hostname or "").lower().strip(".")
        public_parser = None
        if hostname == "open.spotify.com":
            public_parser = self._parse_spotify_playlist
        elif hostname == "music.163.com":
            public_parser = self._parse_netease_playlist
        elif hostname == "y.qq.com" or hostname.endswith(".y.qq.com") or hostname == "music.qq.com":
            public_parser = self._parse_qq_playlist
        if public_parser is not None:
            try:
                return public_parser(url)
            except (KeyError, OSError, TypeError, ValueError):
                pass
        sources = (
            ("SpotifyMusicClient",)
            if hostname == "open.spotify.com"
            else self._allowed_sources
        )
        with self._lock_for(sources):
            songs = self._client(sources).parseplaylist(url)
        if not songs:
            raise ValueError("无法解析歌单，请确认链接公开且属于已启用音源")
        playlist_name = Path(_text(getattr(songs[0], "work_dir", ""))).name.strip()
        playlist_name = re.sub(r"^\d{4}(?:-\d{2}){5}\s+", "", playlist_name)
        playlist_name = (playlist_name or "导入歌单")[:80]
        output_dir = self._output_dir / playlist_name
        output_dir.mkdir(parents=True, exist_ok=True)
        candidates = []
        for song in songs:
            song.work_dir = str(output_dir)
            candidates.append(BackendCandidate(
                source=song.source,
                title=_text(song.song_name),
                artist=_text(song.singers),
                album=_text(song.album),
                extension=_text(song.ext).removeprefix(".").lower(),
                duration_ms=_duration_ms(song.duration_s, song.duration),
                file_size_bytes=_positive_int(song.file_size_bytes),
                bitrate=_positive_int(song.bitrate),
                sample_rate=_positive_int(song.samplerate),
                artwork_url=_optional_text(song.cover_url),
                lyrics=_optional_text(song.lyric),
                opaque=song,
            ))
        return playlist_name, None, candidates

    def _parse_spotify_playlist(self, url: str) -> tuple[str, str | None, list[BackendCandidate]]:
        parsed = urlparse(url)
        parts = [part for part in parsed.path.split("/") if part]
        if len(parts) != 2 or parts[0] != "playlist" or not re.fullmatch(r"[A-Za-z0-9]+", parts[1]):
            raise ValueError("Spotify 歌单链接无效")
        playlist_id = parts[1]
        canonical_url = f"https://open.spotify.com/playlist/{playlist_id}"
        metadata = json.loads(self._fetch_text(
            "https://open.spotify.com/oembed?" + urlencode({"url": canonical_url})
        ))
        embed_html = self._fetch_text(f"https://open.spotify.com/embed/playlist/{playlist_id}")
        match = re.search(
            r'<script[^>]*\bid=["\']__NEXT_DATA__["\'][^>]*>(.*?)</script>',
            embed_html,
            re.DOTALL,
        )
        if match is None:
            raise ValueError("Spotify 公开歌单缺少曲目数据")
        entity = json.loads(match.group(1))["props"]["pageProps"]["state"]["data"]["entity"]
        playlist_name = (_text(metadata.get("title")) or _text(entity.get("name"))).strip()[:80]
        artwork_url = _optional_text(metadata.get("thumbnail_url"))
        candidates = []
        for track in entity.get("trackList", []):
            title = _text(track.get("title")).strip()
            artist = _text(track.get("subtitle")).strip()
            uri = _text(track.get("uri")).strip()
            if not title or not artist or not uri.startswith("spotify:track:"):
                continue
            candidates.append(BackendCandidate(
                source="SpotifyMusicClient",
                title=title,
                artist=artist,
                album="",
                extension="mp3",
                duration_ms=_positive_int(track.get("duration")),
                file_size_bytes=None,
                bitrate=None,
                sample_rate=None,
                artwork_url=artwork_url,
                lyrics=None,
                opaque=SpotifyPlaylistItem(uri),
            ))
        if not playlist_name or not candidates:
            raise ValueError("Spotify 公开歌单没有可同步曲目")
        return playlist_name, artwork_url, candidates

    def _parse_netease_playlist(self, url: str) -> tuple[str, str | None, list[BackendCandidate]]:
        playlist_id = _playlist_id(url, query_keys=("id",))
        if not playlist_id:
            raise ValueError("网易云歌单链接无效")
        detail = self._fetch_json(
            "https://music.163.com/api/v6/playlist/detail?" + urlencode({"id": playlist_id}),
            "https://music.163.com/",
        )
        playlist = detail["playlist"]
        name = _text(playlist.get("name")).strip()[:80]
        cover = _optional_text(playlist.get("coverImgUrl"))
        embedded = {
            _text(track.get("id")): track
            for track in playlist.get("tracks", [])
            if isinstance(track, dict) and _text(track.get("id"))
        }
        track_ids = [
            _text(item.get("id")).strip()
            for item in playlist.get("trackIds", [])
            if isinstance(item, dict) and _text(item.get("id")).strip().isdigit()
        ][:MAX_CANDIDATES]
        songs = {}
        for offset in range(0, len(track_ids), 100):
            batch = track_ids[offset:offset + 100]
            response = self._fetch_json(
                "https://music.163.com/api/song/detail?" + urlencode({
                    "ids": json.dumps([int(item) for item in batch], separators=(",", ":"))
                }),
                "https://music.163.com/",
            )
            for song in response.get("songs", []):
                if isinstance(song, dict):
                    songs[_text(song.get("id"))] = song
        ordered_songs = [songs.get(track_id) or embedded.get(track_id) for track_id in track_ids]
        if not track_ids:
            ordered_songs = list(embedded.values())[:MAX_CANDIDATES]
        candidates = []
        for song in ordered_songs:
            if not isinstance(song, dict):
                continue
            title = _text(song.get("name")).strip()
            artists = song.get("ar") or song.get("artists") or []
            artist = "、".join(
                _text(item.get("name")).strip()
                for item in artists if isinstance(item, dict) and _text(item.get("name")).strip()
            )
            album = song.get("al") or song.get("album") or {}
            identifier = _text(song.get("id")).strip()
            if not title or not artist or not identifier:
                continue
            candidates.append(BackendCandidate(
                source="NeteaseMusicClient",
                title=title,
                artist=artist,
                album=_text(album.get("name")).strip() if isinstance(album, dict) else "",
                extension="mp3",
                duration_ms=_positive_int(song.get("dt") or song.get("duration")),
                file_size_bytes=None,
                bitrate=None,
                sample_rate=None,
                artwork_url=(
                    _optional_text(album.get("picUrl")) if isinstance(album, dict) else None
                ) or cover,
                lyrics=None,
                opaque=PublicPlaylistItem("NeteaseMusicClient", identifier),
            ))
        if not name or not candidates:
            raise ValueError("网易云公开歌单没有可同步曲目")
        return name, cover, candidates

    def _parse_qq_playlist(self, url: str) -> tuple[str, str | None, list[BackendCandidate]]:
        playlist_id = _playlist_id(url, query_keys=("id", "disstid"), path_marker="playlist")
        if not playlist_id:
            raise ValueError("QQ 音乐歌单链接无效")
        page_size = 100
        playlist = None
        songs = []
        for start in range(0, MAX_CANDIDATES, page_size):
            response = self._fetch_json(
                "https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg?" + urlencode({
                    "type": 1,
                    "json": 1,
                    "utf8": 1,
                    "onlysong": 0,
                    "disstid": playlist_id,
                    "song_begin": start,
                    "song_num": page_size,
                    "format": "json",
                    "inCharset": "utf8",
                    "outCharset": "utf-8",
                    "notice": 0,
                    "platform": "yqq.json",
                    "needNewCode": 0,
                }),
                "https://y.qq.com/",
            )
            page = response["cdlist"][0]
            if playlist is None:
                playlist = page
            page_songs = page.get("songlist", [])
            songs.extend(page_songs)
            total = _positive_int(page.get("songnum"))
            if (
                not page_songs
                or len(page_songs) < page_size
                or (total is not None and len(songs) >= min(total, MAX_CANDIDATES))
            ):
                break
        if playlist is None:
            raise ValueError("QQ 音乐公开歌单没有可同步曲目")
        name = _text(playlist.get("dissname")).strip()[:80]
        cover = _optional_text(playlist.get("logo"))
        candidates = []
        for song in songs[:MAX_CANDIDATES]:
            if not isinstance(song, dict):
                continue
            title = _text(song.get("songname") or song.get("songorig")).strip()
            artist = "、".join(
                _text(item.get("name")).strip()
                for item in song.get("singer", [])
                if isinstance(item, dict) and _text(item.get("name")).strip()
            )
            identifier = _text(song.get("songmid")).strip()
            duration_s = _positive_int(song.get("interval"))
            if not title or not artist or not identifier:
                continue
            candidates.append(BackendCandidate(
                source="QQMusicClient",
                title=title,
                artist=artist,
                album=_text(song.get("albumname")).strip(),
                extension="mp3",
                duration_ms=duration_s * 1_000 if duration_s else None,
                file_size_bytes=None,
                bitrate=None,
                sample_rate=None,
                artwork_url=cover,
                lyrics=None,
                opaque=PublicPlaylistItem("QQMusicClient", identifier),
            ))
        if not name or not candidates:
            raise ValueError("QQ 音乐公开歌单没有可同步曲目")
        return name, cover, candidates

    def _fetch_text(self, url: str) -> str:
        request = Request(url, headers={
            "Accept": "application/json,text/html;q=0.9",
            "User-Agent": "Mozilla/5.0 Sona/1.0",
        })
        with urlopen(request, timeout=15) as response:
            return response.read().decode("utf-8")

    def _fetch_json(self, url: str, referer: str | None = None) -> dict[str, Any]:
        headers = {
            "Accept": "application/json",
            "User-Agent": "Mozilla/5.0 Sona/1.0",
        }
        if referer:
            headers["Referer"] = referer
        request = Request(url, headers=headers)
        with urlopen(request, timeout=20) as response:
            value = json.loads(response.read().decode("utf-8"))
        if not isinstance(value, dict):
            raise ValueError("公开歌单接口返回格式无效")
        return value

    def download(self, candidate: BackendCandidate, task_id: str | None = None) -> list[str]:
        if isinstance(candidate.opaque, (SpotifyPlaylistItem, PublicPlaylistItem)):
            use_original_source = (
                isinstance(candidate.opaque, PublicPlaylistItem)
                and candidate.source in self._allowed_sources
            )
            preferred_sources = (candidate.source,) if use_original_source else self._allowed_sources
            query = f"{candidate.title} {candidate.artist}"
            matches = self.search(query, preferred_sources)
            resolved = next((
                item for item in matches
                if _matches_track(item, candidate.title, candidate.artist, candidate.duration_ms)
            ), None) or next((
                item for item in matches
                if _matches_track(item, candidate.title, candidate.artist, None)
            ), None)
            if resolved is None and preferred_sources != self._allowed_sources:
                fallback_sources = tuple(
                    source for source in self._allowed_sources if source != candidate.source
                )
                if fallback_sources:
                    matches = self.search(query, fallback_sources)
                    resolved = next((
                        item for item in matches
                        if _matches_track(
                            item, candidate.title, candidate.artist, candidate.duration_ms
                        )
                    ), None) or next((
                        item for item in matches
                        if _matches_track(item, candidate.title, candidate.artist, None)
                    ), None)
            if resolved is None:
                raise RuntimeError("未在已启用音源中找到歌单歌曲")
            return self.download(resolved, task_id)
        effective_task_id = task_id or str(uuid.uuid4())
        return self._download_runner.run(
            effective_task_id,
            _download_musicdl_candidate,
            str(self._music_dir),
            str(self._state_dir),
            candidate.source,
            candidate.opaque,
        )

    def cancel_download(self, task_id: str) -> None:
        self._download_runner.cancel(task_id)

    def _client(self, sources: tuple[str, ...]):
        key = tuple(sorted(sources))
        client = self._clients.get(key)
        if client is not None:
            return client
        client = self._build_client(sources)
        self._clients[key] = client
        return client

    def _build_client(self, sources: tuple[str, ...]):
        config = {
            source: {
                "work_dir": str(self._state_dir),
                "search_size_per_source": 8,
                "search_size_per_page": 8,
                "strict_limit_search_size_per_page": True,
                "disable_print": True,
            }
            for source in sources
        }
        client = self._musicdl.MusicClient(
            music_sources=list(sources),
            init_music_clients_cfg=config,
            clients_threadings={source: 2 for source in sources},
        )
        return client

    def _lock_for(self, sources: tuple[str, ...]) -> threading.Lock:
        key = tuple(sorted(sources))
        with self._lock:
            return self._source_locks.setdefault(key, threading.Lock())


class AppState:
    def __init__(
        self,
        backend: Any,
        token: str,
        allowed_sources: tuple[str, ...] = DEFAULT_SOURCES,
        cache: CandidateCache | None = None,
    ):
        if not token:
            raise ValueError("SONA_SIDECAR_TOKEN must not be empty")
        self.backend = backend
        self.token = token
        self.allowed_sources = allowed_sources
        self.cache = cache or CandidateCache()
        self._playback_urls: dict[str, CachedCandidate] = {}
        self._playback_lock = threading.Lock()
        self._resolvers = {"ikun": _resolve_ikun}

    def search(self, query: str, sources: tuple[str, ...]) -> list[dict[str, Any]]:
        items = []
        for candidate in self.backend.search(query, sources):
            candidate_id = self.cache.add(candidate)
            items.append(_public_candidate(candidate_id, candidate))
        return items

    def download(self, candidate_id: str, task_id: str | None = None) -> list[str]:
        candidate = self.cache.get(candidate_id)
        if candidate is None:
            raise LookupError("候选结果不存在或已过期，请重新搜索")
        return self.backend.download(candidate, task_id)

    def cancel_download(self, task_id: str) -> None:
        cancel = getattr(self.backend, "cancel_download", None)
        if cancel is not None:
            cancel(task_id)

    def parse_playlist(self, url: str) -> dict[str, Any]:
        name, artwork_url, candidates = self.backend.parse_playlist(url)
        return {
            "name": name,
            "artworkUrl": artwork_url,
            "items": [
                _public_candidate(
                    self.cache.add(candidate, PLAYLIST_CANDIDATE_TTL_SECONDS), candidate
                )
                for candidate in candidates
            ],
        }

    def playback_fallback(
        self, title: str, artist: str, duration_ms: int | None, resolvers: tuple[str, ...]
    ) -> str:
        enabled = tuple(resolver for resolver in resolvers if resolver in self._resolvers)
        if not enabled:
            raise ValueError("没有启用可用的在线播放音源")
        key = "\u0000".join((title.casefold(), artist.casefold(), str(duration_ms or 0), ",".join(enabled)))
        with self._playback_lock:
            cached = self._playback_urls.get(key)
            if cached and cached.expires_at > time.monotonic():
                return cached.candidate.opaque
        candidates = self.backend.search(f"{title} {artist}", _resolver_musicdl_sources(enabled))
        matches = [candidate for candidate in candidates if _matches_track(candidate, title, artist, duration_ms)]
        if not matches:
            raise LookupError("未找到可靠的在线替代歌曲")
        with ThreadPoolExecutor(max_workers=len(enabled)) as executor:
            futures = [
                executor.submit(self._resolvers[resolver], candidate)
                for resolver in enabled for candidate in matches
                if _supports_resolver(resolver, candidate)
            ]
            if not futures:
                raise LookupError("在线候选不包含可解析的平台标识")
            for future in as_completed(futures):
                try:
                    url = future.result()
                    with self._playback_lock:
                        now = time.monotonic()
                        self._playback_urls[key] = CachedCandidate(
                            BackendCandidate("", "", "", "", "", None, None, None, None, None, None, url),
                            now, now + PLAYBACK_URL_TTL_SECONDS
                        )
                    for other in futures:
                        other.cancel()
                    return url
                except Exception:
                    continue
        raise LookupError("所有在线播放音源均未返回可播放链接")


class SonaDownloaderServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address: tuple[str, int], state: AppState):
        self.state = state
        super().__init__(address, SonaDownloaderHandler)


class SonaDownloaderHandler(BaseHTTPRequestHandler):
    server: SonaDownloaderServer

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/health":
            self._json(
                HTTPStatus.OK,
                {
                    "status": "ok",
                    "sources": [
                        {"id": source, "name": source_label(source)}
                        for source in self.server.state.allowed_sources
                    ],
                },
            )
            return
        if not self._authorized():
            return
        if parsed.path == "/v1/sources":
            self._json(
                HTTPStatus.OK,
                {
                    "items": [
                        {"id": source, "name": source_label(source)}
                        for source in self.server.state.allowed_sources
                    ]
                },
            )
            return
        if parsed.path == "/v1/search":
            self._search(parsed.query)
            return
        self._error(HTTPStatus.NOT_FOUND, "接口不存在")

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        if not self._authorized():
            return
        if parsed.path == "/v1/downloads":
            self._download()
            return
        if parsed.path == "/v1/playlists/parse":
            self._parse_playlist()
            return
        if parsed.path == "/v1/playback/fallbacks":
            self._playback_fallback()
            return
        self._error(HTTPStatus.NOT_FOUND, "接口不存在")

    def do_DELETE(self) -> None:
        parsed = urlparse(self.path)
        if not self._authorized():
            return
        prefix = "/v1/downloads/"
        if parsed.path.startswith(prefix):
            task_id = parsed.path.removeprefix(prefix).strip()
            if not task_id or "/" in task_id:
                self._error(HTTPStatus.BAD_REQUEST, "下载任务 ID 无效")
                return
            self.server.state.cancel_download(task_id)
            self.send_response(HTTPStatus.NO_CONTENT.value)
            self.end_headers()
            return
        self._error(HTTPStatus.NOT_FOUND, "接口不存在")

    def _search(self, raw_query: str) -> None:
        query = parse_qs(raw_query)
        keyword = (query.get("q") or [""])[0].strip()
        if not keyword or len(keyword) > MAX_QUERY_LENGTH:
            self._error(HTTPStatus.BAD_REQUEST, "搜索词长度必须为 1 到 120 个字符")
            return
        requested_values = [
            source.strip()
            for source in (query.get("sources") or [""])[0].split(",")
            if source.strip()
        ]
        # Preserve the caller's order while avoiding duplicate searches and
        # duplicate candidates when a client sends sources=a,a.
        requested = tuple(dict.fromkeys(requested_values)) or self.server.state.allowed_sources
        invalid = [source for source in requested if source not in self.server.state.allowed_sources]
        if invalid:
            self._error(HTTPStatus.BAD_REQUEST, f"不支持的音乐来源：{', '.join(invalid)}")
            return
        try:
            items = self.server.state.search(keyword, requested)
            self._json(HTTPStatus.OK, {"items": items})
        except Exception as exception:
            self._error(HTTPStatus.BAD_GATEWAY, f"多源搜索失败：{exception}")

    def _download(self) -> None:
        try:
            body = self._read_json()
            candidate_id = _text(body.get("candidateId")).strip()
            if not candidate_id:
                self._error(HTTPStatus.BAD_REQUEST, "candidateId 不能为空")
                return
            task_id = _text(body.get("taskId")).strip() or None
            files = self.server.state.download(candidate_id, task_id)
            self._json(HTTPStatus.OK, {"files": files})
        except LookupError as exception:
            self._error(HTTPStatus.NOT_FOUND, str(exception))
        except ValueError as exception:
            self._error(HTTPStatus.BAD_REQUEST, str(exception))
        except Exception as exception:
            self._error(HTTPStatus.BAD_GATEWAY, f"下载失败：{exception}")

    def _parse_playlist(self) -> None:
        try:
            url = _text(self._read_json().get("url")).strip()
            if not url or len(url) > MAX_PLAYLIST_URL_LENGTH:
                raise ValueError("歌单链接长度必须为 1 到 2048 个字符")
            normalized_url = _normalize_playlist_url(url)
            parsed = urlparse(normalized_url)
            hostname = (parsed.hostname or "").lower().strip(".")
            if parsed.scheme not in {"http", "https"} or not any(
                hostname == host or hostname.endswith("." + host)
                for host in PLAYLIST_HOSTS
            ):
                raise ValueError("仅支持已启用的咪咕、网易云、QQ、酷我、千千和 Spotify 歌单链接")
            self._json(HTTPStatus.OK, self.server.state.parse_playlist(normalized_url))
        except ValueError as exception:
            self._error(HTTPStatus.BAD_REQUEST, str(exception))
        except Exception as exception:
            self._error(HTTPStatus.BAD_GATEWAY, f"歌单解析失败：{exception}")

    def _playback_fallback(self) -> None:
        try:
            body = self._read_json()
            title = _text(body.get("title")).strip()
            artist = _text(body.get("artist")).strip()
            duration_ms = _positive_int(body.get("durationMs"))
            resolvers = tuple(_text(value).strip() for value in body.get("sources", []) if _text(value).strip())
            if not title or not artist or len(title) > 300 or len(artist) > 300:
                raise ValueError("歌曲标题和艺人不能为空")
            self._json(HTTPStatus.OK, {
                "url": self.server.state.playback_fallback(title, artist, duration_ms, resolvers)
            })
        except LookupError as exception:
            self._error(HTTPStatus.NOT_FOUND, str(exception))
        except ValueError as exception:
            self._error(HTTPStatus.BAD_REQUEST, str(exception))
        except Exception as exception:
            self._error(HTTPStatus.BAD_GATEWAY, f"在线播放解析失败：{exception}")

    def _authorized(self) -> bool:
        supplied = self.headers.get("X-Sona-Token", "")
        if hmac.compare_digest(supplied, self.server.state.token):
            return True
        self._error(HTTPStatus.UNAUTHORIZED, "sidecar 鉴权失败")
        return False

    def _read_json(self) -> dict[str, Any]:
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError as exception:
            raise ValueError("Content-Length 无效") from exception
        if length <= 0 or length > MAX_BODY_BYTES:
            raise ValueError("请求体大小无效")
        try:
            value = json.loads(self.rfile.read(length))
        except (UnicodeDecodeError, json.JSONDecodeError) as exception:
            raise ValueError("请求体不是有效 JSON") from exception
        if not isinstance(value, dict):
            raise ValueError("请求体必须是 JSON 对象")
        return value

    def _error(self, status: HTTPStatus, message: str) -> None:
        self._json(status, {"error": message})

    def _json(self, status: HTTPStatus, value: dict[str, Any]) -> None:
        data = json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status.value)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format: str, *args: Any) -> None:
        print(f"{self.client_address[0]} - {format % args}", flush=True)


def _public_candidate(candidate_id: str, candidate: BackendCandidate) -> dict[str, Any]:
    quality_parts = [candidate.extension.upper() or "音频"]
    if candidate.bitrate:
        quality_parts.append(f"{candidate.bitrate} kbps")
    if candidate.sample_rate:
        quality_parts.append(f"{candidate.sample_rate / 1000:g} kHz")
    return {
        "candidateId": candidate_id,
        "source": candidate.source,
        "sourceName": source_label(candidate.source),
        "title": candidate.title,
        "artist": candidate.artist,
        "album": candidate.album,
        "extension": candidate.extension,
        "quality": " · ".join(quality_parts),
        "durationMs": candidate.duration_ms,
        "fileSizeBytes": candidate.file_size_bytes,
        "artworkUrl": candidate.artwork_url,
        "hasLyrics": bool(candidate.lyrics),
        "lyrics": candidate.lyrics,
    }


def _normalize_playlist_url(value: str) -> str:
    match = re.search(r'https?://[^\s<>"“”]+', value, re.IGNORECASE)
    if match is not None:
        url = match.group(0)
    else:
        url = value.strip()
        if not url or any(character.isspace() for character in url):
            raise ValueError("分享内容中没有找到歌单链接")
        if "://" not in url:
            url = "https://" + url
    url = url.rstrip(".,;:!?，。；：！？、)]}）】》")
    parsed = urlparse(url)
    hostname = (parsed.hostname or "").lower().strip(".")
    if (
        (hostname == "y.qq.com" or hostname.endswith(".y.qq.com"))
        and parsed.path == "/n3/other/pages/details/playlist.html"
    ):
        playlist_id = (parse_qs(parsed.query).get("id") or [""])[0].strip()
        if playlist_id.isdigit():
            return f"https://y.qq.com/n/ryqq/playlist/{playlist_id}"
    return _resolve_short_playlist_url(url) if hostname == "163cn.tv" else url


def _playlist_id(
    url: str, query_keys: tuple[str, ...], path_marker: str | None = None
) -> str | None:
    parsed = urlparse(url)
    values = parse_qs(parsed.query)
    fragment = urlparse(parsed.fragment)
    fragment_values = parse_qs(fragment.query)
    for key in query_keys:
        value = ((values.get(key) or fragment_values.get(key)) or [""])[0].strip()
        if value.isdigit():
            return value
    if path_marker:
        parts = [part for part in parsed.path.split("/") if part]
        if path_marker in parts:
            position = parts.index(path_marker)
            if position + 1 < len(parts) and parts[position + 1].isdigit():
                return parts[position + 1]
    return None


def _resolve_short_playlist_url(url: str) -> str:
    request = Request(url, method="HEAD", headers={"User-Agent": "Mozilla/5.0 Sona/1.0"})
    with urlopen(request, timeout=10) as response:
        resolved_url = response.geturl()
    parsed = urlparse(resolved_url)
    hostname = (parsed.hostname or "").lower().strip(".")
    playlist_id = (parse_qs(parsed.query).get("id") or [""])[0].strip()
    if hostname == "music.163.com" and playlist_id.isdigit():
        return "https://music.163.com/playlist?" + urlencode({"id": playlist_id})
    return resolved_url


def _duration_ms(duration_s: Any, formatted: Any) -> int | None:
    seconds = _positive_int(duration_s)
    if seconds:
        return seconds * 1_000
    text = _text(formatted).strip()
    try:
        parts = [int(part) for part in text.split(":")]
    except ValueError:
        return None
    if len(parts) == 2:
        return (parts[0] * 60 + parts[1]) * 1_000
    if len(parts) == 3:
        return (parts[0] * 3_600 + parts[1] * 60 + parts[2]) * 1_000
    return None


def _positive_int(value: Any) -> int | None:
    try:
        parsed = int(value)
        return parsed if parsed > 0 else None
    except (TypeError, ValueError):
        return None


def _text(value: Any) -> str:
    return "" if value is None else str(value)


def _optional_text(value: Any) -> str | None:
    text = _text(value).strip()
    return text or None


def _resolver_musicdl_sources(resolvers: tuple[str, ...]) -> tuple[str, ...]:
    sources = []
    if "ikun" in resolvers:
        sources.extend(("KuwoMusicClient", "NeteaseMusicClient"))
    return tuple(dict.fromkeys(sources))


def _supports_resolver(resolver: str, candidate: BackendCandidate) -> bool:
    return resolver == "ikun" and candidate.source in {"KuwoMusicClient", "NeteaseMusicClient"}


def _matches_track(candidate: BackendCandidate, title: str, artist: str, duration_ms: int | None) -> bool:
    normalize = lambda value: re.sub(r"[^\w\u4e00-\u9fff]", "", value).casefold()
    if normalize(candidate.title) != normalize(title):
        return False
    if normalize(artist) not in normalize(candidate.artist) and normalize(candidate.artist) not in normalize(artist):
        return False
    return not duration_ms or not candidate.duration_ms or abs(candidate.duration_ms - duration_ms) <= 5_000


def _opaque_value(opaque: Any, name: str) -> str:
    value = opaque.get(name) if isinstance(opaque, dict) else getattr(opaque, name, None)
    return _text(value).strip()


def _resolve_ikun(candidate: BackendCandidate) -> str:
    source = {"KuwoMusicClient": "kw", "NeteaseMusicClient": "wy"}.get(candidate.source)
    song_id = _opaque_value(candidate.opaque, "hash") or _opaque_value(candidate.opaque, "songmid")
    if not source or not song_id:
        raise ValueError("候选缺少 Ikun 所需的平台歌曲标识")
    quality = "flac" if candidate.extension.lower() == "flac" else "320k"
    query = urlencode({"source": source, "songId": song_id, "quality": quality})
    with urlopen(f"http://api.ikunshare.com/url?{query}", timeout=5) as response:
        body = json.loads(response.read())
    url = _text(body.get("url")).strip()
    if body.get("code") != 200 or not re.match(r"^https?://", url, re.I):
        raise ValueError(_text(body.get("message")) or "Ikun 未返回有效播放链接")
    return url


def main() -> None:
    host = os.getenv("SONA_DOWNLOADER_HOST", "0.0.0.0")
    port = int(os.getenv("SONA_DOWNLOADER_PORT", "6700"))
    token = os.getenv("SONA_SIDECAR_TOKEN", "")
    music_dir = Path(os.getenv("SONA_MUSIC_DIR", "/music"))
    state_dir = Path(os.getenv("SONA_DOWNLOADER_STATE_DIR", "/tmp/sona-downloader"))
    configured_sources = tuple(dict.fromkeys(
        source.strip()
        for source in os.getenv("SONA_DOWNLOAD_SOURCES", ",".join(DEFAULT_SOURCES)).split(",")
        if source.strip()
    ))
    if not configured_sources:
        raise ValueError("SONA_DOWNLOAD_SOURCES must contain at least one source")
    # Instantiate the backend before validating the environment so operators
    # can opt into any client shipped by musicdl (the defaults remain the
    # stable, well-tested five Chinese providers).
    backend = MusicDlBackend(music_dir, configured_sources, state_dir)
    invalid = [source for source in configured_sources if source not in backend.registered_sources]
    if invalid:
        raise ValueError(f"Unsupported musicdl sources: {', '.join(invalid)}")
    state = AppState(
        backend,
        token,
        configured_sources,
    )
    server = SonaDownloaderServer((host, port), state)
    print(f"Sona downloader listening on {host}:{port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
