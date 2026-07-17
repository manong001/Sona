#!/usr/bin/env python3
"""抓取公开网易云音乐歌单的曲目元数据。

只读取公开页面中已经返回的歌单信息；不需要 Cookie，也不支持私密歌单。
"""

from __future__ import annotations

import argparse
import html
import json
import re
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import parse_qs, urlparse
from urllib.request import Request, urlopen


class _PlaylistPageParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self._in_song_data = False
        self.song_data = ""
        self.title = ""
        self.cover_url = ""

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        if tag == "textarea" and values.get("id") == "song-list-pre-data":
            self._in_song_data = True
        if tag == "meta" and values.get("name") == "title":
            self.title = values.get("content") or self.title
        if tag == "img" and values.get("class") == "j-img" and not self.cover_url:
            self.cover_url = values.get("data-src") or values.get("src") or ""

    def handle_endtag(self, tag: str) -> None:
        if tag == "textarea":
            self._in_song_data = False

    def handle_data(self, data: str) -> None:
        if self._in_song_data:
            self.song_data += data


def playlist_id(value: str) -> str:
    """Accept a NetEase playlist URL or a numeric playlist id."""
    if value.isdigit():
        return value
    parsed = urlparse(value)
    values = parse_qs(parsed.query)
    identifier = (values.get("id") or [""])[0]
    if parsed.netloc.endswith("music.163.com") and identifier.isdigit():
        return identifier
    raise ValueError("请输入公开网易云歌单链接，或纯数字歌单 ID")


def parse_playlist_page(page: str, identifier: str) -> dict:
    parser = _PlaylistPageParser()
    parser.feed(page)
    if not parser.song_data.strip():
        raise ValueError("页面未包含公开歌单曲目数据，歌单可能不存在、已设为私密或页面结构已变化")
    try:
        songs = json.loads(html.unescape(parser.song_data))
    except json.JSONDecodeError as error:
        raise ValueError("歌单曲目数据格式无效") from error

    tracks = []
    for song in songs:
        artists = song.get("artists") or song.get("ar") or []
        album = song.get("album") or song.get("al") or {}
        tracks.append({
            "id": str(song.get("id", "")),
            "title": song.get("name", ""),
            "artists": [artist.get("name", "") for artist in artists if artist.get("name")],
            "album": album.get("name", ""),
            "durationMs": song.get("duration") or song.get("dt") or 0,
        })
    return {
        "source": "netease",
        "playlistId": identifier,
        "name": re.sub(r"\s*-\s*网易云音乐$", "", parser.title).strip(),
        "artworkUrl": parser.cover_url,
        "tracks": tracks,
    }


def fetch_playlist(identifier: str) -> dict:
    request = Request(
        f"https://music.163.com/playlist?id={identifier}",
        headers={"User-Agent": "Mozilla/5.0 (compatible; SonaPlaylistMetadata/1.0)"},
    )
    with urlopen(request, timeout=15) as response:
        charset = response.headers.get_content_charset() or "utf-8"
        return parse_playlist_page(response.read().decode(charset), identifier)


def main() -> int:
    argument_parser = argparse.ArgumentParser(description="抓取公开网易云歌单元数据")
    argument_parser.add_argument("playlist", help="公开歌单链接或数字 ID")
    argument_parser.add_argument("-o", "--output", type=Path, help="输出 JSON 文件；不传则输出到标准输出")
    arguments = argument_parser.parse_args()
    try:
        data = fetch_playlist(playlist_id(arguments.playlist))
    except (OSError, ValueError) as error:
        print(f"抓取失败：{error}", file=sys.stderr)
        return 1
    output = json.dumps(data, ensure_ascii=False, indent=2) + "\n"
    if arguments.output:
        arguments.output.write_text(output, encoding="utf-8")
    else:
        print(output, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
