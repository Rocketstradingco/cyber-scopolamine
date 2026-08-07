<#
    RTCO Local Agent - install wizard.

    Installs a local, offline AI coding agent: aider (the CLI you talk to) on
    top of Ollama (the engine that runs the model on your GPU), plus the RTCO
    customizations - themed shell, cyberpunk waiting spinner, sandboxed
    workspace, and chat-history archiving.

    Detects your GPU and VRAM and picks a model + context size that actually
    fits, because a model that overflows VRAM silently spills to system RAM
    and runs ~5x slower with no error message.

    No administrator rights required: every component installs per-user.

    Usage:
        irm https://raw.githubusercontent.com/<you>/rtco-local-agent/main/install.ps1 | iex
    or, from a clone:
        .\install.ps1                 # interactive wizard
        .\install.ps1 -Unattended     # accept all detected defaults
#>
[CmdletBinding()]
param(
    [switch]$Unattended,
    [string]$SandboxPath,
    [string]$ModelStorePath,
    [string]$Model,
    [int]$NumCtx,
    [switch]$SkipModelPull,
    [switch]$KeepOllamaAutoUpdate
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$AIDER_VERSION   = '0.86.2'   # patches below are diffs against this exact release
$MIN_OLLAMA      = [version]'0.32.6'  # 0.23.x crashes at startup on AMD (CUDA-only MLX init)
$RTCO_VERSION    = '1.0.0'

# ---------------------------------------------------------------- presentation
$C = @{
    Reset='';Bold='';Orange='';Teal='';Lime='';White='';Muted='';Red='';Amber=''
}
if ($Host.UI.SupportsVirtualTerminal -or $PSVersionTable.PSVersion.Major -ge 7) {
    $e = [char]27
    $C = @{
        Reset="$e[0m"; Bold="$e[1m"
        Orange="$e[38;2;241;106;22m"; Amber="$e[38;2;255;138;55m"
        Teal="$e[38;2;108;243;213m";  Lime="$e[38;2;200;255;107m"
        White="$e[38;2;236;233;225m"; Muted="$e[38;2;119;129;126m"
        Red="$e[38;2;255;117;104m"
    }
}

$script:StepNo = 0
function Write-Banner {
    Write-Host ''
    Write-Host "$($C.Orange)  x  $($C.Bold)$($C.White)RTCO LOCAL AGENT$($C.Reset)$($C.Muted)  //  INSTALL WIZARD v$RTCO_VERSION$($C.Reset)"
    Write-Host "$($C.Muted)     aider + ollama  //  $($C.Teal)100% LOCAL$($C.Muted)  //  $($C.Lime)NO API KEYS, NO CLOUD$($C.Reset)"
    Write-Host ''
}
function Write-Step { param([string]$Text)
    $script:StepNo++
    Write-Host ''
    Write-Host "$($C.Muted)[$($script:StepNo)]$($C.Reset) $($C.Orange)$($C.Bold)$Text$($C.Reset)"
}
function Write-Ok   { param([string]$T) Write-Host "    $($C.Lime)ok$($C.Reset)   $T" }
function Write-Info { param([string]$T) Write-Host "    $($C.Muted)..$($C.Reset)   $T" }
function Write-Warn { param([string]$T) Write-Host "    $($C.Amber)!!$($C.Reset)   $T" }
function Write-Bad  { param([string]$T) Write-Host "    $($C.Red)xx$($C.Reset)   $T" }

function Confirm-Step {
    param([string]$Question, [string]$Default = 'y')
    if ($Unattended) { return ($Default -eq 'y') }
    $hint = if ($Default -eq 'y') { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        Write-Host "    $($C.Teal)?$($C.Reset)    $Question $($C.Muted)$hint$($C.Reset) " -NoNewline
        $a = Read-Host
        if ([string]::IsNullOrWhiteSpace($a)) { $a = $Default }
        switch -Regex ($a.Trim().ToLower()) {
            '^y(es)?$' { return $true }
            '^n(o)?$'  { return $false }
            default    { Write-Warn 'Please answer y or n.' }
        }
    }
}

function Read-Default {
    param([string]$Question, [string]$Default)
    if ($Unattended) { return $Default }
    Write-Host "    $($C.Teal)?$($C.Reset)    $Question"
    Write-Host "         $($C.Muted)default:$($C.Reset) $Default"
    Write-Host "         > " -NoNewline
    $a = Read-Host
    if ([string]::IsNullOrWhiteSpace($a)) { return $Default }
    return $a.Trim()
}

# ------------------------------------------------------------------ detection
function Get-GpuInfo {
    # Win32_VideoController.AdapterRAM is a 32-bit field and reports 4 GB for
    # anything larger, so read the real size from the driver registry key.
    $best = $null
    $keys = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\*' -ErrorAction SilentlyContinue
    foreach ($k in $keys) {
        if (-not $k.DriverDesc) { continue }
        $bytes = $k.'HardwareInformation.qwMemorySize'
        if (-not $bytes) { continue }
        $gb = [math]::Round($bytes / 1GB, 1)
        if (-not $best -or $gb -gt $best.VramGB) {
            $vendor = 'Unknown'
            if ($k.DriverDesc -match 'NVIDIA|GeForce|Quadro|RTX|GTX') { $vendor = 'NVIDIA' }
            elseif ($k.DriverDesc -match 'Radeon|AMD')                { $vendor = 'AMD' }
            elseif ($k.DriverDesc -match 'Intel|Arc')                 { $vendor = 'Intel' }
            $best = [PSCustomObject]@{ Name = $k.DriverDesc; VramGB = $gb; Vendor = $vendor }
        }
    }
    if (-not $best) {
        $vc = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
              Where-Object { $_.AdapterRAM -gt 0 } | Sort-Object AdapterRAM -Descending | Select-Object -First 1
        if ($vc) {
            $best = [PSCustomObject]@{
                Name = $vc.Name; VramGB = [math]::Round($vc.AdapterRAM / 1GB, 1); Vendor = 'Unknown'
            }
        }
    }
    return $best
}

function Get-ModelPlan {
    param([double]$VramGB, [string]$Vendor)
    # Budget: weights + KV cache + compute buffers, leaving ~1.2 GB for the
    # desktop. Erring small on purpose - overflowing VRAM is far worse than a
    # smaller model, because it degrades silently instead of failing.
    $usable = $VramGB - 1.2
    if     ($usable -ge 19) { $t = @{ Base='huihui_ai/qwen2.5-coder-abliterate:14b'; Agent='qwen2.5-coder-abliterate-14b-agent'; Ctx=32768; Label='14b @ 32K' } }
    elseif ($usable -ge 9)  { $t = @{ Base='huihui_ai/qwen2.5-coder-abliterate:7b';  Agent='qwen2.5-coder-abliterate-7b-agent';  Ctx=32768; Label='7b @ 32K'  } }
    elseif ($usable -ge 6)  { $t = @{ Base='huihui_ai/qwen2.5-coder-abliterate:7b';  Agent='qwen2.5-coder-abliterate-7b-agent';  Ctx=16384; Label='7b @ 16K'  } }
    elseif ($usable -ge 3.5){ $t = @{ Base='huihui_ai/qwen2.5-coder-abliterate:3b';  Agent='qwen2.5-coder-abliterate-3b-agent';  Ctx=16384; Label='3b @ 16K'  } }
    elseif ($usable -ge 2)  { $t = @{ Base='huihui_ai/qwen2.5-coder-abliterate:3b';  Agent='qwen2.5-coder-abliterate-3b-agent';  Ctx=8192;  Label='3b @ 8K'   } }
    else                    { $t = @{ Base='huihui_ai/qwen2.5-coder-abliterate:3b';  Agent='qwen2.5-coder-abliterate-3b-agent';  Ctx=8192;  Label='3b @ 8K (CPU)'; CpuOnly=$true } }
    return $t
}

function Get-FastestDriveWithSpace {
    param([double]$NeedGB = 30)
    $best = $null
    foreach ($p in (Get-Partition -ErrorAction SilentlyContinue | Where-Object DriveLetter)) {
        $vol = Get-Volume -DriveLetter $p.DriveLetter -ErrorAction SilentlyContinue
        if (-not $vol -or $vol.DriveType -ne 'Fixed') { continue }
        $freeGB = [math]::Round($vol.SizeRemaining / 1GB, 1)
        if ($freeGB -lt $NeedGB) { continue }
        $media = 'Unknown'; $bus = 'Unknown'
        try {
            $disk = Get-Disk -Number $p.DiskNumber -ErrorAction Stop
            $bus  = [string]$disk.BusType
            $phys = Get-PhysicalDisk -ErrorAction Stop | Where-Object DeviceId -eq $disk.Number
            if ($phys) { $media = $phys.MediaType }
        } catch { }
        # Rank by storage class, not free space. Load time for a 7b measured
        # ~9s from NVMe vs ~57s from a 5400 RPM HDD, so a slightly fuller NVMe
        # beats a roomier SATA SSD - and beats an HDD by a mile.
        $rank = if     ($media -eq 'SSD' -and $bus -eq 'NVMe') { 0 }
                elseif ($media -eq 'SSD')                      { 1 }
                elseif ($media -eq 'HDD')                      { 3 }
                else                                           { 2 }
        $cand = [PSCustomObject]@{ Letter=$p.DriveLetter; FreeGB=$freeGB; Media=$media; Bus=$bus; Rank=$rank }
        if (-not $best -or $cand.Rank -lt $best.Rank -or ($cand.Rank -eq $best.Rank -and $cand.FreeGB -gt $best.FreeGB)) {
            $best = $cand
        }
    }
    return $best
}

# ------------------------------------------------------------------- installers
function Ensure-Uv {
    $uv = Join-Path $env:USERPROFILE '.local\bin\uv.exe'
    if (Test-Path $uv) { Write-Ok "uv already installed"; return $uv }
    $cmd = Get-Command uv -ErrorAction SilentlyContinue
    if ($cmd) { Write-Ok "uv already installed ($($cmd.Source))"; return $cmd.Source }
    Write-Info 'Installing uv (Python tool manager)...'
    Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
    if (-not (Test-Path $uv)) { throw "uv install failed - expected $uv" }
    Write-Ok 'uv installed'
    return $uv
}

function Get-OllamaExe {
    $p = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'
    if (Test-Path $p) { return $p }
    $c = Get-Command ollama -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}

function Ensure-Ollama {
    $exe = Get-OllamaExe
    if ($exe) {
        $v = $null
        try { if ((& $exe --version 2>&1) -join ' ' -match '(\d+\.\d+\.\d+)') { $v = [version]$Matches[1] } } catch { }
        if ($v -and $v -ge $MIN_OLLAMA) { Write-Ok "Ollama $v already installed"; return $exe }
        if ($v) { Write-Warn "Ollama $v is older than $MIN_OLLAMA - upgrading" }
        else    { Write-Warn "Ollama present but not runnable (known crash in 0.23.x on AMD) - reinstalling" }
    }
    Write-Info 'Downloading Ollama installer (~1.5 GB, this is the long part)...'
    $rel = Invoke-RestMethod 'https://api.github.com/repos/ollama/ollama/releases/latest' -Headers @{'User-Agent'='rtco'}
    $asset = $rel.assets | Where-Object name -eq 'OllamaSetup.exe' | Select-Object -First 1
    if (-not $asset) { throw 'Could not find OllamaSetup.exe in the latest Ollama release.' }
    $dst = Join-Path $env:TEMP 'OllamaSetup.exe'
    Invoke-WebRequest $asset.browser_download_url -OutFile $dst -UseBasicParsing -TimeoutSec 3600
    Write-Info "Installing Ollama $($rel.tag_name) (silent, per-user, no admin needed)..."
    $p = Start-Process -FilePath $dst -ArgumentList '/SILENT','/SP-','/NOCANCEL','/CLOSEAPPLICATIONS','/FORCECLOSEAPPLICATIONS' -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "Ollama installer exited with $($p.ExitCode)" }
    Remove-Item $dst -Force -ErrorAction SilentlyContinue
    $exe = Get-OllamaExe
    if (-not $exe) { throw 'Ollama install finished but ollama.exe was not found.' }
    Write-Ok 'Ollama installed'
    return $exe
}

