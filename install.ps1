[CmdletBinding()]
param(
    [switch]$Unattended,
    [switch]$DryRun,
    [string]$SandboxPath,
    [string]$ModelStorePath,
    [string]$Model,
    [int]$NumCtx,
    [switch]$SkipModelPull,
    [switch]$KeepOllamaAutoUpdate
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$AIDER_VERSION = '0.86.2'
$MIN_OLLAMA    = [version]'0.32.6'
$CS_VERSION    = '1.0.0'
$APP_NAME      = 'Cyber-Scopolamine'
$SLUG          = 'cyber-scopolamine'

$e = [char]27
$C = @{
    Reset="$e[0m"; Bold="$e[1m"
    Violet="$e[38;2;168;85;247m"; Plum="$e[38;2;124;58;237m"
    Cyan="$e[38;2;108;243;213m";  Lime="$e[38;2;200;255;107m"
    White="$e[38;2;236;233;225m"; Muted="$e[38;2;110;100;130m"
    Amber="$e[38;2;255;138;55m";  Red="$e[38;2;255;117;104m"
    Orange="$e[38;2;241;106;22m"
}

$script:StepNo = 0
function Write-Step { param([string]$T)
    $script:StepNo++
    Write-Host ''
    Write-Host "$($C.Muted)[$($script:StepNo)]$($C.Reset) $($C.Violet)$($C.Bold)$T$($C.Reset)"
}
function Write-Ok    { param($T) Write-Host "    $($C.Lime)ok$($C.Reset)    $T" }
function Write-Info  { param($T) Write-Host "    $($C.Muted)..$($C.Reset)    $T" }
function Write-Have  { param($T) Write-Host "    $($C.Cyan)have$($C.Reset)  $T" }
function Write-Need  { param($T) Write-Host "    $($C.Amber)need$($C.Reset)  $T" }
function Write-Warn2 { param($T) Write-Host "    $($C.Amber)!!$($C.Reset)    $T" }
function Write-Bad   { param($T) Write-Host "    $($C.Red)xx$($C.Reset)    $T" }

function Confirm-Step {
    param([string]$Question, [string]$Default = 'y')
    if ($Unattended) { return ($Default -eq 'y') }
    $hint = if ($Default -eq 'y') { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        Write-Host "    $($C.Cyan)?$($C.Reset)     $Question $($C.Muted)$hint$($C.Reset) " -NoNewline
        $a = Read-Host
        if ([string]::IsNullOrWhiteSpace($a)) { $a = $Default }
        switch -Regex ($a.Trim().ToLower()) {
            '^y(es)?$' { return $true }
            '^n(o)?$'  { return $false }
            default    { Write-Warn2 'Please answer y or n.' }
        }
    }
}
function Read-Default {
    param([string]$Question, [string]$Default)
    if ($Unattended) { return $Default }
    Write-Host "    $($C.Cyan)?$($C.Reset)     $Question"
    Write-Host "          $($C.Muted)default:$($C.Reset) $Default"
    Write-Host "          > " -NoNewline
    $a = Read-Host
    if ([string]::IsNullOrWhiteSpace($a)) { return $Default }
    return $a.Trim()
}

function Get-GpuInfo {

    $best = $null
    foreach ($k in (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\*' -ErrorAction SilentlyContinue)) {
        if (-not $k.DriverDesc) { continue }
        $bytes = $k.'HardwareInformation.qwMemorySize'
        if (-not $bytes) { continue }
        $gb = [math]::Round($bytes / 1GB, 1)
        if ($best -and $gb -le $best.VramGB) { continue }
        $vendor  = 'Unknown'; $backend = 'CPU'
        if     ($k.DriverDesc -match 'NVIDIA|GeForce|Quadro|RTX|GTX|Tesla') { $vendor='NVIDIA'; $backend='CUDA' }
        elseif ($k.DriverDesc -match 'Radeon|AMD|FirePro')                  { $vendor='AMD';    $backend='Vulkan' }
        elseif ($k.DriverDesc -match 'Intel|Arc')                           { $vendor='Intel';  $backend='Vulkan' }
        $best = [PSCustomObject]@{ Name=$k.DriverDesc; VramGB=$gb; Vendor=$vendor; Backend=$backend }
    }
    return $best
}

function Get-ModelPlan {
    param([double]$VramGB)

    $usable = $VramGB - 1.2
    if     ($usable -ge 19)  { @{ Base='huihui_ai/qwen2.5-coder-abliterate:14b'; Agent='cyscop-14b'; Ctx=32768; Label='14b @ 32K' } }
    elseif ($usable -ge 9)   { @{ Base='huihui_ai/qwen2.5-coder-abliterate:7b';  Agent='cyscop-7b';  Ctx=32768; Label='7b @ 32K'  } }
    elseif ($usable -ge 6)   { @{ Base='huihui_ai/qwen2.5-coder-abliterate:7b';  Agent='cyscop-7b';  Ctx=16384; Label='7b @ 16K'  } }
    elseif ($usable -ge 3.5) { @{ Base='huihui_ai/qwen2.5-coder-abliterate:3b';  Agent='cyscop-3b';  Ctx=16384; Label='3b @ 16K'  } }
    elseif ($usable -ge 2)   { @{ Base='huihui_ai/qwen2.5-coder-abliterate:3b';  Agent='cyscop-3b';  Ctx=8192;  Label='3b @ 8K'   } }
    else                     { @{ Base='huihui_ai/qwen2.5-coder-abliterate:3b';  Agent='cyscop-3b';  Ctx=8192;  Label='3b @ 8K (CPU)'; CpuOnly=$true } }
}

function Get-DriveCandidates {
    param([double]$NeedGB = 30)
    $out = @()
    foreach ($p in (Get-Partition -ErrorAction SilentlyContinue | Where-Object DriveLetter)) {
        $vol = Get-Volume -DriveLetter $p.DriveLetter -ErrorAction SilentlyContinue
        if (-not $vol -or $vol.DriveType -ne 'Fixed') { continue }
        $freeGB = [math]::Round($vol.SizeRemaining / 1GB, 1)
        $media='Unknown'; $bus='Unknown'
        try {
            $disk = Get-Disk -Number $p.DiskNumber -ErrorAction Stop
            $bus  = [string]$disk.BusType
            $phys = Get-PhysicalDisk -ErrorAction Stop | Where-Object DeviceId -eq $disk.Number
            if ($phys) { $media = $phys.MediaType }
        } catch { }

        $rank = if     ($media -eq 'SSD' -and $bus -eq 'NVMe') { 0 }
                elseif ($media -eq 'SSD')                      { 1 }
                elseif ($media -eq 'HDD')                      { 3 }
                else                                           { 2 }
        $out += [PSCustomObject]@{
            Letter=$p.DriveLetter; FreeGB=$freeGB; Media=$media; Bus=$bus; Rank=$rank
            Class = switch ($rank) { 0 {'NVMe SSD'} 1 {'SATA SSD'} 3 {'HDD (slow)'} default {'unknown'} }
            Enough = ($freeGB -ge $NeedGB)
        }
    }
    return $out | Sort-Object @{E={-not $_.Enough}}, Rank, @{E='FreeGB';D=$true}
}

function Get-OllamaExe {
    $p = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'
    if (Test-Path $p) { return $p }
    $c = Get-Command ollama -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}
function Get-OllamaVersion {
    param([string]$Exe)
    if (-not $Exe) { return $null }
    try { if (((& $Exe --version 2>&1) -join ' ') -match '(\d+\.\d+\.\d+)') { return [version]$Matches[1] } } catch { }
    return $null
}
function Get-PatchExe {
    foreach ($p in @('C:\Program Files\Git\usr\bin\patch.exe','C:\Program Files (x86)\Git\usr\bin\patch.exe')) {
        if (Test-Path $p) { return $p }
    }
    $c = Get-Command patch.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    return $null
}

$SrcRoot = if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'config\banner.ps1'))) { $PSScriptRoot } else { $null }
if ($SrcRoot) {
    . (Join-Path $SrcRoot 'config\banner.ps1')
    Show-CsBanner
} else {
    Write-Host ''
    Write-Host "  $($C.Violet)$($C.Bold)CYBER-SCOPOLAMINE$($C.Reset)  $($C.Muted)installer v$CS_VERSION  //  an $($C.Orange)RTCO LABS$($C.Muted) project$($C.Reset)"
    Write-Host ''
}

