[CmdletBinding()]
param(
    [switch]$Unattended,
    [switch]$DryRun,
    [string]$SandboxPath,
    [string]$ModelStorePath,
    [string]$Model,
    [string]$AgentModel,
    [int]$NumCtx,
    [ValidateRange(1024,65535)][int]$OllamaPort = 11435,
    [switch]$SkipModelPull,
    [switch]$DisableOllamaAutoUpdate,
    [switch]$UseExistingSandbox
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$AIDER_VERSION = '0.86.2'
$MIN_OLLAMA    = [version]'0.32.6'
$CS_VERSION    = '1.0.0'
$APP_NAME      = 'Cyber-Scopolamine'
$SLUG          = 'cyber-scopolamine'

function Enable-VirtualTerminal {
    if ($env:NO_COLOR) { return $false }
    if ($PSStyle -and $Host.UI.SupportsVirtualTerminal -and $PSStyle.OutputRendering -eq 'PlainText') {
        try { $PSStyle.OutputRendering = 'Host' } catch { }
    }
    if ($PSVersionTable.PSVersion.Major -ge 7 -or $env:WT_SESSION) { return $true }
    try {
        if (-not ('Cs.Vt' -as [type])) {
            Add-Type -Namespace Cs -Name Vt -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true)]
public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@
        }
        $h = [Cs.Vt]::GetStdHandle(-11)
        $mode = 0
        if ([Cs.Vt]::GetConsoleMode($h, [ref]$mode)) {
            return [Cs.Vt]::SetConsoleMode($h, $mode -bor 0x0004)
        }
    } catch { }
    return $false
}

