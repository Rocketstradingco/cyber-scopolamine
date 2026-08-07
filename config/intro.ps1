function global:Test-CsCanReadKey {
    if ($null -ne $script:CsCanReadKey) { return $script:CsCanReadKey }
    try { $null = [Console]::KeyAvailable; $script:CsCanReadKey = $true }
    catch { $script:CsCanReadKey = $false }
    return $script:CsCanReadKey
}

function global:Write-CsTyped {
    param(
        [string]$Text,
        [string]$Color = '',
        [int]$DelayMs = 12,
        [switch]$NoNewline
    )
    $c = Get-CsPalette
    if ($Color) { Write-Host -NoNewline $Color }
    foreach ($ch in $Text.ToCharArray()) {
        Write-Host -NoNewline $ch
        if ($DelayMs -gt 0) {
            Start-Sleep -Milliseconds $DelayMs
            if ((Test-CsCanReadKey) -and [Console]::KeyAvailable) {
                $null = [Console]::ReadKey($true)
                $script:CsIntroSkip = $true
                $DelayMs = 0
            }
        }
    }
    if ($Color) { Write-Host -NoNewline $c.Reset }
    if (-not $NoNewline) { Write-Host '' }
}

function global:Write-CsPause {
    param([int]$Ms = 400)
    if ($script:CsIntroSkip) { return }
    $steps = [math]::Max(1, [int]($Ms / 40))
    for ($i = 0; $i -lt $steps; $i++) {
        Start-Sleep -Milliseconds 40
        if ((Test-CsCanReadKey) -and [Console]::KeyAvailable) {
            $null = [Console]::ReadKey($true)
            $script:CsIntroSkip = $true
            return
        }
    }
}

function global:Show-CsIntro {
    param([switch]$Fast)

    $c = Get-CsPalette
    $script:CsIntroSkip = [bool]$Fast
    $d = if ($Fast) { 0 } else { 10 }

    try { Clear-Host } catch { }
    Show-CsBanner
    Write-CsPause 500

    Write-Host "  $($c.Muted)$('-' * 66)$($c.Reset)"
    Write-Host ''
    Write-CsTyped '  SCOPOLAMINE' $c.Violet $d -NoNewline
    Write-CsTyped '  (hyoscine)  //  C17H21NO4' $c.Muted $d
    Write-CsPause 350

    Write-Host ''
    Write-CsTyped '  A deliriant alkaloid from the flower of the Brugmansia tree -' '' $d
    Write-CsTyped '  the borrachero, or angel' '' $d -NoNewline
    Write-CsTyped "'s trumpet - that grows across Colombia." '' $d
    Write-CsTyped '  Street name: DEVIL' $c.White $d -NoNewline
    Write-CsTyped "'S BREATH." $c.White $d
    Write-CsPause 450

    Write-Host ''
    Write-CsTyped '  Its reputation comes from one specific effect. It does not' '' $d
    Write-CsTyped '  sedate you, and it does not knock you out. You stay awake,' '' $d
    Write-CsTyped '  you stay lucid, you hold a conversation.' '' $d
    Write-CsPause 400
    Write-Host ''
    Write-CsTyped '  What it takes away is your ability to say no.' $c.Lime $d
    Write-CsPause 700

    Write-Host ''
    Write-Host "  $($c.Muted)$('-' * 66)$($c.Reset)"
    Write-Host ''
    Write-CsTyped '  The model running here is ' '' $d -NoNewline
    Write-CsTyped 'abliterated' $c.Violet $d -NoNewline
    Write-CsTyped '. The refusal behaviour has' '' $d
    Write-CsTyped '  been surgically removed from its weights. It will not lecture' '' $d
    Write-CsTyped '  you, moralise at you, or decline. It has no capacity left to.' '' $d
    Write-CsPause 400
    Write-Host ''
    Write-CsTyped '  Hence the name.' $c.Muted $d
    Write-CsPause 600

    Write-Host ''
    Write-Host "  $($c.Muted)$('-' * 66)$($c.Reset)"
    Write-Host ''
    Write-CsTyped '  THREE THINGS TO KNOW' $c.Cyan $d
    Write-Host ''
    Write-CsTyped '  1.  It runs entirely on your own GPU. No API key, no account,' '' $d
    Write-CsTyped '      no cloud, no bill. Unplug the network and it still works.' '' $d
    Write-CsPause 250
    Write-CsTyped '  2.  It works inside one sandbox folder and starts there, so it' '' $d
    Write-CsTyped '      will not scatter files across your disk. It only edits what' '' $d
    Write-CsTyped '      you add to the chat - a guardrail, not a locked cage.' '' $d
    Write-CsPause 250
    Write-CsTyped '  3.  It is small, and it will be confidently wrong sometimes.' '' $d
    Write-CsTyped '      Nothing is auto-committed. Read its edits before you keep them.' '' $d
    Write-CsPause 500

    Write-Host ''
    Write-Host "  $($c.Muted)$('-' * 66)$($c.Reset)"
    Write-Host ''
    Write-CsTyped '  No guardrails means no guardrails. What it does is on you.' $c.Amber $d
    Write-Host ''
    Write-CsPause 400
    Write-Host "  $($c.Muted)This plays once. Replay any time with $($c.Reset)$($c.Cyan)cyber-scopolamine-intro$($c.Reset)$($c.Muted).$($c.Reset)"
    Write-Host ''
    if (-not $Fast -and (Test-CsCanReadKey)) {
        Write-Host "  $($c.Muted)Press any key to begin...$($c.Reset)" -NoNewline
        try {
            while ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true) }
            $null = [Console]::ReadKey($true)
        } catch { Start-Sleep -Seconds 2 }
        Write-Host ''
    }
    try { Clear-Host } catch { }
}