Write-Step 'Scanning this system'

if ($PSVersionTable.PSVersion.Major -ge 7) { Write-Have "PowerShell $($PSVersionTable.PSVersion)" }
else { Write-Warn2 "PowerShell $($PSVersionTable.PSVersion) - 5.1 works, but PowerShell 7 renders the theme better" }

$gpu = Get-GpuInfo
if ($gpu) {
    Write-Have "GPU: $($gpu.Name)  $($C.Bold)$($gpu.VramGB) GB$($C.Reset)  ($($gpu.Vendor), $($gpu.Backend) backend)"
} else {
    Write-Warn2 'No GPU with reportable VRAM found - will run on CPU (slow but functional)'
    $gpu = [PSCustomObject]@{ Name='(none)'; VramGB=0; Vendor='None'; Backend='CPU' }
}

$ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
Write-Have "RAM: $ramGB GB"

$drives = @(Get-DriveCandidates -NeedGB 30)
$fastest = $drives | Where-Object Enough | Select-Object -First 1
if (-not $fastest) { Write-Bad 'No fixed drive has 30 GB free. Free up space and re-run.'; return }
foreach ($d in ($drives | Select-Object -First 4)) {
    $mark = if ($d.Letter -eq $fastest.Letter) { "$($C.Lime)<- fastest with room$($C.Reset)" } else { '' }
    Write-Info ("drive {0}:  {1,6:N1} GB free  {2,-10} {3}" -f $d.Letter, $d.FreeGB, $d.Class, $mark)
}

