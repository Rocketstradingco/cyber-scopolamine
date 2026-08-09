param([string]$Model)

$ErrorActionPreference = 'Stop'

$cfg = Join-Path $env:USERPROFILE '.config\cyber-scopolamine'
$envFile = Join-Path $cfg 'cs-env.ps1'
if (-not (Test-Path $envFile)) {
    Write-Host "Cyber-Scopolamine is not configured ($envFile missing). Re-run install.ps1." -ForegroundColor Red
    return
}
. $envFile
$banner = Join-Path $cfg 'banner.ps1'
if (Test-Path -LiteralPath $banner) { . $banner }

$c = if (Get-Command Get-CsPalette -ErrorAction SilentlyContinue) { Get-CsPalette } else {
    @{ Reset=''; Bold=''; Violet=''; Cyan=''; Lime=''; White=''; Muted=''; Amber=''; Red=''; Orange='' }
}
if (-not $Model) { $Model = $global:CS_MODEL }
$api = 'http://127.0.0.1:11434'

$env:OLLAMA_MODELS = $global:CS_MODEL_STORE
if (-not $env:OLLAMA_FLASH_ATTENTION) { $env:OLLAMA_FLASH_ATTENTION = '1' }

$orphans = Get-CimInstance Win32_Process -Filter "Name='llama-server.exe'" -ErrorAction SilentlyContinue |
    Where-Object { -not (Get-Process -Id $_.ParentProcessId -ErrorAction SilentlyContinue) }
if ($orphans) {
    Write-Host "Reaping $(@($orphans).Count) orphaned model runner(s) holding VRAM..." -ForegroundColor Yellow
    $orphans | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 2
}

function Test-CsUp {
    try { Invoke-WebRequest "$api/api/tags" -TimeoutSec 3 -UseBasicParsing | Out-Null; return $true } catch { return $false }
}
function Test-CsModel {
    param([string]$Name = $Model)
    try {
        $t = Invoke-RestMethod "$api/api/tags" -TimeoutSec 4
        return [bool]($t.models | Where-Object { $_.name -eq $Name })
    } catch { return $false }
}
function Start-CsOllama {
    Start-Process -FilePath $global:CS_OLLAMA_EXE -ArgumentList 'serve' -WindowStyle Hidden
    for ($i = 0; $i -lt 30; $i++) { Start-Sleep -Seconds 1; if (Test-CsUp) { return $true } }
    return $false
}

if (-not (Test-CsUp)) {
    Write-Host 'Starting Ollama...' -ForegroundColor Yellow
    if (-not (Start-CsOllama)) { Write-Host 'Ollama would not start.' -ForegroundColor Red; return }
}
if (-not (Test-CsModel)) {
    Write-Host "Ollama is running against a different model store - restarting it..." -ForegroundColor Yellow
    Get-Process 'ollama','llama-server' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-CsOllama | Out-Null
}
if (-not (Test-CsModel)) {
    Write-Host ''
    Write-Host "  Model '$Model' was not found in $($global:CS_MODEL_STORE)." -ForegroundColor Red
    Write-Host '  Re-run install.ps1 to rebuild it.'
    Write-Host ''
    return
}

if (Get-Command Show-CsBanner -ErrorAction SilentlyContinue) { Show-CsBanner }

Write-Host "$($c.Muted)-- $($c.Reset)$($c.Bold)$($c.Violet)CYBER-SCOPOLAMINE$($c.Reset) $($c.Muted)chat $('-' * 44)$($c.Reset)"
Write-Host "$($c.Violet)Model: $($c.Reset) $Model $($c.Muted)(local, no API cost)$($c.Reset)"
Write-Host "$($c.Violet)This is$($c.Reset) a plain conversation - the model receives no file context."
Write-Host "        It only writes a transcript when you explicitly use /save."
Write-Host "$($c.Violet)Commands$($c.Reset) /exit  /clear  /model <name>  /save <file>"
Write-Host "$($c.Muted)$('-' * 66)$($c.Reset)"
Write-Host ''

$script:CsSystem = @{
    role    = 'system'
    content = 'You are a local assistant running entirely offline on the user''s own computer through Ollama. You are built on Qwen2.5-Coder; you were not made by OpenAI or Anthropic, and you are not connected to any cloud service. Answer directly and concisely.'
}
$script:CsMessages = @()

Add-Type -AssemblyName System.Net.Http
$http = [System.Net.Http.HttpClient]::new()
$http.Timeout = [TimeSpan]::FromMinutes(15)