function Ensure-Aider {
    param([string]$Uv)
    $aider = Join-Path $env:USERPROFILE '.local\bin\aider.exe'
    if (Test-Path $aider) {
        $cur = ((& $aider --version 2>&1) -join ' ')
        if ($cur -match [regex]::Escape($AIDER_VERSION)) { Write-Ok "aider $AIDER_VERSION already installed"; return $aider }
        Write-Warn "aider present but not $AIDER_VERSION - reinstalling (the RTCO patches are version-locked)"
    }
    Write-Info "Installing aider $AIDER_VERSION..."
    & $Uv tool install --force "aider-chat==$AIDER_VERSION" | Out-Null
    if (-not (Test-Path $aider)) { throw "aider install failed - expected $aider" }
    Write-Ok "aider $AIDER_VERSION installed"
    return $aider
}

function Get-PatchExe {
    foreach ($p in @('C:\Program Files\Git\usr\bin\patch.exe','C:\Program Files (x86)\Git\usr\bin\patch.exe')) {
        if (Test-Path $p) { return $p }
    }
    $c = Get-Command patch.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}

function Start-OllamaServer {
    param([string]$Exe, [string]$ModelStore)
    try {
        Invoke-WebRequest 'http://127.0.0.1:11434/api/tags' -TimeoutSec 3 -UseBasicParsing | Out-Null
        return $true
    } catch { }
    $env:OLLAMA_MODELS = $ModelStore
    Start-Process -FilePath $Exe -ArgumentList 'serve' -WindowStyle Hidden
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        try { Invoke-WebRequest 'http://127.0.0.1:11434/api/tags' -TimeoutSec 2 -UseBasicParsing | Out-Null; return $true } catch { }
    }
    return $false
}

