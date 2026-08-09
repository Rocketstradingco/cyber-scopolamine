$repoRoot = Split-Path -Parent $PSScriptRoot
$historyLib = Join-Path $repoRoot 'bin\cyber-scopolamine-history-lib.ps1'
$historyCommand = Join-Path $repoRoot 'bin\cyber-scopolamine-history.ps1'

Describe 'Cyber-Scopolamine history lifecycle' {
    BeforeEach {
        . $historyLib
        $workspace = Join-Path $TestDrive 'workspace'
        $archive = Join-Path $workspace '.aider-history-archive'
        $history = Join-Path $workspace '.aider.chat.history.md'
        $marker = Join-Path $workspace '.aider-history-restore.pending'
        New-Item -ItemType Directory -Force -Path $archive | Out-Null
    }

    It 'creates collision-resistant archive names' {
        $first = New-CsHistoryArchivePath -ArchiveDirectory $archive
        $second = New-CsHistoryArchivePath -ArchiveDirectory $archive
        $first | Should Not Be $second
        [System.IO.Path]::GetExtension($first) | Should Be '.md'
    }

    It 'preserves a selected restore for the next launch' {
        Set-Content -LiteralPath $history -Value 'restored conversation'
        Set-CsPendingHistoryRestore -MarkerPath $marker -ArchiveName 'selected.md'

        $state = Complete-CsHistoryLaunchPreparation -HistoryPath $history -ArchiveDirectory $archive -MarkerPath $marker

        $state | Should Be 'restored'
        (Get-Content -LiteralPath $history -Raw).Trim() | Should Be 'restored conversation'
        Test-Path -LiteralPath $marker | Should Be $false
        @(Get-ChildItem -LiteralPath $archive -File).Count | Should Be 0
    }

    It 'archives an ordinary previous conversation' {
        Set-Content -LiteralPath $history -Value 'previous conversation'

        $state = Complete-CsHistoryLaunchPreparation -HistoryPath $history -ArchiveDirectory $archive -MarkerPath $marker

        $state | Should Be 'archived'
        Test-Path -LiteralPath $history | Should Be $false
        $saved = @(Get-ChildItem -LiteralPath $archive -File)
        $saved.Count | Should Be 1
        (Get-Content -LiteralPath $saved[0].FullName -Raw).Trim() | Should Be 'previous conversation'
    }

    It 'marks history selected by the load command for restoration' {
        $profileRoot = Join-Path $TestDrive 'profile'
        $configDirectory = Join-Path $profileRoot '.config\cyber-scopolamine'
        New-Item -ItemType Directory -Force -Path $configDirectory | Out-Null
        $configuredWorkspace = Join-Path $TestDrive 'command-workspace'
        $configuredArchive = Join-Path $configuredWorkspace '.aider-history-archive'
        New-Item -ItemType Directory -Force -Path $configuredArchive | Out-Null
        Set-Content -LiteralPath (Join-Path $configuredArchive '20260809-010101-000-a1b2c3d4.md') -Value 'selected chat'
        Set-Content -LiteralPath (Join-Path $configDirectory 'cs-env.ps1') -Value "`$global:CS_SANDBOX = '$configuredWorkspace'"
        $oldProfile = $env:USERPROFILE
        try {
            $env:USERPROFILE = $profileRoot
            & $historyCommand load 1 | Out-Null
        } finally {
            $env:USERPROFILE = $oldProfile
        }

        Test-Path -LiteralPath (Join-Path $configuredWorkspace '.aider-history-restore.pending') | Should Be $true
        (Get-Content -LiteralPath (Join-Path $configuredWorkspace '.aider.chat.history.md') -Raw).Trim() | Should Be 'selected chat'
    }
}

Describe 'Installed command contract' {
    It 'ships standalone status entry points' {
        Test-Path -LiteralPath (Join-Path $repoRoot 'bin\cyber-scopolamine-status.ps1') | Should Be $true
        Test-Path -LiteralPath (Join-Path $repoRoot 'bin\cyber-scopolamine-status.cmd') | Should Be $true
        Test-Path -LiteralPath (Join-Path $repoRoot 'bin\scop.cmd') | Should Be $true
    }
}
