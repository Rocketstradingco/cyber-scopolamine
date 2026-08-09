$repoRoot = Split-Path -Parent $PSScriptRoot
$historyCommand = Join-Path $repoRoot 'bin\cyber-scopolamine-history.ps1'

Describe 'Cyber-Scopolamine history restore contract' {
    It 'marks a selected archive so the next launch restores it' {
        $profileRoot = Join-Path $TestDrive 'profile'
        $configDirectory = Join-Path $profileRoot '.config\cyber-scopolamine'
        $workspace = Join-Path $TestDrive 'workspace'
        $archive = Join-Path $workspace '.aider-history-archive'
        New-Item -ItemType Directory -Force -Path $configDirectory,$archive | Out-Null
        Set-Content -LiteralPath (Join-Path $archive '20260809-010101-000-a1b2c3d4.md') -Value 'selected chat'

        $config = [ordered]@{
            schemaVersion = 1
            sandbox = $workspace
            model = 'cyscop-7b:latest'
            modelStore = (Join-Path $TestDrive 'models')
            ollamaExe = 'C:\Ollama\ollama.exe'
            aiderExe = 'C:\Aider\aider.exe'
            aiderConfig = (Join-Path $configDirectory 'aider.conf.yml')
            numCtx = 16384
            backend = 'test'
            ollamaHost = '127.0.0.1:11435'
            ollamaEndpoint = 'http://127.0.0.1:11435'
        }
        $config | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $configDirectory 'config.json')

        $oldProfile = $env:USERPROFILE
        try {
            $env:USERPROFILE = $profileRoot
            & $historyCommand load 1 | Out-Null
        } finally {
            $env:USERPROFILE = $oldProfile
        }

        Test-Path -LiteralPath (Join-Path $archive '.restore-pending') | Should Be $true
        (Get-Content -LiteralPath (Join-Path $workspace '.aider.chat.history.md') -Raw).Trim() | Should Be 'selected chat'
    }
}

Describe 'Installed command contract' {
    It 'ships standalone status entry points' {
        Test-Path -LiteralPath (Join-Path $repoRoot 'bin\cyber-scopolamine-status.ps1') | Should Be $true
        Test-Path -LiteralPath (Join-Path $repoRoot 'bin\cyber-scopolamine-status.cmd') | Should Be $true
        Test-Path -LiteralPath (Join-Path $repoRoot 'bin\scop.cmd') | Should Be $true
    }
}
