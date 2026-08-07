function global:Enable-CsVirtualTerminal {
    if ($null -ne $script:CsVtOk) { return $script:CsVtOk }

    if ($env:NO_COLOR) {
        $script:CsVtOk = $false
        return $false
    }
    if ($PSStyle -and $Host.UI.SupportsVirtualTerminal -and $PSStyle.OutputRendering -eq 'PlainText') {
        try { $PSStyle.OutputRendering = 'Host' } catch { }
    }

    if ($PSVersionTable.PSVersion.Major -ge 7 -or $env:WT_SESSION) {
        $script:CsVtOk = $true
        return $true
    }
    try {
        if (-not ('Cs.Vt' -as [type])) {
            Add-Type -Namespace Cs -Name Vt -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError=true)]
public static extern IntPtr GetStdHandle(int nStdHandle);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
[DllImport("kernel32.dll", SetLastError=true)]
public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
'@
        }
        $h = [Cs.Vt]::GetStdHandle(-11)
        $mode = 0
        if ([Cs.Vt]::GetConsoleMode($h, [ref]$mode)) {
            $script:CsVtOk = [Cs.Vt]::SetConsoleMode($h, $mode -bor 0x0004)
        } else {
            $script:CsVtOk = $false
        }
    } catch {
        $script:CsVtOk = $false
    }
    return $script:CsVtOk
}

function global:Get-CsPalette {
    if (-not (Enable-CsVirtualTerminal)) {
        return @{
            Reset=''; Bold=''; Violet=''; Plum=''; Cyan=''; Lime=''
            White=''; Muted=''; Amber=''; Red=''; Orange=''
        }
    }
    $e = [char]27
    @{
        Reset  = "$e[0m";                  Bold   = "$e[1m"
        Violet = "$e[38;2;168;85;247m";    Plum   = "$e[38;2;124;58;237m"
        Cyan   = "$e[38;2;108;243;213m";   Lime   = "$e[38;2;200;255;107m"
        White  = "$e[38;2;236;233;225m";   Muted  = "$e[38;2;110;100;130m"
        Amber  = "$e[38;2;255;138;55m";    Red    = "$e[38;2;255;117;104m"
        Orange = "$e[38;2;241;106;22m"
    }
}

function global:Show-CsBanner {
    param([switch]$Compact)

    $c = Get-CsPalette
    $width = try { $Host.UI.RawUI.WindowSize.Width } catch { 100 }
    if ($width -lt 100) { $Compact = $true }

    Write-Host ''

    if (-not $Compact) {
        $cyber = @(
            ' ██████╗██╗   ██╗██████╗ ███████╗██████╗ ',
            '██╔════╝╚██╗ ██╔╝██╔══██╗██╔════╝██╔══██╗',
            '██║      ╚████╔╝ ██████╔╝█████╗  ██████╔╝',
            '██║       ╚██╔╝  ██╔══██╗██╔══╝  ██╔══██╗',
            '╚██████╗   ██║   ██████╔╝███████╗██║  ██║',
            ' ╚═════╝   ╚═╝   ╚═════╝ ╚══════╝╚═╝  ╚═╝'
        )
        $scop = @(
            '███████╗ ██████╗ ██████╗ ██████╗  ██████╗ ██╗      █████╗ ███╗   ███╗██╗███╗   ██╗███████╗',
            '██╔════╝██╔════╝██╔═══██╗██╔══██╗██╔═══██╗██║     ██╔══██╗████╗ ████║██║████╗  ██║██╔════╝',
            '███████╗██║     ██║   ██║██████╔╝██║   ██║██║     ███████║██╔████╔██║██║██╔██╗ ██║█████╗  ',
            '╚════██║██║     ██║   ██║██╔═══╝ ██║   ██║██║     ██╔══██║██║╚██╔╝██║██║██║╚██╗██║██╔══╝  ',
            '███████║╚██████╗╚██████╔╝██║     ╚██████╔╝███████╗██║  ██║██║ ╚═╝ ██║██║██║ ╚████║███████╗',
            '╚══════╝ ╚═════╝ ╚═════╝ ╚═╝      ╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚══════╝'
        )
        foreach ($l in $cyber) { Write-Host "  $($c.Violet)$l$($c.Reset)" }
        foreach ($l in $scop)  { Write-Host "  $($c.Cyan)$l$($c.Reset)" }
        $rule = ([string][char]0x2591) * 30 + ([string][char]0x2592) * 20 + ([string][char]0x2593) * 14
        Write-Host "  $($c.Plum)$rule$($c.Reset)"
        Write-Host "  $($c.Muted)C17H21NO4$($c.Reset)  $($c.Violet)//$($c.Reset)  $($c.White)DEVIL'S BREATH FOR YOUR CODEBASE$($c.Reset)  $($c.Violet)//$($c.Reset)  $($c.Lime)IT CANNOT REFUSE$($c.Reset)"
        Write-Host "  $($c.Muted)local model  //  no api keys  //  no cloud  //  works offline$($c.Reset)"
        Write-Host "  $($c.Muted)an$($c.Reset) $($c.Orange)RTCO LABS$($c.Reset) $($c.Muted)project$($c.Reset)"
    } else {
        Write-Host "  $($c.Violet)╔═╗╦ ╦╔╗ ╔═╗╦═╗$($c.Reset) $($c.Cyan)╔═╗╔═╗╔═╗╔═╗╔═╗╦  ╔═╗╔╦╗╦╔╗╔╔═╗$($c.Reset)"
        Write-Host "  $($c.Violet)║  ╚╦╝╠╩╗║╣ ╠╦╝$($c.Reset) $($c.Cyan)╚═╗║  ║ ║╠═╝║ ║║  ╠═╣║║║║║║║║╣ $($c.Reset)"
        Write-Host "  $($c.Violet)╚═╝ ╩ ╚═╝╚═╝╩╚═$($c.Reset) $($c.Cyan)╚═╝╚═╝╚═╝╩  ╚═╝╩═╝╩ ╩╩ ╩╩╝╚╝╚═╝$($c.Reset)"
        Write-Host "  $($c.Muted)C17H21NO4 // devil's breath for your codebase$($c.Reset)"
        Write-Host "  $($c.Muted)an$($c.Reset) $($c.Orange)RTCO LABS$($c.Reset) $($c.Muted)project$($c.Reset)"
    }
    Write-Host ''
}
