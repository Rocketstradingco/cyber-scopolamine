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
