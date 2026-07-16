# Sona 刮削与下载适配说明

Sona 将曲库刮削和下载拆成两个边界清晰的能力：Java 服务负责扫描、解析和入库，Python 侧车负责调用 `musicdl` 的多源搜索/下载。
下载完成后服务端自动触发一次扫描，因此新文件会在下一次扫描完成后出现在 App 中。

## 刮削策略

1. 读取音频内嵌标签、内嵌封面、内嵌歌词。
2. 读取同名 `.lrc`，其内容优先于远程歌词。
3. 对缺失的标题/艺人/专辑调用 MusicBrainz；封面从 Cover Art Archive 获取。
4. 对缺失的歌词调用 LRCLIB。
5. 如果基础服务没有唯一高置信度结果，再用侧车返回的多源候选做标题、艺人、专辑、封面和歌词补全。
6. 结果保存到 SQLite 曲库索引和 `/data/artwork`，再次扫描时按文件大小与修改时间跳过未变化文件。

当前默认是“库内刮削”：不会自动重命名或回写原始音频文件，避免误匹配破坏用户文件。下载器本身会按 `musicdl` 的默认行为为新下载文件补齐可用标签和歌词；如需物理回写已有文件，应先备份后再单独启用写标签功能。

## 下载侧车

`downloader/` 是无状态 HTTP sidecar：

- `/health` 不需要令牌，仅供 Docker healthcheck 使用。
- 其它接口必须带 `X-Sona-Token`。
- 搜索结果只返回短期 `candidateId`，真实下载地址和平台对象只保存在进程内缓存中。
- 下载路径固定为服务器挂载音乐目录下的 `/music/download`，并且只接受已支持的音频扩展名；App 仅提交和查看任务，不保存这些音频文件。
- 默认来源为咪咕、网易云、QQ、酷我、千千；`SONA_DOWNLOAD_SOURCES` 可启用已安装 `musicdl` 提供的其它客户端。

## 参考项目与许可

刮削交互和来源适配参考 [music-tag-web](https://github.com/xhongc/music-tag-web)，下载能力通过 [musicdl](https://github.com/CharlesPikachu/musicdl) 运行时依赖接入。Sona 没有复制上述项目的源代码；Java 刮削器使用 JAudioTagger 读取本地标签，并通过公开 HTTP 接口获取补全信息。使用下载来源时仍需遵守各平台条款并仅处理自己有权使用的内容。
