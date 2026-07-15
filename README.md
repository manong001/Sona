# Sona

Sona 是一个面向自建曲库的 SwiftUI 原生音乐播放器。

项目采用单仓结构：

- `server/`：Spring Boot 曲库服务，负责扫描本地音乐、登录、元数据和 HTTP Range 播放。
- `ios/`：iOS 17+ SwiftUI 客户端。
- `docs/openapi.yaml`：客户端与服务端共享的 API 契约。

## 已实现

- 管理员创建用户、停用/删除账号和重置密码，服务端保存密码哈希和不透明会话令牌。
- 管理员与普通用户权限隔离；歌单、收藏和播放历史按用户保存在服务端。
- SQLite 曲库，游标分页和歌曲/艺人/专辑搜索。
- MP3、M4A/AAC/ALAC、FLAC、WAV、AIFF、OGG/Opus、APE/WavPack/TTA 扫描与 HTTP Range 播放。
- 本地标签、嵌入封面、嵌入歌词和同名 `.lrc` 优先；MusicBrainz、LRCLIB、Cover Art Archive 保守补全。
- 下载侧车集成 `musicdl` 多源搜索/下载；下载完成后自动触发曲库重新扫描并补全标签、歌词和封面。
- iOS 后台播放、锁屏控制、歌词、离线下载和服务端歌单。
- Spotify 风格的首页、搜索、音乐库、个人抽屉、迷你播放器和全屏播放页。
- App 内触发扫描和查看扫描状态，无服务端管理页面。
- 管理员在 App 内批量上传歌曲并将待入库歌曲划入正常池或发现池；普通用户删除仅进入个人垃圾桶。
- 发现池歌曲最近 10 次有效播放的平均完播率高于 80% 时，自动转入正常歌曲池。
- 儿童模式仅播放管理员标记的儿童歌曲，并提供两套儿童主题。
- 首页提供每日个性推荐、按曲风推荐，以及含播放次数的总榜、韩榜、国榜、美榜和日榜。
- 随机列表按用户维护独立覆盖轮次：未抓取歌曲持续提高优先级，同时保留完播率权重，保证正常歌曲池最终全部出现。

界面规范与还原基准见 [`docs/SPOTIFY_UI_DESIGN.md`](docs/SPOTIFY_UI_DESIGN.md)。
刮削与下载适配边界见 [`docs/METADATA_AND_DOWNLOAD.md`](docs/METADATA_AND_DOWNLOAD.md)。

## Docker 部署

```bash
cp .env.example .env
# 编辑 .env，至少替换 SONA_ADMIN_PASSWORD
docker compose up -d --build
```

已有部署直接执行上述构建命令即可，服务启动时会自动升级现有 `sona.db`，不需要删除数据库。用户管理入口位于 App 的“设置 → 用户管理”。

管理员可在 App 的“设置 → 多源音乐下载”中搜索并加入下载队列。下载器只在 Docker 内网监听
`6700`，服务端通过 `SONA_SIDECAR_TOKEN` 鉴权；不要把该端口映射到公网。支持的默认来源为咪咕、网易云、QQ、酷我和千千，
也可以在 `.env` 的 `SONA_DOWNLOAD_SOURCES` 中按 `musicdl` 的客户端名称替换来源。下载文件写入音乐目录下的 `Downloads/`，
随后由服务端自动扫描入库。

默认映射：

- 音乐目录（服务端读写）：`/vol4/1000/media/download/音乐` → `/music`
- 数据目录：`/vol1/1000/docker/Sona/data` → `/data`
- 服务端口：`6699`

如果 NAS 数据目录不是当前用户可写，请先由管理员创建目录并赋予 Docker 运行用户写权限。服务健康检查：

```bash
curl http://127.0.0.1:6699/api/v1/health
```

## 本地后端

```bash
cd server
SONA_MUSIC_DIR=/path/to/music \
SONA_DATA_DIR=./data \
SONA_ADMIN_PASSWORD=change-me \
mvn spring-boot:run
```

## iOS

用 Xcode 打开 `ios/Sona.xcodeproj`，选择开发团队后运行。Bundle ID 为 `cc.eu.sosee.sona`，最低 iOS 17，默认服务器为 `http://sosee.eu.cc:6699`，也可在 App 设置中修改。

需要生成未签名设备 IPA 时，在 macOS/Xcode 环境执行：

```bash
./ios/build_unsigned_ipa.sh
```

脚本会在 `ios/build/Sona-unsigned.ipa` 生成包含完整 `Payload/Sona.app`、Info.plist 和 AppIcon 的 arm64 包。该包按设计不含签名和描述文件，安装前请用自己的证书与 provisioning profile 重签；也可将输出路径作为第一个参数传入。

> 当前服务器使用明文 HTTP，因此登录密码和音频流可能被同网络中的第三方窃听。仅建议在可信网络或 VPN 中使用；后续启用 HTTPS 时应同时设置 `SONA_SECURE_COOKIE=true`。