if (Enable-VirtualTerminal) {
    $e = [char]27
    $C = @{
        Reset="$e[0m"; Bold="$e[1m"
        Violet="$e[38;2;168;85;247m"; Plum="$e[38;2;124;58;237m"
        Cyan="$e[38;2;108;243;213m";  Lime="$e[38;2;200;255;107m"
        White="$e[38;2;236;233;225m"; Muted="$e[38;2;110;100;130m"
        Amber="$e[38;2;255;138;55m";  Red="$e[38;2;255;117;104m"
        Orange="$e[38;2;241;106;22m"
    }
} else {
    $C = @{
        Reset=''; Bold=''; Violet=''; Plum=''; Cyan=''; Lime=''
        White=''; Muted=''; Amber=''; Red=''; Orange=''
    }
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
        if ($bus -in @('USB','SD','MMC')) { continue }

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

function Get-ExistingOllamaStore {
    foreach ($scope in @('User','Machine')) {
        $v = [Environment]::GetEnvironmentVariable('OLLAMA_MODELS', $scope)
        if ($v -and (Test-Path $v)) { return @{ Path=$v; Source="OLLAMA_MODELS ($scope environment variable)" } }
    }
    $log = Join-Path $env:LOCALAPPDATA 'Ollama\server.log'
    if (Test-Path $log) {
        $hit = Select-String -Path $log -Pattern 'OLLAMA_MODELS:(\S+)' -ErrorAction SilentlyContinue |
               Select-Object -Last 1
        if ($hit -and $hit.Matches[0].Groups[1].Value) {
            $p = $hit.Matches[0].Groups[1].Value.TrimEnd(']','"',',').Replace('\\','\')
            if (Test-Path $p) { return @{ Path=$p; Source='the Ollama server currently in use' } }
        }
    }
    $def = Join-Path $env:USERPROFILE '.ollama\models'
    if (Test-Path (Join-Path $def 'manifests')) { return @{ Path=$def; Source="Ollama's default location" } }
    return $null
}

function Get-RunningOllamaStore {
    $log = Join-Path $env:LOCALAPPDATA 'Ollama\server.log'
    if (-not (Test-Path $log)) { return $null }
    $hit = Select-String -Path $log -Pattern 'OLLAMA_MODELS:(\S+)' -ErrorAction SilentlyContinue | Select-Object -Last 1
    if (-not $hit) { return $null }
    return $hit.Matches[0].Groups[1].Value.TrimEnd(']','"',',').Replace('\\','\')
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

function Resolve-CsPath {
    param([Parameter(Mandatory=$true)][string]$Path, [string]$Label = 'Path')
    if ([string]::IsNullOrWhiteSpace($Path)) { throw "$Label cannot be empty." }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim())
    if (-not [IO.Path]::IsPathRooted($expanded)) { throw "$Label must be an absolute path: $Path" }
    $full = [IO.Path]::GetFullPath($expanded).TrimEnd('\')
    $root = [IO.Path]::GetPathRoot($full).TrimEnd('\')
    if ($full.Equals($root, [StringComparison]::OrdinalIgnoreCase)) { throw "$Label cannot be a drive root: $full" }
    return $full
}

function Test-CsPathOverlap {
    param([string]$Left, [string]$Right)
    $a = $Left.TrimEnd('\')
    $b = $Right.TrimEnd('\')
    return $a.Equals($b, [StringComparison]::OrdinalIgnoreCase) -or
           $a.StartsWith($b + '\', [StringComparison]::OrdinalIgnoreCase) -or
           $b.StartsWith($a + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Invoke-CsNative {
    param([Parameter(Mandatory=$true)][string]$FilePath, [string[]]$Arguments, [string]$FailureMessage)
    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        if (-not $FailureMessage) { $FailureMessage = "$FilePath failed" }
        throw "$FailureMessage (exit code $LASTEXITCODE)."
    }
}

$SrcRoot = if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot 'config\banner.ps1'))) { $PSScriptRoot } else { $null }
if ($SrcRoot) {
    . (Join-Path $SrcRoot 'bin\cyber-scopolamine-common.ps1')
    . (Join-Path $SrcRoot 'config\banner.ps1')
    Show-CsBanner
} else {
    Write-Host ''
    Write-Host "  $($C.Violet)$($C.Bold)CYBER-SCOPOLAMINE$($C.Reset)  $($C.Muted)installer v$CS_VERSION  //  an $($C.Orange)RTCO LABS$($C.Muted) project$($C.Reset)"
    Write-Host ''
    Write-Host "  $($C.Red)This installer could not find the files it needs.$($C.Reset)"
    Write-Host ''
    Write-Host "  install.ps1 has to sit next to the config\, bin\ and patches\"
    Write-Host "  folders it installs. It looks like it was run on its own."
    Write-Host ''
    Write-Host "  $($C.Cyan)Fix:$($C.Reset) extract the whole cyber-scopolamine folder from the ZIP,"
    Write-Host "  then double-click $($C.Bold)Install Cyber-Scopolamine.bat$($C.Reset) inside it."
    Write-Host ''
    Write-Host "  $($C.Muted)The installer needs the complete repository folder; it cannot run$($C.Reset)"
    Write-Host "  $($C.Muted)as a standalone script. See INSTALL.txt for step-by-step instructions.$($C.Reset)"
    Write-Host ''
    return
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
$aiderExe  = Join-Path $env:USERPROFILE ".config\$SLUG\aider-env\Scripts\aider.exe"
$aiderVer  = if (Test-Path $aiderExe) { try { (((& $aiderExe --version 2>&1) -join ' ') -replace '.*?(\d+\.\d+\.\d+).*','$1') } catch { $null } } else { $null }
$patchExe  = Get-PatchExe
$gitExe    = (Get-Command git -ErrorAction SilentlyContinue).Source

$existingStore = Get-ExistingOllamaStore
if ($existingStore) {
    Write-Have "Ollama model store: $($existingStore.Path)"
    Write-Info "found via $($existingStore.Source) - will be shared, not replaced"
}

if ($ollamaVer -and $ollamaVer -ge $MIN_OLLAMA) { Write-Have "Ollama $ollamaVer" }
elseif ($ollamaVer)                             { Write-Need "Ollama $ollamaVer is older than $MIN_OLLAMA - will upgrade" }
else                                            { Write-Need 'Ollama - will download and install (~1.5 GB)' }

if ($uvExe)  { Write-Have "uv ($uvExe)" } else { Write-Need 'uv (Python tool manager) - will install' }
if ($aiderVer -eq $AIDER_VERSION) { Write-Have "private aider $aiderVer" }
elseif ($aiderVer)                { Write-Need "private aider $aiderVer -> will pin to $AIDER_VERSION (the patches target it)" }
else                              { Write-Need "private aider $AIDER_VERSION - will install" }
if ($patchExe) { Write-Have "patch.exe ($patchExe)" } else { Write-Warn2 'patch.exe missing (ships with Git for Windows) - themed spinner will be skipped' }
if ($gitExe)   { Write-Have "git ($gitExe)" }         else { Write-Warn2 'git missing - the workspace will not be a repo' }

Write-Step 'Choosing a model that fits your card'
$plan = Get-ModelPlan -VramGB $gpu.VramGB
if ($plan.CpuOnly) { Write-Warn2 'Not enough VRAM for GPU inference - falling back to the smallest model.' }
Write-Info 'A model bigger than VRAM does not error - it silently spills into'
Write-Info 'system RAM and runs about 5x slower, so this errs on the small side.'
Write-Ok "Recommended: $($C.Bold)$($plan.Label)$($C.Reset)  $($C.Muted)->$($C.Reset) $($plan.Base)"

if (-not $Model)      { $Model = $plan.Base }
if (-not $NumCtx)     { $NumCtx = $plan.Ctx }
if (-not $AgentModel) { $AgentModel = $plan.Agent }
if (-not $Unattended -and -not (Confirm-Step "Use $($plan.Label)?")) {
    $Model      = Read-Default 'Ollama model to pull' $plan.Base
    $NumCtx     = [int](Read-Default 'Context window (num_ctx)' $plan.Ctx)
    $AgentModel = Read-Default 'Name for the local -agent build' $plan.Agent
}
if ($NumCtx -lt 512 -or $NumCtx -gt 131072) { throw 'Context window must be between 512 and 131072.' }
$modelPattern = '^[A-Za-z0-9][A-Za-z0-9._/-]*(?::[A-Za-z0-9][A-Za-z0-9._-]*)?$'
if ($Model -notmatch $modelPattern) { throw "Invalid Ollama model reference: $Model" }
if ($AgentModel -notmatch $modelPattern) { throw "Invalid local model reference: $AgentModel" }
$AgentModelRef = if ($AgentModel -match ':') { $AgentModel } else { "$AgentModel`:latest" }

Write-Step 'Choosing locations'
Write-Info "Put both on your fastest drive. Model load time is dominated by disk:"
Write-Info "measured ~9s from NVMe versus ~57s from a spinning HDD."
Write-Ok "Fastest drive with room: $($C.Bold)$($fastest.Letter):$($C.Reset) ($($fastest.Class), $($fastest.FreeGB) GB free)"
if (-not $SandboxPath) { $SandboxPath = Read-Default 'Workspace folder (the agent starts and normally works here)' "$($fastest.Letter):\$SLUG-sandbox" }

if (-not $ModelStorePath) {
    if ($existingStore) {
        Write-Info 'You already have an Ollama model store. Sharing it means your'
        Write-Info 'existing models keep working and nothing gets downloaded twice.'
        $ModelStorePath = Read-Default 'Model store' $existingStore.Path
    } else {
        $ModelStorePath = Read-Default 'Model store (needs 10-25 GB)' "$($fastest.Letter):\$SLUG\models"
    }
}
$SandboxPath = Resolve-CsPath -Path $SandboxPath -Label 'Workspace path'
$ModelStorePath = Resolve-CsPath -Path $ModelStorePath -Label 'Model store path'
if (Test-CsPathOverlap -Left $SandboxPath -Right $ModelStorePath) {
    throw 'Workspace and model store paths must be separate and cannot contain one another.'
}
$cfgDirPreview = Join-Path $env:USERPROFILE ".config\$SLUG"
if ((Test-CsPathOverlap -Left $SandboxPath -Right $cfgDirPreview) -or
    (Test-CsPathOverlap -Left $ModelStorePath -Right $cfgDirPreview)) {
    throw 'Workspace and model store paths cannot overlap the Cyber-Scopolamine config directory.'
}
$existingConfig = Read-CsJsonFile -Path (Join-Path $cfgDirPreview 'config.json')
$sandboxWasNonEmpty = (Test-Path -LiteralPath $SandboxPath -PathType Container) -and
    @(Get-ChildItem -LiteralPath $SandboxPath -Force -ErrorAction SilentlyContinue).Count -gt 0
if ($sandboxWasNonEmpty -and
    -not $UseExistingSandbox -and
    -not ($existingConfig -and ([string]$existingConfig.sandbox).Equals($SandboxPath, [StringComparison]::OrdinalIgnoreCase))) {
    throw "Workspace is not empty: $SandboxPath. Re-run with -UseExistingSandbox to use it without changing existing project files."
}
$OllamaHost = "127.0.0.1:$OllamaPort"
$OllamaEndpoint = "http://$OllamaHost"

Write-Step 'Ready'
Write-Host "    $($C.Muted)Model      $($C.Reset) $Model"
Write-Host "    $($C.Muted)Local build$($C.Reset) $AgentModelRef  ($NumCtx ctx)"
Write-Host "    $($C.Muted)Backend    $($C.Reset) $($gpu.Backend)  ($($gpu.Vendor))"
Write-Host "    $($C.Muted)Workspace  $($C.Reset) $SandboxPath"
Write-Host "    $($C.Muted)Model store$($C.Reset) $ModelStorePath"
Write-Host "    $($C.Muted)Endpoint   $($C.Reset) $OllamaEndpoint  (dedicated)"
Write-Host "    $($C.Muted)aider      $($C.Reset) $AIDER_VERSION (pinned)"
Write-Host "    $($C.Muted)Shortcut   $($C.Reset) Desktop -> '$APP_NAME'"
Write-Host ''
if ($DryRun) { Write-Host "  $($C.Cyan)Dry run - nothing was changed.$($C.Reset)"; return }
if (-not (Confirm-Step 'Install?')) { Write-Bad 'Cancelled.'; return }

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

$cfgDir  = Join-Path $env:USERPROFILE ".config\$SLUG"
$venvDir = Join-Path $cfgDir 'aider-env'
New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null

$privateAider = Join-Path $venvDir 'Scripts\aider.exe'
$havePrivate  = $false
if (Test-Path $privateAider) {
    try {
        $privateVersionText = ((& $privateAider --version 2>&1) -join ' ')
        if ($LASTEXITCODE -eq 0 -and $privateVersionText -match '(\d+\.\d+\.\d+)') {
            $havePrivate = ([version]$Matches[1] -eq [version]$AIDER_VERSION)
        }
    } catch { }
}

if ($havePrivate) {
    Write-Ok "private aider $AIDER_VERSION already present"
} else {
    Write-Info "Installing a private aider $AIDER_VERSION into $venvDir ..."
    & $uvExe venv $venvDir 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "uv could not create the private environment (exit code $LASTEXITCODE)." }
    $venvPy = Join-Path $venvDir 'Scripts\python.exe'
    if (-not (Test-Path $venvPy)) { throw "Could not create the private environment at $venvDir" }
    & $uvExe pip install --python $venvPy "aider-chat==$AIDER_VERSION" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "uv could not install aider $AIDER_VERSION (exit code $LASTEXITCODE)." }
    if (-not (Test-Path $privateAider)) { throw 'Private aider install failed.' }
    $installedAiderText = ((& $privateAider --version 2>&1) -join ' ')
    if ($LASTEXITCODE -ne 0 -or $installedAiderText -notmatch '(\d+\.\d+\.\d+)' -or
        [version]$Matches[1] -ne [version]$AIDER_VERSION) {
        throw "Private aider version verification failed: $installedAiderText"
    }
    Write-Ok "private aider $AIDER_VERSION installed (your own aider is unchanged)"
}
$aiderExe = $privateAider

Write-Step 'Creating folders and configuration'
$cfgDir   = Join-Path $env:USERPROFILE ".config\$SLUG"
$binDir   = Join-Path $env:USERPROFILE '.local\bin'
$patchDir = Join-Path $cfgDir 'patches'
foreach ($d in @($cfgDir,$binDir,$patchDir,$ModelStorePath,$SandboxPath,(Join-Path $SandboxPath '.aider-history-archive'))) {
    New-Item -ItemType Directory -Force -Path $d | Out-Null
}

$aiderConfig = Join-Path $cfgDir 'aider.conf.yml'
$configPath = Join-Path $cfgDir 'config.json'
$statePath = Join-Path $cfgDir 'install-state.json'
$processStatePath = Join-Path $cfgDir 'ollama-process.json'

if ($existingConfig -and
    (([string]$existingConfig.modelStore -ne $ModelStorePath) -or
     ([string]$existingConfig.ollamaEndpoint -ne $OllamaEndpoint) -or
     ([string]$existingConfig.ollamaExe -ne [string]$ollamaExe))) {
    $global:CS_OLLAMA_EXE = [string]$existingConfig.ollamaExe
    Stop-CsOwnedOllama -ProcessStatePath $processStatePath -ExpectedExe $global:CS_OLLAMA_EXE | Out-Null
}

$config = [ordered]@{
    schemaVersion = 1
    appVersion = $CS_VERSION
    sandbox = $SandboxPath
    model = $AgentModelRef
    modelStore = $ModelStorePath
    ollamaExe = [IO.Path]::GetFullPath($ollamaExe)
    aiderExe = [IO.Path]::GetFullPath($aiderExe)
    aiderConfig = $aiderConfig
    numCtx = $NumCtx
    backend = $gpu.Backend
    ollamaHost = $OllamaHost
    ollamaEndpoint = $OllamaEndpoint
}
Write-CsJsonFile -Path $configPath -Value $config
$legacyEnv = Join-Path $cfgDir 'cs-env.ps1'
if (Test-Path -LiteralPath $legacyEnv) { Remove-Item -LiteralPath $legacyEnv -Force }
Import-CsConfig -Path $configPath | Out-Null

foreach ($f in @('banner.ps1','prompt.ps1','aider-startup.ps1','intro.ps1')) {
    Copy-Item (Join-Path $SrcRoot "config\$f") (Join-Path $cfgDir $f) -Force
}
$conf = (Get-Content (Join-Path $SrcRoot 'config\aider.conf.yml.template') -Raw).Replace('{{MODEL}}', $AgentModelRef)
[System.IO.File]::WriteAllText($aiderConfig, $conf, (New-Object System.Text.UTF8Encoding($false)))
$iconSrc = Join-Path $SrcRoot 'assets\cyber-scopolamine.ico'
$iconDst = Join-Path $cfgDir 'cyber-scopolamine.ico'
if (Test-Path $iconSrc) { Copy-Item $iconSrc $iconDst -Force }
Copy-Item (Join-Path $SrcRoot 'bin\*')     $binDir   -Force
Copy-Item (Join-Path $SrcRoot 'patches\*') $patchDir -Force
Write-Ok "config  -> $cfgDir"
Write-Ok "tools   -> $binDir"

$previousState = Read-CsJsonFile -Path $statePath
$userPath = [Environment]::GetEnvironmentVariable('PATH','User')
$userPathEntries = @($userPath -split [IO.Path]::PathSeparator | Where-Object { $_ })
$pathAddedNow = -not [bool]($userPathEntries | Where-Object {
    try { [IO.Path]::GetFullPath($_).TrimEnd('\').Equals([IO.Path]::GetFullPath($binDir).TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase) }
    catch { $false }
})
if ($pathAddedNow) {
    [Environment]::SetEnvironmentVariable('PATH', "$binDir;$userPath", 'User')
    Write-Ok "added $binDir to PATH"
}
$env:PATH = "$binDir;$env:PATH"

$pathOwned = $pathAddedNow -or [bool]($previousState -and $previousState.pathAdded)
$updaterState = if ($previousState -and $previousState.updater) { $previousState.updater } else {
    [ordered]@{
        enabled = $false
        trayRenamed = $false
        appExe = (Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama app.exe')
        disabledExe = (Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama app.exe.disabled')
        updatesPath = (Join-Path $env:LOCALAPPDATA 'Ollama\updates_v2')
        updatesDirectoryCreated = $false
        originalUpdatesAclSddl = $null
    }
}
$installState = [ordered]@{
    schemaVersion = 1
    appVersion = $CS_VERSION
    installedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    configPath = $configPath
    binDirectory = $binDir
    desktopShortcut = (Join-Path ([Environment]::GetFolderPath('Desktop')) "$APP_NAME.lnk")
    pathAdded = $pathOwned
    ollamaProcessState = $processStatePath
    updater = $updaterState
}
Write-CsJsonFile -Path $statePath -Value $installState

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

Write-Step 'Preparing the workspace'
$gitIgnore = @'
.aider-history-archive/
.aider.chat.history.md
.aider.input.history
.aider.tags.cache.v*/
'@

$noBom = New-Object System.Text.UTF8Encoding($false)
if ($gitExe -and -not (Test-Path (Join-Path $SandboxPath '.git'))) {
    if ($sandboxWasNonEmpty) {
        Write-Warn2 'existing nonempty workspace is not a git repository - leaving it unchanged'
    } else {
        & $gitExe -C $SandboxPath init -b main *>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "Could not initialise the workspace git repository (exit code $LASTEXITCODE)." }
        Write-Ok 'workspace initialised as a git repo'
    }
}
if (Test-Path -LiteralPath (Join-Path $SandboxPath '.git')) {
    $excludePath = Join-Path $SandboxPath '.git\info\exclude'
    $excludeDir = Split-Path -Parent $excludePath
    New-Item -ItemType Directory -Force -Path $excludeDir | Out-Null
    $existingExclude = if (Test-Path -LiteralPath $excludePath) { Get-Content -LiteralPath $excludePath -Raw } else { '' }
    $missingExcludes = @($gitIgnore -split "`r?`n" | Where-Object {
        $_ -and $existingExclude -notmatch ('(?m)^{0}$' -f [regex]::Escape($_))
    })
    if ($missingExcludes.Count -gt 0) {
        $separator = if ($existingExclude -and -not $existingExclude.EndsWith("`n")) { "`r`n" } else { '' }
        $excludeText = $separator + ($missingExcludes -join "`r`n") + "`r`n"
        [IO.File]::AppendAllText($excludePath, $excludeText, $noBom)
    }
}
Write-Ok "workspace -> $SandboxPath"

if (-not $SkipModelPull) {
    Write-Step "Downloading the model ($Model)"
    Write-Info 'Several GB. Resumes if interrupted.'
    $env:OLLAMA_MODELS = $ModelStorePath
    $env:OLLAMA_HOST = $OllamaHost
    Assert-CsDedicatedEndpointAvailable -Endpoint $OllamaEndpoint -ProcessStatePath $processStatePath -ExpectedExe $ollamaExe
    if (-not (Test-CsEndpoint -Endpoint $OllamaEndpoint)) {
        Start-CsOwnedOllama -Exe $ollamaExe -ModelStore $ModelStorePath -HostAddress $OllamaHost -Endpoint $OllamaEndpoint -ProcessStatePath $processStatePath | Out-Null
    }
    & $ollamaExe pull $Model
    if ($LASTEXITCODE -ne 0) { throw "Model pull failed for $Model" }
    Write-Ok 'model downloaded'

    Write-Step "Building the local variant ($AgentModel, num_ctx $NumCtx)"

    $mf = Join-Path $env:TEMP ("cyber-scopolamine-" + [guid]::NewGuid().ToString('N') + '.Modelfile')
    "FROM $Model`n`nPARAMETER num_ctx $NumCtx`n" | Set-Content -Path $mf -Encoding ascii
    & $ollamaExe create $AgentModelRef -f $mf | Out-Null
    $createExit = $LASTEXITCODE
    Remove-Item $mf -Force -ErrorAction SilentlyContinue
    if ($createExit -ne 0) { throw "Model create failed for $AgentModelRef (exit code $createExit)." }

    $visible = $false
    try {
        $tags = Invoke-RestMethod "$OllamaEndpoint/api/tags" -TimeoutSec 5
        $visible = [bool]($tags.models | Where-Object { $_.name -eq $AgentModelRef })
    } catch { }
    if (-not $visible) {
        throw "Built $AgentModelRef but Ollama cannot see it in $ModelStorePath. The install would fail at first launch, so stopping here."
    }
    Write-Ok "created $AgentModelRef and confirmed Ollama can load it"
} else {
    $env:OLLAMA_MODELS = $ModelStorePath
    $env:OLLAMA_HOST = $OllamaHost
    Assert-CsDedicatedEndpointAvailable -Endpoint $OllamaEndpoint -ProcessStatePath $processStatePath -ExpectedExe $ollamaExe
    if (-not (Test-CsEndpoint -Endpoint $OllamaEndpoint)) {
        Start-CsOwnedOllama -Exe $ollamaExe -ModelStore $ModelStorePath -HostAddress $OllamaHost -Endpoint $OllamaEndpoint -ProcessStatePath $processStatePath | Out-Null
    }
    if (-not (Test-CsModelVisible -Model $AgentModelRef -Endpoint $OllamaEndpoint)) {
        throw "-SkipModelPull was requested, but $AgentModelRef is not present in the configured model store."
    }
    Write-Ok "existing model confirmed: $AgentModelRef"
}

Write-Step 'Ollama auto-update'
if ($DisableOllamaAutoUpdate) {
    Write-Info 'Explicitly disabling Ollama auto-update; this change is recorded and reversible.'
    & (Join-Path $binDir 'cyber-scopolamine-noupdate.ps1') | ForEach-Object { Write-Info $_ }
    if ($LASTEXITCODE -ne 0) { throw "Could not disable Ollama auto-update (exit code $LASTEXITCODE)." }
} else { Write-Ok 'left Ollama auto-update unchanged (use -DisableOllamaAutoUpdate to opt in)' }

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
    $lnk.Description      = "$APP_NAME - local AI coding agent, starting in $SandboxPath"
    if (Test-Path $iconDst) { $lnk.IconLocation = "$iconDst,0" }
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
Write-Host "  $($C.Violet)Or$($C.Reset)            run $($C.Cyan)cyber-scopolamine$($C.Reset) in a $($C.Bold)new$($C.Reset) terminal"
Write-Host "                $($C.Muted)(terminals already open won't have it on PATH yet)$($C.Reset)"
Write-Host "  $($C.Violet)Workspace$($C.Reset)     $SandboxPath $($C.Muted)(default working folder; not OS isolation)$($C.Reset)"
Write-Host "  $($C.Violet)Model$($C.Reset)         $AgentModelRef $($C.Muted)($NumCtx ctx, $($gpu.Backend), fully offline)$($C.Reset)"
Write-Host "  $($C.Violet)Old chats$($C.Reset)     $($C.Cyan)cyber-scopolamine-history$($C.Reset) list | view <n> | load <n>"
Write-Host "  $($C.Violet)Status$($C.Reset)        $($C.Cyan)scop$($C.Reset)  (alias for cs-status)"
Write-Host ''
Write-Host "  $($C.Muted)Read the README for what aider vs Ollama means, and the$($C.Reset)"
Write-Host "  $($C.Muted)troubleshooting section if it ever feels slow.$($C.Reset)"
Write-Host ''