$ollamaExe = Get-OllamaExe
$ollamaVer = Get-OllamaVersion -Exe $ollamaExe
$uvExe     = (Get-Command uv -ErrorAction SilentlyContinue).Source
if (-not $uvExe) { $p = Join-Path $env:USERPROFILE '.local\bin\uv.exe'; if (Test-Path $p) { $uvExe = $p } }
$aiderExe  = Join-Path $env:USERPROFILE '.local\bin\aider.exe'
$aiderVer  = if (Test-Path $aiderExe) { try { (((& $aiderExe --version 2>&1) -join ' ') -replace '.*?(\d+\.\d+\.\d+).*','$1') } catch { $null } } else { $null }
$patchExe  = Get-PatchExe
$gitExe    = (Get-Command git -ErrorAction SilentlyContinue).Source

if ($ollamaVer -and $ollamaVer -ge $MIN_OLLAMA) { Write-Have "Ollama $ollamaVer" }
elseif ($ollamaVer)                             { Write-Need "Ollama $ollamaVer is older than $MIN_OLLAMA - will upgrade" }
else                                            { Write-Need 'Ollama - will download and install (~1.5 GB)' }

if ($uvExe)  { Write-Have "uv ($uvExe)" } else { Write-Need 'uv (Python tool manager) - will install' }
if ($aiderVer -eq $AIDER_VERSION) { Write-Have "aider $aiderVer" }
elseif ($aiderVer)                { Write-Need "aider $aiderVer -> will pin to $AIDER_VERSION (the patches target it)" }
else                              { Write-Need "aider $AIDER_VERSION - will install" }
if ($patchExe) { Write-Have "patch.exe ($patchExe)" } else { Write-Warn2 'patch.exe missing (ships with Git for Windows) - themed spinner will be skipped' }
if ($gitExe)   { Write-Have "git ($gitExe)" }         else { Write-Warn2 'git missing - the sandbox will not be a repo' }

Write-Step 'Choosing a model that fits your card'
$plan = Get-ModelPlan -VramGB $gpu.VramGB
if ($plan.CpuOnly) { Write-Warn2 'Not enough VRAM for GPU inference - falling back to the smallest model.' }
Write-Info 'A model bigger than VRAM does not error - it silently spills into'
Write-Info 'system RAM and runs about 5x slower, so this errs on the small side.'
Write-Ok "Recommended: $($C.Bold)$($plan.Label)$($C.Reset)  $($C.Muted)->$($C.Reset) $($plan.Base)"

if (-not $Model)  { $Model  = $plan.Base }
if (-not $NumCtx) { $NumCtx = $plan.Ctx }
$AgentModel = $plan.Agent
if (-not $Unattended -and -not (Confirm-Step "Use $($plan.Label)?")) {
    $Model      = Read-Default 'Ollama model to pull' $plan.Base
    $NumCtx     = [int](Read-Default 'Context window (num_ctx)' $plan.Ctx)
    $AgentModel = Read-Default 'Name for the local -agent build' $plan.Agent
}