# ===================================================================== WIZARD
Write-Banner

# Where are the payload files? Either a clone next to this script, or fetched.
$SrcRoot = if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'config\prompt.ps1'))) { $PSScriptRoot } else { $null }
if (-not $SrcRoot) {
    Write-Step 'Fetching RTCO customizations'
    $tmp = Join-Path $env:TEMP "rtco-local-agent-$(Get-Random)"
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    $zip = Join-Path $tmp 'src.zip'
    Invoke-WebRequest 'https://github.com/REPLACE-ME/rtco-local-agent/archive/refs/heads/main.zip' -OutFile $zip -UseBasicParsing
    Expand-Archive $zip -DestinationPath $tmp -Force
    $SrcRoot = (Get-ChildItem $tmp -Directory | Select-Object -First 1).FullName
    Write-Ok "Downloaded to $SrcRoot"
}

Write-Step 'Scanning this machine'
$gpu = Get-GpuInfo
if ($gpu) {
    Write-Ok "GPU:  $($gpu.Name)  $($C.Bold)$($gpu.VramGB) GB$($C.Reset) VRAM  ($($gpu.Vendor))"
} else {
    Write-Warn 'No discrete GPU detected - the model will run on CPU and will be slow.'
    $gpu = [PSCustomObject]@{ Name='(none)'; VramGB=0; Vendor='None' }
}
$ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
Write-Ok "RAM:  $ramGB GB"
$drive = Get-FastestDriveWithSpace -NeedGB 30
if ($drive) { Write-Ok "Disk: $($drive.Letter): has $($drive.FreeGB) GB free  ($($drive.Media))" }
else        { Write-Bad 'No fixed drive with 30 GB free - free up space and re-run.'; return }
Write-Ok "PowerShell $($PSVersionTable.PSVersion)"

