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
    $body = $c.White

    try { Clear-Host } catch { }
    Show-CsBanner
    Write-CsPause 500

    $rule = '  ' + ('-' * 66)
    Write-Host "$($c.Plum)$rule$($c.Reset)"
    Write-Host ''
    Write-CsTyped '  SCOPOLAMINE' $c.Violet $d -NoNewline
    Write-CsTyped '  (hyoscine)' $c.Cyan $d -NoNewline
    Write-CsTyped '  //  C17H21NO4' $c.Muted $d
    Write-CsPause 350

    Write-Host ''
    Write-CsTyped '  A ' $body $d -NoNewline
    Write-CsTyped 'deliriant alkaloid' $c.Violet $d -NoNewline
    Write-CsTyped ' from the flower of the ' $body $d -NoNewline
    Write-CsTyped 'Brugmansia' $c.Lime $d -NoNewline
    Write-CsTyped ' tree -' $body $d
    Write-CsTyped '  the ' $body $d -NoNewline
    Write-CsTyped 'borrachero' $c.Lime $d -NoNewline
    Write-CsTyped ', or ' $body $d -NoNewline
    Write-CsTyped "angel's trumpet" $c.Lime $d -NoNewline
    Write-CsTyped ' - that grows across Colombia.' $body $d
    Write-CsTyped '  Street name: ' $body $d -NoNewline
    Write-CsTyped "DEVIL'S BREATH." "$($c.Bold)$($c.Amber)" $d
    Write-CsPause 450

    Write-Host ''
    Write-CsTyped '  Its reputation comes from one specific effect. It does not' $body $d
    Write-CsTyped '  sedate you, and it does not knock you out. You stay ' $body $d -NoNewline
    Write-CsTyped 'awake' $c.Cyan $d -NoNewline
    Write-CsTyped ',' $body $d
    Write-CsTyped '  you stay ' $body $d -NoNewline
    Write-CsTyped 'lucid' $c.Cyan $d -NoNewline
    Write-CsTyped ', you hold a conversation.' $body $d
    Write-CsPause 400
    Write-Host ''
    Write-CsTyped '  What it takes away is your ability to say no.' "$($c.Bold)$($c.Lime)" $d
    Write-CsPause 700

    Write-Host ''
    Write-Host "$($c.Plum)$rule$($c.Reset)"
    Write-Host ''
    Write-CsTyped '  The model running here is ' $body $d -NoNewline
    Write-CsTyped 'abliterated' "$($c.Bold)$($c.Violet)" $d -NoNewline
    Write-CsTyped '. The refusal behaviour has' $body $d
    Write-CsTyped '  been ' $body $d -NoNewline
    Write-CsTyped 'surgically removed from its weights' $c.Violet $d -NoNewline
    Write-CsTyped '. It will not lecture' $body $d
    Write-CsTyped '  you, moralise at you, or decline. It has no capacity left to.' $body $d
    Write-CsPause 400
    Write-Host ''
    Write-CsTyped '  Hence the name.' $c.Muted $d
    Write-CsPause 600

    Write-Host ''
    Write-Host "$($c.Plum)$rule$($c.Reset)"
    Write-Host ''
    Write-CsTyped '  THREE THINGS TO KNOW' "$($c.Bold)$($c.Cyan)" $d
    Write-Host ''
    Write-CsTyped '  1.  ' $c.Violet $d -NoNewline
    Write-CsTyped 'It runs entirely on your own GPU.' $c.Lime $d -NoNewline
    Write-CsTyped ' No API key, no account,' $body $d
    Write-CsTyped '      no cloud, no bill. Unplug the network and it still works.' $body $d
    Write-CsPause 250
    Write-CsTyped '  2.  ' $c.Violet $d -NoNewline
    Write-CsTyped 'It works inside one sandbox folder' $c.Lime $d -NoNewline
    Write-CsTyped ' and starts there, so it' $body $d
    Write-CsTyped '      will not scatter files across your disk. It only edits what' $body $d
    Write-CsTyped '      you add to the chat - a guardrail, not a locked cage.' $body $d
    Write-CsPause 250
    Write-CsTyped '  3.  ' $c.Violet $d -NoNewline
    Write-CsTyped 'It is small, and it will be confidently wrong sometimes.' $c.Lime $d
    Write-CsTyped '      Nothing is auto-committed. ' $body $d -NoNewline
    Write-CsTyped 'Read its edits before you keep them.' $c.Amber $d
    Write-CsPause 500

    Write-Host ''
    Write-Host "$($c.Plum)$rule$($c.Reset)"
    Write-Host ''
    Write-CsTyped '  No guardrails means no guardrails. ' "$($c.Bold)$($c.Amber)" $d -NoNewline
    Write-CsTyped 'What it does is on you.' "$($c.Bold)$($c.Red)" $d
    Write-Host ''
    Write-CsPause 400
    Write-Host "  $($c.Muted)This plays once. Replay any time with $($c.Reset)$($c.Cyan)cyber-scopolamine-intro$($c.Reset)$($c.Muted).$($c.Reset)"
    Write-Host ''
    if (-not $Fast -and (Test-CsCanReadKey)) {
        Write-Host "  $($c.Cyan)Press any key to begin...$($c.Reset)" -NoNewline
        try {
            while ([Console]::KeyAvailable) { $null = [Console]::ReadKey($true) }
            $null = [Console]::ReadKey($true)
        } catch { Start-Sleep -Seconds 2 }
        Write-Host ''
    }
    try { Clear-Host } catch { }
}
