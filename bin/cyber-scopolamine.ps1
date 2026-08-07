$ErrorActionPreference = 'Stop'

$envFile = Join-Path $env:USERPROFILE '.config\cyber-scopolamine\cs-env.ps1'
if (-not (Test-Path $envFile)) {
    Write-Host "Cyber-Scopolamine is not configured ($envFile missing). Re-run install.ps1." -ForegroundColor Red
    return
}
. $envFile

$Sandbox = $global:CS_SANDBOX
$Archive = Join-Path $Sandbox '.aider-history-archive'
$Hist    = Join-Path $Sandbox '.aider.chat.history.md'

if (-not (Test-Path $Sandbox)) {
    Write-Host "Sandbox $Sandbox is missing - creating it." -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $Sandbox | Out-Null
}

Set-Location $Sandbox
New-Item -ItemType Directory -Force -Path $Archive | Out-Null

if ((Test-Path $Hist) -and (Get-Item $Hist).Length -gt 0) {
    Move-Item -LiteralPath $Hist -Destination (Join-Path $Archive ((Get-Date -Format 'yyyyMMdd-HHmmss') + '.md'))
}

$env:OLLAMA_MODELS   = $global:CS_MODEL_STORE
$env:OLLAMA_API_BASE = 'http://127.0.0.1:11434'

if (-not $env:OLLAMA_FLASH_ATTENTION) { $env:OLLAMA_FLASH_ATTENTION = '1' }

$orphans = Get-CimInstance Win32_Process -Filter "Name='llama-server.exe'" -ErrorAction SilentlyContinue |
    Where-Object { -not (Get-Process -Id $_.ParentProcessId -ErrorAction SilentlyContinue) }
if ($orphans) {
    Write-Host "Reaping $(@($orphans).Count) orphaned model runner(s) holding VRAM..." -ForegroundColor Yellow
    $orphans | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
}

function Test-CsModelVisible {
    try {
        $tags = Invoke-RestMethod 'http://127.0.0.1:11434/api/tags' -TimeoutSec 4
        return [bool]($tags.models | Where-Object { $_.name -eq $global:CS_MODEL })
    } catch { return $false }
}

function Start-CsOllama {
    Start-Process -FilePath $global:CS_OLLAMA_EXE -ArgumentList 'serve' -WindowStyle Hidden
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        try { Invoke-WebRequest 'http://127.0.0.1:11434/api/tags' -TimeoutSec 2 -UseBasicParsing | Out-Null; return $true } catch { }
    }
    return $false
}

$serverUp = $false
try { Invoke-WebRequest 'http://127.0.0.1:11434/api/tags' -TimeoutSec 3 -UseBasicParsing | Out-Null; $serverUp = $true } catch { }
if (-not $serverUp) {
    Write-Host 'Ollama is not responding on 127.0.0.1:11434 - starting it...' -ForegroundColor Yellow
    $serverUp = Start-CsOllama
}

if ($serverUp -and -not (Test-CsModelVisible)) {
    Write-Host "Ollama is running against a different model store - restarting it..." -ForegroundColor Yellow
    Get-Process 'ollama','llama-server' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    $serverUp = Start-CsOllama
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
    return
}

foreach ($rc in @(
    (Join-Path $env:USERPROFILE '.config\cyber-scopolamine\banner.ps1'),
    (Join-Path $env:USERPROFILE '.config\cyber-scopolamine\prompt.ps1'),
    (Join-Path $env:USERPROFILE '.config\cyber-scopolamine\aider-startup.ps1')
)) {
    if (Test-Path $rc) { . $rc }
}

$introMarker = Join-Path $env:USERPROFILE '.config\cyber-scopolamine\.intro-shown'
$introScript = Join-Path $env:USERPROFILE '.config\cyber-scopolamine\intro.ps1'
if ((-not (Test-Path $introMarker)) -and (Test-Path $introScript)) {
    . $introScript
    try { Show-CsIntro } catch { }
    New-Item -ItemType File -Path $introMarker -Force | Out-Null
}

aider @args
