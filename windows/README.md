# Sona Windows

Sona Windows 使用 Avalonia 与 C# 实现，复用现有 Sona 服务端 API。当前首版覆盖：

- Cookie 会话登录与服务器地址配置
- Spotify 风格三栏桌面布局
- 曲库加载、搜索与刷新
- 播放队列、上一首、播放/暂停、下一首
- 通过 LibVLC 播放已登录的 HTTP 音频流

## 开发验证

```bash
cd windows
dotnet restore Sona.Windows.slnx
dotnet test Sona.Windows.slnx
dotnet run --project Sona.Windows/Sona.Windows.csproj
```

在 macOS 上可验证 UI、API 与构建；音频播放只在 Windows 10/11 上启用。

## 发布 Windows x64

推荐使用仓库中的 GitHub Actions 工作流 `Windows client` 构建。它在 Windows 云机器上运行测试、
生成自包含客户端并上传 `Sona-Windows-x64` 构建产物，目标电脑无需安装 .NET。

也可以在 Windows 开发机本地执行：

双击：

```text
build_windows.bat
```

或在 PowerShell 中执行：

```powershell
./build_windows.ps1
```

脚本默认运行测试，生成自包含目录与 ZIP。可选参数：

```powershell
./build_windows.ps1 -SkipTests   # 跳过测试
./build_windows.ps1 -NoZip       # 不生成 ZIP
```

每次产物写入新的 `windows/dist/Sona-win-x64-时间戳/`，不会删除或覆盖旧版本。

等价的手动命令：

```bash
cd windows
dotnet publish Sona.Windows/Sona.Windows.csproj \
  -c Release \
  -r win-x64 \
  --self-contained true \
  -p:PublishSingleFile=false \
  -o build/win-x64
```

运行 `build/win-x64/Sona.exe`。LibVLC 包含原生 DLL 与插件目录，因此首版不能合并成单文件。