function Send-CsChat {
    param([string]$UserText)

    $script:CsMessages += ,@{ role = 'user'; content = $UserText }
    $wire = @($script:CsSystem) + $script:CsMessages
    $payload = @{ model = $Model; messages = $wire; stream = $true } | ConvertTo-Json -Depth 8 -Compress
    $content = [System.Net.Http.StringContent]::new($payload, [System.Text.Encoding]::UTF8, 'application/json')

    $reply = New-Object System.Text.StringBuilder
    $first = $true
    try {
        $resp = $http.PostAsync("$api/api/chat", $content).GetAwaiter().GetResult()
        if (-not $resp.IsSuccessStatusCode) {
            Write-Host "  [ollama returned $($resp.StatusCode)]" -ForegroundColor Red
            if ($script:CsMessages.Count -gt 1) { $script:CsMessages = $script:CsMessages[0..($script:CsMessages.Count - 2)] } else { $script:CsMessages = @() }
            return
        }
        $stream = $resp.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $reader = [System.IO.StreamReader]::new($stream)
        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            if (-not $line) { continue }
            try { $obj = $line | ConvertFrom-Json } catch { continue }
            $piece = $obj.message.content
            if ($piece) {
                if ($first) { Write-Host "$($c.Cyan)" -NoNewline; $first = $false }
                Write-Host -NoNewline $piece
                [void]$reply.Append($piece)
            }
            if ($obj.done) { break }
        }
        $reader.Dispose()
    } catch {
        Write-Host "  [error talking to Ollama: $($_.Exception.Message)]" -ForegroundColor Red
        if ($script:CsMessages.Count -gt 1) { $script:CsMessages = $script:CsMessages[0..($script:CsMessages.Count - 2)] } else { $script:CsMessages = @() }
        return
    }
    Write-Host "$($c.Reset)"
    Write-Host ''
    $script:CsMessages += ,@{ role = 'assistant'; content = $reply.ToString() }
}

while ($true) {
    Write-Host "$($c.Violet)you$($c.Reset) $($c.Muted)>$($c.Reset) " -NoNewline
    $line = Read-Host
    if ($null -eq $line) { break }
    $line = $line.Trim()
    if (-not $line) { continue }

    if ($line -match '^/(exit|quit|q)$') { break }
    if ($line -eq '/clear') {
        $script:CsMessages = @()
        Write-Host "$($c.Muted)  conversation cleared$($c.Reset)"; Write-Host ''
        continue
    }
    if ($line -match '^/model\s+(\S+)$') {
        $candidate = $Matches[1]
        if (Test-CsModel -Name $candidate) {
            $Model = $candidate
            Write-Host "$($c.Muted)  model -> $Model$($c.Reset)"; Write-Host ''
        } else {
            Write-Host "$($c.Amber)  model '$candidate' is not available in the configured store$($c.Reset)"; Write-Host ''
        }
        continue
    }
    if ($line -match '^/save\s+(.+)$') {
        $requestedPath = $Matches[1].Trim().Trim('"')
        try { $path = [System.IO.Path]::GetFullPath($requestedPath) }
        catch {
            Write-Host "$($c.Amber)  invalid save path: $requestedPath$($c.Reset)"; Write-Host ''
            continue
        }
        $parent = Split-Path -Parent $path
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            Write-Host "$($c.Amber)  folder does not exist: $parent$($c.Reset)"; Write-Host ''
            continue
        }
        if (Test-Path -LiteralPath $path) {
            Write-Host "$($c.Amber)  overwrite $path? [y/N]$($c.Reset) " -NoNewline
            $answer = Read-Host
            if ($answer.Trim().ToLowerInvariant() -notmatch '^y(es)?$') {
                Write-Host "$($c.Muted)  save cancelled$($c.Reset)"; Write-Host ''
                continue
            }
        }
        $dump = ($script:CsMessages | ForEach-Object { "$($_.role): $($_.content)" }) -join "`r`n`r`n"
        Set-Content -LiteralPath $path -Value $dump -Encoding UTF8
        Write-Host "$($c.Muted)  saved to $path$($c.Reset)"; Write-Host ''
        continue
    }
    if ($line -match '^/help$') {
        Write-Host "$($c.Muted)  /exit  /clear  /model <name>  /save <file>$($c.Reset)"; Write-Host ''
        continue
    }
    if ($line -match '^/') {
        Write-Host "$($c.Amber)  unknown command. try /help$($c.Reset)"; Write-Host ''
        continue
    }

    Send-CsChat -UserText $line
}

$http.Dispose()
Write-Host "$($c.Muted)  bye$($c.Reset)"
