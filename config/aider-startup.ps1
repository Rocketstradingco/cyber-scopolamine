$csEnv = Join-Path $env:USERPROFILE '.config\cyber-scopolamine\cs-env.ps1'
# Machine configuration is imported by the launcher before this file is loaded.

$env:OLLAMA_API_BASE = $global:CS_OLLAMA_ENDPOINT
$env:OLLAMA_HOST = $global:CS_OLLAMA_HOST
$global:CsAiderExe = if ($global:CS_AIDER_EXE) { $global:CS_AIDER_EXE }
                     else { Join-Path $env:USERPROFILE '.config\cyber-scopolamine\aider-env\Scripts\aider.exe' }

function global:Get-CsTokensPerSecond {
    param([string]$Model, [int]$TimeoutSec = 30)
    try {
        $body = @{ model = $Model; prompt = 'hi'; stream = $false } | ConvertTo-Json -Compress
        $r = Invoke-RestMethod "$($global:CS_OLLAMA_ENDPOINT)/api/generate" -Method Post `
                -Body $body -ContentType 'application/json' -TimeoutSec $TimeoutSec
        if ($r.eval_count -and $r.eval_duration) {
            return [math]::Round($r.eval_count / ($r.eval_duration / 1e9), 0)
        }
    } catch { }
    return $null
}

function global:Get-CsBenchmarkCache {
    param([string]$Model, [int]$MaxAgeDays = 7)
    $path = Join-Path $env:USERPROFILE '.config\cyber-scopolamine\benchmark.json'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $cached = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $measured = [datetime]::Parse(
            [string]$cached.measured_at,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind)
        if ($cached.model -eq $Model -and [double]$cached.tokens_per_second -gt 0 -and
            $measured -ge (Get-Date).ToUniversalTime().AddDays(-$MaxAgeDays)) {
            return $cached
        }
    } catch { }
    return $null
}

function global:Save-CsBenchmarkCache {
    param([string]$Model, [double]$TokensPerSecond)
    $path = Join-Path $env:USERPROFILE '.config\cyber-scopolamine\benchmark.json'
    try {
        $data = @{
            model = $Model
            tokens_per_second = $TokensPerSecond
            measured_at = (Get-Date).ToUniversalTime().ToString('o')
        } | ConvertTo-Json
        [IO.File]::WriteAllText($path, $data, (New-Object Text.UTF8Encoding($false)))
    } catch { }
}

function global:aider {
    $model = if ($global:CS_MODEL) { $global:CS_MODEL } else { 'qwen2.5-coder-abliterate-7b-agent:latest' }
    $c = if ($global:CsColor) { $global:CsColor } else { Get-CsPalette }
    $forwardArgs = @($args | Where-Object { $_ -notin @('--cs-benchmark','--cs-no-benchmark') })
    $forceBenchmark = @($args) -contains '--cs-benchmark'
    $skipBenchmark = (@($args) -contains '--cs-no-benchmark') -or
                     ($env:CS_SKIP_BENCHMARK -match '^(1|true|yes)$')

    Write-Host "$($c.Muted)-- $($c.Reset)$($c.Bold)$($c.Violet)CYBER-SCOPOLAMINE$($c.Reset) $($c.Muted)local coding agent $('-' * 28)$($c.Reset)"
    Write-Host "$($c.Violet)Model: $($c.Reset) $model $($c.Muted)(Ollama, local, no API cost)$($c.Reset)"
    Write-Host "$($c.Violet)Scope: $($c.Reset) small, well-scoped edits - one or a few files at a time."
    Write-Host "        Not for large multi-file refactors or ambiguous asks;"
    Write-Host "        reach for Claude Code / Codex instead for those."
    Write-Host "$($c.Violet)Memory:$($c.Reset) fresh context each launch - the prior session's chat is"
    Write-Host "        auto-archived, not restored. Browse/reload old ones with"
    Write-Host "        'cyber-scopolamine-history [list|view|load]'."
    Write-Host "$($c.Violet)Mode:  $($c.Reset) this is an editor, not a chatbot - every message is treated"
    Write-Host "        as an edit request. '/ask <question>' asks just one; '/ask'"
    Write-Host "        alone switches to asking, '/code' switches back. For a plain"
    Write-Host "        conversation with no repo attached, run cyber-scopolamine-chat."

    $speed = $null
    $speedSource = $null
    $cache = if (-not $skipBenchmark -and -not $forceBenchmark) {
        Get-CsBenchmarkCache -Model $model
    } else { $null }

    if ($cache) {
        $speed = [double]$cache.tokens_per_second
        $speedSource = 'cached; refresh with --cs-benchmark'
    } elseif (-not $skipBenchmark) {
        $resident = $false
        try {
            $loaded = Invoke-RestMethod "$($global:CS_OLLAMA_ENDPOINT)/api/ps" -TimeoutSec 3
            $resident = [bool]($loaded.models | Where-Object { $_.name -eq $model })
        } catch { }
        $timeout = if ($resident) { 30 } else { 120 }

        if ($resident) {
            $speed = Get-CsTokensPerSecond -Model $model -TimeoutSec $timeout
        } elseif (-not (Get-Command Start-ThreadJob -ErrorAction SilentlyContinue)) {
            Write-Host "$($c.Violet)Speed: $($c.Reset) $($c.Cyan)...$($c.Reset) loading and benchmarking once; future launches use the cache"
            $speed = Get-CsTokensPerSecond -Model $model -TimeoutSec $timeout
        } else {
        $job = Start-ThreadJob -ScriptBlock {
            param($m, $timeoutSeconds, $endpoint)
            try {
                $body = @{ model = $m; prompt = 'hi'; stream = $false } | ConvertTo-Json -Compress
                $r = Invoke-RestMethod "$endpoint/api/generate" -Method Post `
                        -Body $body -ContentType 'application/json' -TimeoutSec $timeoutSeconds
                if ($r.eval_count -and $r.eval_duration) {
                    [math]::Round($r.eval_count / ($r.eval_duration / 1e9), 0)
                }
            } catch { }
        } -ArgumentList $model,$timeout,$global:CS_OLLAMA_ENDPOINT

        $frames = @([char]0x280B,[char]0x2819,[char]0x2839,[char]0x2838,[char]0x283C,
                    [char]0x2834,[char]0x2826,[char]0x2827,[char]0x2807,[char]0x280F)
        $sw = [Diagnostics.Stopwatch]::StartNew(); $i = 0
        while ($job.State -in @('NotStarted','Running') -and $sw.Elapsed.TotalSeconds -lt $timeout) {
            Write-Host -NoNewline ("`r$($c.Violet)Speed: $($c.Reset) $($c.Cyan)$($frames[$i % $frames.Length])$($c.Reset) loading and benchmarking once... {0:N0}s" -f $sw.Elapsed.TotalSeconds)
            Start-Sleep -Milliseconds 90; $i++
        }
        Write-Host -NoNewline ("`r" + (' ' * 72) + "`r")
        $job | Wait-Job -Timeout 15 | Out-Null
        $speed = Receive-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        }

        if ($speed) {
            Save-CsBenchmarkCache -Model $model -TokensPerSecond $speed
            $speedSource = 'measured now; cached for 7 days'
        }
    }

    if ($speed) {
        Write-Host "$($c.Violet)Speed: $($c.Reset) $($c.Lime)~$speed tok/s$($c.Reset) $($c.Muted)($speedSource)$($c.Reset)"
    } elseif ($skipBenchmark) {
        Write-Host "$($c.Violet)Speed: $($c.Reset) $($c.Muted)benchmark skipped; run with --cs-benchmark to measure$($c.Reset)"
    } else {
        Write-Host "$($c.Violet)Speed: $($c.Reset) $($c.Red)unavailable$($c.Reset) (benchmark timed out or failed)"
    }
    Write-Host "$($c.Muted)$('-' * 66)$($c.Reset)"

    & $global:CsAiderExe --config $global:CS_AIDER_CONFIG @forwardArgs
}
