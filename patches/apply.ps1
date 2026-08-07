# Reapplies the cyberpunk waiting-spinner + local model-picker patches to the
# installed aider-chat package. Needed after any `uv tool upgrade aider-chat`
# / reinstall, since these patches edit installed site-packages files
# directly, not aider's own source.
#
# Windows port of apply.sh. Two differences from the server:
#   - site-packages lives at <tool>\Lib\site-packages, not
#     <tool>/lib/python3.12/site-packages
#   - patch(1) comes from Git for Windows rather than the base system
[CmdletBinding()]
param([switch]$Revert)

$ErrorActionPreference = 'Stop'

$patchExe = @(
    'C:\Program Files\Git\usr\bin\patch.exe',
    'C:\Program Files\Git\bin\patch.exe'
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $patchExe) {
    Write-Error "patch.exe not found - install Git for Windows (it ships usr\bin\patch.exe)."
    exit 1
}

$toolDir = (& (Join-Path $env:USERPROFILE '.local\bin\uv.exe') tool dir).Trim()
$pkgRoot = Join-Path $toolDir 'aider-chat\Lib\site-packages'

if (-not (Test-Path (Join-Path $pkgRoot 'aider'))) {
    Write-Error "Could not find the aider package under $pkgRoot - check your aider-chat install path."
    exit 1
}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$patches = @(
    '0001-waiting-py.patch',
    '0002-base-coder-py.patch',
    '0003-commands-py.patch',
    '0004-io-py.patch'
)

Write-Host "Applying to: $pkgRoot"
Push-Location $pkgRoot
try {
    foreach ($p in $patches) {
        $file = Join-Path $here $p
        $args = @('-p1', '--forward', '-r', '-', '--binary')
        if ($Revert) { $args += '--reverse' }
        Write-Host "  $p" -NoNewline
        $out = & $patchExe @args -i $file 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ok" -ForegroundColor Green
        } else {
            Write-Host "  FAILED" -ForegroundColor Red
            $out | ForEach-Object { "    $_" }
        }
    }
} finally {
    Pop-Location
}

Write-Host ''
Write-Host "Done. Random cyberpunk waiting text should show on next aider run,"
Write-Host "'/model' with no argument lists local Ollama aliases, and"
Write-Host "'/model ' + Tab now arrow-completes through them (cloud models excluded)."
