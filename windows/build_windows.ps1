param(
    [switch]$SkipTests,
    [switch]$NoZip
)

$ErrorActionPreference = "Stop"

function Invoke-DotNet {
    param([Parameter(Mandatory)][string[]]$Arguments)

    & dotnet @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet $($Arguments -join ' ') 执行失败，退出码：$LASTEXITCODE"
    }
}

if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
    throw "此脚本只能在 Windows 10/11 x64 上运行。请使用 GitHub Actions 在云端打包。"
}

if (-not [System.Environment]::Is64BitOperatingSystem) {
    throw "Sona Windows 当前只支持 64 位 Windows。"
}

if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw "未找到 .NET SDK。请先安装 .NET 10 SDK：https://dotnet.microsoft.com/download"
}

$sdkVersion = (& dotnet --version).Trim()
if ($LASTEXITCODE -ne 0 -or [int]($sdkVersion.Split('.')[0]) -lt 10) {
    throw "需要 .NET 10 SDK，当前版本：$sdkVersion"
}

$solutionPath = Join-Path $PSScriptRoot "Sona.Windows.slnx"
$projectPath = Join-Path $PSScriptRoot "Sona.Windows\Sona.Windows.csproj"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$distRoot = Join-Path $PSScriptRoot "dist"
$outputDirectory = Join-Path $distRoot "Sona-win-x64-$timestamp"
$archivePath = "$outputDirectory.zip"

New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null

Write-Host ""
Write-Host "Sona Windows 打包" -ForegroundColor Green
Write-Host "SDK：$sdkVersion"
Write-Host "输出：$outputDirectory"
Write-Host ""

Write-Host "[1/4] 恢复项目依赖..." -ForegroundColor Cyan
Invoke-DotNet @("restore", $solutionPath)

if ($SkipTests) {
    Write-Host "[2/4] 已跳过测试。" -ForegroundColor Yellow
} else {
    Write-Host "[2/4] 运行测试..." -ForegroundColor Cyan
    Invoke-DotNet @("test", $solutionPath, "--no-restore", "--configuration", "Release")
}

Write-Host "[3/4] 恢复 Windows x64 运行时..." -ForegroundColor Cyan
Invoke-DotNet @("restore", $projectPath, "--runtime", "win-x64")

Write-Host "[4/4] 发布自包含客户端..." -ForegroundColor Cyan
Invoke-DotNet @(
    "publish", $projectPath,
    "--configuration", "Release",
    "--runtime", "win-x64",
    "--self-contained", "true",
    "--no-restore",
    "-p:PublishSingleFile=false",
    "--output", $outputDirectory
)

$exePath = Join-Path $outputDirectory "Sona.exe"
if (-not (Test-Path $exePath -PathType Leaf)) {
    throw "打包失败：未生成 $exePath"
}

$libVlc = Get-ChildItem $outputDirectory -Recurse -Filter "libvlc.dll" -File | Select-Object -First 1
if (-not $libVlc) {
    throw "打包失败：产物中缺少 libvlc.dll"
}

if (-not $NoZip) {
    Write-Host "正在生成分发压缩包..." -ForegroundColor Cyan
    Compress-Archive -Path (Join-Path $outputDirectory "*") -DestinationPath $archivePath -CompressionLevel Optimal
}

$sizeMB = [Math]::Round((Get-ChildItem $outputDirectory -Recurse -File | Measure-Object Length -Sum).Sum / 1MB, 1)

Write-Host ""
Write-Host "打包成功！" -ForegroundColor Green
Write-Host "EXE：$exePath"
Write-Host "目录大小：$sizeMB MB"
if (-not $NoZip) {
    Write-Host "ZIP：$archivePath"
}
Write-Host "请将整个输出目录或 ZIP 发到目标 Windows 电脑，不要只复制 Sona.exe。" -ForegroundColor Yellow
