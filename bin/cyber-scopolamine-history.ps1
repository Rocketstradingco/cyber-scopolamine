[CmdletBinding()]
param(
    [ValidateSet('list','view','load')][string]$Command = 'list',
    [string]$Ref
)

$ErrorActionPreference = 'Stop'

$envFile = Join-Path $env:USERPROFILE '.config\cyber-scopolamine\cs-env.ps1'
if (-not (Test-Path $envFile)) {
    Write-Host "Cyber-Scopolamine is not configured ($envFile missing). Re-run install.ps1." -ForegroundColor Red
    return
}
. $envFile

$Sandbox = $global:CS_SANDBOX
$Archive = Join-Path $Sandbox '.aider-history-archive'
$Hist    = Join-Path $Sandbox '.aider.chat.history.md'
New-Item -ItemType Directory -Force -Path $Archive | Out-Null

function Get-Archived {
    Get-ChildItem -LiteralPath $Archive -Filter '*.md' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending
}
function Resolve-Ref {
    param([string]$R)
    $files = @(Get-Archived)
    if ($R -match '^\d+$') {
        $i = [int]$R
        if ($i -ge 1 -and $i -le $files.Count) { return $files[$i - 1] }
        return $null
    }
    return $files | Where-Object Name -eq $R | Select-Object -First 1
}

switch ($Command) {
    'list' {
        $files = @(Get-Archived)
        if ($files.Count -eq 0) { Write-Host 'No archived conversations yet.'; break }
        Write-Host 'Archived conversations (newest first):'
        $i = 1
        foreach ($f in $files) { '{0,2}  {1}  {2,8:N1} KB' -f $i, $f.Name, ($f.Length / 1KB); $i++ }
    }
    'view' {
        if (-not $Ref) { Write-Error 'Usage: cyber-scopolamine-history view <n|file>'; exit 1 }
        $f = Resolve-Ref $Ref
        if (-not $f) { Write-Error "Not found: $Ref"; exit 1 }
        Get-Content -LiteralPath $f.FullName | Out-Host -Paging
    }
    'load' {
        if (-not $Ref) { Write-Error 'Usage: cyber-scopolamine-history load <n|file>'; exit 1 }
        $f = Resolve-Ref $Ref
        if (-not $f) { Write-Error "Not found: $Ref"; exit 1 }
        if ((Test-Path $Hist) -and (Get-Item $Hist).Length -gt 0) {
            Move-Item -LiteralPath $Hist -Destination (Join-Path $Archive ((Get-Date -Format 'yyyyMMdd-HHmmss') + '.md'))
            Write-Host 'Archived current active history first.'
        }
        Copy-Item -LiteralPath $f.FullName -Destination $Hist
        Write-Host "Loaded $($f.Name) - the next launch in this sandbox will restore it."
    }
}
