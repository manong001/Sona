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
- MP3、M4A/AAC/ALAC、FLAC、WAV、AIFF 扫描与 HTTP Range 播放。
- 本地标签、嵌入封面、嵌入歌词和同名 `.lrc` 优先；MusicBrainz、LRCLIB、Cover Art Archive 保守补全。
- iOS 后台播放、锁屏控制、歌词、离线下载和服务端歌单。
- Spotify 风格的首页、搜索、音乐库、个人抽屉、迷你播放器和全屏播放页。
- App 内触发扫描和查看扫描状态，无服务端管理页面。

界面规范与还原基准见 [`docs/SPOTIFY_UI_DESIGN.md`](docs/SPOTIFY_UI_DESIGN.md)。

## Docker 部署

```bash
cp .env.example .env
# 编辑 .env，至少替换 SONA_ADMIN_PASSWORD
docker compose up -d --build
```

已有部署直接执行上述构建命令即可，服务启动时会自动升级现有 `sona.db`，不需要删除数据库。用户管理入口位于 App 的“设置 → 用户管理”。

默认映射：

- 音乐目录（只读）：`/vol4/1000/media/download/音乐` → `/music`
- 数据目录：`/vol4/1000/docker/sona` → `/data`
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

> 当前服务器使用明文 HTTP，因此登录密码和音频流可能被同网络中的第三方窃听。仅建议在可信网络或 VPN 中使用；后续启用 HTTPS 时应同时设置 `SONA_SECURE_COOKIE=true`。
