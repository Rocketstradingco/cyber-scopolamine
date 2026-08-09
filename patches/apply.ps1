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

$pkgRoot = $null
$common = Join-Path $env:USERPROFILE '.local\bin\cyber-scopolamine-common.ps1'
if (Test-Path $common) {
    . $common
    Import-CsConfig | Out-Null
    if ($global:CS_AIDER_EXE -and (Test-Path $global:CS_AIDER_EXE)) {
        $scripts = Split-Path -Parent $global:CS_AIDER_EXE
        $candidate = Join-Path (Split-Path -Parent $scripts) 'Lib\site-packages'
        if (Test-Path (Join-Path $candidate 'aider')) { $pkgRoot = $candidate }
    }
}
if (-not $pkgRoot) {
    $venv = Join-Path $env:USERPROFILE '.config\cyber-scopolamine\aider-env\Lib\site-packages'
    if (Test-Path (Join-Path $venv 'aider')) { $pkgRoot = $venv }
}

if (-not $pkgRoot) {
    Write-Error "Could not find the private aider package. Re-run install.ps1."
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
$applied = 0; $already = 0; $failed = 0
Push-Location $pkgRoot
try {
    foreach ($p in $patches) {
        $file = Join-Path $here $p
        $args = @('-p1', '--forward', '-r', '-', '--binary')
        if ($Revert) { $args += '--reverse' }
        Write-Host "  $p" -NoNewline
        $out = & $patchExe @args -i $file 2>&1
        $text = ($out | Out-String)
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ok" -ForegroundColor Green
            $applied++
        } elseif ($text -match 'previously applied|Reversed \(or previously applied\)') {
            Write-Host "  already applied" -ForegroundColor Cyan
            $already++
        } else {
            Write-Host "  FAILED" -ForegroundColor Red
            $out | ForEach-Object { "    $_" }
            $failed++
        }
    }
} finally {
    Pop-Location
}

Write-Host ''
if ($failed -gt 0) {
    Write-Host "$failed patch(es) failed - aider works, but without the themed spinner." -ForegroundColor Red
    Write-Host "This usually means aider is not the pinned version the patches target."
    exit 1
}
Write-Host "Done ($applied applied, $already already in place)."
Write-Host "The themed waiting animation shows on the next run, and '/model'"
Write-Host "lists only your local models instead of thousands of cloud ones."