Write-Step 'Choosing locations'
Write-Info "Put both on your fastest drive. Model load time is dominated by disk:"
Write-Info "measured ~9s from NVMe versus ~57s from a spinning HDD."
Write-Ok "Fastest drive with room: $($C.Bold)$($fastest.Letter):$($C.Reset) ($($fastest.Class), $($fastest.FreeGB) GB free)"
if (-not $SandboxPath)    { $SandboxPath    = Read-Default 'Sandbox folder (the ONLY folder the agent may edit)' "$($fastest.Letter):\$SLUG-sandbox" }
if (-not $ModelStorePath) { $ModelStorePath = Read-Default 'Model store (needs 10-25 GB)' "$($fastest.Letter):\$SLUG\models" }

Write-Step 'Ready'
Write-Host "    $($C.Muted)Model      $($C.Reset) $Model"
Write-Host "    $($C.Muted)Local build$($C.Reset) $AgentModel  ($NumCtx ctx)"
Write-Host "    $($C.Muted)Backend    $($C.Reset) $($gpu.Backend)  ($($gpu.Vendor))"
Write-Host "    $($C.Muted)Sandbox    $($C.Reset) $SandboxPath"
Write-Host "    $($C.Muted)Model store$($C.Reset) $ModelStorePath"
Write-Host "    $($C.Muted)aider      $($C.Reset) $AIDER_VERSION (pinned)"
Write-Host "    $($C.Muted)Shortcut   $($C.Reset) Desktop -> '$APP_NAME'"
Write-Host ''
if ($DryRun) { Write-Host "  $($C.Cyan)Dry run - nothing was changed.$($C.Reset)"; return }
if (-not (Confirm-Step 'Install?')) { Write-Bad 'Cancelled.'; return }

if (-not $SrcRoot) {
    Write-Step 'Downloading customizations'
    $tmp = Join-Path $env:TEMP "$SLUG-$(Get-Random)"
    New-Item -ItemType Directory -Force -Path $tmp | Out-Null
    Invoke-WebRequest "https://github.com/Rocketstradingco/$SLUG/archive/refs/heads/main.zip" -OutFile "$tmp\src.zip" -UseBasicParsing
    Expand-Archive "$tmp\src.zip" -DestinationPath $tmp -Force
    $SrcRoot = (Get-ChildItem $tmp -Directory | Select-Object -First 1).FullName
    Write-Ok "fetched to $SrcRoot"
}

Write-Step 'Installing prerequisites'
if (-not $uvExe) {
    Write-Info 'Installing uv...'
    Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
    $uvExe = Join-Path $env:USERPROFILE '.local\bin\uv.exe'
    if (-not (Test-Path $uvExe)) { throw 'uv install failed.' }
    Write-Ok 'uv installed'
} else { Write-Ok 'uv already present' }

if (-not $ollamaVer -or $ollamaVer -lt $MIN_OLLAMA) {
    Write-Info 'Downloading Ollama (~1.5 GB - the long part)...'
    $rel = Invoke-RestMethod 'https://api.github.com/repos/ollama/ollama/releases/latest' -Headers @{'User-Agent'=$SLUG}
    $asset = $rel.assets | Where-Object name -eq 'OllamaSetup.exe' | Select-Object -First 1
    if (-not $asset) { throw 'OllamaSetup.exe not found in the latest release.' }
    $dst = Join-Path $env:TEMP 'OllamaSetup.exe'
    Invoke-WebRequest $asset.browser_download_url -OutFile $dst -UseBasicParsing -TimeoutSec 3600
    Write-Info "Installing Ollama $($rel.tag_name) (silent, per-user)..."
    $p = Start-Process -FilePath $dst -ArgumentList '/SILENT','/SP-','/NOCANCEL','/CLOSEAPPLICATIONS','/FORCECLOSEAPPLICATIONS' -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "Ollama installer exited with $($p.ExitCode)" }
    Remove-Item $dst -Force -ErrorAction SilentlyContinue
    $ollamaExe = Get-OllamaExe
    if (-not $ollamaExe) { throw 'Ollama installed but ollama.exe not found.' }
    Write-Ok 'Ollama installed'
} else { Write-Ok "Ollama $ollamaVer already present" }

if ($aiderVer -ne $AIDER_VERSION) {
    Write-Info "Installing aider $AIDER_VERSION..."
    & $uvExe tool install --force "aider-chat==$AIDER_VERSION" | Out-Null
    if (-not (Test-Path $aiderExe)) { throw 'aider install failed.' }
    Write-Ok "aider $AIDER_VERSION installed"
} else { Write-Ok "aider $AIDER_VERSION already present" }

