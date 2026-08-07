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
    $c = $global:CsColor
    $envFile = Join-Path $env:USERPROFILE '.config\cyber-scopolamine\cs-env.ps1'
    if (Test-Path $envFile) { . $envFile }

    $os = Get-CimInstance Win32_OperatingSystem

    Write-Host ''
    Write-Host "$($c.Bold)$($c.White)CYBER-SCOPOLAMINE$($c.Reset)$($c.Muted)  //  STATUS$($c.Reset)"

    $gpuName = (Get-CimInstance Win32_VideoController -EA SilentlyContinue |
                Where-Object { $_.AdapterRAM -gt 0 } | Select-Object -First 1).Name
    if ($gpuName) { Write-Host ("$($c.Violet){0,-12}$($c.Reset) {1}" -f 'GPU', $gpuName) }
    try {
        $usedMB = ((Get-Counter '\GPU Adapter Memory(*)\Dedicated Usage' -EA Stop).CounterSamples |
                   Measure-Object CookedValue -Sum).Sum / 1MB
        Write-Host ("$($c.Violet){0,-12}$($c.Reset) {1:N0} MB in use" -f 'VRAM', $usedMB)
    } catch { }

    $model = 'not loaded'
    $ollamaUp = $false
    try {
        $exe = if ($global:CS_OLLAMA_EXE) { $global:CS_OLLAMA_EXE } else { Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe' }
        $ps = & $exe ps 2>$null | Select-Object -Skip 1
        if ($ps) { $model = ($ps | Select-Object -First 1) -replace '\s{2,}', '  ' }
        $ollamaUp = [bool](Get-Process 'ollama' -EA SilentlyContinue)
    } catch { }
    Write-Host ("$($c.Violet){0,-12}$($c.Reset) {1}" -f 'MODEL', $model)

    $col = if ($ollamaUp) { $c.Lime } else { $c.Red }
    Write-Host ("$($c.Violet){0,-12}$($c.Reset) $col{1}$($c.Reset)" -f 'OLLAMA', $(if ($ollamaUp) { 'running' } else { 'stopped' }))

    $orphans = @(Get-CimInstance Win32_Process -Filter "Name='llama-server.exe'" -EA SilentlyContinue |
                 Where-Object { -not (Get-Process -Id $_.ParentProcessId -EA SilentlyContinue) })
    if ($orphans.Count -gt 0) {
        Write-Host ("$($c.Violet){0,-12}$($c.Reset) $($c.Red){1} orphaned runner(s) holding VRAM - relaunch to reap$($c.Reset)" -f 'WARNING', $orphans.Count)
    }

    if ($global:CS_SANDBOX) {
        Write-Host ("$($c.Violet){0,-12}$($c.Reset) {1}" -f 'SANDBOX', $global:CS_SANDBOX)
    }
    if ($global:CS_MODEL_STORE -and (Test-Path $global:CS_MODEL_STORE)) {
        $d = Get-PSDrive -Name ($global:CS_MODEL_STORE.Substring(0,1)) -EA SilentlyContinue
        if ($d) { Write-Host ("$($c.Violet){0,-12}$($c.Reset) {1}  ({2:N0} GB free)" -f 'MODELS', $global:CS_MODEL_STORE, ($d.Free/1GB)) }
    }
    Write-Host ("$($c.Violet){0,-12}$($c.Reset) {1:N1} GB used / {2:N1} GB free" -f 'MEMORY',
        (($os.TotalVisibleMemorySize-$os.FreePhysicalMemory)/1MB), ($os.FreePhysicalMemory/1MB))
    Write-Host ''
}

Set-Alias -Name scop -Value cs-status -Scope Global

if (-not $env:CS_BANNER_SHOWN) {
    $env:CS_BANNER_SHOWN = '1'
    if (Get-Command Show-CsBanner -ErrorAction SilentlyContinue) { Show-CsBanner }
}
