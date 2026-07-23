# musicdl `SpotifyMusicClient` 研究

## 结论

- `musicdl` 当前最新发布版是 `2.13.2`，PyPI 页面标注发布时间为 `2026-07-20`。`2.13.1` 的发布时间是 `2026-07-08`。
- 我对官方 PyPI 发布包 `2.13.1`、`2.13.2`，以及 GitHub `master` 分支中的 `musicdl/modules/sources/spotify.py` 和 `musicdl/modules/utils/spotifyutils.py` 做了对比；这两份 Spotify 相关源码在三个版本之间没有差异。
- 因此，`2.13.2` 和 `master` 都没有修复 `SpotifyMusicClient` 里 `spowload` 那段轮询，也没有给它增加可靠的总超时、最大重试次数或截止时间。`2.13.1` 也同样没有。
- 代码里已经存在的是“单次请求级”超时，例如 `SpotubeSecureClient.fetchserverpublickey()` 的 `timeout=60`、`securepost()` 的 `timeout=90`，以及若干第三方 API 调用的 `timeout=10/20/30`。这些超时不约束 `spowload` 的状态轮询。

## 版本对照

| 版本 | 来源 | 结论 |
| --- | --- | --- |
| `2.13.1` | [PyPI](https://pypi.org/project/musicdl/2.13.1/) | `SpotifyMusicClient` 相关源码与 `2.13.2` / `master` 一致 |
| `2.13.2` | [PyPI 最新发布版](https://pypi.org/project/musicdl/2.13.2/) | 最新发布版；`SpotifyMusicClient` 相关源码未增加新的轮询或总超时 |
| `master` | [GitHub 源码](https://github.com/CharlesPikachu/musicdl/blob/master/musicdl/modules/sources/spotify.py) / [spotifyutils.py](https://github.com/CharlesPikachu/musicdl/blob/master/musicdl/modules/utils/spotifyutils.py) | 与 `2.13.2` 的这两个文件一致 |

## 搜索行为

- `SpotifyMusicClient._constructsearchurls()` 只是按页构造搜索请求，然后调用 `SpotifyMusicClientSearchUtils.searchbykeyword()`。
- `searchbykeyword()` 最终请求 Spotify 的 Pathfinder GraphQL 接口，属于一次请求-一次返回的元数据查询，不会进入第三方音频转换轮询。
- 相关源码：
  - [`spotify.py` 的 `_constructsearchurls()`](https://github.com/CharlesPikachu/musicdl/blob/master/musicdl/modules/sources/spotify.py#L37-L47)
  - [`spotifyutils.py` 的 `query()` / `searchbykeyword()`](https://github.com/CharlesPikachu/musicdl/blob/master/musicdl/modules/utils/spotifyutils.py#L161-L178)

## 下载行为

- `SpotifyMusicClient._parsewiththirdpartapis()` 会按顺序尝试多个第三方解析器，`spowload` 是其中一个下载路径。
- 真正的轮询发生在 `_parsewithspowloadapi()`：它先 `POST /convert` 拿任务 ID，然后每 2 秒请求一次 `https://spowload.cc/tasks/{task_id}`，直到拿到 `download_url` 或返回 `failed`。
- 这段循环没有上限次数，也没有整体截止时间；如果服务长期保持“未完成”状态，就会一直轮询。
- 相关源码：
  - [`spotify.py` 的 `_parsewithspowloadapi()`](https://github.com/CharlesPikachu/musicdl/blob/master/musicdl/modules/sources/spotify.py#L194-L223)
  - [`spotify.py` 的 `_parsewiththirdpartapis()`](https://github.com/CharlesPikachu/musicdl/blob/master/musicdl/modules/sources/spotify.py#L224-L230)

## 超时与轮询

- `SpotifyMusicClient` 自身没有给 `spowload` 轮询包装一个“总超时”。
- `spotifyutils.py` 中 Spotube 下载回退路径的超时只覆盖单次请求，例如 `fetchserverpublickey()` 的 `timeout=60` 和 `securepost()` 的 `timeout=90`。
- `SpotifyMusicClientSearchUtils.getdownloadflagfromspotify()` 会遍历候选视频 ID 并发起多次请求，但它不是轮询循环；它依赖底层请求超时和返回结果来结束。
- 相关源码：
  - [`spotifyutils.py` 的 `fetchserverpublickey()`](https://github.com/CharlesPikachu/musicdl/blob/master/musicdl/modules/utils/spotifyutils.py#L297-L304)
  - [`spotifyutils.py` 的 `securepost()`](https://github.com/CharlesPikachu/musicdl/blob/master/musicdl/modules/utils/spotifyutils.py#L322-L335)
  - [`spotifyutils.py` 的 `getdownloadflagfromspotify()`](https://github.com/CharlesPikachu/musicdl/blob/master/musicdl/modules/utils/spotifyutils.py#L397-L405)

## 官方发布说明

- `2.13.2` 的 PyPI release note 只写了新增若干第三方平台支持、维护多家 API、以及修正 playlist parsing 的行为；没有看到 Spotify 客户端的专门修复说明。
- `2.13.1` 的 release note 主要是进度展示、下线失效客户端、优化第三方 API 和 Soda Music cookies 支持，也没有提到 Spotify 的轮询或超时修复。
- 相关页面：
  - [PyPI `musicdl 2.13.2`](https://pypi.org/project/musicdl/2.13.2/)
  - [PyPI `musicdl 2.13.1`](https://pypi.org/project/musicdl/2.13.1/)

## 可复用结论

- 如果 Sona 现在依赖 `musicdl 2.13.1` 来处理 Spotify，升级到 `2.13.2` 或跟随 `master`，都不能指望解决 `spowload` 那条无限轮询问题。
- 要解决这个问题，必须在 `SpotifyMusicClient._parsewithspowloadapi()` 的轮询循环里显式加入总超时、最大轮数，或外部取消机制。

## Sona 的处理

- Spotify 搜索只调用元数据接口，不在搜索阶段解析音频。
- Spotify 下载解析运行在独立进程中，整体最多等待 30 秒；超时后先终止进程，必要时强制回收。
- Spotify 超时或解析失败后，使用同一首歌的标题、艺人和时长在其他已启用音源中匹配并继续下载。

## 说明

- 本文只使用官方 PyPI 页面和 GitHub 源码页面。
- 结论基于 `2026-07-23` 检查时的 upstream 状态；后续 upstream 变更可能改变上述结论。
