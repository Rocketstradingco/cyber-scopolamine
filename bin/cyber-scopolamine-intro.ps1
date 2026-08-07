param([switch]$Fast)

$ErrorActionPreference = 'Stop'

$cfg = Join-Path $env:USERPROFILE '.config\cyber-scopolamine'
foreach ($f in @('banner.ps1','intro.ps1')) {
    $p = Join-Path $cfg $f
    if (-not (Test-Path $p)) {
        Write-Host "Cyber-Scopolamine is not configured ($p missing). Re-run install.ps1." -ForegroundColor Red
        return
    }
    . $p
}

Show-CsIntro -Fast:$Fast
