@echo off
rem Reapply the RTCO cyberpunk spinner + local model-picker patches to aider.
rem Run after any aider upgrade - the patches edit site-packages directly.
if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
  "%ProgramFiles%\PowerShell\7\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.config\rtco\aider-cyberpunk-waiting-patch\apply.ps1" %*
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\.config\rtco\aider-cyberpunk-waiting-patch\apply.ps1" %*
)
