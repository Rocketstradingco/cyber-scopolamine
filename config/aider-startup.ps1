# Wraps the real `aider` binary with a startup banner: current live generation
# speed, what this local setup is actually good and bad for, and a reminder
# that chat history is archived per session.
#
# Functions are declared global: so they survive into the interactive shell the
# launcher leaves you in - PowerShell discards script-scoped functions when a
# script ends, unlike a bash rcfile.

$rtcoEnv = Join-Path $env:USERPROFILE '.config\rtco\rtco-env.ps1'
if (Test-Path $rtcoEnv) { . $rtcoEnv }

$env:OLLAMA_API_BASE = 'http://127.0.0.1:11434'
$global:RtcoAiderExe = if ($global:RTCO_AIDER_EXE) { $global:RTCO_AIDER_EXE }
                       else { Join-Path $env:USERPROFILE '.local\bin\aider.exe' }

function global:Get-RtcoTokensPerSecond {
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
    $model = if ($global:RTCO_MODEL) { $global:RTCO_MODEL } else { 'qwen2.5-coder-abliterate-7b-agent:latest' }
    $e = [char]27

    Write-Host "$e[38;2;119;129;126m-- $e[0m$e[1;38;2;241;106;22mRTCO local coding agent$e[0m $e[38;2;119;129;126m$('-' * 34)$e[0m"
    Write-Host "$e[38;2;241;106;22mModel: $e[0m $model $e[38;2;119;129;126m(Ollama, local, no API cost)$e[0m"
    Write-Host "$e[38;2;241;106;22mScope: $e[0m small, well-scoped edits - one or a few files at a time."
    Write-Host "        Not for large multi-file refactors or ambiguous asks;"
    Write-Host "        reach for Claude Code / Codex instead for those."
    Write-Host "$e[38;2;241;106;22mMemory:$e[0m fresh context each launch - the prior session's chat is"
    Write-Host "        auto-archived, not restored. Browse/reload old ones with"
    Write-Host "        'rtco-aider-history [list|view|load]'."

    # Show a spinner while the model loads into VRAM instead of dead air. The
    # probe is not wasted work: it is what pulls the model in, so aider's first
    # real prompt is instant.
    $speed = $null
    $resident = $false
    try {
        $loaded = Invoke-RestMethod 'http://127.0.0.1:11434/api/ps' -TimeoutSec 3
        $resident = [bool]($loaded.models | Where-Object { $_.name -eq $model })
    } catch { }

    if ($resident) {
        $speed = Get-RtcoTokensPerSecond -Model $model -TimeoutSec 30
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
        while ($job.State -eq 'Running' -and $sw.Elapsed.TotalSeconds -lt 300) {
            Write-Host -NoNewline ("`r$e[38;2;241;106;22mSpeed: $e[0m $e[38;2;108;243;213m$($frames[$i % $frames.Length])$e[0m loading model into VRAM... {0:N0}s" -f $sw.Elapsed.TotalSeconds)
            Start-Sleep -Milliseconds 90; $i++
        }
        Write-Host -NoNewline ("`r" + (' ' * 72) + "`r")
        $speed = Receive-Job $job -ErrorAction SilentlyContinue
        Remove-Job $job -Force -ErrorAction SilentlyContinue
    }

    if ($speed) {
        Write-Host "$e[38;2;241;106;22mSpeed: $e[0m $e[38;2;200;255;107m~$speed tok/s$e[0m right now"
    } else {
        Write-Host "$e[38;2;241;106;22mSpeed: $e[0m $e[38;2;255;117;104munavailable$e[0m (Ollama not reachable)"
    }
    Write-Host "$e[38;2;119;129;126m$('-' * 66)$e[0m"

    & $global:RtcoAiderExe @args
}

# The uncensored general model is a chat model, not code-tuned. Asked to write
# files it echoes aider's own file-listing template back as file content -
# producing files that "exist" but are garbage. So it is locked to `ask`
# chat-mode: aider never parses or applies file edits from it, whatever it
# outputs. The coding models above are untouched.
function global:aider-uncensored {
    $e = [char]27
    Write-Host "$e[38;2;119;129;126m-- $e[0m$e[1;38;2;241;106;22mRTCO local chatbot$e[0m $e[38;2;119;129;126m(uncensored, chat-only) ------------$e[0m"
    Write-Host "$e[38;2;241;106;22mScope: $e[0m conversation only - file edits are disabled (chat-mode"
    Write-Host "        ask), since this model isn't code-tuned and produces"
    Write-Host "        broken stub files if asked to write code. Use 'aider'"
    Write-Host "        for anything that needs real files written."
    Write-Host "$e[38;2;119;129;126m$('-' * 66)$e[0m"

    & $global:RtcoAiderExe --model uncensored --chat-mode ask @args
}