Write-Step 'Creating folders and configuration'
$cfgDir   = Join-Path $env:USERPROFILE ".config\$SLUG"
$binDir   = Join-Path $env:USERPROFILE '.local\bin'
$patchDir = Join-Path $cfgDir 'patches'
foreach ($d in @($cfgDir,$binDir,$patchDir,$ModelStorePath,$SandboxPath,(Join-Path $SandboxPath '.aider-history-archive'))) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

@"
# Generated by the $APP_NAME installer on $(Get-Date -Format 'yyyy-MM-dd HH:mm').
# Machine-specific values - every script reads these, so nothing hardcodes a
# path. Edit here to move things.
`$global:CS_SANDBOX     = '$SandboxPath'
`$global:CS_MODEL       = '$AgentModel`:latest'
`$global:CS_MODEL_STORE = '$ModelStorePath'
`$global:CS_OLLAMA_EXE  = '$ollamaExe'
`$global:CS_AIDER_EXE   = '$aiderExe'
`$global:CS_NUM_CTX     = $NumCtx
`$global:CS_BACKEND     = '$($gpu.Backend)'
"@ | Set-Content -Path (Join-Path $cfgDir 'cs-env.ps1') -Encoding UTF8

foreach ($f in @('banner.ps1','prompt.ps1','aider-startup.ps1')) {
    Copy-Item (Join-Path $SrcRoot "config\$f") (Join-Path $cfgDir $f) -Force
}
Copy-Item (Join-Path $SrcRoot 'bin\*')     $binDir   -Force
Copy-Item (Join-Path $SrcRoot 'patches\*') $patchDir -Force
Write-Ok "config  -> $cfgDir"
Write-Ok "tools   -> $binDir"

$userPath = [Environment]::GetEnvironmentVariable('PATH','User')
if ($userPath -notlike "*$binDir*") {
    [Environment]::SetEnvironmentVariable('PATH', "$binDir;$userPath", 'User')
    Write-Ok "added $binDir to PATH"
}
$env:PATH = "$binDir;$env:PATH"

Write-Step 'Applying the themed aider patches'
if ($patchExe) {
    & (Join-Path $patchDir 'apply.ps1') | ForEach-Object { Write-Info $_ }
    if ($LASTEXITCODE -eq 0) {
        Write-Ok 'themed spinner + local-only model picker in place'
    } else {
        Write-Warn2 'patches did not apply - aider still works, but with the stock spinner.'
        Write-Warn2 'Retry later with: cyber-scopolamine-patch'
    }
} else {
    Write-Warn2 'patch.exe not found - install Git for Windows, then run: cyber-scopolamine-patch'
    Write-Warn2 'Everything else works; you just get the stock aider spinner.'
}

Write-Step 'Building the sandbox'
$conf = (Get-Content (Join-Path $SrcRoot 'config\aider.conf.yml.template') -Raw).Replace('{{MODEL}}', "$AgentModel`:latest")
$conf | Set-Content -Path (Join-Path $SandboxPath '.aider.conf.yml') -Encoding UTF8
@'
.aider-history-archive/
.aider.chat.history.md
.aider.input.history
.aider.tags.cache.v*/
'@ | Set-Content -Path (Join-Path $SandboxPath '.gitignore') -Encoding UTF8
if ($gitExe -and -not (Test-Path (Join-Path $SandboxPath '.git'))) {
    & git -C $SandboxPath init -b main *>&1 | Out-Null
    Write-Ok 'sandbox initialised as a git repo'
}
Write-Ok "sandbox -> $SandboxPath"

