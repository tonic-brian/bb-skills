#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Offers to install what mermaid-charts needs, asking once for each item that is missing and installing only on a
    yes: Python, Node.js, the pinned renderer, and an Inkscape that draws Mermaid's styles, at or above the floor
    `inkscape_png.py --plan` names.

.DESCRIPTION
    Asks in order, and only about what is missing. Python comes first, since every tool here is Python: without it
    nothing else can be checked. Node.js is asked about only when the renderer is missing and the Node.js on PATH
    won't do, and a declined or failed Node.js skips the renderer. The commands come from the skill's own tools,
    `mermaid_svg.py plan` and `inkscape_png.py --plan`, which choose one for this machine. Python's come from here:
    the Python Install Manager through winget on Windows, Homebrew's python on macOS. On Linux, Python and Node.js
    are named, never installed: distributions differ, and their Node.js is often older than the renderer needs.

    Each answer comes from -Answer when it names the item, else from the console. With no console and no answer,
    the item is declined. Nothing is remembered: run it again to be asked again.

    Run it as often as you like. It ends with one line per item: already there, installed, declined, named,
    skipped, or failed. It exits 0 for any combination of answers, and 1 when an install it ran failed.

.PARAMETER Check
    Install nothing and ask nothing: exit 0 when nothing is missing, 1 when something is, and 2 on an error.

.PARAMETER Answer
    Answers given ahead, as item=answer: python, node, renderer and inkscape, each yes or no. When no Inkscape
    install was chosen for this machine, inkscape may name one of the offered package managers instead.

.EXAMPLE
    pwsh -NoProfile -File setup.ps1

.EXAMPLE
    pwsh -NoProfile -File setup.ps1 -Answer renderer=yes,inkscape=no
#>
[CmdletBinding()]
param(
    [switch] $Check,
    [string[]] $Answer
)

# Test seams, read only by the functions below. BB_SKILLS_ASSUME_CONSOLE=1 treats stdin as a console, so a test can
# feed answers to the real questions. BB_SKILLS_PLATFORM is win32, darwin or linux, for a platform this machine
# isn't. BB_SKILLS_PATH_SOURCE names a JSON file with machine and user PATH strings, read instead of the registry.
# BB_SKILLS_SYSTEM_PYTHON stands in for macOS's /usr/bin/python3, the stub that must not run without the Command
# Line Tools.

$script:Tools = Join-Path $PSScriptRoot 'tools'
$script:MinimumPython = [version] '3.9'
$script:SystemPython = if ($env:BB_SKILLS_SYSTEM_PYTHON) { $env:BB_SKILLS_SYSTEM_PYTHON } else { '/usr/bin/python3' }

function Get-Platform {
    if ($env:BB_SKILLS_PLATFORM) { return $env:BB_SKILLS_PLATFORM }
    if ($IsWindows) { return 'win32' }
    if ($IsMacOS) { return 'darwin' }
    'linux'
}

function Test-Console {
    if ($env:BB_SKILLS_ASSUME_CONSOLE -eq '1') { return $true }
    $nonInteractive = @([Environment]::GetCommandLineArgs() | Where-Object { $_ -match '^-noni' }).Count -gt 0
    -not [Console]::IsInputRedirected -and -not $nonInteractive
}

function Find-Program([string] $Name) {
    # Scripts too, so a test's stand-in on PATH is found the way a real program is.
    $found = Get-Command -Name $Name -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($found) { $found.Source } else { $null }
}

function Split-Command([string] $Text) {
    # The tools' commands are plain words: a program, then its arguments, with no quoting to undo.
    , @($Text -split '\s+' | Where-Object { $_ })
}

function Start-Attached([string] $Program, [string[]] $Arguments) {
    # Runs a program on this console, unpiped, and returns its exit code. Piped, even through Out-Host, a question
    # it writes without a line ending, such as winget's agreement prompt, stays hidden until the answer's Enter
    # completes the line. A script found on PATH, as a test's stand-in is, runs in a pwsh of its own.
    if ($Program -like '*.ps1') {
        $file = [Environment]::ProcessPath
        $all = @('-NoProfile', '-File', $Program) + @($Arguments)
    } else {
        $file = $Program
        $all = @($Arguments)
    }
    $start = [Diagnostics.ProcessStartInfo]::new($file)
    foreach ($argument in $all) { $start.ArgumentList.Add([string] $argument) }
    $start.UseShellExecute = $false
    $process = [Diagnostics.Process]::Start($start)
    $process.WaitForExit()
    $process.ExitCode
}

