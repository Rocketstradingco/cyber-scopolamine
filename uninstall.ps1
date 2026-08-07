[CmdletBinding()]
param([switch]$Force, [switch]$DryRun)

$ErrorActionPreference = 'Stop'

$SLUG    = 'cyber-scopolamine'
$cfgDir  = Join-Path $env:USERPROFILE ".config\$SLUG"
$binDir  = Join-Path $env:USERPROFILE '.local\bin'
$lnkPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Cyber-Scopolamine.lnk'

$e = [char]27
$vt = ($PSVersionTable.PSVersion.Major -ge 7 -or $env:WT_SESSION)
$V = if ($vt) { "$e[38;2;168;85;247m" } else { '' }
$M = if ($vt) { "$e[38;2;110;100;130m" } else { '' }
$L = if ($vt) { "$e[38;2;200;255;107m" } else { '' }
$A = if ($vt) { "$e[38;2;255;138;55m" } else { '' }
$R = if ($vt) { "$e[0m" } else { '' }

$sandbox = $null
$store   = $null
$model   = $null
$envFile = Join-Path $cfgDir 'cs-env.ps1'
if (Test-Path $envFile) {
    . $envFile
    $sandbox = $global:CS_SANDBOX
    $store   = $global:CS_MODEL_STORE
    $model   = $global:CS_MODEL
}

$targets = @()
if (Test-Path $cfgDir)  { $targets += $cfgDir }
if (Test-Path $lnkPath) { $targets += $lnkPath }
$cmds = @(Get-ChildItem "$binDir\$SLUG*" -ErrorAction SilentlyContinue)

Write-Host ''
Write-Host "$V CYBER-SCOPOLAMINE $R$M// uninstall$R"
Write-Host ''

if (-not $targets -and -not $cmds) {
    Write-Host "  Nothing to remove - it does not appear to be installed."
    Write-Host ''
    return
}

Write-Host "  ${A}Will remove:$R"
foreach ($t in $targets) { Write-Host "    $t" }
foreach ($c in $cmds)    { Write-Host "    $($c.FullName)" }
Write-Host ''
Write-Host "  ${L}Will NOT touch:$R"
Write-Host "    Ollama, and every model you have - including any this tool built"
if ($store)   { Write-Host "    model store   $store" }
if ($sandbox) { Write-Host "    your sandbox  $sandbox" }
Write-Host "    your own aider install, if you have one"
Write-Host ''

if ($DryRun) { Write-Host "  ${M}Dry run - nothing was changed.$R"; Write-Host ''; return }

if (-not $Force) {
    Write-Host "  Proceed? [y/N] " -NoNewline
    $a = Read-Host
    if ($a.Trim().ToLower() -notmatch '^y(es)?$') { Write-Host '  Cancelled.'; Write-Host ''; return }
}

Get-Process 'ollama','llama-server' -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -eq 'llama-server' } |
    Stop-Process -Force -ErrorAction SilentlyContinue

$removed = 0
foreach ($c in $cmds) {
    Remove-Item -LiteralPath $c.FullName -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path $c.FullName)) { $removed++ }
}
if (Test-Path $lnkPath) { Remove-Item -LiteralPath $lnkPath -Force -ErrorAction SilentlyContinue }
if (Test-Path $cfgDir)  { Remove-Item -LiteralPath $cfgDir -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ''
Write-Host "  ${L}Removed$R $removed command(s), the config folder, the private aider"
Write-Host "  environment, and the desktop shortcut."
Write-Host ''
Write-Host "  ${M}Left in place, on purpose:$R"
if ($sandbox -and (Test-Path $sandbox)) {
    $n = @(Get-ChildItem $sandbox -Recurse -File -Force -ErrorAction SilentlyContinue).Count
    Write-Host "    $sandbox  ($n files - your work)"
    Write-Host "      remove yourself with:  Remove-Item -Recurse '$sandbox'"
}
if ($model) {
    Write-Host "    the model $model, and every other model you have"
    Write-Host "      remove yourself with:  ollama rm $($model -replace ':latest$','')"
}
Write-Host "    Ollama - uninstall from Windows Settings > Apps if you want it gone"
Write-Host ''
Write-Host "  ${M}Models are never deleted here. Reinstalling reuses them.$R"
Write-Host ''
