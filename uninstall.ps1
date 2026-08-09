[CmdletBinding()]
param([switch]$Force, [switch]$DryRun)

$script = Join-Path $PSScriptRoot 'bin\cyber-scopolamine-uninstall.ps1'
& $script -Force:$Force -DryRun:$DryRun
exit $LASTEXITCODE