Write-Step 'Choosing a model that fits your card'
$plan = Get-ModelPlan -VramGB $gpu.VramGB -Vendor $gpu.Vendor
if ($plan.CpuOnly) {
    Write-Warn 'Not enough VRAM for GPU inference - falling back to the smallest model.'
}
Write-Info "A model bigger than VRAM does not error - it silently spills to"
Write-Info "system RAM and runs roughly 5x slower, so this errs small."
Write-Ok "Recommended: $($C.Bold)$($plan.Label)$($C.Reset)  ->  $($plan.Base)"

if (-not $Model)  { $Model  = $plan.Base }
if (-not $NumCtx) { $NumCtx = $plan.Ctx }
$AgentModel = $plan.Agent

if (-not $Unattended) {
    if (-not (Confirm-Step "Use $($plan.Label)?")) {
        $Model  = Read-Default 'Ollama model to pull' $plan.Base
        $NumCtx = [int](Read-Default 'Context window (num_ctx)' $plan.Ctx)
        $AgentModel = (($Model -split '/')[-1] -replace ':','-') + '-agent'
    }
}

Write-Step 'Choosing locations'
if (-not $SandboxPath)    { $SandboxPath    = Read-Default 'Sandbox folder (the ONLY folder the agent may edit)' "$($drive.Letter):\rtco-sandbox" }
if (-not $ModelStorePath) { $ModelStorePath = Read-Default 'Model store (needs ~10-25 GB; put it on your fastest SSD)' "$($drive.Letter):\ollama\models" }

Write-Step 'Ready to install'
Write-Host "    $($C.Muted)Model      $($C.Reset) $Model  ($NumCtx ctx)"
Write-Host "    $($C.Muted)Sandbox    $($C.Reset) $SandboxPath"
Write-Host "    $($C.Muted)Model store$($C.Reset) $ModelStorePath"
Write-Host "    $($C.Muted)aider      $($C.Reset) $AIDER_VERSION (pinned - RTCO patches target it)"
Write-Host "    $($C.Muted)Shortcut   $($C.Reset) Desktop -> 'RTCO Local Agent (Sandbox)'"
Write-Host ''
if (-not (Confirm-Step 'Proceed with installation?')) { Write-Bad 'Cancelled.'; return }

