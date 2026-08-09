if ($global:CS_PROMPT_LOADED) { return }
$global:CS_PROMPT_LOADED = $true

$csBin = Join-Path $env:USERPROFILE '.local\bin'
if ((Test-Path $csBin) -and ($env:PATH -notlike "*$csBin*")) { $env:PATH = "$csBin;$env:PATH" }

$bannerFile = Join-Path $env:USERPROFILE '.config\cyber-scopolamine\banner.ps1'
if (Test-Path $bannerFile) { . $bannerFile }

$global:CsColor = if (Get-Command Get-CsPalette -ErrorAction SilentlyContinue) { Get-CsPalette } else {
    $e = [char]27
    @{ Reset="$e[0m"; Bold="$e[1m"; Violet="$e[38;2;168;85;247m"; Plum="$e[38;2;124;58;237m"
       Cyan="$e[38;2;108;243;213m"; Lime="$e[38;2;200;255;107m"; White="$e[38;2;236;233;225m"
       Muted="$e[38;2;110;100;130m"; Amber="$e[38;2;255;138;55m"; Red="$e[38;2;255;117;104m"
       Orange="$e[38;2;241;106;22m" }
}

function global:_cs_git_segment {
    $c = $global:CsColor
    git rev-parse --is-inside-work-tree 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { return '' }
    $branch = git symbolic-ref --quiet --short HEAD 2>$null
    if (-not $branch) { $branch = git rev-parse --short HEAD 2>$null }
    if (-not $branch) { return '' }
    $dirty = ''
    if (git status --porcelain --untracked-files=normal 2>$null) { $dirty = '*' }
    return " $($c.Muted)git:$($c.Lime)$branch$dirty$($c.Reset)"
}

function global:prompt {
    $exitCode = $LASTEXITCODE
    $ok = $?
    $c = $global:CsColor

    $gitSegment = _cs_git_segment
    $jobsSegment = ''
    $jobCount = @(Get-Job -State Running -ErrorAction SilentlyContinue).Count
    if ($jobCount -gt 0) { $jobsSegment = " $($c.Muted)jobs:$($c.Amber)$jobCount$($c.Reset)" }

    if ($ok -and (($null -eq $exitCode) -or ($exitCode -eq 0))) {
        $statusSegment = "$($c.Lime)$([char]0x25C6)$($c.Reset)"
    } else {
        $statusSegment = "$($c.Red)x$exitCode$($c.Reset)"
    }

    $path = $PWD.Path.Replace($env:USERPROFILE, '~')
    $parts = $path -split '[\\/]'
    if ($parts.Count -gt 3) { $path = '...' + [IO.Path]::DirectorySeparatorChar + ($parts[-3..-1] -join [IO.Path]::DirectorySeparatorChar) }

    $host.UI.RawUI.WindowTitle = "CYBER-SCOPOLAMINE // $env:USERNAME@$env:COMPUTERNAME // $path"

    $line  = "$($c.Muted)$([char]0x256D)$([char]0x2500)$($c.Reset) "
    $line += "$($c.Violet)$($c.Bold)CYBER-SCOPOLAMINE$($c.Reset) "
    $line += "$($c.Muted)//$($c.Reset) $($c.White)$env:USERNAME@$env:COMPUTERNAME$($c.Reset) "
    $line += "$($c.Muted)//$($c.Reset) $($c.Cyan)$path$($c.Reset)"
    $line += "$gitSegment$jobsSegment "
    $line += "$($c.Muted)// $(Get-Date -Format 'HH:mm')$($c.Reset)"

    Write-Host $line
    return "$($c.Muted)$([char]0x2570)$([char]0x2500)$($c.Reset) $statusSegment "
}

function global:cs-status {
    $statusScript = Join-Path $env:USERPROFILE '.local\bin\cyber-scopolamine-status.ps1'
    if (-not (Test-Path -LiteralPath $statusScript)) {
        Write-Host "Status command is missing: $statusScript" -ForegroundColor Red
        return
    }
    & $statusScript
}

Set-Alias -Name scop -Value cs-status -Scope Global

if (-not $env:CS_BANNER_SHOWN) {
    $env:CS_BANNER_SHOWN = '1'
    if (Get-Command Show-CsBanner -ErrorAction SilentlyContinue) { Show-CsBanner }
}
