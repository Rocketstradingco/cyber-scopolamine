[CmdletBinding()]
param([switch]$Force, [switch]$DryRun)

$ErrorActionPreference = 'Stop'
$SLUG = 'cyber-scopolamine'
$cfgDir = Join-Path $env:USERPROFILE ".config\$SLUG"
$binDir = Join-Path $env:USERPROFILE '.local\bin'
$lnkPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Cyber-Scopolamine.lnk'
$common = Join-Path $PSScriptRoot 'cyber-scopolamine-common.ps1'
if (-not (Test-Path -LiteralPath $common)) { throw "Runtime helper is missing: $common" }
. $common

$config = $null
$state = $null
try { $config = Read-CsJsonFile -Path (Join-Path $cfgDir 'config.json') } catch { Write-Warning $_.Exception.Message }
try { $state = Read-CsJsonFile -Path (Join-Path $cfgDir 'install-state.json') } catch { Write-Warning $_.Exception.Message }
$sandbox = if ($config) { [string]$config.sandbox } else { $null }
$store = if ($config) { [string]$config.modelStore } else { $null }
$model = if ($config) { [string]$config.model } else { $null }

$cmds = @(Get-ChildItem -Path (Join-Path $binDir "$SLUG*") -File -ErrorAction SilentlyContinue)
$scop = Join-Path $binDir 'scop.cmd'
if (Test-Path -LiteralPath $scop) { $cmds += Get-Item -LiteralPath $scop }
$targets = @()
if (Test-Path -LiteralPath $cfgDir) { $targets += $cfgDir }
if (Test-Path -LiteralPath $lnkPath) { $targets += $lnkPath }

Write-Host ''
Write-Host ' CYBER-SCOPOLAMINE // uninstall'
Write-Host ''
if (-not $targets -and -not $cmds) { Write-Host '  Nothing to remove.'; return }

Write-Host '  Will remove:' -ForegroundColor Yellow
$targets | ForEach-Object { Write-Host "    $_" }
$cmds | ForEach-Object { Write-Host "    $($_.FullName)" }
if ($state -and $state.updater -and $state.updater.enabled) {
    Write-Host '    Cyber-Scopolamine-owned Ollama auto-update changes (restored first)'
}
Write-Host ''
Write-Host '  Will preserve:' -ForegroundColor Green
if ($sandbox) { Write-Host "    workspace: $sandbox" }
if ($store) { Write-Host "    model store: $store" }
Write-Host '    Ollama and models'
Write-Host ''

if ($DryRun) { Write-Host '  Dry run - nothing changed.'; return }
if (-not $Force) {
    Write-Host '  Proceed? [y/N] ' -NoNewline
    $answer = Read-Host
    if ($answer.Trim().ToLower() -notmatch '^y(es)?$') { Write-Host '  Cancelled.'; return }
}

if ($state -and $state.updater -and $state.updater.enabled) {
    & (Join-Path $PSScriptRoot 'cyber-scopolamine-noupdate.ps1') -Undo
    if ($LASTEXITCODE -ne 0) { throw "Could not restore Ollama auto-update state (exit code $LASTEXITCODE)." }
}

if ($config) {
    $global:CS_OLLAMA_EXE = [string]$config.ollamaExe
    $processState = if ($state -and $state.ollamaProcessState) { [string]$state.ollamaProcessState } else { Join-Path $cfgDir 'ollama-process.json' }
    Stop-CsOwnedOllama -ProcessStatePath $processState -ExpectedExe $global:CS_OLLAMA_EXE | Out-Null
}

foreach ($command in $cmds) { Remove-Item -LiteralPath $command.FullName -Force }
if (Test-Path -LiteralPath $lnkPath) { Remove-Item -LiteralPath $lnkPath -Force }

if ($state -and $state.pathAdded) {
    $userPath = [Environment]::GetEnvironmentVariable('PATH','User')
    $kept = @($userPath -split [IO.Path]::PathSeparator | Where-Object {
        if (-not $_) { return $false }
        try { -not ([IO.Path]::GetFullPath($_).TrimEnd('\').Equals([IO.Path]::GetFullPath($binDir).TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) }
        catch { $true }
    })
    [Environment]::SetEnvironmentVariable('PATH', ($kept -join [IO.Path]::PathSeparator), 'User')
}

if (Test-Path -LiteralPath $cfgDir) { Remove-Item -LiteralPath $cfgDir -Recurse -Force }

Write-Host ''
Write-Host "  Removed $($cmds.Count) command file(s), configuration, private aider, and shortcut." -ForegroundColor Green
if ($sandbox -and (Test-Path -LiteralPath $sandbox)) { Write-Host "  Preserved workspace: $sandbox" }
if ($model) { Write-Host "  Preserved model: $model" }
Write-Host ''
