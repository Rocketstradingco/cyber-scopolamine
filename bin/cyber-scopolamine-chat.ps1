$ErrorActionPreference = 'Stop'

$envFile = Join-Path $env:USERPROFILE '.config\cyber-scopolamine\cs-env.ps1'
if (-not (Test-Path $envFile)) {
    Write-Host "Cyber-Scopolamine is not configured ($envFile missing). Re-run install.ps1." -ForegroundColor Red
    return
}
. $envFile

Set-Location $global:CS_SANDBOX

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

try {
    Invoke-WebRequest 'http://127.0.0.1:11434/api/tags' -TimeoutSec 3 -UseBasicParsing | Out-Null
} catch {
    Write-Host 'Ollama is not responding on 127.0.0.1:11434 - starting it...' -ForegroundColor Yellow
    Start-Process -FilePath $global:CS_OLLAMA_EXE -ArgumentList 'serve' -WindowStyle Hidden
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        try { Invoke-WebRequest 'http://127.0.0.1:11434/api/tags' -TimeoutSec 2 -UseBasicParsing | Out-Null; break } catch { }
    }
}

foreach ($rc in @(
    (Join-Path $env:USERPROFILE '.config\cyber-scopolamine\banner.ps1'),
    (Join-Path $env:USERPROFILE '.config\cyber-scopolamine\prompt.ps1'),
    (Join-Path $env:USERPROFILE '.config\cyber-scopolamine\aider-startup.ps1')
)) {
    if (Test-Path $rc) { . $rc }
}

aider --chat-mode ask @args
