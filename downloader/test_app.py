import json
import threading
import time
import unittest
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
from unittest.mock import patch
from urllib.error import HTTPError
from urllib.parse import parse_qs, quote, urlparse
from urllib.request import Request, urlopen

from app import (
    AppState,
    BackendCandidate,
    MusicDlBackend,
    PublicPlaylistItem,
    SonaDownloaderServer,
    SpotifyPlaylistItem,
)


class FakeBackend:
    def __init__(self, music_dir: Path):
        self.music_dir = music_dir
        self.downloaded = []
        self.parsed_playlist_urls = []

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
        self.parsed_playlist_urls.append(url)
        return (
            "测试歌单",
            "https://image.example.test/playlist.jpg",
            self.search("歌单歌曲", ("NeteaseMusicClient",)),
        )


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

    def test_playback_fallback_caches_the_first_valid_url(self):
        calls = 0

        def resolve(candidate):
            nonlocal calls
            calls += 1
            return "https://audio.example.test/song.flac"

        self.server.state._resolvers["ikun"] = resolve
        first = self.server.state.playback_fallback("测试歌曲", "测试歌手", 180_000, ("ikun",))
        second = self.server.state.playback_fallback("测试歌曲", "测试歌手", 180_000, ("ikun",))

        self.assertEqual("https://audio.example.test/song.flac", first)
        self.assertEqual(first, second)
        self.assertEqual(1, calls)

    def test_parses_playlist_url_and_caches_every_candidate(self):
        status, body = self.request(
            "POST",
            "/v1/playlists/parse",
            {"url": "https://music.163.com/#/playlist?id=123"},
        )

        self.assertEqual(200, status)
        self.assertEqual("测试歌单", body["name"])
        self.assertEqual("https://image.example.test/playlist.jpg", body["artworkUrl"])
        self.assertEqual("歌单歌曲", body["items"][0]["title"])
        self.assertTrue(body["items"][0]["candidateId"])

    def test_accepts_spotify_playlist_url(self):
        status, body = self.request(
            "POST",
            "/v1/playlists/parse",
            {"url": "https://open.spotify.com/playlist/37i9dQZF1E8NWHOpySOxQd"},
        )

        self.assertEqual(200, status)
        self.assertEqual("测试歌单", body["name"])

    def test_extracts_and_resolves_netease_short_url_from_share_text(self):
        canonical_url = "https://music.163.com/playlist?id=17797258373"
        with patch("app.urlopen") as opener:
            opener.return_value.__enter__.return_value.geturl.return_value = (
                "https://music.163.com/playlist?app_version=9.5.50"
                "&id=17797258373&userid=17993476&dlt=0846"
            )
            status, body = self.request(
                "POST",
                "/v1/playlists/parse",
                {
                    "url": (
                        "分享歌单: 最近循环停不下来的热歌 "
                        "https://163cn.tv/bbwqMXlr (@网易云音乐)"
                    )
                },
            )

        self.assertEqual(200, status)
        self.assertEqual("测试歌单", body["name"])
        opener.assert_called_once()
        self.assertEqual("https://163cn.tv/bbwqMXlr", opener.call_args.args[0].full_url)
        self.assertEqual([canonical_url], self.backend.parsed_playlist_urls)

    def test_normalizes_qq_music_share_playlist_url(self):
        status, body = self.request(
            "POST",
            "/v1/playlists/parse",
            {
                "url": (
                    "https://i2.y.qq.com/n3/other/pages/details/playlist.html"
                    "?hosteuin=Ne4zoevAoiEA&id=7526304337&appversion=200605"
                    "&ADTAG=wxfshare&appshare=iphone_wx"
                )
            },
        )

        self.assertEqual(200, status)
        self.assertEqual("测试歌单", body["name"])
        self.assertEqual(
            ["https://y.qq.com/n/ryqq/playlist/7526304337"],
            self.backend.parsed_playlist_urls,
        )

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
            backend._fetch_json = lambda url, referer=None: (_ for _ in ()).throw(
                OSError("public parser unavailable")
            )
            backend._client = lambda sources: SimpleNamespace(
                parseplaylist=lambda url: [song]
            )

            name, _, candidates = backend.parse_playlist("https://music.163.com/playlist?id=1")

        self.assertEqual("我的歌单", name)
        self.assertEqual("我的歌单", Path(song.work_dir).name)
        self.assertEqual("测试歌曲", candidates[0].title)

    def test_netease_playlist_uses_public_metadata_and_fetches_every_track(self):
        detail = {
            "playlist": {
                "name": "网易云公开歌单",
                "coverImgUrl": "https://image.example.test/netease.jpg",
                "trackIds": [{"id": 1}, {"id": 2}],
                "tracks": [{"id": 1, "name": "首屏歌曲"}],
            }
        }
        songs = {
            "songs": [
                {
                    "id": 1, "name": "第一首", "duration": 180_000,
                    "artists": [{"name": "歌手甲"}],
                    "album": {"name": "专辑甲", "picUrl": "https://image.test/1.jpg"},
                },
                {
                    "id": 2, "name": "第二首", "duration": 210_000,
                    "artists": [{"name": "歌手乙"}],
                    "album": {"name": "专辑乙", "picUrl": "https://image.test/2.jpg"},
                },
            ]
        }
        requested_urls = []
        backend = MusicDlBackend.__new__(MusicDlBackend)
        backend._allowed_sources = ("NeteaseMusicClient", "QQMusicClient")
        backend._fetch_json = lambda url, referer=None: (
            requested_urls.append(url) or (detail if "/playlist/detail" in url else songs)
        )
        backend._client = lambda sources: self.fail("不应调用 musicdl 网易云解析器")

        name, _, candidates = backend.parse_playlist(
            "https://music.163.com/playlist?id=17797258373"
        )

        self.assertEqual("网易云公开歌单", name)
        self.assertEqual(["第一首", "第二首"], [item.title for item in candidates])
        self.assertEqual("歌手乙", candidates[1].artist)
        self.assertEqual(210_000, candidates[1].duration_ms)
        self.assertEqual(2, len(requested_urls))
        self.assertIsInstance(candidates[0].opaque, PublicPlaylistItem)

    def test_qq_playlist_uses_public_metadata(self):
        response = {
            "code": 0,
            "cdlist": [{
                "dissname": "QQ 公开歌单",
                "logo": "https://image.example.test/qq.jpg",
                "songlist": [{
                    "songmid": "song-mid", "songname": "QQ 歌曲", "interval": 185,
                    "singer": [{"name": "歌手甲"}, {"name": "歌手乙"}],
                    "albumname": "QQ 专辑",
                }],
            }],
        }
        requested_urls = []
        backend = MusicDlBackend.__new__(MusicDlBackend)
        backend._allowed_sources = ("NeteaseMusicClient", "QQMusicClient")
        backend._fetch_json = lambda url, referer=None: requested_urls.append(url) or response
        backend._client = lambda sources: self.fail("不应调用 musicdl QQ 解析器")

        name, artwork_url, candidates = backend.parse_playlist(
            "https://y.qq.com/n/ryqq/playlist/7526304337"
        )

        self.assertEqual("QQ 公开歌单", name)
        self.assertEqual("https://image.example.test/qq.jpg", artwork_url)
        self.assertEqual("QQ 歌曲", candidates[0].title)
        self.assertEqual("歌手甲、歌手乙", candidates[0].artist)
        self.assertEqual(185_000, candidates[0].duration_ms)
        self.assertEqual(1, len(requested_urls))
        self.assertIsInstance(candidates[0].opaque, PublicPlaylistItem)

    def test_qq_playlist_fetches_every_page(self):
        songs = [{
            "songmid": f"song-mid-{index}", "songname": f"QQ 歌曲 {index}",
            "interval": 185, "singer": [{"name": "歌手"}], "albumname": "QQ 专辑",
        } for index in range(411)]
        requested_starts = []

        def fetch_page(url, referer=None):
            query = parse_qs(urlparse(url).query)
            start = int(query["song_begin"][0])
            size = int(query["song_num"][0])
            requested_starts.append(start)
            return {"code": 0, "cdlist": [{
                "dissname": "QQ 公开歌单", "songnum": len(songs),
                "songlist": songs[start:start + size],
            }]}

        backend = MusicDlBackend.__new__(MusicDlBackend)
        backend._allowed_sources = ("NeteaseMusicClient", "QQMusicClient")
        backend._fetch_json = fetch_page
        backend._client = lambda sources: self.fail("不应调用 musicdl QQ 解析器")

        _, _, candidates = backend.parse_playlist(
            "https://y.qq.com/n/ryqq/playlist/9563730925"
        )

        self.assertEqual(411, len(candidates))
        self.assertEqual([0, 100, 200, 300, 400], requested_starts)

    def test_spotify_playlist_uses_spotify_parser_outside_default_sources(self):
        song = SimpleNamespace(
            source="SpotifyMusicClient",
            work_dir="/tmp/SpotifyMusicClient/Spotify 歌单",
            song_name="Spotify 歌曲",
            singers="测试歌手",
            album="测试专辑",
            ext="mp3",
            duration_s=180,
            duration="03:00",
            file_size_bytes=100,
            bitrate=320,
            samplerate=44100,
            cover_url=None,
            lyric=None,
        )
        selected_sources = []
        with TemporaryDirectory() as directory:
            backend = MusicDlBackend.__new__(MusicDlBackend)
            backend._allowed_sources = ("NeteaseMusicClient", "QQMusicClient")
            backend._output_dir = Path(directory)
            backend._lock = threading.Lock()
            backend._source_locks = {}
            backend._fetch_text = lambda url: (_ for _ in ()).throw(OSError("Spotify unavailable"))
            backend._client = lambda sources: (
                selected_sources.append(sources)
                or SimpleNamespace(parseplaylist=lambda url: [song])
            )

            _, _, candidates = backend.parse_playlist(
                "https://open.spotify.com/playlist/37i9dQZF1E8NWHOpySOxQd"
            )

        self.assertEqual([("SpotifyMusicClient",)], selected_sources)
        self.assertEqual("SpotifyMusicClient", candidates[0].source)

    def test_spotify_playlist_prefers_public_embed_metadata(self):
        entity = {
            "name": "公开 Spotify 歌单",
            "trackList": [
                {
                    "uri": "spotify:track:first",
                    "title": "第一首",
                    "subtitle": "歌手甲",
                    "duration": 185_000,
                },
                {
                    "uri": "spotify:track:second",
                    "title": "第二首",
                    "subtitle": "歌手乙",
                    "duration": 201_000,
                },
            ],
        }
        next_data = {
            "props": {"pageProps": {"state": {"data": {"entity": entity}}}}
        }
        oembed = json.dumps({
            "title": "公开 Spotify 歌单",
            "thumbnail_url": "https://image.example.test/playlist.jpg",
        })
        embed = (
            '<script id="__NEXT_DATA__" type="application/json">'
            + json.dumps(next_data, ensure_ascii=False)
            + "</script>"
        )
        requested_urls = []
        backend = MusicDlBackend.__new__(MusicDlBackend)
        backend._allowed_sources = ("NeteaseMusicClient", "QQMusicClient")
        backend._lock = threading.Lock()
        backend._source_locks = {}
        backend._fetch_text = lambda url: (
            requested_urls.append(url) or (oembed if "/oembed?" in url else embed)
        )
        backend._client = lambda sources: self.fail("不应调用 musicdl Spotify 解析器")

        name, _, candidates = backend.parse_playlist(
            "https://open.spotify.com/playlist/playlist123?si=share-token"
        )

        self.assertEqual("公开 Spotify 歌单", name)
        self.assertEqual(2, len(candidates))
        self.assertEqual("第一首", candidates[0].title)
        self.assertEqual("歌手甲", candidates[0].artist)
        self.assertEqual(185_000, candidates[0].duration_ms)
        self.assertEqual("https://image.example.test/playlist.jpg", candidates[0].artwork_url)
        self.assertEqual(2, len(requested_urls))

    def test_spotify_playlist_item_resolves_from_enabled_sources_when_downloaded(self):
        spotify = BackendCandidate(
            "SpotifyMusicClient", "测试歌曲", "测试歌手", "", "mp3",
            180_000, None, None, None, None, None,
            SpotifyPlaylistItem("spotify:track:test"),
        )
        public = BackendCandidate(
            "NeteaseMusicClient", "测试歌曲", "测试歌手", "", "mp3",
            180_000, None, None, None, None, None,
            PublicPlaylistItem("NeteaseMusicClient", "123"),
        )
        resolved = BackendCandidate(
            "NeteaseMusicClient", "测试歌曲", "测试歌手", "测试专辑", "flac",
            180_000, 1_000, 1_411, 44_100, None, None, SimpleNamespace(),
        )
        queries = []
        with TemporaryDirectory() as directory:
            music_dir = Path(directory).resolve()
            downloaded = music_dir / "download" / "测试歌曲.flac"
            downloaded.parent.mkdir(parents=True)
            downloaded.write_bytes(b"audio")
            backend = MusicDlBackend.__new__(MusicDlBackend)
            backend._allowed_sources = ("NeteaseMusicClient", "QQMusicClient")
            backend._music_dir = music_dir
            backend._lock = threading.Lock()
            backend._source_locks = {}
            backend.search = lambda query, sources: (
                queries.append((query, sources)) or [resolved]
            )
            backend._client = lambda sources: SimpleNamespace(
                download=lambda song_infos: [SimpleNamespace(_save_path=str(downloaded))]
            )

            files = backend.download(spotify)
            public_files = backend.download(public)

        self.assertEqual(["download/测试歌曲.flac"], files)
        self.assertEqual(files, public_files)
        self.assertEqual(
            [
                ("测试歌曲 测试歌手", ("NeteaseMusicClient", "QQMusicClient")),
                ("测试歌曲 测试歌手", ("NeteaseMusicClient", "QQMusicClient")),
            ],
            queries,
        )

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
