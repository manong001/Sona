@echo off
setlocal

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_windows.ps1" %*
set "SONA_BUILD_EXIT=%ERRORLEVEL%"

if not "%SONA_BUILD_EXIT%"=="0" (
  echo.
  echo Sona Windows packaging failed with exit code %SONA_BUILD_EXIT%.
)

if "%~1"=="" pause
exit /b %SONA_BUILD_EXIT%
