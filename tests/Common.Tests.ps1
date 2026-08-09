Describe 'Cyber-Scopolamine inert configuration' {
    BeforeEach {
        . (Join-Path (Split-Path -Parent $PSScriptRoot) 'bin\cyber-scopolamine-common.ps1')
    }

    It 'round-trips paths with spaces, apostrophes, and Unicode as JSON data' {
        $path = Join-Path $TestDrive 'config.json'
        $value = [ordered]@{
            schemaVersion = 1
            sandbox = "C:\Users\O'Brien\données workspace"
            model = 'cyscop-7b:latest'
            modelStore = "D:\Model Store\O'Brien"
        }
        Write-CsJsonFile -Path $path -Value $value
        $loaded = Read-CsJsonFile -Path $path
        if ($loaded.sandbox -ne $value.sandbox) { throw 'Sandbox path did not round-trip through JSON.' }
        if ($loaded.modelStore -ne $value.modelStore) { throw 'Model-store path did not round-trip through JSON.' }
    }

    It 'rejects an unsupported config schema' {
        $path = Join-Path $TestDrive 'bad-schema.json'
        Write-CsJsonFile -Path $path -Value @{ schemaVersion = 99 }
        $threw = $false
        try { Import-CsConfig -Path $path | Out-Null } catch { $threw = $true }
        if (-not $threw) { throw 'Unsupported config schema was accepted.' }
    }

    It 'does not execute PowerShell text stored in JSON values' {
        $path = Join-Path $TestDrive 'inert.json'
        $payload = "'; throw 'executed'; '"
        Write-CsJsonFile -Path $path -Value @{ schemaVersion = 1; value = $payload }
        if ((Read-CsJsonFile -Path $path).value -ne $payload) { throw 'JSON payload changed or executed.' }
    }
}

Describe 'Cyber-Scopolamine Ollama ownership guard' {
    BeforeEach {
        . (Join-Path (Split-Path -Parent $PSScriptRoot) 'bin\cyber-scopolamine-common.ps1')
    }

    It 'rejects a live PID when the executable does not match' {
        $path = Join-Path $TestDrive 'process.json'
        Write-CsJsonFile -Path $path -Value @{
            schemaVersion = 1
            pid = $PID
            startedAtUtc = (Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
        }
        $owned = Get-CsOwnedOllamaProcess -ProcessStatePath $path -ExpectedExe 'C:\definitely-not-ollama.exe'
        if ($null -ne $owned) { throw 'A process with the wrong executable was accepted as owned.' }
    }

    It 'refuses an occupied endpoint when no owned process validates' {
        Mock Test-CsEndpoint { $true }
        Mock Get-CsOwnedOllamaProcess { $null }
        $threw = $false
        try { Assert-CsDedicatedEndpointAvailable -Endpoint 'http://127.0.0.1:11435' -ExpectedExe 'C:\ollama.exe' } catch { $threw = $true }
        if (-not $threw) { throw 'An unowned occupied endpoint was accepted.' }
    }
}
