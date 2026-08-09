$ErrorActionPreference = 'Stop'

function Get-CsConfigDirectory {
    Join-Path $env:USERPROFILE '.config\cyber-scopolamine'
}

function Get-CsConfigPath {
    Join-Path (Get-CsConfigDirectory) 'config.json'
}

function Get-CsInstallStatePath {
    Join-Path (Get-CsConfigDirectory) 'install-state.json'
}

function Get-CsProcessStatePath {
    Join-Path (Get-CsConfigDirectory) 'ollama-process.json'
}

function Read-CsJsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $text = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($text)) { throw "Configuration file is empty: $Path" }
    try { return $text | ConvertFrom-Json }
    catch { throw "Configuration file is invalid JSON: $Path`n$($_.Exception.Message)" }
}

function Write-CsJsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $temp = Join-Path $parent ('.' + [IO.Path]::GetFileName($Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $json = $Value | ConvertTo-Json -Depth 12
        [IO.File]::WriteAllText($temp, $json, (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temp -Destination $Path -Force
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}

function Import-CsConfig {
    param([string]$Path = (Get-CsConfigPath))

    $cfg = Read-CsJsonFile -Path $Path
    if (-not $cfg) { throw "Cyber-Scopolamine is not configured ($Path missing). Re-run install.ps1." }
    if ($cfg.schemaVersion -ne 1) { throw "Unsupported Cyber-Scopolamine config schema: $($cfg.schemaVersion)" }

    foreach ($required in @('sandbox','model','modelStore','ollamaExe','aiderExe','aiderConfig','ollamaEndpoint','ollamaHost')) {
        if ([string]::IsNullOrWhiteSpace([string]$cfg.$required)) {
            throw "Cyber-Scopolamine config is missing '$required': $Path"
        }
    }

    $global:CS_CONFIG         = $cfg
    $global:CS_SANDBOX        = [string]$cfg.sandbox
    $global:CS_MODEL          = [string]$cfg.model
    $global:CS_MODEL_STORE    = [string]$cfg.modelStore
    $global:CS_OLLAMA_EXE     = [string]$cfg.ollamaExe
    $global:CS_AIDER_EXE      = [string]$cfg.aiderExe
    $global:CS_AIDER_CONFIG   = [string]$cfg.aiderConfig
    $global:CS_NUM_CTX        = [int]$cfg.numCtx
    $global:CS_BACKEND        = [string]$cfg.backend
    $global:CS_OLLAMA_ENDPOINT = ([string]$cfg.ollamaEndpoint).TrimEnd('/')
    $global:CS_OLLAMA_HOST    = [string]$cfg.ollamaHost
    return $cfg
}

function Test-CsEndpoint {
    param([string]$Endpoint = $global:CS_OLLAMA_ENDPOINT, [int]$TimeoutSec = 3)
    if (-not $Endpoint) { return $false }
    try {
        Invoke-WebRequest "$($Endpoint.TrimEnd('/'))/api/tags" -TimeoutSec $TimeoutSec -UseBasicParsing | Out-Null
        return $true
    } catch { return $false }
}

function Test-CsModelVisible {
    param(
        [string]$Model = $global:CS_MODEL,
        [string]$Endpoint = $global:CS_OLLAMA_ENDPOINT
    )
    try {
        $tags = Invoke-RestMethod "$($Endpoint.TrimEnd('/'))/api/tags" -TimeoutSec 4
        return [bool]($tags.models | Where-Object { $_.name -eq $Model })
    } catch { return $false }
}

function Get-CsOwnedOllamaProcess {
    param(
        [string]$ProcessStatePath = (Get-CsProcessStatePath),
        [string]$ExpectedExe = $global:CS_OLLAMA_EXE
    )

    $state = Read-CsJsonFile -Path $ProcessStatePath
    if (-not $state -or -not $state.pid -or -not $state.startedAtUtc -or -not $ExpectedExe) { return $null }
    $process = Get-Process -Id ([int]$state.pid) -ErrorAction SilentlyContinue
    if (-not $process) { return $null }

    try {
        $actualPath = [IO.Path]::GetFullPath([string]$process.Path)
        $wantedPath = [IO.Path]::GetFullPath([string]$ExpectedExe)
        $actualStart = $process.StartTime.ToUniversalTime()
        $wantedStart = [datetime]::Parse([string]$state.startedAtUtc).ToUniversalTime()
        if (-not $actualPath.Equals($wantedPath, [StringComparison]::OrdinalIgnoreCase)) { return $null }
        if ([math]::Abs(($actualStart - $wantedStart).TotalSeconds) -gt 5) { return $null }
        return $process
    } catch { return $null }
}

function Start-CsOwnedOllama {
    param(
        [string]$Exe = $global:CS_OLLAMA_EXE,
        [string]$ModelStore = $global:CS_MODEL_STORE,
        [string]$HostAddress = $global:CS_OLLAMA_HOST,
        [string]$Endpoint = $global:CS_OLLAMA_ENDPOINT,
        [string]$ProcessStatePath = (Get-CsProcessStatePath),
        [int]$WaitSeconds = 30
    )

    if (Test-CsEndpoint -Endpoint $Endpoint) {
        if (-not (Get-CsOwnedOllamaProcess -ProcessStatePath $ProcessStatePath -ExpectedExe $Exe)) {
            throw "The endpoint $Endpoint is responding, but its process is not owned by Cyber-Scopolamine. No process was stopped."
        }
        return $true
    }
    if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) { throw "Ollama executable not found: $Exe" }
    if (-not $HostAddress) { throw 'Dedicated Ollama host is not configured.' }

    $oldModels = $env:OLLAMA_MODELS
    $oldHost = $env:OLLAMA_HOST
    try {
        $env:OLLAMA_MODELS = $ModelStore
        $env:OLLAMA_HOST = $HostAddress
        $process = Start-Process -FilePath $Exe -ArgumentList 'serve' -WindowStyle Hidden -PassThru
    } finally {
        $env:OLLAMA_MODELS = $oldModels
        $env:OLLAMA_HOST = $oldHost
    }

    Write-CsJsonFile -Path $ProcessStatePath -Value ([ordered]@{
        schemaVersion = 1
        pid = $process.Id
        executable = [IO.Path]::GetFullPath($Exe)
        startedAtUtc = $process.StartTime.ToUniversalTime().ToString('o')
        endpoint = $Endpoint
        modelStore = $ModelStore
    })

    for ($i = 0; $i -lt $WaitSeconds; $i++) {
        Start-Sleep -Seconds 1
        if (Test-CsEndpoint -Endpoint $Endpoint -TimeoutSec 2) { return $true }
        if ($process.HasExited) { break }
    }
    throw "Cyber-Scopolamine's dedicated Ollama server did not start at $Endpoint."
}

function Stop-CsOwnedOllama {
    param(
        [string]$ProcessStatePath = (Get-CsProcessStatePath),
        [string]$ExpectedExe = $global:CS_OLLAMA_EXE
    )

    $process = Get-CsOwnedOllamaProcess -ProcessStatePath $ProcessStatePath -ExpectedExe $ExpectedExe
    if ($process) {
        Stop-Process -Id $process.Id -Force -ErrorAction Stop
        try { Wait-Process -Id $process.Id -Timeout 10 -ErrorAction SilentlyContinue } catch { }
    }
    if (Test-Path -LiteralPath $ProcessStatePath) {
        Remove-Item -LiteralPath $ProcessStatePath -Force -ErrorAction SilentlyContinue
    }
    return [bool]$process
}

function Assert-CsDedicatedEndpointAvailable {
    param(
        [string]$Endpoint = $global:CS_OLLAMA_ENDPOINT,
        [string]$ProcessStatePath = (Get-CsProcessStatePath),
        [string]$ExpectedExe = $global:CS_OLLAMA_EXE
    )

    if (-not (Test-CsEndpoint -Endpoint $Endpoint)) { return }
    if (-not (Get-CsOwnedOllamaProcess -ProcessStatePath $ProcessStatePath -ExpectedExe $ExpectedExe)) {
        throw "The dedicated endpoint $Endpoint is already in use by a process Cyber-Scopolamine does not own. Choose another -OllamaPort; no process was stopped."
    }
}