if (-not $SkipModelPull) {
    Write-Step "Downloading the model ($Model)"
    Write-Info 'Several GB. Resumes if interrupted.'
    $env:OLLAMA_MODELS = $ModelStorePath
    $up = $false
    try { Invoke-WebRequest 'http://127.0.0.1:11434/api/tags' -TimeoutSec 3 -UseBasicParsing | Out-Null; $up = $true } catch { }
    if (-not $up) {
        Start-Process -FilePath $ollamaExe -ArgumentList 'serve' -WindowStyle Hidden
        for ($i=0; $i -lt 30; $i++) { Start-Sleep -Seconds 1; try { Invoke-WebRequest 'http://127.0.0.1:11434/api/tags' -TimeoutSec 2 -UseBasicParsing | Out-Null; $up=$true; break } catch { } }
    }
    if (-not $up) { throw 'Ollama did not start - cannot pull the model.' }
    & $ollamaExe pull $Model
    if ($LASTEXITCODE -ne 0) { throw "Model pull failed for $Model" }
    Write-Ok 'model downloaded'

    Write-Step "Building the local variant ($AgentModel, num_ctx $NumCtx)"

    $mf = Join-Path $env:TEMP "$AgentModel.Modelfile"
    "FROM $Model`n`nPARAMETER num_ctx $NumCtx`n" | Set-Content -Path $mf -Encoding ascii
    & $ollamaExe create $AgentModel -f $mf | Out-Null
    Remove-Item $mf -Force -ErrorAction SilentlyContinue
    Write-Ok "created $AgentModel"
}

Write-Step 'Ollama auto-update'
if (-not $KeepOllamaAutoUpdate) {
    Write-Info 'Ollama self-updates silently, and 0.23.x builds crash at startup'
    Write-Info 'on AMD cards - taking the whole agent down with no warning.'
    if (Confirm-Step 'Disable Ollama auto-update? (recommended)') {
        & (Join-Path $binDir 'cyber-scopolamine-noupdate.ps1') | ForEach-Object { Write-Info $_ }
    }
}

Write-Step 'Creating the desktop icon'
$desktop  = [Environment]::GetFolderPath('Desktop')
$lnkPath  = Join-Path $desktop "$APP_NAME.lnk"
$pwshExe  = if (Test-Path "$env:ProgramFiles\PowerShell\7\pwsh.exe") { "$env:ProgramFiles\PowerShell\7\pwsh.exe" } else { "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" }
$wt       = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\wt.exe'
$launcher = Join-Path $binDir 'cyber-scopolamine.ps1'
try {
    $ws  = New-Object -ComObject WScript.Shell
    $lnk = $ws.CreateShortcut($lnkPath)
    if (Test-Path $wt) {
        $lnk.TargetPath = $wt
        $lnk.Arguments  = "-d `"$SandboxPath`" `"$pwshExe`" -NoLogo -NoExit -NoProfile -ExecutionPolicy Bypass -File `"$launcher`""
    } else {
        $lnk.TargetPath = $pwshExe
        $lnk.Arguments  = "-NoLogo -NoExit -NoProfile -ExecutionPolicy Bypass -File `"$launcher`""
    }
    $lnk.WorkingDirectory = $SandboxPath
    $lnk.Description      = "$APP_NAME - local AI coding agent, confined to $SandboxPath"
    $icon = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\app.ico'
    if (Test-Path $icon) { $lnk.IconLocation = "$icon,0" }
    $lnk.Save()
    Write-Ok "created '$lnkPath'"
} catch {
    Write-Warn2 "Could not create the shortcut: $($_.Exception.Message)"
    Write-Warn2 'Start it from a terminal with:  cyber-scopolamine'
}

Write-Host ''
Write-Host "  $($C.Lime)$($C.Bold)Installed.$($C.Reset)"
Write-Host ''
Write-Host "  $($C.Violet)Start$($C.Reset)         double-click $($C.Bold)$APP_NAME$($C.Reset) on your Desktop"
Write-Host "  $($C.Violet)Or$($C.Reset)            run $($C.Cyan)cyber-scopolamine$($C.Reset) in any terminal"
Write-Host "  $($C.Violet)Sandbox$($C.Reset)       $SandboxPath $($C.Muted)(the only folder it can edit)$($C.Reset)"
Write-Host "  $($C.Violet)Model$($C.Reset)         $AgentModel $($C.Muted)($NumCtx ctx, $($gpu.Backend), fully offline)$($C.Reset)"
Write-Host "  $($C.Violet)Old chats$($C.Reset)     $($C.Cyan)cyber-scopolamine-history$($C.Reset) list | view <n> | load <n>"
Write-Host "  $($C.Violet)Status$($C.Reset)        $($C.Cyan)scop$($C.Reset)  (alias for cs-status)"
Write-Host ''
Write-Host "  $($C.Muted)Read the README for what aider vs Ollama means, and the$($C.Reset)"
Write-Host "  $($C.Muted)troubleshooting section if it ever feels slow.$($C.Reset)"
Write-Host ''
