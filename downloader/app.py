from __future__ import annotations

import hmac
import json
import os
import threading
import time
import uuid
from dataclasses import dataclass
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse


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
MAX_CANDIDATES = 1_000
CANDIDATE_TTL_SECONDS = 30 * 60
SUPPORTED_AUDIO_EXTENSIONS = frozenset(
    {"mp3", "m4a", "aac", "flac", "alac", "wav", "aiff", "aif", "ogg", "opus", "ape", "wv", "tta"}
)


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


@dataclass
class CachedCandidate:
    candidate: BackendCandidate
    created_at: float


class CandidateCache:
    def __init__(self, clock=time.monotonic):
        self._clock = clock
        self._items: dict[str, CachedCandidate] = {}
        self._lock = threading.Lock()

    def add(self, candidate: BackendCandidate) -> str:
        with self._lock:
            self._purge_locked()
            if len(self._items) >= MAX_CANDIDATES:
                oldest = min(self._items, key=lambda key: self._items[key].created_at)
                self._items.pop(oldest, None)
            candidate_id = str(uuid.uuid4())
            self._items[candidate_id] = CachedCandidate(candidate, self._clock())
            return candidate_id

    def get(self, candidate_id: str) -> BackendCandidate | None:
        with self._lock:
            self._purge_locked()
            cached = self._items.get(candidate_id)
            return cached.candidate if cached else None

    def _purge_locked(self) -> None:
        expires_before = self._clock() - CANDIDATE_TTL_SECONDS
        expired = [
            candidate_id
            for candidate_id, cached in self._items.items()
            if cached.created_at < expires_before
        ]
        for candidate_id in expired:
            self._items.pop(candidate_id, None)


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
        self._output_dir = self._music_dir / "Downloads"
        self._output_dir.mkdir(parents=True, exist_ok=True)
        self._state_dir = state_dir.resolve()
        self._state_dir.mkdir(parents=True, exist_ok=True)
        self._allowed_sources = allowed_sources
        self._registered_sources = frozenset(MusicClientBuilder.REGISTERED_MODULES)
        self._clients: dict[tuple[str, ...], Any] = {}
        self._lock = threading.Lock()

    @property
    def registered_sources(self) -> frozenset[str]:
        return self._registered_sources

    def search(self, query: str, sources: tuple[str, ...]) -> list[BackendCandidate]:
        with self._lock:
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

    def download(self, candidate: BackendCandidate) -> list[str]:
        with self._lock:
            client = self._client((candidate.source,))
            downloaded = client.download(song_infos=[candidate.opaque])
        files: list[str] = []
        for song in downloaded:
            # musicdl normally sets _save_path, but a few third-party clients
            # only populate save_path.  Accept both while retaining the path
            # boundary check below.
            raw_path = getattr(song, "_save_path", None) or getattr(song, "save_path", None)
            if not raw_path:
                continue
            resolved = Path(raw_path).resolve()
            try:
                relative = resolved.relative_to(self._music_dir)
            except ValueError as exception:
                raise RuntimeError("musicdl returned a path outside /music") from exception
            if resolved.is_file() and resolved.suffix.removeprefix(".").lower() in SUPPORTED_AUDIO_EXTENSIONS:
                files.append(relative.as_posix())
        if not files:
            raise RuntimeError("musicdl did not produce an audio file")
        return files

    def _client(self, sources: tuple[str, ...]):
        key = tuple(sorted(sources))
        client = self._clients.get(key)
        if client is not None:
            return client
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
        self._clients[key] = client
        return client


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

    def search(self, query: str, sources: tuple[str, ...]) -> list[dict[str, Any]]:
        items = []
        for candidate in self.backend.search(query, sources):
            candidate_id = self.cache.add(candidate)
            items.append(_public_candidate(candidate_id, candidate))
        return items

    def download(self, candidate_id: str) -> list[str]:
        candidate = self.cache.get(candidate_id)
        if candidate is None:
            raise LookupError("候选结果不存在或已过期，请重新搜索")
        return self.backend.download(candidate)


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
            files = self.server.state.download(candidate_id)
            self._json(HTTPStatus.OK, {"files": files})
        except LookupError as exception:
            self._error(HTTPStatus.NOT_FOUND, str(exception))
        except ValueError as exception:
            self._error(HTTPStatus.BAD_REQUEST, str(exception))
        except Exception as exception:
            self._error(HTTPStatus.BAD_GATEWAY, f"下载失败：{exception}")

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
