[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$cfg = Join-Path $env:USERPROFILE '.config\cyber-scopolamine'
$common = Join-Path $PSScriptRoot 'cyber-scopolamine-common.ps1'
if (-not (Test-Path -LiteralPath $common)) { throw "Runtime helper is missing: $common. Re-run install.ps1." }
. $common
try { Import-CsConfig | Out-Null }
catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 2 }

$bannerFile = Join-Path $cfg 'banner.ps1'
if (Test-Path -LiteralPath $bannerFile) { . $bannerFile }
$c = if (Get-Command Get-CsPalette -ErrorAction SilentlyContinue) { Get-CsPalette } else {
    @{ Reset=''; Bold=''; Violet=''; Lime=''; White=''; Muted=''; Red='' }
}

$os = Get-CimInstance Win32_OperatingSystem

Write-Host ''
Write-Host "$($c.Bold)$($c.White)CYBER-SCOPOLAMINE$($c.Reset)$($c.Muted)  //  STATUS$($c.Reset)"

$gpuName = (Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
            Where-Object { $_.AdapterRAM -gt 0 } | Select-Object -First 1).Name
if ($gpuName) { Write-Host ("$($c.Violet){0,-12}$($c.Reset) {1}" -f 'GPU', $gpuName) }
try {
    $usedMB = ((Get-Counter '\GPU Adapter Memory(*)\Dedicated Usage' -ErrorAction Stop).CounterSamples |
               Measure-Object CookedValue -Sum).Sum / 1MB
    Write-Host ("$($c.Violet){0,-12}$($c.Reset) {1:N0} MB in use" -f 'VRAM', $usedMB)
} catch { }

$model = 'not loaded'
$ollamaUp = Test-CsEndpoint
try {
    $env:OLLAMA_HOST = $global:CS_OLLAMA_HOST
    $ps = & $global:CS_OLLAMA_EXE ps 2>$null | Select-Object -Skip 1
    if ($ps) { $model = ($ps | Select-Object -First 1) -replace '\s{2,}', '  ' }
} catch { }
Write-Host ("$($c.Violet){0,-12}$($c.Reset) {1}" -f 'MODEL', $model)

$col = if ($ollamaUp) { $c.Lime } else { $c.Red }
Write-Host ("$($c.Violet){0,-12}$($c.Reset) $col{1}$($c.Reset)" -f 'OLLAMA', $(if ($ollamaUp) { 'running' } else { 'stopped' }))
Write-Host ("$($c.Violet){0,-12}$($c.Reset) {1}" -f 'ENDPOINT', $global:CS_OLLAMA_ENDPOINT)

if ($global:CS_SANDBOX) {
    Write-Host ("$($c.Violet){0,-12}$($c.Reset) {1}" -f 'WORKSPACE', $global:CS_SANDBOX)
}
if ($global:CS_MODEL_STORE -and (Test-Path -LiteralPath $global:CS_MODEL_STORE)) {
    $driveName = [System.IO.Path]::GetPathRoot($global:CS_MODEL_STORE).TrimEnd('\').TrimEnd(':')
    $drive = Get-PSDrive -Name $driveName -ErrorAction SilentlyContinue
    if ($drive) { Write-Host ("$($c.Violet){0,-12}$($c.Reset) {1}  ({2:N0} GB free)" -f 'MODELS', $global:CS_MODEL_STORE, ($drive.Free/1GB)) }
}
Write-Host ("$($c.Violet){0,-12}$($c.Reset) {1:N1} GB used / {2:N1} GB free" -f 'MEMORY',
    (($os.TotalVisibleMemorySize-$os.FreePhysicalMemory)/1MB), ($os.FreePhysicalMemory/1MB))
Write-Host ''
