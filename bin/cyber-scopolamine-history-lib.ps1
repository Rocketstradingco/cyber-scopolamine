function New-CsHistoryArchivePath {
    param([Parameter(Mandatory=$true)][string]$ArchiveDirectory)

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $suffix = [Guid]::NewGuid().ToString('N').Substring(0, 8)
    Join-Path $ArchiveDirectory "$stamp-$suffix.md"
}

function Save-CsActiveHistory {
    param(
        [Parameter(Mandatory=$true)][string]$HistoryPath,
        [Parameter(Mandatory=$true)][string]$ArchiveDirectory
    )

    if (-not (Test-Path -LiteralPath $HistoryPath)) { return $null }
    if ((Get-Item -LiteralPath $HistoryPath).Length -eq 0) { return $null }

    New-Item -ItemType Directory -Force -Path $ArchiveDirectory | Out-Null
    $destination = New-CsHistoryArchivePath -ArchiveDirectory $ArchiveDirectory
    Move-Item -LiteralPath $HistoryPath -Destination $destination
    return $destination
}

function Set-CsPendingHistoryRestore {
    param(
        [Parameter(Mandatory=$true)][string]$MarkerPath,
        [Parameter(Mandatory=$true)][string]$ArchiveName
    )

    [System.IO.File]::WriteAllText(
        $MarkerPath,
        $ArchiveName,
        (New-Object System.Text.UTF8Encoding($false)))
}

function Complete-CsHistoryLaunchPreparation {
    param(
        [Parameter(Mandatory=$true)][string]$HistoryPath,
        [Parameter(Mandatory=$true)][string]$ArchiveDirectory,
        [Parameter(Mandatory=$true)][string]$MarkerPath
    )

    if ((Test-Path -LiteralPath $MarkerPath) -and
        (Test-Path -LiteralPath $HistoryPath) -and
        (Get-Item -LiteralPath $HistoryPath).Length -gt 0) {
        Remove-Item -LiteralPath $MarkerPath -Force
        return 'restored'
    }

    if (Test-Path -LiteralPath $MarkerPath) {
        Remove-Item -LiteralPath $MarkerPath -Force
    }
    $archived = Save-CsActiveHistory -HistoryPath $HistoryPath -ArchiveDirectory $ArchiveDirectory
    if ($archived) { return 'archived' }
    return 'empty'
}
