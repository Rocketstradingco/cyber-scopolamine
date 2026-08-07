# Launched by the RTCO Local Agent desktop icon. Drops into the isolated
# sandbox, archives the previous session's chat history (so nothing is lost
# but the model doesn't silently carry context between sessions), runs the
# RTCO shell setup so the banner and prompt are live, launches aider, and
# leaves you in an ordinary shell there afterwards instead of closing the
# window.
#
# Old conversations: browse/reload with `rtco-aider-history`.
$ErrorActionPreference = 'Stop'

# Machine-specific paths live here, written by the installer.
$envFile = Join-Path $env:USERPROFILE '.config\rtco\rtco-env.ps1'
if (-not (Test-Path $envFile)) {
    Write-Host "RTCO is not configured ($envFile is missing). Re-run install.ps1." -ForegroundColor Red
    return
}
. $envFile

$Sandbox = $global:RTCO_SANDBOX
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

$env:OLLAMA_MODELS   = $global:RTCO_MODEL_STORE
$env:OLLAMA_API_BASE = 'http://127.0.0.1:11434'
# Measured ~+9% generation speed on AMD/Vulkan; harmless elsewhere.
if (-not $env:OLLAMA_FLASH_ATTENTION) { $env:OLLAMA_FLASH_ATTENTION = '1' }

# Reap orphaned model runners before anything else. Ollama runs each model in
# a child `llama-server.exe`, and those outlive the parent if ollama is killed
# or crashes - while still holding their full VRAM allocation. A stale pair can
# leave too little VRAM for the next model, which then spills to system RAM
# over PCIe and collapses generation speed (measured: 33 -> 6 tok/s). Nothing
# reports this as an error; `ollama ps` still claims "100% GPU".
$orphans = Get-CimInstance Win32_Process -Filter "Name='llama-server.exe'" -ErrorAction SilentlyContinue |
    Where-Object { -not (Get-Process -Id $_.ParentProcessId -ErrorAction SilentlyContinue) }
if ($orphans) {
    Write-Host "Reaping $(@($orphans).Count) orphaned model runner(s) holding VRAM..." -ForegroundColor Yellow
    $orphans | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
}

# Ollama must be up or aider fails with a confusing connection error. Start
# `ollama serve` rather than the tray app: the tray app is also the
# auto-updater, and an unattended update once installed a build that crashes
# at startup on AMD cards.
try {
    Invoke-WebRequest 'http://127.0.0.1:11434/api/tags' -TimeoutSec 3 -UseBasicParsing | Out-Null
} catch {
    Write-Host 'Ollama is not responding on 127.0.0.1:11434 - starting it...' -ForegroundColor Yellow
    Start-Process -FilePath $global:RTCO_OLLAMA_EXE -ArgumentList 'serve' -WindowStyle Hidden
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        try { Invoke-WebRequest 'http://127.0.0.1:11434/api/tags' -TimeoutSec 2 -UseBasicParsing | Out-Null; break } catch { }
    }
}

# Load the RTCO shell setup so the prompt, banner, rtco-status and the aider
# wrapper are all live in the shell you are left in afterwards.
foreach ($rc in @(
    (Join-Path $env:USERPROFILE '.config\rtco\prompt.ps1'),
    (Join-Path $env:USERPROFILE '.config\rtco\aider-startup.ps1')
)) {
    if (Test-Path $rc) { . $rc }
}

# `aider` here is the wrapper function from aider-startup.ps1, not the exe.
aider @args
