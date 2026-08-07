[CmdletBinding()]
param([switch]$Undo, [switch]$Status)

$ErrorActionPreference = 'Stop'

$AppExe   = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama app.exe'
$Disabled = "$AppExe.disabled"
$Updates  = Join-Path $env:LOCALAPPDATA 'Ollama\updates_v2'

function Show-State {
    $app = Test-Path -LiteralPath $AppExe
    $dis = Test-Path -LiteralPath $Disabled
    if ($dis -and -not $app) { Write-Host 'Auto-update: DISABLED (tray app renamed to .disabled)' -ForegroundColor Green }
    elseif ($app)            { Write-Host 'Auto-update: ENABLED (tray app present)' -ForegroundColor Yellow }
    else                     { Write-Host 'Auto-update: tray app not found at all' -ForegroundColor DarkYellow }
    if (Test-Path -LiteralPath $Updates) {
        $denied = (icacls $Updates 2>&1 | Select-String -SimpleMatch '(DENY)') -ne $null
        Write-Host "Update cache write-deny ACL: $(if ($denied) { 'present' } else { 'absent' })"
    }
}

if ($Status) { Show-State; return }

Get-Process 'ollama*' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

if ($Undo) {
    if (Test-Path -LiteralPath $Disabled) {
        if (Test-Path -LiteralPath $AppExe) { Remove-Item -LiteralPath $Disabled -Force }
        else { Rename-Item -LiteralPath $Disabled -NewName 'ollama app.exe' }
        Write-Host 'Restored the tray app (auto-update re-enabled).'
    }
    if (Test-Path -LiteralPath $Updates) {
        icacls $Updates /remove:d "$env:USERNAME" | Out-Null
        Write-Host 'Removed the write-deny ACL on the update cache.'
    }
    Show-State
    return
}

if (Test-Path -LiteralPath $AppExe) {
    if (Test-Path -LiteralPath $Disabled) { Remove-Item -LiteralPath $Disabled -Force }
    Rename-Item -LiteralPath $AppExe -NewName 'ollama app.exe.disabled'
    Write-Host 'Renamed "ollama app.exe" -> "ollama app.exe.disabled".'
} else {
    Write-Host 'Tray app already disabled or absent.'
}

New-Item -ItemType Directory -Force -Path $Updates | Out-Null
Get-ChildItem -LiteralPath $Updates -Recurse -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
icacls $Updates /deny "$($env:USERNAME):(OI)(CI)(W)" | Out-Null
Write-Host 'Applied write-deny ACL to the update staging directory.'
Write-Host ''
Show-State
