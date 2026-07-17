import unittest

from netease_playlist_scraper import parse_playlist_page, playlist_id


class NetEasePlaylistScraperTest(unittest.TestCase):
    def test_parses_public_playlist_page_data(self):
        page = '''<meta name="title" content="测试歌单 - 网易云音乐">
        <textarea id="song-list-pre-data">[{"id":1,"name":"测试歌","artists":[{"name":"歌手"}],"album":{"name":"专辑"},"duration":180000}]</textarea>'''

        playlist = parse_playlist_page(page, "123")

        self.assertEqual("测试歌单", playlist["name"])
        self.assertEqual("测试歌", playlist["tracks"][0]["title"])
        self.assertEqual(["歌手"], playlist["tracks"][0]["artists"])

    def test_accepts_url_or_numeric_id(self):
        self.assertEqual("123", playlist_id("123"))
        self.assertEqual("123", playlist_id("https://music.163.com/playlist?id=123"))


if __name__ == "__main__":
    unittest.main()