Write-Step 'Installing prerequisites'
$uv     = Ensure-Uv
$ollama = Ensure-Ollama
$aider  = Ensure-Aider -Uv $uv

Write-Step 'Creating folders'
$cfgDir   = Join-Path $env:USERPROFILE '.config\rtco'
$binDir   = Join-Path $env:USERPROFILE '.local\bin'
$patchDir = Join-Path $cfgDir 'aider-cyberpunk-waiting-patch'
foreach ($d in @($cfgDir, $binDir, $patchDir, $ModelStorePath, $SandboxPath, (Join-Path $SandboxPath '.aider-history-archive'))) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}
Write-Ok "config -> $cfgDir"
Write-Ok "tools  -> $binDir"
Write-Ok "sandbox-> $SandboxPath"

Write-Step 'Writing machine configuration'
$envFile = Join-Path $cfgDir 'rtco-env.ps1'
@"
# Generated by the RTCO Local Agent installer on $(Get-Date -Format 'yyyy-MM-dd HH:mm').
# Machine-specific values. Every RTCO script reads these, so nothing else
# hardcodes a path - edit here to move things.
`$global:RTCO_SANDBOX      = '$SandboxPath'
`$global:RTCO_MODEL        = '$AgentModel`:latest'
`$global:RTCO_MODEL_STORE  = '$ModelStorePath'
`$global:RTCO_OLLAMA_EXE   = '$ollama'
`$global:RTCO_AIDER_EXE    = '$aider'
`$global:RTCO_NUM_CTX      = $NumCtx
"@ | Set-Content -Path $envFile -Encoding UTF8
Write-Ok "wrote $envFile"

foreach ($f in @('prompt.ps1','aider-startup.ps1')) {
    Copy-Item (Join-Path $SrcRoot "config\$f") (Join-Path $cfgDir $f) -Force
}
foreach ($f in (Get-ChildItem (Join-Path $SrcRoot 'bin') -File)) {
    Copy-Item $f.FullName (Join-Path $binDir $f.Name) -Force
}
Copy-Item (Join-Path $SrcRoot 'patches\*') $patchDir -Force
Write-Ok 'copied RTCO customizations'

# ~/.local/bin on PATH so the rtco-* commands work in any shell
$userPath = [Environment]::GetEnvironmentVariable('PATH','User')
if ($userPath -notlike "*$binDir*") {
    [Environment]::SetEnvironmentVariable('PATH', "$binDir;$userPath", 'User')
    Write-Ok "added $binDir to your PATH"
}
$env:PATH = "$binDir;$env:PATH"

Write-Step 'Applying RTCO aider patches'
$patchExe = Get-PatchExe
if ($patchExe) {
    & (Join-Path $patchDir 'apply.ps1') | ForEach-Object { Write-Info $_ }
    Write-Ok 'cyberpunk waiting spinner + local model picker applied'
} else {
    Write-Warn 'patch.exe not found (it ships with Git for Windows).'
    Write-Warn 'Install Git, then run:  rtco-aider-patch'
    Write-Warn 'Everything else works without it - you just get the stock aider spinner.'
}

Write-Step 'Configuring the sandbox'
$conf = Get-Content (Join-Path $SrcRoot 'config\aider.conf.yml.template') -Raw
$conf = $conf.Replace('{{MODEL}}', "$AgentModel`:latest")
$conf | Set-Content -Path (Join-Path $SandboxPath '.aider.conf.yml') -Encoding UTF8
@'
.aider-history-archive/
.aider.chat.history.md
.aider.input.history
.aider.tags.cache.v*/
'@ | Set-Content -Path (Join-Path $SandboxPath '.gitignore') -Encoding UTF8

if (Get-Command git -ErrorAction SilentlyContinue) {
    if (-not (Test-Path (Join-Path $SandboxPath '.git'))) {
        & git -C $SandboxPath init -b main *>&1 | Out-Null
        Write-Ok 'sandbox initialised as a git repo (aider works best in one)'
    }
} else {
    Write-Warn 'git not found - the sandbox is not a repo. aider still works, with fewer safety nets.'
}
Write-Ok "config -> $SandboxPath\.aider.conf.yml"

