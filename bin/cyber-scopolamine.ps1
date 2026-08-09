$ErrorActionPreference = 'Stop'

$common = Join-Path $PSScriptRoot 'cyber-scopolamine-common.ps1'
if (-not (Test-Path -LiteralPath $common)) { throw "Runtime helper is missing: $common. Re-run install.ps1." }
. $common
try { Import-CsConfig | Out-Null }
catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 2 }

$Sandbox = $global:CS_SANDBOX
$Archive = Join-Path $Sandbox '.aider-history-archive'
$Hist    = Join-Path $Sandbox '.aider.chat.history.md'
$RestoreMarker = Join-Path $Archive '.restore-pending'

if (-not (Test-Path $Sandbox)) {
    Write-Host "Sandbox $Sandbox is missing - creating it." -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $Sandbox | Out-Null
}

Set-Location $Sandbox
New-Item -ItemType Directory -Force -Path $Archive | Out-Null

$restorePending = Test-Path -LiteralPath $RestoreMarker
if (-not $restorePending -and (Test-Path $Hist) -and (Get-Item $Hist).Length -gt 0) {
    $archiveName = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8) + '.md'
    Move-Item -LiteralPath $Hist -Destination (Join-Path $Archive $archiveName)
}

$env:OLLAMA_MODELS   = $global:CS_MODEL_STORE
$env:OLLAMA_HOST     = $global:CS_OLLAMA_HOST
$env:OLLAMA_API_BASE = $global:CS_OLLAMA_ENDPOINT

if (-not $env:OLLAMA_FLASH_ATTENTION) { $env:OLLAMA_FLASH_ATTENTION = '1' }

try {
    Assert-CsDedicatedEndpointAvailable
    if (-not (Test-CsEndpoint)) {
        Write-Host "Starting Cyber-Scopolamine's dedicated Ollama server at $($global:CS_OLLAMA_ENDPOINT)..." -ForegroundColor Yellow
        Start-CsOwnedOllama | Out-Null
    }
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 3
}

if (-not (Test-CsModelVisible)) {
    Write-Host ''
    Write-Host "  Model '$($global:CS_MODEL)' was not found." -ForegroundColor Red
    Write-Host "  Store: $($global:CS_MODEL_STORE)" -ForegroundColor Red
    Write-Host ''
    Write-Host '  Rebuild it with:' -ForegroundColor Yellow
    Write-Host "    ollama create $($global:CS_MODEL -replace ':latest$','') -f <Modelfile>" -ForegroundColor Yellow
    Write-Host '  or re-run install.ps1, which will pull and build it for you.'
    Write-Host ''
    exit 4
}

foreach ($rc in @(
    (Join-Path $env:USERPROFILE '.config\cyber-scopolamine\banner.ps1'),
    (Join-Path $env:USERPROFILE '.config\cyber-scopolamine\prompt.ps1'),
    (Join-Path $env:USERPROFILE '.config\cyber-scopolamine\aider-startup.ps1')
)) {
    if (Test-Path $rc) { . $rc }
}

if ($restorePending) { Remove-Item -LiteralPath $RestoreMarker -Force -ErrorAction SilentlyContinue }

$introMarker = Join-Path $env:USERPROFILE '.config\cyber-scopolamine\.intro-shown'
$introScript = Join-Path $env:USERPROFILE '.config\cyber-scopolamine\intro.ps1'
if ((-not (Test-Path $introMarker)) -and (Test-Path $introScript)) {
    . $introScript
    try { Show-CsIntro } catch { }
    New-Item -ItemType File -Path $introMarker -Force | Out-Null
}

aider @args
