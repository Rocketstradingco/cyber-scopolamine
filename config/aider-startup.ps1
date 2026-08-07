$csEnv = Join-Path $env:USERPROFILE '.config\cyber-scopolamine\cs-env.ps1'
if (Test-Path $csEnv) { . $csEnv }

$env:OLLAMA_API_BASE = 'http://127.0.0.1:11434'
$global:CsAiderExe = if ($global:CS_AIDER_EXE) { $global:CS_AIDER_EXE }
                     else { Join-Path $env:USERPROFILE '.local\bin\aider.exe' }

function global:Get-CsTokensPerSecond {
    param([string]$Model, [int]$TimeoutSec = 30)
    try {
        $body = @{ model = $Model; prompt = 'hi'; stream = $false } | ConvertTo-Json -Compress
        $r = Invoke-RestMethod 'http://127.0.0.1:11434/api/generate' -Method Post `
                -Body $body -ContentType 'application/json' -TimeoutSec $TimeoutSec
        if ($r.eval_count -and $r.eval_duration) {
            return [math]::Round($r.eval_count / ($r.eval_duration / 1e9), 0)
        }
    } catch { }
    return $null
}

function global:aider {
    $model = if ($global:CS_MODEL) { $global:CS_MODEL } else { 'qwen2.5-coder-abliterate-7b-agent:latest' }
    $c = if ($global:CsColor) { $global:CsColor } else { Get-CsPalette }

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

    $speed = $null; $resident = $false
    try {
        $loaded = Invoke-RestMethod 'http://127.0.0.1:11434/api/ps' -TimeoutSec 3
        $resident = [bool]($loaded.models | Where-Object { $_.name -eq $model })
    } catch { }

    if ($resident) {
        $speed = Get-CsTokensPerSecond -Model $model -TimeoutSec 30
    } else {
        $job = Start-ThreadJob -ScriptBlock {
            param($m)
            try {
                $body = @{ model = $m; prompt = 'hi'; stream = $false } | ConvertTo-Json -Compress
                $r = Invoke-RestMethod 'http://127.0.0.1:11434/api/generate' -Method Post `
                        -Body $body -ContentType 'application/json' -TimeoutSec 300
                if ($r.eval_count -and $r.eval_duration) {
                    [math]::Round($r.eval_count / ($r.eval_duration / 1e9), 0)
                }
            } catch { }
        } -ArgumentList $model

        $frames = @([char]0x280B,[char]0x2819,[char]0x2839,[char]0x2838,[char]0x283C,
                    [char]0x2834,[char]0x2826,[char]0x2827,[char]0x2807,[char]0x280F)
        $sw = [Diagnostics.Stopwatch]::StartNew(); $i = 0
        while ($job.State -in @('NotStarted','Running') -and $sw.Elapsed.TotalSeconds -lt 300) {
            Write-Host -NoNewline ("`r$($c.Violet)Speed: $($c.Reset) $($c.Cyan)$($frames[$i % $frames.Length])$($c.Reset) dosing the model into VRAM... {0:N0}s" -f $sw.Elapsed.TotalSeconds)
            Start-Sleep -Milliseconds 90; $i++
        }
        Write-Host -NoNewline ("`r" + (' ' * 72) + "`r")
        $job | Wait-Job -Timeout 15 | Out-Null
        $speed = Receive-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
    }

    if ($speed) {
        Write-Host "$($c.Violet)Speed: $($c.Reset) $($c.Lime)~$speed tok/s$($c.Reset) right now"
    } else {
        Write-Host "$($c.Violet)Speed: $($c.Reset) $($c.Red)unavailable$($c.Reset) (Ollama not reachable)"
    }
    Write-Host "$($c.Muted)$('-' * 66)$($c.Reset)"

    & $global:CsAiderExe @args
}
