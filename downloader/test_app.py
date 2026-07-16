import json
import threading
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, urlopen

from app import AppState, BackendCandidate, MusicDlBackend, SonaDownloaderServer


class FakeBackend:
    def __init__(self, music_dir: Path):
        self.music_dir = music_dir
        self.downloaded = []

    def search(self, query, sources):
        return [
            BackendCandidate(
                source=sources[0],
                title=query,
                artist="测试歌手",
                album="测试专辑",
                extension="flac",
                duration_ms=180_000,
                file_size_bytes=12_345,
                bitrate=1_411,
                sample_rate=44_100,
                artwork_url="https://example.test/cover.jpg",
                lyrics="[00:01.00]歌词",
                opaque={"privateDownloadUrl": "https://secret.test/audio.flac"},
            )
        ]

    def download(self, candidate):
        self.downloaded.append(candidate)
        target = self.music_dir / "download" / "测试.flac"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(b"audio")
        return ["download/测试.flac"]

    def parse_playlist(self, url):
        return "测试歌单", self.search("歌单歌曲", ("NeteaseMusicClient",))


class DownloaderApiTest(unittest.TestCase):
    def setUp(self):
        self.temporary = TemporaryDirectory()
        self.backend = FakeBackend(Path(self.temporary.name))
        self.server = SonaDownloaderServer(
            ("127.0.0.1", 0),
            AppState(self.backend, "test-token"),
        )
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.base_url = f"http://127.0.0.1:{self.server.server_port}"

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        self.temporary.cleanup()

    def test_health_does_not_require_token(self):
        status, body = self.request("GET", "/health", authenticated=False)
        self.assertEqual(200, status)
        self.assertEqual("ok", body["status"])
        self.assertEqual("MiguMusicClient", body["sources"][0]["id"])

    def test_search_requires_token_and_hides_download_url(self):
        with self.assertRaises(HTTPError) as context:
            self.request("GET", "/v1/search?q=test", authenticated=False)
        self.assertEqual(401, context.exception.code)
        context.exception.close()

        status, body = self.request("GET", f"/v1/search?q={quote('测试歌曲')}")
        self.assertEqual(200, status)
        self.assertEqual(1, len(body["items"]))
        candidate = body["items"][0]
        self.assertEqual("测试歌曲", candidate["title"])
        self.assertEqual("FLAC · 1411 kbps · 44.1 kHz", candidate["quality"])
        self.assertNotIn("downloadUrl", candidate)
        self.assertNotIn("privateDownloadUrl", json.dumps(candidate))

    def test_download_uses_opaque_cached_candidate(self):
        _, search = self.request("GET", "/v1/search?q=test")
        candidate_id = search["items"][0]["candidateId"]

        status, result = self.request(
            "POST",
            "/v1/downloads",
            {"candidateId": candidate_id},
        )

        self.assertEqual(200, status)
        self.assertEqual(["download/测试.flac"], result["files"])
        self.assertEqual(1, len(self.backend.downloaded))

    def test_parses_playlist_url_and_caches_every_candidate(self):
        status, body = self.request(
            "POST",
            "/v1/playlists/parse",
            {"url": "https://music.163.com/#/playlist?id=123"},
        )

        self.assertEqual(200, status)
        self.assertEqual("测试歌单", body["name"])
        self.assertEqual("歌单歌曲", body["items"][0]["title"])
        self.assertTrue(body["items"][0]["candidateId"])

    def test_rejects_unknown_source_and_candidate(self):
        with self.assertRaises(HTTPError) as source_error:
            self.request("GET", "/v1/search?q=test&sources=UnknownClient")
        self.assertEqual(400, source_error.exception.code)
        source_error.exception.close()

        with self.assertRaises(HTTPError) as candidate_error:
            self.request("POST", "/v1/downloads", {"candidateId": "missing"})
        self.assertEqual(404, candidate_error.exception.code)
        candidate_error.exception.close()

    def test_different_source_searches_are_not_serialized(self):
        class SlowClient:
            def search(self, keyword):
                time.sleep(0.2)
                return {"MiguMusicClient": [], "QQMusicClient": []}

        backend = MusicDlBackend.__new__(MusicDlBackend)
        backend._lock = threading.Lock()
        backend._source_locks = {}
        backend._client = lambda sources: SlowClient()
        started = time.monotonic()
        with ThreadPoolExecutor(max_workers=2) as executor:
            futures = [
                executor.submit(backend.search, "test", ("MiguMusicClient",)),
                executor.submit(backend.search, "test", ("QQMusicClient",)),
            ]
            for future in futures:
                future.result()

        self.assertLess(time.monotonic() - started, 0.35)

    def test_playlist_name_omits_musicdl_timestamp_prefix(self):
        song = SimpleNamespace(
            source="NeteaseMusicClient",
            work_dir="/tmp/NeteaseMusicClient/2026-07-16-02-30-00 我的歌单",
            song_name="测试歌曲",
            singers="测试歌手",
            album="测试专辑",
            ext="flac",
            duration_s=180,
            duration="03:00",
            file_size_bytes=100,
            bitrate=1411,
            samplerate=44100,
            cover_url=None,
            lyric=None,
        )
        with TemporaryDirectory() as directory:
            backend = MusicDlBackend.__new__(MusicDlBackend)
            backend._allowed_sources = ("NeteaseMusicClient",)
            backend._output_dir = Path(directory)
            backend._lock = threading.Lock()
            backend._source_locks = {}
            backend._client = lambda sources: SimpleNamespace(
                parseplaylist=lambda url: [song]
            )

            name, candidates = backend.parse_playlist("https://music.163.com/playlist?id=1")

        self.assertEqual("我的歌单", name)
        self.assertEqual("我的歌单", Path(song.work_dir).name)
        self.assertEqual("测试歌曲", candidates[0].title)

    def request(self, method, path, body=None, authenticated=True):
        data = None if body is None else json.dumps(body).encode()
        request = Request(self.base_url + path, data=data, method=method)
        if data is not None:
            request.add_header("Content-Type", "application/json")
        if authenticated:
            request.add_header("X-Sona-Token", "test-token")
        with urlopen(request, timeout=5) as response:
            return response.status, json.loads(response.read())


if __name__ == "__main__":
    unittest.main()
