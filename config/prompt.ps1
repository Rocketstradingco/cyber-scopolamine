# RTCO Labs interactive PowerShell shell.
# Palette: RTCO orange, signal teal, status lime, warm white, and graphite.
# Windows port of rtcolabserver:~/.config/rtco/prompt.bash.

if ($global:RTCO_PROMPT_LOADED) { return }
$global:RTCO_PROMPT_LOADED = $true

$local:bin = Join-Path $env:USERPROFILE '.local\bin'
if ((Test-Path $local:bin) -and ($env:PATH -notlike "*$local:bin*")) {
    $env:PATH = "$local:bin;$env:PATH"
}

$global:RtcoColor = @{
    Reset  = "`e[0m";                    Bold  = "`e[1m"
    Orange = "`e[38;2;241;106;22m";      Amber = "`e[38;2;255;138;55m"
    Teal   = "`e[38;2;108;243;213m";     Lime  = "`e[38;2;200;255;107m"
    White  = "`e[38;2;236;233;225m";     Muted = "`e[38;2;119;129;126m"
    Red    = "`e[38;2;255;117;104m"
}

function global:_rtco_git_segment {
    $c = $global:RtcoColor
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
    $c = $global:RtcoColor

    $gitSegment = _rtco_git_segment

    $jobsSegment = ''
    $jobCount = @(Get-Job -State Running -ErrorAction SilentlyContinue).Count
    if ($jobCount -gt 0) {
        $jobsSegment = " $($c.Muted)jobs:$($c.Amber)$jobCount$($c.Reset)"
    }

    if ($ok -and (($null -eq $exitCode) -or ($exitCode -eq 0))) {
        $statusSegment = "$($c.Lime)$([char]0x25C6)$($c.Reset)"
    } else {
        $statusSegment = "$($c.Red)x$exitCode$($c.Reset)"
    }

    # PROMPT_DIRTRIM=3 equivalent - keep the tail of deep paths.
    $path = $PWD.Path.Replace($env:USERPROFILE, '~')
    $parts = $path -split '[\\/]'
    if ($parts.Count -gt 3) { $path = '...' + [IO.Path]::DirectorySeparatorChar + ($parts[-3..-1] -join [IO.Path]::DirectorySeparatorChar) }

    $host.UI.RawUI.WindowTitle = "RTCO LABS // $env:USERNAME@$env:COMPUTERNAME // $path"

    $time = Get-Date -Format 'HH:mm'
    $line = "$($c.Muted)$([char]0x256D)$([char]0x2500)$($c.Reset) "
    $line += "$($c.Orange)$($c.Bold)RTCO LABS$($c.Reset) "
    $line += "$($c.Muted)//$($c.Reset) $($c.White)$env:USERNAME@$env:COMPUTERNAME$($c.Reset) "
    $line += "$($c.Muted)//$($c.Reset) $($c.Teal)$path$($c.Reset)"
    $line += "$gitSegment$jobsSegment "
    $line += "$($c.Muted)// $time$($c.Reset)"

    Write-Host $line
    return "$($c.Muted)$([char]0x2570)$([char]0x2500)$($c.Reset) $statusSegment "
}

function global:rtco-banner {
    $c = $global:RtcoColor
    Write-Host ''
    Write-Host "$($c.Orange)  $([char]0x25C6)  $($c.Bold)$($c.White)RTCO LABS$($c.Reset)$($c.Muted)  //  LOCAL AGENT WORKSTATION$($c.Reset)"
    Write-Host "$($c.Muted)     WINDOWS  //  $($c.Teal)PRIVATE TAILNET$($c.Muted)  //  $($c.Lime)OPERATOR READY$($c.Reset)"
    Write-Host ''
}

function global:rtco-status {
    $c = $global:RtcoColor

    $tailnetIp = (tailscale ip -4 2>$null | Select-Object -First 1)
    $disk = Get-PSDrive -Name C
    $storage = "{0:N0} GB used / {1:N0} GB free" -f ($disk.Used / 1GB), ($disk.Free / 1GB)
    $os = Get-CimInstance Win32_OperatingSystem
    $memory = "{0:N1} GB used / {1:N1} GB available" -f `
        (($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1MB), ($os.FreePhysicalMemory / 1MB)
    $uptime = (Get-Date) - $os.LastBootUpTime
    $uptimeText = "{0}d {1}h {2}m" -f $uptime.Days, $uptime.Hours, $uptime.Minutes

    Write-Host ''
    Write-Host "$($c.Bold)$($c.White)RTCO LABS$($c.Reset)$($c.Muted)  //  NODE STATUS$($c.Reset)"
    foreach ($row in @(
        @('HOST',    $env:COMPUTERNAME),
        @('TAILNET', $(if ($tailnetIp) { $tailnetIp } else { 'unavailable' })),
        @('UPTIME',  $uptimeText),
        @('STORAGE', $storage),
        @('MEMORY',  $memory)
    )) {
        Write-Host ("$($c.Orange){0,-12}$($c.Reset) {1}" -f $row[0], $row[1])
    }

    # GPU line has no server equivalent - this box is the one with the card.
    $gpu = 'not loaded'
    try {
        $ps = & (Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe') ps 2>$null | Select-Object -Skip 1
        if ($ps) { $gpu = ($ps | Select-Object -First 1) -replace '\s{2,}', '  ' }
    } catch { }
    Write-Host ("$($c.Orange){0,-12}$($c.Reset) {1}" -f 'MODEL', $gpu)

    foreach ($svc in @('ollama', 'docker', 'sshd', 'tailscaled')) {
        $state = 'inactive'
        switch ($svc) {
            'ollama'     { if (Get-Process 'ollama' -ErrorAction SilentlyContinue) { $state = 'active' } }
            'docker'     { if (Get-Process 'com.docker.backend', 'Docker Desktop' -ErrorAction SilentlyContinue) { $state = 'active' } }
            'sshd'       { if ((Get-Service sshd -ErrorAction SilentlyContinue).Status -eq 'Running') { $state = 'active' } }
            'tailscaled' { if (Get-Process 'tailscaled', 'tailscale-ipn' -ErrorAction SilentlyContinue) { $state = 'active' } }
        }
        $color = if ($state -eq 'active') { $c.Lime } else { $c.Red }
        Write-Host ("$($c.Orange){0,-12}$($c.Reset) $color{1}$($c.Reset)" -f $svc.ToUpper(), $state)
    }
    Write-Host ''
}

Set-Alias -Name rtco -Value rtco-status -Scope Global

if (-not $env:RTCO_BANNER_SHOWN) {
    $env:RTCO_BANNER_SHOWN = '1'
    rtco-banner
}
