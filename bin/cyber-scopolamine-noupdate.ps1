[CmdletBinding()]
param([switch]$Undo, [switch]$Status)

$ErrorActionPreference = 'Stop'
$common = Join-Path $PSScriptRoot 'cyber-scopolamine-common.ps1'
if (-not (Test-Path -LiteralPath $common)) { throw "Runtime helper is missing: $common" }
. $common

$statePath = Get-CsInstallStatePath
$state = Read-CsJsonFile -Path $statePath
if (-not $state) { throw "Install state is missing: $statePath. Re-run install.ps1." }

$AppExe   = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama app.exe'
$Disabled = "$AppExe.disabled"
$Updates  = Join-Path $env:LOCALAPPDATA 'Ollama\updates_v2'

function Save-UpdaterState {
    param($Updater)
    $state.updater = $Updater
    Write-CsJsonFile -Path $statePath -Value $state
}

function Stop-OllamaTrayApp {
    $wanted = [IO.Path]::GetFullPath($AppExe)
    Get-CimInstance Win32_Process -Filter "Name='ollama app.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            try { ([IO.Path]::GetFullPath([string]$_.ExecutablePath)).Equals($wanted, [StringComparison]::OrdinalIgnoreCase) }
            catch { $false }
        } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop }
}

function Show-State {
    $owned = [bool]($state.updater -and $state.updater.enabled)
    Write-Host "Auto-update change owned by Cyber-Scopolamine: $(if ($owned) { 'YES' } else { 'NO' })"
    Write-Host "Tray app: $(if (Test-Path -LiteralPath $AppExe) { 'present' } elseif (Test-Path -LiteralPath $Disabled) { 'renamed/disabled' } else { 'not found' })"
    if (Test-Path -LiteralPath $Updates) {
        Write-Host "Update cache: $Updates"
    }
}

if ($Status) { Show-State; return }

if ($Undo) {
    if (-not $state.updater -or -not $state.updater.enabled) {
        Write-Host 'No Cyber-Scopolamine-owned auto-update change to undo.'
        Show-State
        return
    }

    if ($state.updater.originalUpdatesAclSddl -and (Test-Path -LiteralPath $Updates)) {
        $security = New-Object Security.AccessControl.DirectorySecurity
        $security.SetSecurityDescriptorSddlForm([string]$state.updater.originalUpdatesAclSddl)
        Set-Acl -LiteralPath $Updates -AclObject $security
        Write-Host 'Restored the original update-cache ACL.'
    }
    if ($state.updater.trayRenamed -and (Test-Path -LiteralPath $Disabled)) {
        if (Test-Path -LiteralPath $AppExe) {
            throw "Cannot restore the tray app because both paths exist: $AppExe and $Disabled"
        }
        Rename-Item -LiteralPath $Disabled -NewName 'ollama app.exe'
        Write-Host 'Restored the Ollama tray app.'
    }
    if ($state.updater.updatesDirectoryCreated -and (Test-Path -LiteralPath $Updates)) {
        if (@(Get-ChildItem -LiteralPath $Updates -Force -ErrorAction SilentlyContinue).Count -eq 0) {
            Remove-Item -LiteralPath $Updates -Force
        }
    }

    Save-UpdaterState ([ordered]@{
        enabled = $false; trayRenamed = $false; appExe = $AppExe; disabledExe = $Disabled
        updatesPath = $Updates; updatesDirectoryCreated = $false; originalUpdatesAclSddl = $null
    })
    Show-State
    return
}

if ($state.updater -and $state.updater.enabled) {
    Write-Host 'Ollama auto-update is already disabled by Cyber-Scopolamine.'
    Show-State
    return
}

if ((Test-Path -LiteralPath $AppExe) -and (Test-Path -LiteralPath $Disabled)) {
    throw "Refusing to replace either Ollama tray executable because both paths already exist."
}

$createdUpdates = -not (Test-Path -LiteralPath $Updates)
New-Item -ItemType Directory -Force -Path $Updates | Out-Null
$originalSddl = (Get-Acl -LiteralPath $Updates).Sddl
$trayRenamed = $false
try {
    if (Test-Path -LiteralPath $AppExe) {
        Stop-OllamaTrayApp
        Rename-Item -LiteralPath $AppExe -NewName 'ollama app.exe.disabled'
        $trayRenamed = $true
        Write-Host 'Renamed the Ollama tray app to disable its updater.'
    } elseif (Test-Path -LiteralPath $Disabled) {
        throw 'The Ollama tray app was already disabled outside Cyber-Scopolamine; refusing to claim ownership.'
    } else {
        throw "Ollama tray app not found: $AppExe"
    }

    & icacls.exe $Updates /deny "$($env:USERNAME):(OI)(CI)(W)" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls failed with exit code $LASTEXITCODE" }

    Save-UpdaterState ([ordered]@{
        enabled = $true; trayRenamed = $trayRenamed; appExe = $AppExe; disabledExe = $Disabled
        updatesPath = $Updates; updatesDirectoryCreated = $createdUpdates; originalUpdatesAclSddl = $originalSddl
    })
    Write-Host 'Auto-update disabled. The original ACL and rename are recorded for uninstall/undo.'
} catch {
    if ($originalSddl -and (Test-Path -LiteralPath $Updates)) {
        try {
            $security = New-Object Security.AccessControl.DirectorySecurity
            $security.SetSecurityDescriptorSddlForm($originalSddl)
            Set-Acl -LiteralPath $Updates -AclObject $security
        } catch { }
    }
    if ($trayRenamed -and (Test-Path -LiteralPath $Disabled) -and -not (Test-Path -LiteralPath $AppExe)) {
        Rename-Item -LiteralPath $Disabled -NewName 'ollama app.exe' -ErrorAction SilentlyContinue
    }
    throw
}

Show-State
