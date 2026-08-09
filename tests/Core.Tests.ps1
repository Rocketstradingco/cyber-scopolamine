Describe 'Cyber-Scopolamine history restore contract' {
    BeforeEach {
        $script:repoRoot = Split-Path -Parent $PSScriptRoot
        $script:historyCommand = Join-Path $script:repoRoot 'bin\cyber-scopolamine-history.ps1'
    }

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
            & $script:historyCommand load 1 | Out-Null
        } finally {
            $env:USERPROFILE = $oldProfile
        }

        if (-not (Test-Path -LiteralPath (Join-Path $archive '.restore-pending'))) {
            throw 'History restore marker was not created.'
        }
        if ((Get-Content -LiteralPath (Join-Path $workspace '.aider.chat.history.md') -Raw).Trim() -ne 'selected chat') {
            throw 'Selected history was not copied to the active history file.'
        }
    }
}

Describe 'Installed command contract' {
    BeforeEach {
        $script:repoRoot = Split-Path -Parent $PSScriptRoot
    }

    It 'ships standalone status entry points' {
        foreach ($relativePath in @(
            'bin\cyber-scopolamine-status.ps1',
            'bin\cyber-scopolamine-status.cmd',
            'bin\scop.cmd'
        )) {
            if (-not (Test-Path -LiteralPath (Join-Path $script:repoRoot $relativePath))) {
                throw "Missing installed command entry point: $relativePath"
            }
        }
    }
}