if (-not $SkipModelPull) {
    Write-Step "Downloading the model  ($Model)"
    Write-Info 'Several GB - this is the slowest step. It resumes if interrupted.'
    if (-not (Start-OllamaServer -Exe $ollama -ModelStore $ModelStorePath)) {
        throw 'Ollama did not start - cannot pull the model.'
    }
    $env:OLLAMA_MODELS = $ModelStorePath
    & $ollama pull $Model
    if ($LASTEXITCODE -ne 0) { throw "Model pull failed for $Model" }
    Write-Ok 'model downloaded'

    Write-Step "Building the -agent variant  (num_ctx $NumCtx)"
    # Stock Ollama defaults to a small context, which starves aider: its repo
    # map alone is budgeted at 4096 tokens before any file content.
    $mf = Join-Path $env:TEMP "$AgentModel.Modelfile"
    "FROM $Model`n`nPARAMETER num_ctx $NumCtx`n" | Set-Content -Path $mf -Encoding ascii
    & $ollama create $AgentModel -f $mf | Out-Null
    Remove-Item $mf -Force -ErrorAction SilentlyContinue
    Write-Ok "created $AgentModel (num_ctx $NumCtx)"
}

Write-Step 'Ollama auto-update'
if (-not $KeepOllamaAutoUpdate) {
    Write-Info 'Ollama silently self-updates, and 0.23.x builds crash at startup'
    Write-Info 'on AMD cards, taking the whole agent down with no warning.'
    if (Confirm-Step 'Disable Ollama auto-update? (recommended)') {
        & (Join-Path $binDir 'rtco-ollama-noupdate.ps1') | ForEach-Object { Write-Info $_ }
    }
}

Write-Step 'Creating the desktop icon'
# Per-user Desktop needs no elevation.
$desktop = [Environment]::GetFolderPath('Desktop')
$lnkPath = Join-Path $desktop 'RTCO Local Agent (Sandbox).lnk'
$pwsh    = if (Test-Path "$env:ProgramFiles\PowerShell\7\pwsh.exe") { "$env:ProgramFiles\PowerShell\7\pwsh.exe" } else { "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }
$wt      = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'
$launcher = Join-Path $binDir 'rtco-sandbox-aider.ps1'
try {
    $ws  = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($lnkPath)
    if (Test-Path $wt) {
        $lnk.TargetPath = $wt
        $lnk.Arguments  = "-d `"$SandboxPath`" `"$pwsh`" -NoLogo -NoExit -NoProfile -ExecutionPolicy Bypass -File `"$launcher`""
    } else {
        $lnk.TargetPath = $pwsh
        $lnk.Arguments  = "-NoLogo -NoExit -NoProfile -ExecutionPolicy Bypass -File `"$launcher`""
    }
    $lnk.WorkingDirectory = $SandboxPath
    $lnk.Description      = "Local aider + Ollama coding agent, quarantined to $SandboxPath"
    $icon = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\app.ico'
    if (Test-Path $icon) { $lnk.IconLocation = "$icon,0" }
    $lnk.Save()
    Write-Ok "created '$lnkPath'"
} catch {
    Write-Warn "Could not create the desktop shortcut: $($_.Exception.Message)"
    Write-Warn "You can still start it by running:  rtco-sandbox-aider"
}

Write-Host ''
Write-Host "$($C.Lime)$($C.Bold)  Installation complete.$($C.Reset)"
Write-Host ''
Write-Host "  $($C.Orange)Start it$($C.Reset)      Double-click $($C.Bold)RTCO Local Agent (Sandbox)$($C.Reset) on your Desktop"
Write-Host "  $($C.Orange)Or$($C.Reset)            run $($C.Teal)rtco-sandbox-aider$($C.Reset) in any terminal"
Write-Host "  $($C.Orange)Sandbox$($C.Reset)       $SandboxPath  $($C.Muted)(the only folder it can edit)$($C.Reset)"
Write-Host "  $($C.Orange)Model$($C.Reset)         $AgentModel  $($C.Muted)($NumCtx ctx, fully offline)$($C.Reset)"
Write-Host "  $($C.Orange)Old chats$($C.Reset)     $($C.Teal)rtco-aider-history$($C.Reset) list | view <n> | load <n>"
Write-Host "  $($C.Orange)Machine info$($C.Reset)  $($C.Teal)rtco-status$($C.Reset)"
Write-Host ''
Write-Host "  $($C.Muted)Read the README for what aider vs Ollama means and how to use it.$($C.Reset)"
Write-Host ''
