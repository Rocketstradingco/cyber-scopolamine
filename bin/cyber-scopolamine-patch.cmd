@echo off
if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
  "%ProgramFiles%\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.config\cyber-scopolamine\patches\apply.ps1" %*
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.config\cyber-scopolamine\patches\apply.ps1" %*
)
