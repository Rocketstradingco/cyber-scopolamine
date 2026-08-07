# Disable Ollama's silent auto-updater on this machine.
#
# Why: on 2026-08-06 a stale deferred update installed 0.23.2, whose image-gen
# (MLX) module is built CUDA-only but initializes unconditionally at process
# start. On this AMD RX 5700 XT that is an instant access violation
# (0xc0000005), which kills *every* ollama subcommand - including `serve` -
# so the whole local agent stack goes down without warning.
#
# Ollama has no supported setting for this (see ollama/ollama issues #3459,
# #4498, #6024, #11804). The tray app "ollama app.exe" IS the updater: it
# spawns the update poller at startup. Disabling it costs only the tray icon;
# `ollama serve` runs the API perfectly well on its own, and that is what
# rtco-sandbox-aider.ps1 starts.
#
# Re-run this after any manual Ollama install - the installer restores the app.
#
# Usage:
#   rtco-ollama-noupdate           # disable auto-update
#   rtco-ollama-noupdate -Undo     # restore stock behaviour
#   rtco-ollama-noupdate -Status   # report current state
[CmdletBinding()]
param(
    [switch]$Undo,
    [switch]$Status
)

$ErrorActionPreference = 'Stop'

$AppExe   = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama app.exe'
$Disabled = "$AppExe.disabled"
$Updates  = Join-Path $env:LOCALAPPDATA 'Ollama\updates_v2'

function Show-Status {
    $appPresent  = Test-Path -LiteralPath $AppExe
    $disPresent  = Test-Path -LiteralPath $Disabled
    if ($disPresent -and -not $appPresent) {
        Write-Host 'Auto-update: DISABLED (tray app renamed to .disabled)' -ForegroundColor Green
    } elseif ($appPresent) {
        Write-Host 'Auto-update: ENABLED (tray app present)' -ForegroundColor Yellow
    } else {
        Write-Host 'Auto-update: tray app not found at all' -ForegroundColor DarkYellow
    }
    if (Test-Path -LiteralPath $Updates) {
        $denied = (icacls $Updates 2>&1 | Select-String -SimpleMatch '(DENY)') -ne $null
        Write-Host "Update cache write-deny ACL: $(if ($denied) { 'present' } else { 'absent' })"
    }
}

if ($Status) { Show-Status; return }

if ($Undo) {
    Get-Process 'ollama*' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    if (Test-Path -LiteralPath $Disabled) {
        if (Test-Path -LiteralPath $AppExe) { Remove-Item -LiteralPath $Disabled -Force }
        else { Rename-Item -LiteralPath $Disabled -NewName 'ollama app.exe' }
        Write-Host 'Restored the tray app (auto-update re-enabled).'
    }
    if (Test-Path -LiteralPath $Updates) {
        icacls $Updates /remove:d "$env:USERNAME" | Out-Null
        Write-Host 'Removed the write-deny ACL on the update cache.'
    }
    Show-Status
    return
}

# --- disable ---
Get-Process 'ollama*' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

if (Test-Path -LiteralPath $AppExe) {
    if (Test-Path -LiteralPath $Disabled) { Remove-Item -LiteralPath $Disabled -Force }
    Rename-Item -LiteralPath $AppExe -NewName 'ollama app.exe.disabled'
    Write-Host 'Renamed "ollama app.exe" -> "ollama app.exe.disabled".'
} else {
    Write-Host 'Tray app already disabled or absent.'
}

# Belt and braces: even if something launches the updater, it cannot stage a
# downloaded installer here.
New-Item -ItemType Directory -Force -Path $Updates | Out-Null
Get-ChildItem -LiteralPath $Updates -Recurse -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
icacls $Updates /deny "$($env:USERNAME):(OI)(CI)(W)" | Out-Null
Write-Host 'Applied write-deny ACL to the update staging directory.'

Write-Host ''
Write-Host 'Start the API with:  ollama serve   (rtco-sandbox-aider does this for you)'
Show-Status