function Invoke-Shown([string] $Text) {
    # A command the developer watches: its output, its questions and any password prompt reach the console as written.
    $words = Split-Command $Text
    $program = Find-Program $words[0]
    if (-not $program) {
        Write-Host "  $($words[0]) is not on PATH, so this can't run: $Text"
        return $false
    }
    Write-Host "  Running: $Text"
    (Start-Attached $program @($words | Select-Object -Skip 1)) -eq 0
}

function Update-ProcessPath([string] $Platform) {
    # A package manager's change to PATH reaches only new processes. Rebuild this one's as a new shell would order
    # it, machine entries then user entries, and keep every entry only this process had, after them.
    if ($Platform -ne 'win32') { return }
    if ($env:BB_SKILLS_PATH_SOURCE) {
        $source = Get-Content -LiteralPath $env:BB_SKILLS_PATH_SOURCE -Raw | ConvertFrom-Json
        $machine, $user = [string] $source.machine, [string] $source.user
    } else {
        $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    }
    $separator = [IO.Path]::PathSeparator
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $ordered = [Collections.Generic.List[string]]::new()
    foreach ($entry in (@("$machine".Split($separator)) + @("$user".Split($separator)) + @("$env:PATH".Split($separator)))) {
        $expanded = [Environment]::ExpandEnvironmentVariables($entry).Trim()
        if (-not $expanded) { continue }
        if ($seen.Add($expanded.TrimEnd('\', '/'))) { $ordered.Add($expanded) }
    }
    $env:PATH = $ordered -join $separator
}

function Get-Python([string] $Platform) {
    # The Python to run the tools with, as a command line's first words, or $null when there is none new enough.
    $candidates = [Collections.Generic.List[object]]::new()
    if ($Platform -eq 'win32') {
        $py = Find-Program 'py'
        if ($py) { $candidates.Add(@($py, '-3')) }
    } elseif ($Platform -eq 'darwin') {
        # Never the bare /usr/bin/python3 without the Command Line Tools: that stub opens an install dialog.
        foreach ($path in '/opt/homebrew/bin/python3', '/usr/local/bin/python3') {
            if (Test-Path -LiteralPath $path -PathType Leaf) { $candidates.Add(@($path)) }
        }
        $onPath = Find-Program 'python3'
        if ($onPath -and $onPath -ne $script:SystemPython) { $candidates.Add(@($onPath)) }
        $tools = Find-Program 'xcode-select'
        if ($onPath -eq $script:SystemPython -and $tools) {
            & $tools -p *> $null
            if ($LASTEXITCODE -eq 0) { $candidates.Add(@($onPath)) }
        }
    } else {
        $python3 = Find-Program 'python3'
        if ($python3) { $candidates.Add(@($python3)) }
    }
    foreach ($command in $candidates) {
        $rest = @($command | Select-Object -Skip 1) + @('-c', 'import sys; print(sys.version_info[0], sys.version_info[1])')
        $text = & $command[0] @rest 2> $null | Out-String
        if ($LASTEXITCODE -eq 0 -and $text -match '^\s*(\d+)\s+(\d+)') {
            if ([version] "$($Matches[1]).$($Matches[2])" -ge $script:MinimumPython) { return , $command }
        }
    }
    $null
}

function Get-ToolPlan([object[]] $Python, [string] $Tool, [string[]] $Arguments) {
    $rest = @($Python | Select-Object -Skip 1) + @((Join-Path $script:Tools $Tool)) + $Arguments
    $text = & $Python[0] @rest 2> $null | Out-String
    if ($LASTEXITCODE -ne 0) { throw "$Tool $($Arguments -join ' ') exited $LASTEXITCODE" }
    $text | ConvertFrom-Json
}

function Read-Answers([string[]] $Given) {
    $map = @{}
    foreach ($pair in @($Given | ForEach-Object { $_ -split ',' } | Where-Object { $_ })) {
        $item, $value = $pair -split '=', 2
        if (-not $value) { throw "an answer must be item=answer, not '$pair'" }
        $map[$item.Trim().ToLowerInvariant()] = $value.Trim().ToLowerInvariant()
    }
    $map
}

function Request-Answer([hashtable] $Given, [string] $Item, [string] $Question, [string[]] $Choices) {
    # yes, no, or one of Choices: from -Answer when it names Item, else from the console, else no. An answer given
    # ahead is echoed with its question, so a log shows what it decided.
    if ($Given.ContainsKey($Item)) {
        $reply = $Given[$Item]
        Write-Host "$Question $reply (from -Answer)"
    }
    elseif (Test-Console) {
        if (-not $script:Hinted) {
            Write-Host 'Answer y to install, or press Enter to skip.'
            $script:Hinted = $true
        }
        if ($Choices) {
            Write-Host $Question
            for ($i = 0; $i -lt $Choices.Count; $i++) { Write-Host "  $($i + 1)) $($Choices[$i])" }
            Write-Host '  Enter a number, or nothing for no: ' -NoNewline
        } else {
            Write-Host "$Question [y/N] " -NoNewline
        }
        $reply = [Console]::In.ReadLine()
        $reply = if ($null -eq $reply) { '' } else { $reply.Trim().ToLowerInvariant() }
    } else { $reply = 'no' }

    if ($Choices) {
        # A choice is "manager: commands". It is picked by its number, by its manager's whole name, or by a prefix
        # that fits only one; anything else is no.
        $number = 0
        if ([int]::TryParse($reply, [ref] $number) -and $number -ge 1 -and $number -le $Choices.Count) {
            return $Choices[$number - 1]
        }
        $exact = @($Choices | Where-Object { ($_ -split ':', 2)[0].Trim().ToLowerInvariant() -eq $reply })
        if ($reply -and $exact.Count -eq 1) { return $exact[0] }
        $prefixed = @($Choices | Where-Object { $reply -and $_.ToLowerInvariant().StartsWith($reply) })
        if ($prefixed.Count -eq 1) { return $prefixed[0] }
        return 'no'
    }
    if ($reply -in 'y', 'yes') { 'yes' } else { 'no' }
}

function Invoke-MermaidSetup {
    param([switch] $CheckOnly, [string[]] $Given)
    $ErrorActionPreference = 'Stop'
    $platform = Get-Platform
    $answers = Read-Answers $Given
    $results = [ordered]@{}
    $failed = $false

    # Python, without which nothing else can be checked.
    $python = Get-Python $platform
    if ($python) {
        $results['Python'] = 'already there'
    } else {
        if ($CheckOnly) { return 1 }
        $commands = @()
        if ($platform -eq 'win32' -and (Find-Program 'winget')) {
            $commands = @('winget install --id Python.PythonInstallManager -e')
        } elseif ($platform -eq 'darwin' -and (Find-Program 'brew')) {
            $commands = @('brew install python')
        }
        if (-not $commands) {
            $how = switch ($platform) {
                'linux' { "your distribution's python3 package, such as: sudo apt install python3" }
                'darwin' { 'the installer at https://www.python.org/downloads/macos/' }
                default { 'the Python Install Manager at https://www.python.org/downloads/windows/' }
            }
            Write-Host "Python $($script:MinimumPython) or later is missing. Install it with $how, then run this again."
            $results['Python'] = 'named'
        } elseif ((Request-Answer $answers 'python' "Python $($script:MinimumPython) or later is missing. Install it with: $($commands -join ', then ')?") -eq 'yes') {
            $ran = $true
            foreach ($command in $commands) { $ran = $ran -and (Invoke-Shown $command) }
            Update-ProcessPath $platform
            $python = Get-Python $platform
            if (-not $python -and $platform -eq 'win32' -and (Find-Program 'py')) {
                # The manager is there but holds no runtime yet.
                $null = Invoke-Shown 'py install -y 3'
                $python = Get-Python $platform
            }
            $results['Python'] = if ($python) { 'installed' } else { 'failed' }
            $failed = $failed -or -not $python
        } else {
            $results['Python'] = 'declined'
        }
        if (-not $python) {
            Write-Host 'Without Python, nothing else can be checked.'
            Write-Summary $results
            return [int] $failed
        }
    }

    $renderer = Get-ToolPlan $python 'mermaid-svg/mermaid_svg.py' @('plan')
    $inkscape = Get-ToolPlan $python 'inkscape_png.py' @('--plan')
    $rendererMissing = $renderer.install.state -ne 'current'
    $inkscapeMissing = $null -eq $inkscape.found
    if ($CheckOnly) { return [int] ($rendererMissing -or $inkscapeMissing) }

    # Node.js, only for a renderer that is missing; then the renderer.
    if ($rendererMissing) {
        $nodeOk = [bool] $renderer.node.ok
        if ($nodeOk) {
            $results['Node.js'] = 'already there'
        } else {
            $need = "Node.js $($renderer.minimumNode) or later"
            $have = if ($renderer.node.version) { "Node.js $($renderer.node.version) is too old" } else { 'There is no Node.js' }
            if (-not $renderer.nodeInstall) {
                Write-Host "$have, and the renderer needs $need. Install it from https://nodejs.org/en/download or with nvm, then run this again."
                $results['Node.js'] = 'named'
            } elseif ((Request-Answer $answers 'node' "$have, and the renderer needs $need. Install it with: $($renderer.nodeInstall)?") -eq 'yes') {
                $null = Invoke-Shown $renderer.nodeInstall
                Update-ProcessPath $platform
                $renderer = Get-ToolPlan $python 'mermaid-svg/mermaid_svg.py' @('plan')
                $nodeOk = [bool] $renderer.node.ok
                $results['Node.js'] = if ($nodeOk) { 'installed' } else { 'failed' }
                $failed = $failed -or -not $nodeOk
            } else {
                $results['Node.js'] = 'declined'
            }
        }
        if (-not $nodeOk) {
            Write-Host 'The renderer needs Node.js, so it is skipped.'
            $results['renderer'] = 'skipped'
        } else {
            $verb = if ($renderer.install.state -eq 'stale') { 'Update' } else { 'Install' }
            $question = "$verb the renderer into $($renderer.install.folder)? About 700 MB: mermaid-cli and Puppeteer " +
                "from the npm registry, and chrome-headless-shell from Google's Chrome for Testing storage."
            if ((Request-Answer $answers 'renderer' $question) -eq 'yes') {
                $rest = @($python | Select-Object -Skip 1) + @((Join-Path $script:Tools 'mermaid-svg' 'mermaid_svg.py'), 'setup')
                $null = Start-Attached $python[0] $rest
                $renderer = Get-ToolPlan $python 'mermaid-svg/mermaid_svg.py' @('plan')
                $ok = $renderer.install.state -eq 'current'
                $results['renderer'] = if ($ok) { 'installed' } else { 'failed' }
                $failed = $failed -or -not $ok
            } else {
                $results['renderer'] = 'declined'
            }
        }
    } else {
        $results['renderer'] = 'already there'
    }

    # Inkscape, at the floor its tool's plan names.
    $wanted = "Inkscape $($inkscape.minimum) or later"
    if (-not $inkscapeMissing) {
        $results['Inkscape'] = 'already there'
    } elseif ($inkscape.configured) {
        Write-Host "INKSCAPE names a program that won't do: $($inkscape.notes -join '; '). Point it at $wanted, or unset it."
        $results['Inkscape'] = 'named'
    } else {
        $commands = @()
        if ($inkscape.chosen) {
            $question = "$wanted is missing ($($inkscape.reason)). Install it with: $($inkscape.chosen.commands -join ', then ')?"
            if ((Request-Answer $answers 'inkscape' $question) -eq 'yes') { $commands = @($inkscape.chosen.commands) }
        } elseif (@($inkscape.candidates).Count -gt 0) {
            $byChoice = [ordered]@{}
            foreach ($row in $inkscape.candidates) { $byChoice["$($row.manager): $($row.commands -join ', then ')"] = @($row.commands) }
            $question = "$wanted is missing, and no install was chosen for this machine ($($inkscape.reason)). Install it with one of these?"
            $choice = Request-Answer $answers 'inkscape' $question ([string[]] @($byChoice.Keys))
            if ($choice -ne 'no') { $commands = $byChoice[$choice] }
        } else {
            Write-Host "$wanted is missing, and none of lesson 4's installs fits this machine. Install it from https://inkscape.org."
            $results['Inkscape'] = 'named'
        }
        if ($commands) {
            $ran = $true
            foreach ($command in $commands) { if ($ran) { $ran = Invoke-Shown $command } }
            Update-ProcessPath $platform
            $inkscape = Get-ToolPlan $python 'inkscape_png.py' @('--plan')
            $ok = $ran -and $null -ne $inkscape.found
            $results['Inkscape'] = if ($ok) { 'installed' } else { 'failed' }
            $failed = $failed -or -not $ok
        } elseif (-not $results.Contains('Inkscape')) {
            $results['Inkscape'] = 'declined'
        }
    }

    Write-Summary $results
    [int] $failed
}

function Write-Summary([System.Collections.Specialized.OrderedDictionary] $Results) {
    Write-Host ''
    Write-Host 'mermaid-charts setup:'
    foreach ($item in $Results.Keys) { Write-Host ('  {0,-10} {1}' -f $item, $Results[$item]) }
}

function Exit-Script([int] $Code) {
    # A bare exit would close an editor's host that dot-sourced this file; there a failure throws instead.
    if ($Host.Name -like '*Visual Studio Code*') {
        if ($Code -ne 0) { throw "setup finished with exit code $Code" }
        return
    }
    exit $Code
}

if (-not $env:BB_SKILLS_NOEXEC) {
    try {
        $code = Invoke-MermaidSetup -CheckOnly:$Check -Given $Answer
    } catch {
        Write-Host "mermaid-charts setup: $($_.Exception.Message)"
        $code = 2
    }
    Exit-Script $code
}
