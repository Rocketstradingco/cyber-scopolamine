@echo off
title Cyber-Scopolamine installer
cd /d "%~dp0"

if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
  "%ProgramFiles%\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
)

set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" (
  echo Installer exited with code %RC%.
  echo.
)
echo Press any key to close this window.
pause >nul
