#!/usr/bin/env pwsh
#Requires -Version 7.4

<#
.SYNOPSIS
    Installs this repository's skills into Claude Code's skills folder, with their setups, hooks and settings. Read
    only unless -Apply.

.DESCRIPTION
    With no action and nobody to ask, it shows the state of things and changes nothing: each skill against its
    installed copy, each setup's check, each skill's hooks and settings, as an ok line or the step that fixes it.
    With no action and a person at a terminal, it offers a menu: Status, the Enter choice; Install or update; Hooks;
    Settings; Remove hooks. It then asks only what the flags have not answered, shows what would change, asks
    whether to apply it, defaulting to no, and prints the flags that would do the same next time. A skill whose
    SKILL.md has a compatibility: line shows it as [needs ...] in the menu's list of skills, in the status while it
    is not installed, and in a dry run.

    An action is -Skill, which installs the skills it names; -AddHooks, -RemoveHooks or -Configure; or -Apply alone,
    which installs every skill. -SkillSource and -SkillDestination only say where, and -NonInteractive only whether
    anyone is asked. Without -Apply an action is a dry run: each copy, setup, hook and setting it would change is a
    would line, nothing is written, and it ends with the command that applies it. -Apply with -WhatIf is a dry run
    too, and so is the menu under -WhatIf. -Confirm is refused, since a dry run already shows each change, and so is
    a flag the action it comes with would drop, such as -Skill beside -AddHooks.

    An install copies each skill into the skills folder, ~/.claude/skills unless -SkillDestination names another,
    and reads it back. A copy it replaces goes first to a backup folder beside the skills folder, never inside it,
    skills.bak-<time>, with a RESTORE.md saying how to put it back; -NoBackup keeps none, and needs -Force. Then each
    skill's setup.ps1 runs when its -Check finds something missing: with a person there, or with -Setup or
    -SetupAnswer; with nobody there and neither, its items are declined, and the run says which flag answers them.
    Then a skill's hooks, from its hooks.json, are offered for the settings.json beside the skills folder, once its
    setup finds nothing missing; then its settings, from its plugin.json userConfig and its env.json. -Yes answers
    each offer yes. Each change to settings.json is shown, written under a lock beside it, settings.json.lock, after
    a stamped backup, and refused, naming the command to run again, when the file changed since it was read. Hooks
    that name a skill folder that is gone are reported, and offered for removal.

    A skill can be installed under another name, with -Rename or as the answer to a question: its folder and its
    SKILL.md take the new name, and the copy keeps a .renamed-from naming its skill, so later installs replace it
    where it is. A skill renamed in this repository lists its earlier names in .former-names, and a copy under one
    of them is the skill's. A new name takes lowercase letters, digits and hyphens, a letter or a digit first, and is
    refused when it is one of Claude Code's own, from tools/builtin-commands.txt, another skill's, or a folder that
    isn't this skill's, a refusal no flag overrides.

    Every problem with the flags is found before anything changes, each on a FAIL line naming its fix. A question
    nobody can answer takes its safe default and says so with the flag that answers it; one with none, such as the
    name for a skill whose own is taken, ends the run with exit 64.

    -Set and -SetupAnswer take several pairs in one string, separated by commas: -Set
    tuned.level=4,tuned.TUNED_COUNT=7, -SetupAnswer mermaid-charts:renderer=yes,mermaid-charts:inkscape=no. A value
    holding a comma, as a list setting's does, is in double quotes: -Set 'crunch.tags="a, b",crunch.level=4'.

.PARAMETER SkillSource
    Folder holding the skill folders. The folder this script is in without it.

.PARAMETER SkillDestination
    Claude Code's skills folder. ~/.claude/skills without it, on every platform.

.PARAMETER Apply
    Make the changes. Without it nothing is written.

.PARAMETER Yes
    Answer yes to the offers inside an install: each skill's hooks, and each stale hook's removal.

.PARAMETER Force
    With -NoBackup, replace installed copies without keeping them.

.PARAMETER NoBackup
    Keep no copy of what an install replaces. Needs -Force.

.PARAMETER NoSetup
    Run no skill's setup. A skill that brings hooks still has its setup's -Check run, since its hooks wait until that
    finds nothing missing.

.PARAMETER Setup
    Run each needed setup even with nobody there, which then declines every item it isn't given an answer for.

.PARAMETER SetupAnswer
    Answers for a skill's setup, as skill:item=yes pairs, comma-separated; each skill's reach its setup as its own
    -Answer item=yes.

.PARAMETER NoHooks
    Offer no skill's hooks.

.PARAMETER NoSettings
    Offer no skill's settings.

.PARAMETER Set
    A setting's value, as skill.key=value pairs, comma-separated; a value in double quotes may hold commas, and - takes
    a value out.

.PARAMETER AddHooks
    An action: add this installed skill's hooks to settings.json. Naming it is the answer: with -Apply nothing is
    asked about them.

.PARAMETER RemoveHooks
    An action: take this skill's hooks out of settings.json, and nothing else.

.PARAMETER Configure
    An action: this installed skill's settings. With -Set those values are written; without it a person is asked
    each one, and with nobody there each is kept.

.PARAMETER Rename
    Install skills under other names, as old=new pairs, comma-separated: agent-times=times,plan-file=plan-doc. A
    pair naming a skill's own name undoes its rename. A skill named here is not asked about.

.PARAMETER AskNames
    With a person there, ask what to install every skill as, not only the skills with no installed copy.

.PARAMETER Skill
    An action: install only these skills, comma-separated, each by its own name or the name it is installed under.
    -Rename may then name only these.

.PARAMETER NonInteractive
    Ask nothing, as when nobody is there.

.PARAMETER Options
    List the actions and flags, and change nothing.

.PARAMETER Rest
    Any argument the other parameters don't take, which is an error.

.PARAMETER WhatIf
    With -Apply, a dry run, as an action without -Apply is; with no action at a terminal, the menu as a dry run.

.PARAMETER Confirm
    Refused: nothing here asks per change, since a run without -Apply shows each one, and the menu asks before it
    applies.

.EXAMPLE
    pwsh -NoProfile -File Install-Skills.ps1

    With nobody to ask, shows what is installed and what an install would change; at a terminal, offers a menu.

.EXAMPLE
    pwsh -NoProfile -File Install-Skills.ps1 -Apply

    Installs or updates every skill, asking only what a person can answer.

.EXAMPLE
    pwsh -NoProfile -File Install-Skills.ps1 -Skill crunch

    A dry run: what installing crunch would change, ending with the command that does it.

.EXAMPLE
    pwsh -NoProfile -File Install-Skills.ps1 -Skill agent-times -Rename agent-times=times -Apply

    Installs agent-times alone, as /times.

.EXAMPLE
    pwsh -NoProfile -File Install-Skills.ps1 -AddHooks crunch -Apply

    Adds crunch's hooks to settings.json.

.EXAMPLE
    pwsh -NoProfile -File Install-Skills.ps1 -Configure crunch -Apply

    Asks about each of crunch's settings, and writes the change on a yes.

.NOTES
    Exit codes:
      0   done, or nothing to do: a dry run, the status, or an offer declined
      1   done, with a warning left unresolved
      2   a step failed, or the flags were refused, a stray argument included; nothing is left half written
      64  an answer is needed, such as a skill's name, and nobody is there to ask

    Besides these, pwsh itself exits 1, before the script runs, on an argument it can't bind: an ambiguous
    abbreviation such as -No, a parameter given twice, one missing its value, or a switch given a word, as
    -Apply:nope. No FAIL line is written then, only pwsh's own error.

    BB_SKILLS_NOEXEC set to anything makes the script define its functions and run nothing.
    BB_SKILLS_NO_PROMPT set to anything asks nothing, as -NonInteractive does. NO_COLOR turns colour off.

    Test seams, for tests/test-install-skills.ps1: BB_SKILLS_ASSUME_CONSOLE=1 takes input as a console's and
    BB_SKILLS_ASSUME_TERMINAL=1 output as a terminal's; BB_SKILLS_CLAUDE_VERSION stands for claude --version;
    BB_SKILLS_FAIL_BEFORE=<skill> and BB_SKILLS_FAIL_AFTER_STAGING=1 stop a run partway with an error, and
    BB_SKILLS_STOP_BEFORE=<skill> and BB_SKILLS_STOP_AFTER_STAGING=1 at the same points as Ctrl+C would;
    BB_SKILLS_DISTURB_SETTINGS=1 changes settings.json between its write and its read-back.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium', PositionalBinding = $false)]
param(
    [string] $SkillSource = $PSScriptRoot,
    [string] $SkillDestination = (Join-Path $HOME '.claude' 'skills'),
    [switch] $Apply,
    [switch] $Yes,
    [switch] $Force,
    [switch] $NoBackup,
    [switch] $NoSetup,
    [switch] $Setup,
    [string[]] $SetupAnswer,
    [switch] $NoHooks,
    [switch] $NoSettings,
    [string[]] $Set,
    [string] $AddHooks,
    [string] $RemoveHooks,
    [string] $Configure,
    [string[]] $Rename,
    [switch] $AskNames,
    [string[]] $Skill,
    [switch] $NonInteractive,
    [switch] $Options,
    [Parameter(ValueFromRemainingArguments)] [string[]] $Rest
)

# The parameters this run was given, read here at script scope: inside Invoke-Main, which declares none,
# $PSBoundParameters is that function's own and empty. A dry run ends with them, plus -Apply.
$script:InstallerBound = [hashtable]::new($PSBoundParameters, [StringComparer]::OrdinalIgnoreCase)
$script:InstallerPath = if ($PSCommandPath) { $PSCommandPath } else { $MyInvocation.MyCommand.Path }
$script:UseColour = $false
$script:WrapWidth = 0

. (Join-Path $PSScriptRoot 'tools' 'SkillHooks.ps1')
$script:ReservedNamesPath = Join-Path $PSScriptRoot 'tools' 'builtin-commands.txt'
# A renamed copy's record of the skill it came from: one line, the source skill's name.
$script:RenameMarker = '.renamed-from'
# A skill's list of the names it had before the source renamed it, one to a line.
$script:FormerNamesFile = '.former-names'
# Claude Code's skills page sets no rule for a name's characters, so this is the plan's: lowercase letters, digits
# and hyphens, at most 64, which every skill here meets; and a letter or a digit first, as - answers the name question.
$script:NameRule = '^[a-z0-9][a-z0-9-]{0,63}$'
# How long a run waits for another to let go of settings.json.lock before it gives up.
$script:LockWaitMs = 3000

# One table of the actions and flags: -Options lists it, the menu's choices are its rows with a Menu label, and a
# test holds each name in it to a real parameter.
$script:InstallerFlags = @(
    @{ Name = 'Apply'; Kind = 'action'; Text = 'Make the changes; alone, install every skill. Without it a run writes nothing.' }
    @{ Name = 'Skill'; Kind = 'action'; Menu = 'Install or update'; Detail = 'copy skills in, choosing which'; Text = 'Install only these skills, comma-separated.' }
    @{ Name = 'AddHooks'; Kind = 'action'; Menu = 'Hooks'; Detail = 'add a skill''s hooks to settings.json'; Text = 'Add this installed skill''s hooks to settings.json.' }
    @{ Name = 'Configure'; Kind = 'action'; Menu = 'Settings'; Detail = 'change a skill''s settings'; Text = 'This installed skill''s settings: -Set''s values, or each asked.' }
    @{ Name = 'RemoveHooks'; Kind = 'action'; Menu = 'Remove hooks'; Detail = 'take a skill''s hooks out of settings.json'; Text = 'Take this skill''s hooks out of settings.json.' }
    @{ Name = 'Yes'; Kind = 'flag'; Text = 'Answer yes to each hooks offer and each stale hook''s removal.' }
    @{ Name = 'Set'; Kind = 'flag'; Text = 'Settings'' values: skill.key=value, comma-separated; "a, b" for a list.' }
    @{ Name = 'SetupAnswer'; Kind = 'flag'; Text = 'Setup answers: skill:item=yes, comma-separated, each passed as -Answer.' }
    @{ Name = 'Rename'; Kind = 'flag'; Text = 'Install skills under other names: old=new, comma-separated.' }
    @{ Name = 'AskNames'; Kind = 'flag'; Text = 'Ask the name of every skill, not only the new ones.' }
    @{ Name = 'NoSetup'; Kind = 'flag'; Text = 'Run no setup; a skill''s hooks still wait for its check.' }
    @{ Name = 'Setup'; Kind = 'flag'; Text = 'Run each needed setup even with nobody there.' }
    @{ Name = 'NoHooks'; Kind = 'flag'; Text = 'Offer no skill''s hooks.' }
    @{ Name = 'NoSettings'; Kind = 'flag'; Text = 'Offer no skill''s settings.' }
    @{ Name = 'NoBackup'; Kind = 'flag'; Text = 'Keep no copy of what is replaced; needs -Force.' }
    @{ Name = 'Force'; Kind = 'flag'; Text = 'With -NoBackup, replace without keeping a copy.' }
    @{ Name = 'NonInteractive'; Kind = 'flag'; Text = 'Ask nothing, as when nobody is there.' }
    @{ Name = 'SkillSource'; Kind = 'flag'; Text = 'The folder holding the skills; this script''s folder without it.' }
    @{ Name = 'SkillDestination'; Kind = 'flag'; Text = 'The skills folder; ~/.claude/skills without it.' }
    @{ Name = 'Options'; Kind = 'flag'; Text = 'List the actions and flags, changing nothing.' }
)

# The run's tally: a warning left unresolved makes its exit 1, and a step that failed 2.
$script:RunWarnings = 0
$script:RunFailures = 0
# The flags each named action takes besides -SkillDestination: what -Options and the conflicts check hold it to, and
# all the menu's command for it carries.
$script:ActionTakes = @{ AddHooks = @('Yes'); RemoveHooks = @(); Configure = @('Set') }
# A run's answers that a flag can give again: the settings a person typed and the run wrote, as -Set entries, and each
# yes or no to a hooks offer or a stale hook's removal, which -Yes answers. Made anew by each run.
$script:SettingAnswers = [Collections.Generic.List[string]]::new()
$script:YesAnswers = [Collections.Generic.List[bool]]::new()

#region --------------- Shared helpers: tools/New-SkillPack.ps1 carries them byte for byte, tests/test-script-conventions.ps1 pins them

function Test-UseColour {
    <# Whether output gets colour: never under NO_COLOR; always under an editor's host; else on a terminal alone. #>
    [OutputType([bool])]
    param([bool] $NoColorVariable, [string] $HostName, [bool] $EditorPresent, [bool] $OutputRedirected)
    if ($NoColorVariable) { return $false }
    if ($EditorPresent -or $HostName -like '*Visual Studio Code*') { return $true }
    return ($HostName -eq 'ConsoleHost' -and -not $OutputRedirected)
}

function Test-CanPrompt {
    <# Whether a person can be asked, by REUSABLE-PATTERNS section 1.3's table, read top to bottom. Pure. #>
    [OutputType([bool])]
    param([bool] $NonInteractiveSwitch, [bool] $NoPromptVariable, [string] $HostName, [bool] $EditorPresent,
        [bool] $InputRedirected, [bool] $HostNonInteractive)
    if ($NonInteractiveSwitch -or $NoPromptVariable) { return $false }
    if ($EditorPresent -or $HostName -like '*Visual Studio Code*') { return $true }
    if ($HostName -ne 'ConsoleHost') { return $false }
    return (-not $InputRedirected -and -not $HostNonInteractive)
}

function Initialize-Output {
    <#
        Sets the colour gate and the width prose wraps to, once a run. BB_SKILLS_ASSUME_TERMINAL=1 is a test seam
        that takes output as a terminal's for colour; prose wraps only where the console really is one.
    #>
    $redirected = [Console]::IsOutputRedirected
    $script:UseColour = Test-UseColour -NoColorVariable ($null -ne [Environment]::GetEnvironmentVariable('NO_COLOR')) `
        -HostName $Host.Name -EditorPresent $script:InEditor `
        -OutputRedirected ($redirected -and $env:BB_SKILLS_ASSUME_TERMINAL -ne '1')
    $script:WrapWidth = 0
    if ($script:InEditor -or ($Host.Name -eq 'ConsoleHost' -and -not $redirected)) {
        try { $script:WrapWidth = [int] $Host.UI.RawUI.WindowSize.Width } catch { $script:WrapWidth = 0 }
    }
}

function Test-HostNonInteractive {
    <#
        Whether pwsh itself was started with -NonInteractive, abbreviated or not: its own arguments only, those
        before -File, -Command or -EncodedCommand, so a script's own -NonInteractive is left to the script. Pure.
    #>
    [OutputType([bool])]
    param([string[]] $Arguments)
    foreach ($argument in @($Arguments | Select-Object -Skip 1)) {
        if ($argument -match '^-(f|fi|fil|file|c|co|com|comm|comma|comman|command|e|ec|en|enc\w*|cwa|commandwithargs)$') { return $false }
        if ($argument -match '^-noni') { return $true }
    }
    return $false
}

function Test-PersonThere {
    <# Section 1.3's facts for this process. BB_SKILLS_ASSUME_CONSOLE=1 is a test seam that takes input as a console's. #>
    [OutputType([bool])]
    param([bool] $NonInteractiveSwitch)
    return (Test-CanPrompt -NonInteractiveSwitch $NonInteractiveSwitch -NoPromptVariable ([bool] $env:BB_SKILLS_NO_PROMPT) `
        -HostName $Host.Name -EditorPresent $script:InEditor `
        -InputRedirected ([Console]::IsInputRedirected -and $env:BB_SKILLS_ASSUME_CONSOLE -ne '1') `
        -HostNonInteractive (Test-HostNonInteractive ([Environment]::GetCommandLineArgs())))
}

function Format-Wrapped {
    <# Text wrapped at word breaks to fit $Width, each line after the first indented by $Indent. Pure. #>
    [OutputType([string])]
    param([string] $Text, [int] $Width, [int] $Indent)
    $room = $Width - $Indent - 1
    if ($Width -le 0 -or $room -lt 20) { return $Text }
    $lines = [Collections.Generic.List[string]]::new()
    foreach ($paragraph in $Text -split "`n") {
        $line = ''
        foreach ($word in $paragraph -split ' ') {
            if ($line -and ($line.Length + 1 + $word.Length) -gt $room) { $lines.Add($line); $line = $word }
            elseif ($line) { $line += ' ' + $word }
            else { $line = $word }
        }
        $lines.Add($line)
    }
    return ($lines -join ("`n" + (' ' * $Indent)))
}

function Write-Head {
    <# A step starting: a blank line, then ==> and its name. #>
    param([string] $Text)
    Write-Host ''
    if ($script:UseColour) { Write-Host ($PSStyle.Bold + '==> ' + $Text + $PSStyle.Reset) }
    else { Write-Host ('==> ' + $Text) }
}

function Write-Tag {
    <#
        One tagged line: two spaces, the tag in a column five wide, a space, the text. The tag carries the meaning;
        colour, where the gate allows it, repeats it. Prose wraps under the text unless -NoWrap.
    #>
    param([string] $Tag, [string] $Text, [switch] $NoWrap)
    $colour = switch -CaseSensitive ($Tag) {
        'ok' { $PSStyle.Foreground.Green }
        '..' { $PSStyle.Foreground.BrightBlack }
        'would' { $PSStyle.Foreground.BrightBlack }
        'note' { $PSStyle.Foreground.Yellow }
        'warn' { $PSStyle.Foreground.Yellow }
        'FAIL' { $PSStyle.Foreground.Red }
        'page' { $PSStyle.Foreground.Cyan }
        '?' { $PSStyle.Foreground.Cyan }
        default { throw "Write-Tag has no tag '$Tag'." }
    }
    $body = if ($NoWrap) { $Text } else { Format-Wrapped $Text $script:WrapWidth 8 }
    $pad = ' ' * (5 - $Tag.Length + 1)
    if (-not $script:UseColour) { Write-Host ('  ' + $Tag + $pad + $body) }
    elseif ($Tag -eq '..' -or $Tag -eq 'would') { Write-Host ('  ' + $colour + $Tag + $pad + $body + $PSStyle.Reset) }
    else { Write-Host ('  ' + $colour + $Tag + $PSStyle.Reset + $pad + $body) }
}

function Write-Kv {
    <# A field line: the .. tag, the name in a column $Width wide, the value. #>
    param([string] $Key, [string] $Value, [int] $Width = 20)
    $name = $Key.PadRight($Width)
    if ($script:UseColour) { Write-Host ('  ' + $PSStyle.Foreground.BrightBlack + '..    ' + $name + $PSStyle.Reset + ' ' + $Value) }
    else { Write-Host ('  ..    ' + $name + ' ' + $Value) }
}

function Read-Answer {
    <#
        Asks one question and returns the answer, trimmed; Enter takes $Default. $Check returns '' for a good
        answer or a sentence saying why it isn't, shown before the question is asked again. Returns $null when
        input ends, so a caller treats nobody's answer as its default.
    #>
    [OutputType([string])]
    param([string] $Question, [string] $Default = '', [scriptblock] $Check = { '' })
    while ($true) {
        Write-Host ''
        Write-Tag '?' $Question
        $shown = if ($Default) { "[$Default] > " } else { '> ' }
        Write-Host ((' ' * 8) + $shown) -NoNewline
        $reply = Read-Host
        if ($null -eq $reply) { Write-Host ''; return $null }
        $reply = $reply.Trim()
        if (-not $reply) { $reply = $Default }
        $why = if ($reply) { [string] (& $Check $reply) } else { 'An answer is needed.' }
        if (-not $why) { return $reply }
        Write-Tag 'warn' $why
    }
}

function Read-YesNo {
    <# Asks a yes-or-no question; Enter takes the capital letter. Returns $true, $false, or $null when input ends. #>
    param([string] $Question, [switch] $DefaultYes)
    $choices = if ($DefaultYes) { 'Y/n' } else { 'y/N' }
    while ($true) {
        Write-Host ''
        Write-Tag '?' $Question
        Write-Host ((' ' * 8) + "[$choices] > ") -NoNewline
        $reply = Read-Host
        if ($null -eq $reply) { Write-Host ''; return $null }
        switch ($reply.Trim().ToLowerInvariant()) {
            '' { return [bool] $DefaultYes }
            { $_ -in 'y', 'yes' } { return $true }
            { $_ -in 'n', 'no' } { return $false }
        }
        Write-Tag 'warn' 'Answer y or n.'
    }
}

function Format-RunCommand {
    <#
        The command that runs a script again: pwsh -NoProfile -File and its path, then the parameters it was given,
        with $Set overriding and $Drop removing, sorted by name and -Apply last. Pure.

        A value is printed bare when pwsh, bash and zsh all read it as written, and in single quotes otherwise. A
        value holding a single quote, typographic ones included, has no quoting all three read the same: it is
        printed in PowerShell's, its quotes doubled, and PowerShellOnly says so. An array is joined with commas, which
        the scripts split themselves, since pwsh -File hands each argument over as one string. A switch that is
        false, and an empty value, are left out, except -Confirm:$false, which is kept, quoted.
    #>
    [OutputType([hashtable])]
    param([string] $ScriptPath, [hashtable] $Bound, [hashtable] $Set = @{}, [string[]] $Drop = @())

    $p = [hashtable]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($k in $Bound.Keys) { $p[$k] = $Bound[$k] }
    foreach ($k in $Set.Keys) { $p[$k] = $Set[$k] }
    foreach ($k in $Drop) { $p.Remove($k) }
    $keys = @($p.Keys | Where-Object { $_ -ne 'Apply' } | Sort-Object) + @($p.Keys | Where-Object { $_ -eq 'Apply' })
    $quotes = '[''‘’‚‛]'
    $quote = {
        param([string] $Value, [bool] $Always)
        if ($Value -match $quotes) {
            return "'" + [Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($Value) + "'"
        }
        if (-not $Always -and $Value -cmatch '^[A-Za-z_/][A-Za-z0-9_./=+-]*$') { return $Value }
        return "'" + $Value + "'"
    }
    $words = [Collections.Generic.List[string]]::new()
    $values = [Collections.Generic.List[string]]::new()
    foreach ($w in 'pwsh', '-NoProfile', '-File', (& $quote $ScriptPath $true)) { $words.Add($w) }
    $values.Add($ScriptPath)
    foreach ($k in $keys) {
        $v = $p[$k]
        if ($v -is [Management.Automation.SwitchParameter] -or $v -is [bool]) {
            if ([bool] $v) { $words.Add("-$k") } elseif ($k -eq 'Confirm') { $words.Add("'-Confirm:`$false'") }
            continue
        }
        $parts = @(@($v) | ForEach-Object { [string] $_ } | Where-Object { $_ -ne '' })
        if ($parts.Count -eq 0) { continue }
        $words.Add("-$k")
        $words.Add((& $quote ($parts -join ',') $false))
        $values.Add($parts -join ',')
    }
    return @{ Text = ($words -join ' '); PowerShellOnly = (@($values | Where-Object { $_ -match $quotes }).Count -gt 0) }
}

#endregion


#region ------------------------------------------------------------- The installer's own helpers

function Write-RunWarning([string] $Text, [switch] $NoWrap) {
    # A warning the run leaves unresolved, which makes its exit 1.
    $script:RunWarnings++
    Write-Tag 'warn' $Text -NoWrap:$NoWrap
}

function Write-RunFailure([string] $Text, [switch] $NoWrap) {
    # A step that failed, which makes the run's exit 2.
    $script:RunFailures++
    Write-Tag 'FAIL' $Text -NoWrap:$NoWrap
}

function Get-RunExitCode {
    if ($script:RunFailures -gt 0) { return 2 }
    if ($script:RunWarnings -gt 0) { return 1 }
    return 0
}

function Get-ApplyCommand {
    <# The command that applies a run: its parameters, with $Set over them, -Apply last, -WhatIf left out. #>
    param([hashtable] $Bound = $script:InstallerBound, [hashtable] $Set = @{}, [string[]] $Drop = @())
    $all = @{ Apply = $true }
    foreach ($k in $Set.Keys) { $all[$k] = $Set[$k] }
    Format-RunCommand $script:InstallerPath $Bound -Set $all -Drop (@('WhatIf', 'Confirm', 'Rest', 'Options') + $Drop)
}

function Write-ApplyCommand([string] $Lead, [hashtable] $Command) {
    # A command on a line of its own, ending the line, with the note PowerShell's quoting needs.
    Write-Tag '..' "${Lead}: $($Command.Text)" -NoWrap
    if ($Command.PowerShellOnly) { Write-Tag 'note' 'That command quotes a value as PowerShell does, which bash and zsh read differently.' }
}

function Get-ActionCommand([string] $Destination, [hashtable] $Action) {
    # The command for one named action on the skills folder $Destination, with -Apply.
    $bound = @{ SkillDestination = $Destination }
    foreach ($k in $Action.Keys) { $bound[$k] = $Action[$k] }
    Format-RunCommand $script:InstallerPath $bound -Set @{ Apply = $true }
}

function Format-SetupCommand([string] $Script, [string[]] $Arguments = @()) {
    # The command that runs a skill's setup itself, asking its own questions. Its path is quoted as PowerShell reads
    # it, every single quote doubled, typographic ones included, which PowerShell reads as quotes too; a path holding
    # one reads differently in bash and zsh, and the command says so after it, as Format-RunCommand does.
    $quoted = "'" + [Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($Script) + "'"
    $words = @('pwsh', '-NoProfile', '-File', $quoted) + $Arguments
    $note = if ($Script -match '[''‘’‚‛]') { ' (quoted as PowerShell reads it: run it from pwsh)' } else { '' }
    ($words -join ' ') + $note
}

function Get-NamedActionCommand {
    <#
        The command that does one named action, -AddHooks, -RemoveHooks or -Configure on $Name, with -Apply: the skills
        folder the run was given, and of the run's other flags only those the action takes, with $Set over them. The
        menu's commands, and a refused action's "run it again", are built here, so none carries a flag the action
        refuses, nor turns into an install.
    #>
    param([string] $Action, [string] $Name, [hashtable] $Set = @{})
    $bound = @{}
    foreach ($key in @('SkillDestination') + @($script:ActionTakes[$Action])) {
        if ($script:InstallerBound.ContainsKey($key)) { $bound[$key] = $script:InstallerBound[$key] }
    }
    $all = @{ $Action = $Name }
    foreach ($k in $Set.Keys) { $all[$k] = $Set[$k] }
    Get-ApplyCommand -Bound $bound -Set $all
}

function Test-SameFolderName([string] $A, [string] $B) {
    # Whether two names are one folder's: without regard to case where the file system ignores it, Windows and macOS,
    # and exactly elsewhere, where Alpha and alpha are two folders, as the pack's Test-PathInside decides. Pure.
    $comparison = if ($IsWindows -or $IsMacOS) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    [string]::Equals($A, $B, $comparison)
}

function Get-FolderComparer {
    # The comparer for a set of folder names, by Test-SameFolderName's rule.
    if ($IsWindows -or $IsMacOS) { return [StringComparer]::OrdinalIgnoreCase }
    [StringComparer]::Ordinal
}

function Test-NamedAmong([string] $Name, [string[]] $Names) {
    # Whether $Name is one of $Names as folders go, by Test-SameFolderName's rule. Pure.
    @($Names | Where-Object { Test-SameFolderName $_ $Name }).Count -gt 0
}

function Resolve-InstallerPath([string] $Path) {
    # A folder as the run uses it: ~ expanded, made full against the current location, no trailing separator.
    $separators = [char[]] @([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if ($Path.StartsWith('~')) { $Path = $HOME + $Path.Substring(1) }
    [IO.Path]::GetFullPath($Path, (Get-Location -PSProvider FileSystem).ProviderPath).TrimEnd($separators)
}

function Invoke-SkillSetup([string] $Script, [string[]] $Arguments, [switch] $Quiet, [switch] $Unattended) {
    # The setup runs in a child pwsh, and its exit code is returned. Without BB_SKILLS_NOEXEC: inherited from an
    # installer that was dot-sourced, it would make the setup define its functions and run nothing, reporting
    # nothing missing. Quiet, its output is discarded and its input closed. Otherwise it runs on this console,
    # unpiped: piped, even through Out-Host, a question written without a line ending stays hidden until the
    # answer's Enter completes the line, so the setup would wait on a question nobody can see. Unattended, with
    # nobody there for the installer, it is told so three ways: pwsh -NonInteractive, BB_SKILLS_NO_PROMPT, and its
    # input closed, so it takes its answers and declines the rest rather than asking.
    $start = [Diagnostics.ProcessStartInfo]::new([Environment]::ProcessPath)
    $words = @('-NoProfile')
    if ($Unattended) { $words += '-NonInteractive' }
    foreach ($argument in $words + @('-File', $Script) + @($Arguments)) { $start.ArgumentList.Add([string] $argument) }
    $start.UseShellExecute = $false
    [void] $start.Environment.Remove('BB_SKILLS_NOEXEC')
    if ($Unattended) { $start.Environment['BB_SKILLS_NO_PROMPT'] = '1' }
    if ($Quiet -or $Unattended) { $start.RedirectStandardInput = $true }
    if ($Quiet) {
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
    }
    $process = [Diagnostics.Process]::Start($start)
    if ($Quiet -or $Unattended) { $process.StandardInput.Close() }
    if ($Quiet) {
        $out = $process.StandardOutput.ReadToEndAsync()
        $err = $process.StandardError.ReadToEndAsync()
    }
    $process.WaitForExit()
    if ($Quiet) { $null = $out.Result, $err.Result }
    $process.ExitCode
}

function Get-SettingsPath([string] $Destination) {
    # The settings.json a skills folder's hooks go into: the one beside it, as ~/.claude/settings.json is beside
    # ~/.claude/skills.
    Join-Path (Split-Path -Parent $Destination) 'settings.json'
}

function Write-SettingsUnderLock {
    <#
        Writes settings.json under settings.json.lock, held open for no one else while the file is read again and
        written, then read back. Status is written; changed (the file changed since it was read, so nothing was
        written); locked (another run holds the lock); unread (the file doesn't read back as written); or whatif
        (-WhatIf, so nothing was written, the lock included). Backup is the stamped copy's path, or '' for a new file.
        The lock goes when the write is done, in a finally, and is never taken from another run that holds it.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param($Settings, [string] $Text)
    $lockPath = $Settings.Path + '.lock'
    if (-not $PSCmdlet.ShouldProcess($Settings.Path, 'Write the settings, under the lock beside them')) {
        return @{ Status = 'whatif'; Backup = ''; Lock = $lockPath }
    }
    $lock = $null
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while ($null -eq $lock) {
        try {
            $lock = [IO.FileStream]::new($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None, 1,
                [IO.FileOptions]::DeleteOnClose)
        } catch [IO.IOException] {
            if ($clock.ElapsedMilliseconds -ge $script:LockWaitMs) { return @{ Status = 'locked'; Backup = ''; Lock = $lockPath } }
            Start-Sleep -Milliseconds 200
        } catch [UnauthorizedAccessException] {
            if ($clock.ElapsedMilliseconds -ge $script:LockWaitMs) { return @{ Status = 'locked'; Backup = ''; Lock = $lockPath } }
            Start-Sleep -Milliseconds 200
        }
    }
    try {
        # The question, if any, was asked above, so the write inside asks none of its own.
        $backup = Write-SettingsFile $Settings $Text -Confirm:$false
        if ($null -eq $backup) { return @{ Status = 'changed'; Backup = ''; Lock = $lockPath } }
        # Test seam: something else changing the file between the write and the read-back.
        if ($env:BB_SKILLS_DISTURB_SETTINGS -eq '1') { [IO.File]::AppendAllText($Settings.Path, ' ') }
        # Read back while the lock is still held, so the bytes compared are this run's.
        $encoding = [Text.UTF8Encoding]::new($false)
        $expected = [byte[]] ([Text.UTF8Encoding]::new($Settings.Bom).GetPreamble() + $encoding.GetBytes($Text))
        $landed = if (Test-Path -LiteralPath $Settings.Path -PathType Leaf) { Get-Sha256 ([IO.File]::ReadAllBytes($Settings.Path)) } else { '' }
        if ($landed -ne (Get-Sha256 $expected)) { return @{ Status = 'unread'; Backup = $backup; Lock = $lockPath } }
        return @{ Status = 'written'; Backup = $backup; Lock = $lockPath }
    } finally {
        # DeleteOnClose takes the lock file away with the handle; deleting it by name could take another run's.
        $lock.Dispose()
    }
}

function Write-SettingsRefusal([hashtable] $Result, [string] $SettingsPath, [hashtable] $Again) {
    # A settings write that couldn't be made: the reason, and the command to run again.
    if ($Result.Status -eq 'whatif') {
        Write-Tag 'ok' "Under -WhatIf nothing is written to $SettingsPath."
        return
    }
    if ($Result.Status -eq 'locked') {
        Write-RunFailure "$SettingsPath is locked by another run, which holds $($Result.Lock): nothing was written. Run this again once it ends."
    } elseif ($Result.Status -eq 'unread') {
        $kept = if ($Result.Backup) { " The settings as they were: $($Result.Backup)" } else { '' }
        Write-RunFailure "$SettingsPath doesn't read back as it was written, so something else may have changed it.$kept" -NoWrap
    } else {
        Write-RunFailure "$SettingsPath changed while this ran, so nothing was written over the change. Run this again to see it."
    }
    Write-ApplyCommand 'To run it again' $Again
}

function Show-SettingsChange([string] $Old, [string] $New) {
    foreach ($line in @(Get-LineDiff $Old $New)) { Write-Tag '..' $line -NoWrap }
}

#endregion

#region ------------------------------------------------------------- Names

function Get-ReservedNames {
    # The names Claude Code keeps for itself, from tools/builtin-commands.txt, compared without regard to case.
    if (-not (Test-Path -LiteralPath $script:ReservedNamesPath -PathType Leaf)) {
        throw "$($script:ReservedNamesPath) is missing, so a new name can't be checked against Claude Code's own."
    }
    $reserved = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($line in [IO.File]::ReadAllLines($script:ReservedNamesPath)) {
        $line = $line.Trim()
        if ($line -and -not $line.StartsWith('#')) { [void] $reserved.Add($line) }
    }
    Write-Output -NoEnumerate $reserved
}

function Read-FormerNames([string] $SkillDir, [string] $Label) {
    # The earlier names a skill's .former-names lists, one to a line, blank lines passed over. Throws on a line that
    # can't be a skill's name.
    $file = Join-Path $SkillDir $script:FormerNamesFile
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return }
    foreach ($line in [IO.File]::ReadAllLines($file)) {
        $name = $line.Trim()
        if (-not $name) { continue }
        if ($name -cnotmatch $script:NameRule) {
            throw "$Label's $($script:FormerNamesFile) lists '$name', which can't be a skill's name."
        }
        $name
    }
}

function Get-FormerNames($Skills) {
    # Each earlier name the source's skills list, with the skill that lists it. Throws, before anything changes, on one
    # that is a source skill's own name or that two skills list.
    $map = @{}
    foreach ($skill in $Skills) {
        foreach ($earlier in @(Read-FormerNames $skill.FullName $skill.Name)) {
            if ($earlier -in $Skills.Name) {
                throw "$($skill.Name)'s $($script:FormerNamesFile) lists $earlier, which is a skill of the source."
            }
            if ($map.ContainsKey($earlier) -and $map[$earlier] -ine $skill.Name) {
                $both = @($map[$earlier], $skill.Name) | Sort-Object
                throw "$earlier is listed in $($script:FormerNamesFile) by both $($both[0]) and $($both[1])."
            }
            $map[$earlier] = $skill.Name
        }
    }
    $map
}

function Get-InstalledCopies([string] $Destination, [hashtable] $FormerNames = @{}) {
    # Each folder in the skills folder, with the skill it belongs to: the one its .renamed-from names, or, without
    # one, the one it is named after; and where that is an earlier name of a source skill's, that skill.
    if (-not (Test-Path -LiteralPath $Destination -PathType Container)) { return }
    foreach ($folder in Get-ChildItem -LiteralPath $Destination -Directory) {
        $owner = $folder.Name
        $renamed = $false
        $marker = Join-Path $folder.FullName $script:RenameMarker
        if (Test-Path -LiteralPath $marker -PathType Leaf) {
            $recorded = [IO.File]::ReadAllText($marker).Trim()
            if ($recorded) { $owner = $recorded; $renamed = $true }
        }
        if ($FormerNames.ContainsKey($owner)) { $owner = $FormerNames[$owner] }
        [pscustomobject] @{ Folder = $folder.Name; Owner = $owner; Renamed = $renamed }
    }
}

function Split-ListArgument([string[]] $Values) {
    # A list parameter's entries: pwsh -File passes a list as one string, so each value is split on commas outside
    # double quotes, and each entry trimmed. Pure.
    $entries = [Collections.Generic.List[string]]::new()
    foreach ($value in @($Values)) {
        if ($null -eq $value) { continue }
        $part = [Text.StringBuilder]::new()
        $quoted = $false
        foreach ($ch in $value.ToCharArray()) {
            if ($ch -eq '"') { $quoted = -not $quoted }
            if ($ch -eq ',' -and -not $quoted) {
                $entries.Add($part.ToString().Trim())
                [void] $part.Clear()
                continue
            }
            [void] $part.Append($ch)
        }
        $entries.Add($part.ToString().Trim())
    }
    @($entries | Where-Object { $_ })
}

function Read-RenamePairs([string[]] $Pairs, [string[]] $SkillNames) {
    # -Rename as each source skill's new name, and a sentence for each pair that can't be one.
    $map = [ordered] @{}
    $problems = [Collections.Generic.List[string]]::new()
    foreach ($pair in @(Split-ListArgument $Pairs)) {
        $parts = @($pair -split '=', 2 | ForEach-Object { $_.Trim() })
        if ($parts.Count -ne 2 -or -not $parts[0] -or -not $parts[1]) {
            $problems.Add("-Rename takes old=new pairs, comma-separated, and '$pair' isn't one.")
            continue
        }
        $known = @($SkillNames | Where-Object { $_ -ieq $parts[0] })
        if ($known.Count -eq 0) { $problems.Add("-Rename names $($parts[0]), but the source has no skill named $($parts[0])."); continue }
        if ($map.Contains($known[0])) { $problems.Add("-Rename names $($known[0]) twice."); continue }
        $map[$known[0]] = $parts[1]
    }
    @{ Map = $map; Problems = $problems.ToArray() }
}

function Resolve-ChosenNames([string[]] $Names, [string[]] $SkillNames, $Copies) {
    # The source skills -Skill names, by their own names or the names their copies are installed under, found
    # through .renamed-from, and a sentence for each name that is neither or both.
    $found = [Collections.Generic.List[string]]::new()
    $problems = [Collections.Generic.List[string]]::new()
    foreach ($entry in @(Split-ListArgument $Names)) {
        $own = @($SkillNames | Where-Object { $_ -ieq $entry })
        $installedAs = @($Copies | Where-Object { $_.Renamed -and $_.Folder -ieq $entry -and $_.Owner -in $SkillNames } |
            ForEach-Object { $_.Owner })
        if ($own.Count -gt 0 -and $installedAs.Count -gt 0 -and $installedAs[0] -ine $own[0]) {
            $problems.Add("'$entry' names two skills: the source's $($own[0]), and $($installedAs[0]), installed as $entry. Rename one of them first.")
            continue
        }
        $match = @(@($own) + @($installedAs) | Select-Object -First 1)
        if ($match.Count -eq 0) { $problems.Add("-Skill names $entry, but no skill of this source has that name or is installed under it."); continue }
        $canonical = @($SkillNames | Where-Object { $_ -ieq $match[0] })[0]
        if (-not $found.Contains($canonical)) { $found.Add($canonical) }
    }
    @{ Names = $found.ToArray(); Problems = $problems.ToArray() }
}

function Get-InstallNameProblem {
    # Why $Skill can't be installed under $Target, or $null when it can. $Settled holds the names the skills before it
    # install under, and $Planned the names those after it would.
    param([string] $Skill, [string] $Target, $Copies, $Settled, $Planned, [string] $Destination, $Reserved)
    if ($Target -cne $Skill) {
        if ($Target -cnotmatch $script:NameRule) {
            return "'$Target' can't be a skill's name: it takes lowercase letters, digits and hyphens, at most 64 of them, a letter or a digit first."
        }
        if ($Reserved.Contains($Target)) { return "'$Target' is Claude Code's own /$Target, which a skill of that name would replace." }
    }
    # Folder names compare as the file system compares them: Test-SameFolderName.
    foreach ($copy in $Copies) {
        if ($copy.Renamed -and (Test-SameFolderName $copy.Folder $Target) -and -not (Test-SameFolderName $copy.Owner $Skill)) {
            return "$Skill can't be installed as ${Target}: that folder is $($copy.Owner)'s copy. Give one of them another name with -Rename."
        }
    }
    # A folder this skill already holds is its own: a skill after it that wants the name is the one refused.
    $holds = @($Copies | Where-Object { (Test-SameFolderName $_.Folder $Target) -and (Test-SameFolderName $_.Owner $Skill) }).Count -gt 0
    $others = @($Settled.GetEnumerator())
    if (-not $holds) { $others += @($Planned.GetEnumerator()) }
    foreach ($entry in $others) {
        if (-not (Test-SameFolderName $entry.Key $Skill) -and (Test-SameFolderName $entry.Value $Target)) { return "'$Target' is the name $($entry.Key) installs under." }
    }
    foreach ($copy in $Copies) {
        if ((Test-SameFolderName $copy.Folder $Target) -and -not (Test-SameFolderName $copy.Owner $Skill)) {
            return "'$Target' is a folder in $Destination that isn't $Skill's. There is no override for that, -Force included: give $Skill another name with -Rename."
        }
    }
    $null
}

function Read-InstallName {
    <#
        Asks what to install $SkillName as, offering $Offer, until the answer is a name it can take: Enter takes the
        offer, and - leaves the skill as it is. A y, yes, n or no is asked again, since the same run asks y/N
        questions. Returns Name, $null with Skip for -, or Ended when input ran out, Name then the offer or $null.
    #>
    param([string] $SkillName, [string] $Offer, [string] $Reason, [switch] $IsNew, $Copies, $Settled, $Planned,
        [string] $Destination, $Reserved)
    if ($Reason) { Write-Tag 'note' $Reason }
    $question = if ($IsNew) { "$SkillName is new here. Install it as (- leaves it out)" } else { "Install $SkillName as (- leaves it out)" }
    $answer = Read-Answer $question $Offer {
        param([string] $Typed)
        if ($Typed -eq '-') { return '' }
        if ($Typed -in 'y', 'yes', 'n', 'no') {
            $instead = if ($Offer) { ", or Enter for $Offer" } else { '' }
            return "'$Typed' reads as an answer to a yes/no question. Type a name$instead."
        }
        $refusal = Get-InstallNameProblem -Skill $SkillName -Target $Typed -Copies $Copies -Settled $Settled -Planned $Planned `
            -Destination $Destination -Reserved $Reserved
        if ($refusal) { return $refusal }
        return ''
    }
    if ($null -eq $answer) { return @{ Ended = $true; Skip = $false; Name = $(if ($Offer) { $Offer } else { $null }) } }
    if ($answer -eq '-') { return @{ Ended = $false; Skip = $true; Name = $null } }
    return @{ Ended = $false; Skip = $false; Name = $answer }
}

function Resolve-InstallNames {
    <#
        The name each source skill installs under, settled before anything changes: -Rename's, else the answer to
        the question, $null where it was -, else the name its copy already has, else its own. A renamed copy outranks
        one under the skill's own name. With -Ask, a skill -Rename doesn't name is asked about when it has no copy,
        when its name can't be used, or for every skill with -AskAll. Problems holds -Rename's names that can't be
        used, and NeedsName each skill whose name can't be used with nobody to ask. Answered holds the names given
        at the terminal, to fold into the command that does the same again.
    #>
    param($Skills, $Copies, $RenameMap, [string] $Destination, [switch] $Ask, [switch] $AskAll, [string[]] $Chosen = @())
    $planned = [ordered] @{}
    $isNew = @{}
    foreach ($skill in $Skills) {
        $mine = @($Copies | Where-Object { Test-SameFolderName $_.Owner $skill.Name })
        $isNew[$skill.Name] = $mine.Count -eq 0
        $renamedCopy = @($mine | Where-Object Renamed | Sort-Object Folder | Select-Object -First 1)
        $plannedName = $skill.Name
        if ($RenameMap.Contains($skill.Name)) { $plannedName = $RenameMap[$skill.Name] }
        elseif ($renamedCopy.Count -gt 0) { $plannedName = $renamedCopy[0].Folder }
        $planned[$skill.Name] = $plannedName
    }
    $reserved = Get-ReservedNames
    $settled = [ordered] @{}
    $problems = [Collections.Generic.List[string]]::new()
    $needs = [Collections.Generic.List[object]]::new()
    $answered = [ordered] @{}
    foreach ($skill in $Skills) {
        $target = $planned[$skill.Name]
        $planned.Remove($skill.Name)
        if ($Chosen.Count -gt 0 -and $skill.Name -notin $Chosen) {
            $settled[$skill.Name] = $target
            continue
        }
        $problem = Get-InstallNameProblem -Skill $skill.Name -Target $target -Copies $Copies -Settled $settled `
            -Planned $planned -Destination $Destination -Reserved $reserved
        if ($RenameMap.Contains($skill.Name)) {
            if ($problem) { $problems.Add($problem) }
        } elseif ($Ask -and ($AskAll -or $isNew[$skill.Name] -or $problem)) {
            $offer = if ($problem) { '' } else { $target }
            $reply = Read-InstallName -SkillName $skill.Name -Offer $offer -Reason $problem -IsNew:($isNew[$skill.Name]) `
                -Copies $Copies -Settled $settled -Planned $planned -Destination $Destination -Reserved $reserved
            if ($reply.Ended -and -not $reply.Name) {
                $needs.Add([pscustomobject] @{ Skill = $skill.Name; Problem = "No name was given for $($skill.Name)." })
            }
            # A name typed in place of the one on offer is folded into the command that does the same again; a -,
            # which no flag says, is not.
            $offered = $target
            $target = if ($reply.Skip) { $null } else { $reply.Name }
            if (-not $reply.Ended -and -not $reply.Skip -and $target -cne $offered) { $answered[$skill.Name] = $target }
        } elseif ($problem) {
            $needs.Add([pscustomobject] @{ Skill = $skill.Name; Problem = $problem })
        }
        $settled[$skill.Name] = $target
    }
    @{ Names = $settled; Problems = $problems.ToArray(); NeedsName = $needs.ToArray(); Answered = $answered }
}

function Get-MentionPatterns([string] $Name) {
    # Where a skill's name can only mean the skill: a command, its / starting a word and nothing after the name that
    # would make it a longer name, a path or a file; and the installer's own -AddHooks, -RemoveHooks and -Configure,
    # across a line break too. Never the name as an ordinary word: commit, handoff and choices are English.
    $escaped = [regex]::Escape($Name)
    @{
        Command = '(?m)(?<=^|[\s"''(\[`])/' + $escaped + '(?![A-Za-z0-9_/-]|\.[A-Za-z])'
        Argument = '(?<=-(?i:AddHooks|RemoveHooks|Configure)\s+)' + $escaped + '(?![A-Za-z0-9_-])'
        CodeSpan = '`' + $escaped + '`'
    }
}

function Rename-SkillText([string] $Text, [string] $From, [string] $To) {
    # SKILL.md's text with the skill's name changed from $From to $To where it can only mean the skill: its
    # frontmatter's name: line, and each mention Get-MentionPatterns finds.
    $match = [regex]::Match($Text, '\A---\r?\n(.*?\r?\n)---(\r?\n|\z)', 'Singleline')
    if ($match.Success) {
        $block = $match.Groups[1]
        $renamed = [regex]::Replace($block.Value, '(?m)^name:[ \t]*' + [regex]::Escape($From) + '[ \t]*(?=\r?$)', "name: $To")
        $Text = $Text.Substring(0, $block.Index) + $renamed + $Text.Substring($block.Index + $block.Length)
    }
    $patterns = Get-MentionPatterns $From
    $Text = [regex]::Replace($Text, $patterns.Command, "/$To")
    [regex]::Replace($Text, $patterns.Argument, $To)
}

function Get-ChangedLines([string] $Old, [string] $New) {
    # The lines a rename changed, by number. A rename changes no line breaks, so the lines pair up.
    $before = $Old -split '\r?\n'
    $after = $New -split '\r?\n'
    for ($i = 0; $i -lt [Math]::Min($before.Count, $after.Count); $i++) {
        if ($before[$i] -cne $after[$i]) { [pscustomobject] @{ Number = $i + 1; Old = $before[$i]; New = $after[$i] } }
    }
}

function Find-SkillMentions([string] $Text, [string] $Name) {
    # The lines of a SKILL.md that mention the skill $Name, as a command, an -AddHooks, -RemoveHooks or -Configure
    # argument, or a code span holding just the name, each once, in order.
    $patterns = Get-MentionPatterns $Name
    $lines = $Text -split '\r?\n'
    $numbers = [Collections.Generic.SortedSet[int]]::new()
    foreach ($pattern in $patterns.Command, $patterns.Argument, $patterns.CodeSpan) {
        foreach ($found in [regex]::Matches($Text, $pattern)) {
            [void] $numbers.Add(([regex]::Matches($Text.Substring(0, $found.Index), '\n')).Count + 1)
        }
    }
    foreach ($number in $numbers) { [pscustomobject] @{ Number = $number; Line = $lines[$number - 1] } }
}

function Get-RenamedSkillBytes([string] $SkillFile, [string] $From, [string] $To) {
    # A SKILL.md as a rename writes it: the renamed text, with the BOM it had. Returns Bytes, and Text both ways.
    $bytes = [IO.File]::ReadAllBytes($SkillFile)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $text = [IO.File]::ReadAllText($SkillFile)
    $renamedText = Rename-SkillText $text $From $To
    $encoding = [Text.UTF8Encoding]::new($bom)
    @{ Bytes = [byte[]] ($encoding.GetPreamble() + $encoding.GetBytes($renamedText)); Old = $text; New = $renamedText; Bom = $bom }
}

function Get-ExpectedCopy([string] $SourceDir, [string] $Name, [string] $Source) {
    # Each file a copy of the skill in $SourceDir installed as $Name holds, by its path inside the copy, with its
    # SHA-256: the source's files, and for a rename the renamed SKILL.md and the .renamed-from naming $Source.
    $files = [ordered] @{}
    $root = [IO.Path]::GetFullPath($SourceDir)
    foreach ($file in @(Get-ChildItem -LiteralPath $SourceDir -Recurse -File -Force | Sort-Object FullName)) {
        $relative = [IO.Path]::GetRelativePath($root, $file.FullName).Replace('\', '/')
        $files[$relative] = Get-Sha256 ([IO.File]::ReadAllBytes($file.FullName))
    }
    if ($Name -cne $Source) {
        $files['SKILL.md'] = Get-Sha256 (Get-RenamedSkillBytes (Join-Path $SourceDir 'SKILL.md') $Source $Name).Bytes
        $files[$script:RenameMarker] = Get-Sha256 ([Text.UTF8Encoding]::new($false).GetBytes("$Source`n"))
    }
    $files
}

function Get-CopyDifference([string] $SourceDir, [string] $CopyDir, [string] $Name, [string] $Source) {
    # The first way the copy in $CopyDir differs from what an install of $SourceDir as $Name writes, or '' when it
    # doesn't.
    $want = Get-ExpectedCopy $SourceDir $Name $Source
    $root = [IO.Path]::GetFullPath($CopyDir)
    $have = [ordered] @{}
    foreach ($file in @(Get-ChildItem -LiteralPath $CopyDir -Recurse -File -Force | Sort-Object FullName)) {
        $have[[IO.Path]::GetRelativePath($root, $file.FullName).Replace('\', '/')] = Get-Sha256 ([IO.File]::ReadAllBytes($file.FullName))
    }
    foreach ($path in $want.Keys) {
        if (-not $have.Contains($path)) { return "$path is missing" }
        if ($have[$path] -ne $want[$path]) { return "$path differs" }
    }
    foreach ($path in $have.Keys) { if (-not $want.Contains($path)) { return "$path is not the source's" } }
    ''
}

function Copy-SkillToStaging {
    # A copy of the skill at $From, built in $StagingRoot under the name it installs as: for a rename, its SKILL.md
    # renamed and its .renamed-from written. Returns its path and the lines a rename changed; under -WhatIf, nothing.
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([string] $From, [string] $StagingRoot, [string] $Name, [string] $Source)
    $staged = Join-Path $StagingRoot $Name
    if (-not $PSCmdlet.ShouldProcess($staged, "Stage a copy of $From")) { return }
    if (-not (Test-Path -LiteralPath $StagingRoot -PathType Container)) { New-Item -ItemType Directory -Path $StagingRoot | Out-Null }
    Copy-Item -LiteralPath $From -Destination $staged -Recurse
    $changes = @()
    if ($Name -cne $Source) {
        $skillFile = Join-Path $staged 'SKILL.md'
        $renamed = Get-RenamedSkillBytes $skillFile $Source $Name
        [IO.File]::WriteAllBytes($skillFile, $renamed.Bytes)
        [IO.File]::WriteAllText((Join-Path $staged $script:RenameMarker), "$Source`n", [Text.UTF8Encoding]::new($false))
        $changes = @(Get-ChangedLines $renamed.Old $renamed.New)
    }
    [pscustomobject] @{ Path = $staged; Changes = $changes }
}

function Get-FreePath([string] $Path) {
    # $Path, or $Path-2, -3 and so on when an earlier run in the same second already took it.
    $candidate = $Path
    for ($n = 2; Test-Path -LiteralPath $candidate; $n++) { $candidate = "$Path-$n" }
    $candidate
}

function Write-RestoreNotes {
    <#
        RESTORE.md in a backup folder: what it holds and how to put each copy back. $Saved holds each kept folder's
        name, Folder, and the name of the copy that replaced it, Now, which a rename makes another; a copy that never
        landed, in a run that stopped, has nothing to move out. Written beside its name, then moved into place. A write
        into the backup folder, so the install passes -Confirm:$false.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([string] $BackupRoot, [string] $Destination, $Saved)
    $target = Join-Path $BackupRoot 'RESTORE.md'
    if (-not $PSCmdlet.ShouldProcess($target, 'Write the notes on putting the replaced copies back')) { return }
    # Every single quote doubled, typographic ones included, which PowerShell reads as quotes too.
    $quote = { param([string] $Path) "'" + [Management.Automation.Language.CodeGeneration]::EscapeSingleQuotedStringContent($Path) + "'" }
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add('# Restoring what an install replaced')
    $lines.Add('')
    $lines.Add("This folder holds the copies of skills in ``$Destination`` that an install replaced on " +
        (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture) + ' UTC: ' +
        (($Saved | ForEach-Object { "``$($_.Folder)``" }) -join ', ') + '.')
    $lines.Add('')
    $lines.Add('To put one back, move the copy that replaced it out of the skills folder, then move this one in. For each:')
    $movedOut = [Collections.Generic.HashSet[string]]::new((Get-FolderComparer))
    foreach ($entry in $Saved) {
        $installed = Join-Path $Destination $entry.Now
        $kept = Join-Path $BackupRoot $entry.Folder
        $lines.Add('')
        $lines.Add($(if ($entry.Now -cne $entry.Folder) { "``$($entry.Folder)``, replaced by ``$($entry.Now)``:" } else { "``$($entry.Folder)``:" }))
        $lines.Add('')
        $lines.Add('```powershell')
        if ($movedOut.Add($entry.Now)) {
            $lines.Add("if (Test-Path -LiteralPath $(& $quote $installed)) { Move-Item -LiteralPath $(& $quote $installed) -Destination $(& $quote ((Join-Path $BackupRoot $entry.Now) + '.installed')) }")
        }
        $lines.Add("Move-Item -LiteralPath $(& $quote $kept) -Destination $(& $quote (Join-Path $Destination $entry.Folder))")
        $lines.Add('```')
    }
    $hooked = @($Saved | Where-Object { Test-Path -LiteralPath (Join-Path $BackupRoot $_.Folder 'hooks.json') -PathType Leaf })
    if ($hooked.Count -gt 0) {
        # A renamed copy's hooks name its new folder, which the moves above take away: those come out first. Then each
        # copy put back has its own offered again, -Yes taking out any other hook left naming a folder that is gone.
        $commands = [Collections.Generic.List[hashtable]]::new()
        $removed = [Collections.Generic.HashSet[string]]::new((Get-FolderComparer))
        foreach ($entry in $hooked) {
            if (-not (Test-SameFolderName $entry.Now $entry.Folder) -and $removed.Add($entry.Now)) {
                $commands.Add((Get-ActionCommand $Destination @{ RemoveHooks = $entry.Now }))
            }
        }
        foreach ($entry in $hooked) { $commands.Add((Get-ActionCommand $Destination @{ AddHooks = $entry.Folder; Yes = $true })) }
        $lines.Add('')
        $lines.Add('A copy whose skill brings hooks needs them offered again once it is back. After the moves, run these in order:')
        $lines.Add('')
        $lines.Add('```')
        foreach ($command in $commands) { $lines.Add($command.Text) }
        $lines.Add('```')
        if (@($commands | Where-Object { $_.PowerShellOnly }).Count -gt 0) {
            $lines.Add('')
            $lines.Add('They quote a value as PowerShell does, which bash and zsh read differently: run them from pwsh.')
        }
    }
    $temporary = "$target.tmp"
    [IO.File]::WriteAllText($temporary, (($lines -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $target -Force
}

function New-SkillsFolder {
    # The skills folder, made when it isn't there.
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([string] $Path)
    if (Test-Path -LiteralPath $Path -PathType Container) { return }
    if ($PSCmdlet.ShouldProcess($Path, 'Make the skills folder')) { New-Item -ItemType Directory -Path $Path | Out-Null }
}

function Move-ToBackup {
    <#
        An installed copy moved out of the skills folder into the run's backup folder, made when it isn't there, before
        its replacement goes in. Returns the folder's name; under -WhatIf, nothing. A write into the backup folder, so
        the install passes -Confirm:$false.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([string] $Path, [string] $BackupRoot)
    $leaf = Split-Path -Leaf $Path
    if (-not $PSCmdlet.ShouldProcess($Path, "Move the installed copy into $BackupRoot")) { return }
    if (-not (Test-Path -LiteralPath $BackupRoot -PathType Container)) { New-Item -ItemType Directory -Path $BackupRoot | Out-Null }
    Move-Item -LiteralPath $Path -Destination (Join-Path $BackupRoot $leaf)
    $leaf
}

function Remove-InstalledCopy {
    # An installed copy deleted before its replacement goes in, keeping none: -NoBackup -Force.
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([string] $Path)
    if ($PSCmdlet.ShouldProcess($Path, 'Delete the installed copy, keeping none')) { Remove-Item -LiteralPath $Path -Recurse -Force }
}

function Move-StagedCopy {
    # A staged copy moved into its place in the skills folder.
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([string] $Staged, [string] $Target)
    if ($PSCmdlet.ShouldProcess($Target, "Move the staged copy $Staged into place")) { Move-Item -LiteralPath $Staged -Destination $Target }
}

function Remove-StagingIfEmpty {
    # True when the staging folder holds something, which is left there; an empty one is removed.
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param([string] $Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    if (@(Get-ChildItem -LiteralPath $Path -Force).Count -gt 0) { return $true }
    if ($PSCmdlet.ShouldProcess($Path, 'Remove the empty staging folder')) { Remove-Item -LiteralPath $Path }
    $false
}

#endregion

#region ------------------------------------------------------------- Settings

function Read-SetPairs([string[]] $Values) {
    # -Set as pairs: Skill, Key, and Value, $null for -, a value's double quotes taken off; and a sentence for each
    # entry that is no skill.key=value pair.
    $pairs = [Collections.Generic.List[object]]::new()
    $problems = [Collections.Generic.List[string]]::new()
    foreach ($entry in @(Split-ListArgument $Values)) {
        if ($entry -notmatch '^([^.=\s]+)\.([^=\s]+)=(.*)$') {
            $problems.Add("-Set takes skill.key=value pairs, comma-separated, and '$entry' isn't one.")
            continue
        }
        $value = $Matches[3].Trim()
        if ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) { $value = $value.Substring(1, $value.Length - 2) }
        $pairs.Add([pscustomobject] @{ Skill = $Matches[1]; Key = $Matches[2]; Value = $(if ($value -eq '-') { $null } else { $value }); Entry = $entry })
    }
    @{ Pairs = $pairs.ToArray(); Problems = $problems.ToArray() }
}

function Resolve-SetValues($Pairs, $Declared, [string] $SkillName) {
    # Each -Set pair for one skill as the setting it sets and the JSON value it writes, $null to take it out; and a
    # sentence for each that names no setting the skill declares, a secret one, or a value that doesn't fit.
    $values = [Collections.Generic.List[object]]::new()
    $problems = [Collections.Generic.List[string]]::new()
    $settings = @($Declared.Options) + @($Declared.Variables)
    foreach ($pair in @($Pairs)) {
        $setting = @($settings | Where-Object { $_.Name -ceq $pair.Key }) + @($settings | Where-Object { $_.Name -ieq $pair.Key }) | Select-Object -First 1
        if ($null -eq $setting) {
            $known = (@($settings | Where-Object { -not $_.Sensitive } | ForEach-Object { $_.Name }) -join ', ')
            $problems.Add("-Set names $($pair.Entry), but $SkillName declares no setting $($pair.Key)$(if ($known) { "; it declares $known" }).")
            continue
        }
        if ($setting.Sensitive) { $problems.Add("-Set names $($pair.Entry), but $($setting.Name) is kept secret: set it in /config, which keeps it in secure storage."); continue }
        if ($null -eq $pair.Value) { $values.Add([pscustomobject] @{ Setting = $setting; Value = $null; Shown = '-' }); continue }
        $converted = ConvertTo-SettingValue $setting $pair.Value
        if ($converted.Problem) { $problems.Add("-Set names $($pair.Entry), but $($setting.Name) takes $(Get-SettingTakes $setting)."); continue }
        $values.Add([pscustomobject] @{ Setting = $setting; Value = $converted.Value; Shown = $pair.Value })
    }
    @{ Values = $values.ToArray(); Problems = $problems.ToArray() }
}

function Read-SettingAnswer($Setting, $Current) {
    # Asks one setting's value: the current value is what Enter keeps, - takes it out, and an answer that doesn't fit
    # is told what it takes and asked again. Returns Change and Value, $null to take it out.
    $leaves = if ($Setting.Unset) { "- leaves it unset: $($Setting.Unset)" } else { '- leaves it unset' }
    $question = '{0}: {1} ({2}; {3})' -f $Setting.Name, $Setting.Description, (Get-SettingTakes $Setting), $leaves
    $shown = if ($null -ne $Current) { Format-SettingNode $Current } else { '-' }
    $answer = Read-Answer $question $shown {
        param([string] $Typed)
        if ($Typed -eq '-') { return '' }
        $converted = ConvertTo-SettingValue $Setting $Typed
        if ($converted.Problem) { return "'$Typed' won't do: $($converted.Problem)." }
        return ''
    }
    if ($null -eq $answer -or $answer -ceq $shown) { return [pscustomobject] @{ Change = $false; Value = $null; Typed = '' } }
    if ($answer -eq '-') { return [pscustomobject] @{ Change = $null -ne $Current; Value = $null; Typed = '-' } }
    [pscustomobject] @{ Change = $true; Value = (ConvertTo-SettingValue $Setting $answer).Value; Typed = $answer }
}

function Format-SetEntry([string] $Skill, [string] $Key, [string] $Typed) {
    # One -Set entry, skill.key=value, as an answer typed at the terminal folds into the command: the value in double
    # quotes when it holds a comma, as -Set's list syntax takes it. Pure.
    $value = if ($Typed.Contains(',')) { '"' + $Typed + '"' } else { $Typed }
    "$Skill.$Key=$value"
}

function Get-SettingsProblem($Settings, [string] $Key) {
    # Why the settings file can't take a skill's settings, or $null.
    if ($Settings.Problem) { return $Settings.Problem }
    Get-SettingsShapeProblem $Settings.Root $Key
}

#endregion


#region ------------------------------------------------------------- Hooks and settings offers

function Get-HookChange {
    <#
        What registering one skill's hooks would make of the settings beside $Destination: Kind blocked (Tag and
        Message say why), registered, or change (Settings, Text, What, Path); Notes are said either way. $SourceDir is
        where hooks.json is read, the installed copy unless a dry run reads the source for the copy it would make.
    #>
    param([string] $Name, [string] $SkillDir, [string] $Destination, [string[]] $FormerDirs = @(), [string] $SourceDir = '')
    $settingsPath = Get-SettingsPath $Destination
    $notes = [Collections.Generic.List[string]]::new()
    $blocked = { param([string] $Tag, [string] $Message) @{ Kind = 'blocked'; Tag = $Tag; Message = $Message; Notes = $notes.ToArray(); Path = $settingsPath } }
    if (Test-InGitWorkTree (Split-Path -Parent $settingsPath)) {
        return (& $blocked 'note' "$Name brings hooks, but $settingsPath is inside a git work tree, where this machine's paths don't belong. Not offered.")
    }
    $declared = if ($SourceDir) { Get-SkillHooks $SourceDir $SkillDir } else { Get-SkillHooks $SkillDir }
    if ($declared.Problem) { return (& $blocked 'warn' "$Name brings hooks, but $($declared.Problem). Not offered.") }
    if ($declared.UsesArgs) {
        $version = Get-ClaudeVersion
        if ($null -eq $version) {
            $notes.Add("$Name's hooks need Claude Code $($script:MinimumArgsVersion) or later. claude --version couldn't be read here, as when Claude Code comes only with a desktop app or an IDE, so make sure yours is that recent.")
        } elseif ($version -lt $script:MinimumArgsVersion) {
            return (& $blocked 'warn' "$Name's hooks need Claude Code $($script:MinimumArgsVersion) or later, and claude here is $version. Not offered.")
        }
    }
    $settings = Read-SettingsFile $settingsPath
    if ($settings.Problem) { return (& $blocked 'warn' "$Name brings hooks, but $settingsPath can't be changed: $($settings.Problem)") }
    $plan = Get-HookPlan $settings $declared.Hooks $SkillDir $FormerDirs
    if ($plan.State -eq 'registered') { return @{ Kind = 'registered'; Notes = $notes.ToArray(); Path = $settingsPath } }
    $what = if ($plan.Moved) { 'moves them from {0} in' -f ((@($FormerDirs | Where-Object { $_ }) | Split-Path -Leaf) -join ', ') }
        elseif ($plan.State -eq 'replace') { 'replaces its earlier hooks in' } else { 'registers them in' }
    @{ Kind = 'change'; Notes = $notes.ToArray(); Path = $settingsPath; Settings = $settings; Text = (Format-SettingsText $settings $plan.Root); What = $what }
}

function Write-HookNotes([hashtable] $Change) {
    foreach ($note in $Change.Notes) { Write-Tag 'note' $note }
    if ($Change.Kind -ne 'blocked') { return }
    if ($Change.Tag -eq 'warn') { Write-RunWarning $Change.Message } else { Write-Tag 'note' $Change.Message }
}

function Invoke-HookOffer {
    <#
        Offers one installed skill's hooks for the settings beside $Destination. $Mode is ask, for a person; yes, for
        -Yes or a named -AddHooks; or later, for nobody there, which says the flag that adds them. Returns registered,
        registered now, declined, not asked, not offered or failed.
    #>
    param([string] $Name, [string] $SkillDir, [string] $Destination, [string] $Mode, [string[]] $FormerDirs = @())
    $change = Get-HookChange $Name $SkillDir $Destination $FormerDirs
    Write-HookNotes $change
    if ($change.Kind -eq 'blocked') { return 'not offered' }
    if ($change.Kind -eq 'registered') { return 'registered' }
    $again = Get-ActionCommand $Destination @{ AddHooks = $Name }
    if ($Mode -eq 'later') {
        Write-Tag 'note' "$Name brings hooks, not added: nobody is there to ask, and -Yes adds them."
        Write-ApplyCommand 'To add them' $again
        return 'not asked'
    }
    Write-Tag '..' "$Name brings hooks. This change $($change.What) $($change.Path):"
    Show-SettingsChange $change.Settings.Text $change.Text
    if ($Mode -eq 'ask') {
        # Kept, since -Yes gives this answer next time when every such answer was a yes.
        $yes = [bool] (Read-YesNo 'Register them?')
        $script:YesAnswers.Add($yes)
        if (-not $yes) {
            Write-ApplyCommand 'Not registered. To add them later' $again
            return 'declined'
        }
    }
    $result = Write-SettingsUnderLock $change.Settings $change.Text
    if ($result.Status -ne 'written') {
        Write-SettingsRefusal $result $change.Path $again
        return 'failed'
    }
    if ($result.Backup) { Write-Tag 'ok' "Registered. The settings as they were: $($result.Backup)" -NoWrap }
    else { Write-Tag 'ok' "Registered, in a new $($change.Path)" -NoWrap }
    'registered now'
}

function Invoke-StaleHookCheck {
    <#
        Reports hooks that name something under the skills folder that is gone, since each fails on every tool call it
        matches. $Mode is ask, yes or report; dry says what -Apply would do. Left in place, as a person's no or with
        nobody to ask, they are the safe default, said with the flag that removes them: a note, as a declined offer is,
        not a warning.
    #>
    param([string] $Destination, [string] $Mode, [hashtable] $Again)
    $settingsPath = Get-SettingsPath $Destination
    $settings = Read-SettingsFile $settingsPath
    if ($settings.Problem -or -not $settings.Exists) { return }
    $stale = @(Get-StaleHandlers $settings $Destination)
    if ($stale.Count -eq 0) { return }
    Write-Tag '..' "These hooks in $settingsPath name something under $Destination that is gone, so each fails on every tool call it matches:"
    foreach ($entry in $stale) { Write-Tag '..' ('  {0} {1}: {2}' -f $entry.Event, $entry.Matcher, ($entry.Missing -join ', ')) -NoWrap }
    $plan = Get-StaleRemovalPlan $settings $Destination
    $text = Format-SettingsText $settings $plan.Root
    if ($Mode -eq 'dry') {
        if ($script:InstallerBound.ContainsKey('Yes')) { Write-Tag 'would' "Remove them from $settingsPath." }
        else { Write-Tag 'note' 'They would be left in place: -Yes removes them, or a person asked.' }
        return
    }
    if ($Mode -eq 'report') {
        Write-Tag 'note' 'They are left in place: nobody is there to ask, and -Yes removes them.'
        return
    }
    Show-SettingsChange $settings.Text $text
    if ($Mode -eq 'ask') {
        $yes = [bool] (Read-YesNo 'Remove them?')
        $script:YesAnswers.Add($yes)
        if (-not $yes) {
            Write-Tag 'note' 'They are left in place: -Yes on an install removes them.'
            return
        }
    }
    $result = Write-SettingsUnderLock $settings $text
    if ($result.Status -ne 'written') { Write-SettingsRefusal $result $settingsPath $Again; return }
    Write-Tag 'ok' "Removed. The settings as they were: $($result.Backup)" -NoWrap
}

function Invoke-SettingsOffer {
    <#
        Offers one installed skill's settings for the settings.json beside $Destination. $Mode is ask, a person asked
        each value, first whether to change any with -AskFirst; set, $Values from -Set written as they are, or once a
        person says yes with -AskWrite; or later, nobody there, each kept and the flag that sets one said. -DryRun
        shows the change and writes nothing; -NoCommand leaves the command that asks again to the caller. Returns
        written, unchanged, declined, kept, dry, not offered or failed. The answers a person typed are added to the
        run's $script:SettingAnswers as -Set entries once written, or shown under -DryRun, for the command that does
        the same again; answers declined are not, since that command would write them.
    #>
    param([string] $Name, [string] $SkillDir, [string] $Destination, [string] $Mode, $Values = @(), [switch] $AskFirst,
        [switch] $AskWrite, [switch] $DryRun, [switch] $NoCommand)
    $settingsPath = Get-SettingsPath $Destination
    if (Test-InGitWorkTree (Split-Path -Parent $settingsPath)) {
        Write-Tag 'note' "$Name has settings, but $settingsPath is inside a git work tree, where this machine's settings don't belong. Not offered."
        return 'not offered'
    }
    $declared = Get-SkillSettings $SkillDir
    if ($declared.Problem) { Write-RunWarning "$Name has settings, but $($declared.Problem). Not offered."; return 'not offered' }
    $settings = Read-SettingsFile $settingsPath
    $problem = Get-SettingsProblem $settings $declared.Key
    if ($problem) { Write-RunWarning "$Name has settings, but $settingsPath can't be changed: $problem"; return 'not offered' }
    $again = Get-ActionCommand $Destination @{ Configure = $Name }
    if ($Mode -eq 'later') {
        Write-Tag 'note' "$Name's settings are kept: nobody is there to ask, and -Set $Name.<key>=<value> sets one."
        Write-ApplyCommand "$Name has settings. To change them" $again
        return 'kept'
    }
    if ($Mode -eq 'ask' -and $AskFirst -and -not (Read-YesNo "$Name has settings. Change any now?")) {
        Write-ApplyCommand 'Nothing was written. To change them later' $again
        return 'declined'
    }
    $changes = [Collections.Generic.List[object]]::new()
    $typed = [Collections.Generic.List[string]]::new()
    if ($Mode -eq 'ask') {
        Write-Tag '..' 'Enter keeps a value, and - takes it out.'
        foreach ($group in @(
                @{ Settings = $declared.Options; Heading = "The options of its mod, in pluginConfigs's $($declared.Key):" },
                @{ Settings = $declared.Variables; Heading = 'The variables its hooks read, in env:' })) {
            if ($group.Settings.Count -eq 0) { continue }
            Write-Tag '..' $group.Heading
            foreach ($setting in $group.Settings) {
                if ($setting.Sensitive) {
                    Write-Tag '..' "$($setting.Name) is kept secret, so it isn't asked here: set it in /config, which keeps it in secure storage."
                    continue
                }
                $answer = Read-SettingAnswer $setting (Get-SettingNode $settings.Root $setting $declared.Key)
                if ($answer.Change) {
                    $changes.Add([pscustomobject] @{ Setting = $setting; Value = $answer.Value })
                    $typed.Add((Format-SetEntry $Name $setting.Name $answer.Typed))
                }
            }
        }
    } else {
        foreach ($value in @($Values)) { $changes.Add($value) }
    }
    $root = $settings.Root.DeepClone()
    foreach ($change in $changes) { Set-SettingNode $root $change.Setting $declared.Key $change.Value }
    $text = Format-SettingsText $settings $root
    if ($changes.Count -eq 0 -or ($settings.Exists -and $text -ceq $settings.Text)) {
        Write-Tag 'ok' 'Nothing to change: nothing written.'
        return 'unchanged'
    }
    if ($DryRun) {
        Write-Tag 'would' "Set them in ${settingsPath}:"
        Show-SettingsChange $settings.Text $text
        Write-Tag 'ok' 'Dry run: nothing written.'
        foreach ($entry in $typed) { $script:SettingAnswers.Add($entry) }
        return 'dry'
    }
    Write-Tag '..' "This change sets them in ${settingsPath}:"
    Show-SettingsChange $settings.Text $text
    if (($Mode -eq 'ask' -or $AskWrite) -and -not (Read-YesNo 'Write them?')) {
        if ($NoCommand) { Write-Tag 'ok' 'Nothing was written.' }
        else { Write-ApplyCommand 'Nothing was written. To change them later' $again }
        return 'declined'
    }
    $result = Write-SettingsUnderLock $settings $text
    if ($result.Status -ne 'written') { Write-SettingsRefusal $result $settingsPath $again; return 'failed' }
    if ($result.Backup) { Write-Tag 'ok' "Written. The settings as they were: $($result.Backup)" -NoWrap }
    else { Write-Tag 'ok' "Written, in a new $settingsPath" -NoWrap }
    Write-Tag '..' 'New sessions use them; one already open may keep what it started with.'
    foreach ($entry in $typed) { $script:SettingAnswers.Add($entry) }
    'written'
}

#endregion

#region ------------------------------------------------------------- The plan, the status, the dry run and the install

function Get-SourceSkills([string] $Source) {
    @(Get-ChildItem -LiteralPath $Source -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf })
}

function Get-SkillCompatibility {
    <#
        A SKILL.md's compatibility: line, what the skill needs, as the value on that one line with its quotes taken
        off; '' when the front matter has none, or holds it as a block. Pure.
    #>
    [OutputType([string])]
    param([string] $Text)
    $lines = $Text.Replace("`r`n", "`n").Split("`n")
    if ($lines.Count -lt 3 -or $lines[0] -ne '---') { return '' }
    for ($i = 1; $i -lt $lines.Count -and $lines[$i] -ne '---'; $i++) {
        if ($lines[$i] -notmatch '^compatibility:\s*(.*)$') { continue }
        $value = $Matches[1].Trim()
        if ($value -match "^'(.*)'$") { return $Matches[1].Replace("''", "'") }
        if ($value -match '^"(.*)"$') { return $Matches[1] }
        if ($value -match '^[>|]') { return '' }
        return $value
    }
    return ''
}

function Get-SkillNeeds([string] $SkillDir) {
    # What a source skill needs, from its SKILL.md's compatibility: line, shown as [needs ...]; '' when it says nothing.
    Get-SkillCompatibility ([IO.File]::ReadAllText((Join-Path $SkillDir 'SKILL.md')))
}

function Get-DeclaredName([string] $SkillDir) {
    # The name: line of a SKILL.md's front matter, or $null.
    $line = Get-Content -LiteralPath (Join-Path $SkillDir 'SKILL.md') -TotalCount 5 | Where-Object { $_ -like 'name:*' } | Select-Object -First 1
    if ($line) { return $line.Substring(5).Trim() }
    $null
}

function New-InstallPlan {
    <#
        Everything an install needs settled before it changes anything: the skills, their copies and the names they
        install under, -Rename's, -Skill's, -Set's and -SetupAnswer's, each problem with them, and each name nobody
        can give. With $Ask, a person is asked the names the flags don't give, once the flags hold no problem.
    #>
    param([string] $Source, [string] $Destination, [string[]] $Chosen, [bool] $Ask)
    $plan = @{
        Source = $Source; Destination = $Destination; Problems = [Collections.Generic.List[string]]::new(); NeedsName = @()
        Skills = @(); Selected = @(); Names = [ordered] @{}; Copies = @(); FormerNames = @{}; Skipped = @(); Chosen = @()
        SetValues = @{}; SetupAnswers = @{}; Answered = [ordered] @{}
    }
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { $plan.Problems.Add("Skill source folder not found: $Source"); return $plan }
    if (Test-SameFolderName $Source $Destination) { $plan.Problems.Add("Source and destination are the same folder: $Source"); return $plan }
    $skills = Get-SourceSkills $Source
    if ($skills.Count -eq 0) { $plan.Problems.Add("No skill folders (a folder containing SKILL.md) found under: $Source"); return $plan }
    $plan.Skills = $skills
    try { $plan.FormerNames = Get-FormerNames $skills } catch { $plan.Problems.Add($_.Exception.Message) }
    $plan.Copies = @(Get-InstalledCopies $Destination $plan.FormerNames)
    $names = @($skills.Name)

    $picked = Resolve-ChosenNames $Chosen $names $plan.Copies
    foreach ($p in $picked.Problems) { $plan.Problems.Add($p) }
    $plan.Chosen = @($picked.Names)
    $renames = Read-RenamePairs $Rename $names
    foreach ($p in $renames.Problems) { $plan.Problems.Add($p) }
    if ($plan.Chosen.Count -gt 0) {
        foreach ($renamed in @($renames.Map.Keys)) {
            if ($renamed -notin $plan.Chosen) { $plan.Problems.Add("-Rename names $renamed, which -Skill leaves out.") }
        }
    }
    if ($NoBackup -and -not $Force) {
        $plan.Problems.Add('-NoBackup replaces installed copies without keeping them: pass -Force as well, or leave -NoBackup out.')
    }
    # The skill of this run a name in -Set or -SetupAnswer means: its own name, the name -Rename gives it, which the
    # dry run's advice uses, or the name a renamed copy of it is installed under.
    $inRun = { param([string] $Named)
        $inChosen = { param($s) $plan.Chosen.Count -eq 0 -or $s.Name -in $plan.Chosen }
        $own = @($skills | Where-Object { $_.Name -ieq $Named -and (& $inChosen $_) })
        if ($own.Count) { return $own[0] }
        $renamedTo = @($renames.Map.GetEnumerator() | Where-Object { $_.Value -ieq $Named } | ForEach-Object { $_.Key })
        if ($renamedTo.Count) { return @($skills | Where-Object { $_.Name -ieq $renamedTo[0] -and (& $inChosen $_) }) | Select-Object -First 1 }
        $copy = @($plan.Copies | Where-Object { $_.Renamed -and (Test-SameFolderName $_.Folder $Named) })
        if ($copy.Count) { return @($skills | Where-Object { (Test-SameFolderName $_.Name $copy[0].Owner) -and (& $inChosen $_) }) | Select-Object -First 1 }
        $null
    }
    $sets = Read-SetPairs $Set
    foreach ($p in $sets.Problems) { $plan.Problems.Add($p) }
    $settingsPath = Get-SettingsPath $Destination
    $settingsFile = $null
    foreach ($group in @($sets.Pairs | Group-Object Skill)) {
        $skill = & $inRun $group.Name
        if ($null -eq $skill) { $plan.Problems.Add("-Set names $($group.Name), which is no skill this run installs."); continue }
        $declared = Get-SkillSettings $skill.FullName
        $resolved = Resolve-SetValues $group.Group $declared $skill.Name
        foreach ($p in $resolved.Problems) { $plan.Problems.Add($p) }
        $plan.SetValues[$skill.Name] = $resolved.Values
        # The file the values go into is read now, so a problem with it stops the run before anything is copied.
        if ($NoSettings -or $resolved.Values.Count -eq 0) { continue }
        if (Test-InGitWorkTree (Split-Path -Parent $settingsPath)) {
            $plan.Problems.Add("-Set names $($group.Name)'s settings, but $settingsPath is inside a git work tree, where this machine's settings don't belong.")
            continue
        }
        if ($null -eq $settingsFile) { $settingsFile = Read-SettingsFile $settingsPath }
        $problem = Get-SettingsProblem $settingsFile $declared.Key
        if ($problem) { $plan.Problems.Add("-Set names $($group.Name)'s settings, but $settingsPath can't be changed: $problem") }
    }
    foreach ($entry in @(Split-ListArgument $SetupAnswer)) {
        if ($entry -notmatch '^([^:\s]+):([^=\s]+=.+)$') { $plan.Problems.Add("-SetupAnswer takes skill:item=answer pairs, comma-separated, and '$entry' isn't one."); continue }
        $skill = & $inRun $Matches[1]
        $answer = $Matches[2]
        if ($null -eq $skill -or -not (Test-Path -LiteralPath (Join-Path $skill.FullName 'setup.ps1') -PathType Leaf)) {
            $plan.Problems.Add("-SetupAnswer names $($Matches[1]), which is no skill with a setup that this run installs.")
            continue
        }
        if (-not $plan.SetupAnswers.ContainsKey($skill.Name)) { $plan.SetupAnswers[$skill.Name] = [Collections.Generic.List[string]]::new() }
        $plan.SetupAnswers[$skill.Name].Add($answer)
    }

    $resolved = Resolve-InstallNames -Skills $skills -Copies $plan.Copies -RenameMap $renames.Map -Destination $Destination `
        -Ask:($Ask -and $plan.Problems.Count -eq 0) -AskAll:$AskNames -Chosen $plan.Chosen
    foreach ($p in $resolved.Problems) { $plan.Problems.Add($p) }
    $plan.NeedsName = $resolved.NeedsName
    $plan.Names = $resolved.Names
    $plan.Answered = $resolved.Answered
    # ForEach-Object { $_.Name }, never ForEach-Object Name: the member form asks ShouldProcess, so under -WhatIf it
    # returns nothing. So throughout.
    $plan.Skipped = @($skills | Where-Object { $null -eq $plan.Names[$_.Name] } | ForEach-Object { $_.Name })
    $plan.Selected = @($skills | Where-Object { ($plan.Chosen.Count -eq 0 -or $_.Name -in $plan.Chosen) -and $_.Name -notin $plan.Skipped })
    $plan
}

function Write-PlanProblems([hashtable] $Plan, [string] $NotAsked = 'nobody is there to give one') {
    # The flags' problems, each a FAIL line, and nothing changed: 2. Else each name not given, saying why it wasn't
    # asked: 64. Else 0.
    if ($Plan.Problems.Count -gt 0) {
        foreach ($problem in $Plan.Problems) { Write-Tag 'FAIL' $problem }
        Write-Tag 'FAIL' 'Nothing changed: each problem above is in the flags or the source, and stops the run before anything is written.'
        return 2
    }
    if ($Plan.NeedsName.Count -gt 0) {
        foreach ($need in $Plan.NeedsName) {
            Write-Tag 'FAIL' "$($need.Problem) Needs a name for $($need.Skill), and ${NotAsked}: pass -Rename $($need.Skill)=<name>."
        }
        return 64
    }
    0
}

function Get-FoldedSet([hashtable] $Plan, [hashtable] $Extra = @{}) {
    <#
        What a run's answers add to its command: each name typed at the terminal as a -Rename pair, beside -Rename's
        own; and a skill left out with -, as -Skill naming the rest of those the run chose, or of every skill. -Skill
        is then '' when nothing is left, which Write-FoldedCommand says rather than print a command that installs all.
    #>
    $set = @{}
    if ($Plan.Answered.Count -gt 0) {
        $pairs = @(Split-ListArgument $Rename) + @($Plan.Answered.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" })
        $set['Rename'] = $pairs -join ','
    }
    if ($Plan.Skipped.Count -gt 0) {
        $base = if ($Plan.Chosen.Count -gt 0) { @($Plan.Chosen) } else { @($Plan.Skills | ForEach-Object { $_.Name }) }
        $set['Skill'] = @($base | Where-Object { $_ -notin $Plan.Skipped }) -join ','
    }
    foreach ($k in $Extra.Keys) { $set[$k] = $Extra[$k] }
    $set
}

function Write-FoldedCommand([string] $Lead, [hashtable] $Set) {
    # The command a run's flags and answers make, after $Lead; or, when every skill was left out, a note saying there
    # is none, since -Skill with nothing in it would be left out and the command would install every skill.
    if ($Set.ContainsKey('Skill') -and -not $Set['Skill']) {
        Write-Tag 'note' 'Every skill was left out, so there is no command that does this again.'
        return
    }
    Write-ApplyCommand $Lead (Get-ApplyCommand -Set $Set)
}

function Show-InstallStatus {
    <# The read-only status: each skill, its setup's check, its hooks and settings, as ok or the step that fixes it. #>
    param([string] $Source, [string] $Destination)
    $plan = New-InstallPlan $Source $Destination @() $false
    $hard = @($plan.Problems | Where-Object { $_ -match '^(Skill source folder not found|Source and destination are the same|No skill folders)' })
    if ($hard.Count -gt 0) { foreach ($p in $hard) { Write-Tag 'FAIL' $p }; return 2 }
    $settingsPath = Get-SettingsPath $Destination
    $settings = Read-SettingsFile $settingsPath
    Write-Head "Skills in $Destination, from $Source"
    foreach ($p in $plan.Problems) { Write-Tag 'warn' $p }
    foreach ($need in $plan.NeedsName) { Write-Tag 'warn' "$($need.Problem) An install needs -Rename $($need.Skill)=<name>." }
    foreach ($skill in $plan.Skills) {
        $name = $skill.Name
        $folder = $plan.Names[$name]
        if (-not $folder) { $folder = $name }
        $copyDir = Join-Path $Destination $folder
        $owned = @($plan.Copies | Where-Object { (Test-SameFolderName $_.Folder $folder) -and (Test-SameFolderName $_.Owner $name) }).Count -gt 0
        $as = if ($folder -cne $name) { " as $folder" } else { '' }
        if (-not $owned) {
            $needs = Get-SkillNeeds $skill.FullName
            Write-Tag '..' ("$name is not installed: -Apply installs it$as." + $(if ($needs) { " [needs $needs]" }))
        } else {
            $difference = Get-CopyDifference $skill.FullName $copyDir $folder $name
            if (-not $difference) { Write-Tag 'ok' "$name is installed$as as its source has it." }
            else { Write-Tag '..' "$name, installed$as, differs from its source ($difference): -Apply replaces it, keeping this copy in a backup." }
        }
        $setupFile = 'setup.ps1'
        if (-not $NoSetup -and (Test-Path -LiteralPath (Join-Path $skill.FullName $setupFile) -PathType Leaf)) {
            $checkScript = if ($owned -and (Test-Path -LiteralPath (Join-Path $copyDir $setupFile) -PathType Leaf)) { Join-Path $copyDir $setupFile } else { Join-Path $skill.FullName $setupFile }
            $checked = Invoke-SkillSetup $checkScript @('-Check') -Quiet
            if ($checked -eq 0) { Write-Tag 'ok' "$name's setup finds nothing missing." }
            elseif ($checked -eq 1) { Write-Tag '..' "$name's setup finds something missing: an install runs it for a person, or with -Setup or -SetupAnswer." }
            else { Write-Tag 'warn' "$name's setup could not check what is missing (exit $checked), so whether it lacks anything is unknown. Run it yourself: $(Format-SetupCommand $checkScript)" }
        }
        if (-not $NoHooks -and (Test-Path -LiteralPath (Join-Path $skill.FullName 'hooks.json') -PathType Leaf)) {
            if (-not $owned) { Write-Tag '..' "$name brings hooks, offered once it is installed." }
            else {
                $change = Get-HookChange $folder $copyDir $Destination
                foreach ($note in $change.Notes) { Write-Tag 'note' $note }
                if ($change.Kind -eq 'registered') { Write-Tag 'ok' "$name's hooks are registered in $settingsPath." }
                elseif ($change.Kind -eq 'blocked') { Write-Tag $change.Tag $change.Message }
                else { Write-Tag '..' "$name's hooks are not registered: -AddHooks $folder -Apply registers them, or -Yes on an install." }
            }
        }
        if (-not $NoSettings) {
            $declared = Get-SkillSettings $skill.FullName
            if ($declared.Problem) { Write-Tag 'warn' "$name has settings, but $($declared.Problem)." }
            elseif ($declared.Names.Count -gt 0) {
                if (-not $owned) { Write-Tag '..' "$name has settings, offered once it is installed." }
                elseif ($settings.Problem) { Write-Tag 'warn' "$name has settings, but $settingsPath can't be read: $($settings.Problem)" }
                else {
                    $set = @(@($declared.Options) + @($declared.Variables) | Where-Object { $null -ne (Get-SettingNode $settings.Root $_ $declared.Key) }).Count
                    Write-Tag 'ok' "$name's settings: $($declared.Names.Count) declared, $set set; -Configure $folder -Apply changes them."
                }
            }
        }
    }
    if (-not $settings.Problem -and $settings.Exists) {
        $stale = @(Get-StaleHandlers $settings $Destination)
        # A note, as an install that leaves one in place says it: the safe default, with the flag that removes it.
        foreach ($entry in $stale) { Write-Tag 'note' ("A hook in $settingsPath names something gone: {0} {1}: {2}. -Yes removes it on an install." -f $entry.Event, $entry.Matcher, ($entry.Missing -join ', ')) }
    }
    $sourceNames = [string[]] @($plan.Skills | ForEach-Object { $_.Name })
    foreach ($copy in @($plan.Copies | Where-Object { -not (Test-NamedAmong $_.Owner $sourceNames) })) { Write-Tag '..' "$($copy.Folder) is not this source's, and an install leaves it alone." }
    Write-Head 'Done'
    Write-Tag 'ok' 'Read only: nothing written.'
    Write-ApplyCommand 'To install or update every skill' (Get-ApplyCommand)
    0
}

function Get-CopyLine([hashtable] $Plan, $Skill) {
    # What an install does with one skill, as its line says it: Install or Replace, its name, as and was.
    $name = $Skill.Name
    $installName = $Plan.Names[$name]
    $target = Join-Path $Plan.Destination $installName
    $earlier = @($Plan.Copies | Where-Object { (Test-SameFolderName $_.Owner $name) -and -not (Test-SameFolderName $_.Folder $installName) })
    $exists = Test-Path -LiteralPath $target -PathType Container
    $action = if ($exists -or $earlier.Count -gt 0) { 'Replace' } else { 'Install' }
    $line = "$action $name"
    if ($installName -cne $name) { $line += " as $installName" }
    if ($earlier.Count -gt 0) { $line += ' (was ' + (@($earlier | ForEach-Object { $_.Folder }) -join ', ') + ')' }
    @{ Line = $line; Action = $action; Target = $target; Earlier = $earlier; Exists = $exists; InstallName = $installName }
}

function Test-SetupRuns([hashtable] $Plan, [string] $Name, [bool] $Person) {
    # Whether an install runs a needed setup: for a person, or with -Setup, or with -SetupAnswer for it.
    $Person -or $Setup -or $Plan.SetupAnswers.ContainsKey($Name)
}

function Show-InstallDryRun {
    <# What an install would do, as would lines, writing nothing; then, unless -NoCommand, the command that does it. #>
    param([hashtable] $Plan, [bool] $Person, [switch] $NoCommand)
    $destination = $Plan.Destination
    $settingsPath = Get-SettingsPath $destination
    Write-Head "Dry run: installing into $destination"
    foreach ($skill in $Plan.Selected) {
        $copy = Get-CopyLine $Plan $skill
        $needs = Get-SkillNeeds $skill.FullName
        Write-Tag 'would' ($copy.Line + $(if ($needs) { "  [needs $needs]" }))
        $declared = Get-DeclaredName $skill.FullName
        if ($declared -and $declared -ne $skill.Name) { Write-Tag 'warn' "$($skill.Name)/SKILL.md declares name '$declared'; the folder name is what becomes /$($copy.InstallName)." }
    }
    if ($Plan.Skipped.Count -gt 0) { Write-Tag '..' ('Left as they are, as asked: ' + ($Plan.Skipped -join ', ')) }
    $checks = @{}
    if (-not $NoSetup) {
        foreach ($skill in $Plan.Selected) {
            if (-not (Test-Path -LiteralPath (Join-Path $skill.FullName 'setup.ps1') -PathType Leaf)) { continue }
            $copy = Get-CopyLine $Plan $skill
            $installed = Join-Path $copy.Target 'setup.ps1'
            $checkScript = if (Test-Path -LiteralPath $installed -PathType Leaf) { $installed } else { Join-Path $skill.FullName 'setup.ps1' }
            $checked = Invoke-SkillSetup $checkScript @('-Check') -Quiet
            $checks[$skill.Name] = $checked
            if ($checked -eq 0) { continue }
            if ($checked -ne 1) { Write-Tag 'warn' "$($copy.InstallName)'s setup could not check what is missing (exit $checked)."; continue }
            if (Test-SetupRuns $Plan $skill.Name $Person) {
                $given = if ($Plan.SetupAnswers.ContainsKey($skill.Name)) { ', given -Answer ' + ($Plan.SetupAnswers[$skill.Name] -join ',') } else { '' }
                Write-Tag 'would' "Run $($copy.InstallName)'s setup, which finds something missing$given."
                if (-not $Plan.SetupAnswers.ContainsKey($skill.Name)) {
                    Write-Tag '..' "Its setup asks its own questions once the copies are in: to answer them yourself, run $(Format-SetupCommand $installed)" -NoWrap
                }
            } else {
                Write-Tag 'note' "$($copy.InstallName) needs something installed: with nobody to answer, its setup isn't run and its items are declined. -SetupAnswer $($copy.InstallName):<item>=yes answers one, and -Setup runs it."
            }
        }
    }
    if (-not $NoHooks) {
        foreach ($skill in $Plan.Selected) {
            if (-not (Test-Path -LiteralPath (Join-Path $skill.FullName 'hooks.json') -PathType Leaf)) { continue }
            $copy = Get-CopyLine $Plan $skill
            $name = $copy.InstallName
            # Under -NoSetup no check ran above, but the hooks still wait for it, as an install's do.
            if (-not $checks.ContainsKey($skill.Name) -and (Test-Path -LiteralPath (Join-Path $skill.FullName 'setup.ps1') -PathType Leaf)) {
                $installed = Join-Path $copy.Target 'setup.ps1'
                $checkScript = if (Test-Path -LiteralPath $installed -PathType Leaf) { $installed } else { Join-Path $skill.FullName 'setup.ps1' }
                $checks[$skill.Name] = Invoke-SkillSetup $checkScript @('-Check') -Quiet
            }
            if ($checks.ContainsKey($skill.Name) -and $checks[$skill.Name] -ne 0) {
                Write-Tag '..' "$name brings hooks, offered once its setup finds nothing missing."
                continue
            }
            $former = @($copy.Earlier | ForEach-Object { Join-Path $destination $_.Folder })
            $change = Get-HookChange $name $copy.Target $destination $former $skill.FullName
            foreach ($note in $change.Notes) { Write-Tag 'note' $note }
            if ($change.Kind -eq 'blocked') { Write-Tag $change.Tag $change.Message; continue }
            if ($change.Kind -eq 'registered') { Write-Tag 'ok' "$name's hooks are registered."; continue }
            if ($Yes) {
                Write-Tag 'would' "Register $name's hooks: this change $($change.What) $($change.Path):"
                Show-SettingsChange $change.Settings.Text $change.Text
            } elseif ($Person) {
                Write-Tag 'would' "Offer $name's hooks for $($change.Path), showing the change."
            } else {
                Write-Tag 'note' "$name brings hooks, which would not be added: nobody is there to ask, and -Yes adds them."
            }
        }
    }
    if (-not $NoSettings) {
        foreach ($skill in $Plan.Selected) {
            $declared = Get-SkillSettings $skill.FullName
            if ($declared.Names.Count -eq 0 -and -not $declared.Problem) { continue }
            $copy = Get-CopyLine $Plan $skill
            $name = $copy.InstallName
            if ($declared.Problem) { Write-Tag 'warn' "$name has settings, but $($declared.Problem)."; continue }
            $listed = @(@($declared.Options) + @($declared.Variables) | ForEach-Object { $_.Name }) -join ', '
            if ($Plan.SetValues.ContainsKey($skill.Name) -and $Plan.SetValues[$skill.Name].Count -gt 0) {
                foreach ($value in $Plan.SetValues[$skill.Name]) { Write-Tag 'would' "Set $name's $($value.Setting.Name) to $($value.Shown) in $settingsPath." }
                continue
            }
            $installedCopy = if ($copy.Exists) { $copy.Target } elseif ($copy.Earlier.Count -gt 0) { Join-Path $destination $copy.Earlier[0].Folder } else { '' }
            $prior = if ($installedCopy) { (Get-SkillSettings $installedCopy).Names } else { $null }
            $new = @($declared.Names | Where-Object { $null -eq $prior -or $_ -notin $prior })
            if ($new.Count -eq 0) { Write-ApplyCommand "$name has settings. To change them" (Get-ActionCommand $destination @{ Configure = $name }) }
            elseif ($Person) { Write-Tag 'would' "Offer $name's settings: $listed." }
            else { Write-Tag 'note' "$name's settings would be kept: nobody is there to ask, and -Set $name.<key>=<value> sets one ($listed)." }
        }
    }
    Invoke-StaleHookCheck $destination 'dry' @{}
    Write-Head 'Done'
    Write-Tag 'ok' 'Dry run: nothing written.'
    if (-not $NoCommand) { Write-FoldedCommand 'To apply it' (Get-FoldedSet $Plan) }
    0
}

function Invoke-InstallApply {
    <#
        The install itself, once its plan holds no problem: copies, setups, hooks, settings and stale hooks. $Again is
        the command a refused write names to run again: the run's own, with its answers folded in, unless the menu
        gives the one it chose.
    #>
    param([hashtable] $Plan, [bool] $Person, [hashtable] $Again = $null)
    if (-not $Again) { $Again = Get-ApplyCommand -Set (Get-FoldedSet $Plan) }
    $destination = $Plan.Destination
    $source = $Plan.Source
    New-SkillsFolder $destination
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupRoot = Get-FreePath ('{0}.bak-{1}' -f $destination, $stamp)
    $stagingRoot = Get-FreePath ('{0}.tmp-{1}' -f $destination, $stamp)
    $saved = [Collections.Generic.List[object]]::new()
    $installed = 0
    $replaced = 0
    $installedNames = [Collections.Generic.List[string]]::new()
    $replacedNames = [Collections.Generic.List[string]]::new()
    $unread = [Collections.Generic.HashSet[string]]::new((Get-FolderComparer))
    $formerDirs = @{}
    $priorSettings = @{}

    $saveEarlier = {
        param([string] $Path, [string] $Now)
        # Into the run's backup, with the name of the copy that replaces it, or gone under -NoBackup -Force.
        if ($NoBackup) { Remove-InstalledCopy $Path; return }
        $kept = Move-ToBackup $Path $backupRoot -Confirm:$false
        if ($kept) { $saved.Add([pscustomobject] @{ Folder = $kept; Now = $Now }) }
    }

    # Every other installed skill's SKILL.md, for the mentions of a renamed one: the skills this run installs, as they
    # install, and every other folder as it stands.
    $skillFiles = @(foreach ($skill in $Plan.Selected) {
        [pscustomobject] @{ Owner = $skill.Name; Label = $Plan.Names[$skill.Name]; Path = Join-Path $skill.FullName 'SKILL.md' }
    })
    $selectedNames = [string[]] @($Plan.Selected | ForEach-Object { $_.Name })
    $skillFiles += @(foreach ($copy in $Plan.Copies) {
        $path = Join-Path $destination $copy.Folder 'SKILL.md'
        if (-not (Test-NamedAmong $copy.Owner $selectedNames) -and (Test-Path -LiteralPath $path -PathType Leaf)) {
            [pscustomobject] @{ Owner = $copy.Owner; Label = $copy.Folder; Path = $path }
        }
    })

    Write-Head "Installing into $destination"
    $copied = $false
    $current = ''
    try {
        foreach ($skill in $Plan.Selected) {
            $name = $skill.Name
            $current = $name
            $copy = Get-CopyLine $Plan $skill
            $installName = $copy.InstallName
            $target = $copy.Target
            $renaming = $installName -cne $name
            $declared = Get-DeclaredName $skill.FullName
            if ($declared -and $declared -ne $name) {
                Write-RunWarning "$name/SKILL.md declares name '$declared'; the folder name is what becomes /$installName."
            }
            # Read before that copy is replaced, which under -NoBackup leaves nothing to read.
            $priorSettings[$name] = $null
            $installedCopy = if ($copy.Exists) { $target } elseif ($copy.Earlier.Count -gt 0) { Join-Path $destination $copy.Earlier[0].Folder }
            if ($installedCopy) { $priorSettings[$name] = (Get-SkillSettings $installedCopy).Names }
            # Test seams: a run made to fail before a named skill, or once a renamed one is staged; and the same two
            # stopped as Ctrl+C stops a run, with a PipelineStoppedException, which no catch sees.
            if ($env:BB_SKILLS_FAIL_BEFORE -ieq $name) { throw "BB_SKILLS_FAIL_BEFORE: stopping before $name." }
            if ($env:BB_SKILLS_STOP_BEFORE -ieq $name) { throw [Management.Automation.PipelineStoppedException]::new() }
            $staged = Copy-SkillToStaging $skill.FullName $stagingRoot $installName $name
            if ($renaming -and $env:BB_SKILLS_FAIL_AFTER_STAGING -eq '1') { throw "BB_SKILLS_FAIL_AFTER_STAGING: stopping once $name is staged." }
            if ($renaming -and $env:BB_SKILLS_STOP_AFTER_STAGING -eq '1') { throw [Management.Automation.PipelineStoppedException]::new() }
            if ($copy.Exists) { & $saveEarlier $target $installName }
            foreach ($earlier in $copy.Earlier) { & $saveEarlier (Join-Path $destination $earlier.Folder) $installName }
            $formerDirs[$name] = @($copy.Earlier | ForEach-Object { Join-Path $destination $_.Folder })
            Move-StagedCopy $staged.Path $target
            if ($copy.Action -eq 'Replace') { $replaced++; $replacedNames.Add($installName) } else { $installed++; $installedNames.Add($installName) }
            $difference = Get-CopyDifference $skill.FullName $target $installName $name
            if ($difference) {
                # A copy that isn't the source's gets no setup, hooks or settings from this run.
                Write-RunFailure "$installName doesn't read back as its source has it: $difference. Its setup, hooks and settings are left for a run that copies it whole."
                [void] $unread.Add($name)
            } else { Write-Tag 'ok' $copy.Line }
            if (-not $renaming) { continue }
            foreach ($change in $staged.Changes) {
                Write-Tag '..' ('SKILL.md:{0,-4} - {1}' -f $change.Number, $change.Old) -NoWrap
                Write-Tag '..' ('SKILL.md:{0,-4} + {1}' -f $change.Number, $change.New) -NoWrap
            }
            # Other skills that name it are left as they are, and listed.
            foreach ($other in $skillFiles) {
                if (Test-SameFolderName $other.Owner $name) { continue }
                $mentions = @(Find-SkillMentions ([IO.File]::ReadAllText($other.Path)) $name)
                if ($mentions.Count -eq 0) { continue }
                Write-Tag '..' "$($other.Label) names $name, and is left as it is:"
                foreach ($mention in $mentions) { Write-Tag '..' ('  {0}/SKILL.md:{1}: {2}' -f $other.Label, $mention.Number, $mention.Line.Trim()) -NoWrap }
            }
        }
        $copied = $true
    } finally {
        # However the copies end, an error or Ctrl+C, which no catch sees: what they replaced is in the backup with a
        # RESTORE.md, the staging folder goes when it is empty and is named when it holds a copy, and a run that
        # stopped says so.
        if ($saved.Count -gt 0) {
            Write-RestoreNotes $backupRoot $destination $saved.ToArray() -Confirm:$false
            if (-not $copied) { Write-Tag 'FAIL' "The copies replaced before it stopped: $backupRoot, with RESTORE.md saying how to put them back." -NoWrap }
        }
        if (Remove-StagingIfEmpty $stagingRoot) {
            $lead = if ($copied) { '' } else { "Stopped at $current. " }
            Write-Tag 'FAIL' "${lead}What it staged is left in $stagingRoot" -NoWrap
        }
    }

    Write-Tag 'ok' "Installed $installed new, replaced $replaced, in $destination" -NoWrap
    if ($saved.Count -gt 0) { Write-Tag '..' "Previous copies: $backupRoot, with RESTORE.md saying how to put them back." -NoWrap }
    if ($Plan.Skipped.Count -gt 0) { Write-Tag '..' ('Left as they are, as asked: ' + ($Plan.Skipped -join ', ')) }
    # A renamed copy belongs to its source skill, so it isn't another's left alone.
    $sourceNames = [string[]] @($Plan.Skills | ForEach-Object { $_.Name })
    $extra = @(Get-InstalledCopies $destination $Plan.FormerNames | Where-Object { -not (Test-NamedAmong $_.Owner $sourceNames) })
    if ($extra.Count -gt 0) { Write-Tag '..' ('Left untouched (not in source): ' + ($extra.Folder -join ', ')) }

    # Setups, once every skill is in place, each run from its installed copy, under the name it is installed as. Each
    # one's last -Check is kept: a skill's hooks are offered only once its setup finds nothing missing.
    $checks = @{}
    if (-not $NoSetup) {
        foreach ($skill in $Plan.Selected) {
            if ($unread.Contains($skill.Name)) { continue }
            if (-not (Test-Path -LiteralPath (Join-Path $skill.FullName 'setup.ps1') -PathType Leaf)) { continue }
            $name = $Plan.Names[$skill.Name]
            $setupScript = Join-Path $destination $name 'setup.ps1'
            if (-not (Test-Path -LiteralPath $setupScript -PathType Leaf)) { continue }
            $rerun = Format-SetupCommand $setupScript
            $checked = Invoke-SkillSetup $setupScript @('-Check') -Quiet
            $checks[$name] = $checked
            if ($checked -eq 0) { continue }
            if ($checked -ne 1) {
                Write-RunWarning "$name's setup could not check what is missing (exit $checked), so whether it lacks anything is unknown. Run it yourself: $rerun" -NoWrap
                continue
            }
            if (-not (Test-SetupRuns $Plan $skill.Name $Person)) {
                Write-Tag 'note' "$name needs something installed. With nobody to answer, its setup isn't run and its items are declined: -SetupAnswer ${name}:<item>=yes answers one, and -Setup runs it to decline the rest."
                Write-Tag '..' "To be asked about it: $rerun" -NoWrap
                continue
            }
            $arguments = @()
            if ($Plan.SetupAnswers.ContainsKey($skill.Name)) { $arguments = @('-Answer', ($Plan.SetupAnswers[$skill.Name] -join ',')) }
            if ($Person) { Write-Tag '..' "$name can install what it is missing, asking about each: its setup starts." }
            else { Write-Tag '..' "$name can install what it is missing: its setup starts, with nobody to ask, so it takes the answers given and declines the rest." }
            $clock = [Diagnostics.Stopwatch]::StartNew()
            $result = Invoke-SkillSetup $setupScript $arguments -Unattended:(-not $Person)
            $seconds = [Math]::Round($clock.Elapsed.TotalSeconds, 1).ToString([Globalization.CultureInfo]::InvariantCulture)
            if ($result -ne 0) {
                Write-RunFailure "$name's setup did not finish (exit $result) after $seconds s. The skill is installed; run the setup again with: $rerun" -NoWrap
            } else {
                Write-Tag 'ok' "$name's setup ended, after $seconds s."
            }
            $checks[$name] = Invoke-SkillSetup $setupScript @('-Check') -Quiet
            if ($result -eq 0 -and $checks[$name] -ne 0) {
                Write-RunWarning "$name's setup still finds something missing. To be asked about it again: $rerun" -NoWrap
            }
        }
    }

    # Hooks, once each skill's setup finds nothing missing.
    if (-not $NoHooks) {
        foreach ($skill in $Plan.Selected) {
            if ($unread.Contains($skill.Name)) { continue }
            if (-not (Test-Path -LiteralPath (Join-Path $skill.FullName 'hooks.json') -PathType Leaf)) { continue }
            $name = $Plan.Names[$skill.Name]
            $skillDir = Join-Path $destination $name
            $setupScript = Join-Path $skillDir 'setup.ps1'
            if (Test-Path -LiteralPath $setupScript -PathType Leaf) {
                if (-not $checks.ContainsKey($name)) { $checks[$name] = Invoke-SkillSetup $setupScript @('-Check') -Quiet }
                if ($checks[$name] -ne 0) {
                    Write-Tag '..' "$name brings hooks, offered once its setup finds nothing missing: at the next install, or with:"
                    Write-ApplyCommand 'To add them then' (Get-ActionCommand $destination @{ AddHooks = $name })
                    continue
                }
            }
            $mode = if ($Yes) { 'yes' } elseif ($Person) { 'ask' } else { 'later' }
            $null = Invoke-HookOffer $name $skillDir $destination $mode @($formerDirs[$skill.Name])
        }
    }

    # Settings, after the hooks: -Set's values written; else asked about when a skill declares one its installed copy
    # didn't, a first install included, and otherwise named, with the command that asks.
    if (-not $NoSettings) {
        foreach ($skill in $Plan.Selected) {
            if ($unread.Contains($skill.Name)) { continue }
            $declared = Get-SkillSettings $skill.FullName
            if ($declared.Names.Count -eq 0 -and -not $declared.Problem) { continue }
            $name = $Plan.Names[$skill.Name]
            if ($declared.Problem) { Write-RunWarning "$name has settings, but $($declared.Problem). Not offered."; continue }
            $skillDir = Join-Path $destination $name
            if ($Plan.SetValues.ContainsKey($skill.Name) -and $Plan.SetValues[$skill.Name].Count -gt 0) {
                $null = Invoke-SettingsOffer $name $skillDir $destination 'set' $Plan.SetValues[$skill.Name]
                continue
            }
            $prior = $priorSettings[$skill.Name]
            $new = @($declared.Names | Where-Object { $null -eq $prior -or $_ -notin $prior })
            if ($new.Count -eq 0) {
                Write-ApplyCommand "$name has settings. To change them" (Get-ActionCommand $destination @{ Configure = $name })
                continue
            }
            if ($Person) { $null = Invoke-SettingsOffer $name $skillDir $destination 'ask' -AskFirst }
            else { $null = Invoke-SettingsOffer $name $skillDir $destination 'later' }
        }
    }

    $staleMode = if ($Yes) { 'yes' } elseif ($Person -and -not $NoHooks) { 'ask' } else { 'report' }
    Invoke-StaleHookCheck $destination $staleMode $Again

    Write-Head 'Done'
    $code = Get-RunExitCode
    if ($code -eq 2) { Write-Tag 'FAIL' 'Done, but a step failed: each FAIL line above says what, and what to run.' }
    elseif ($code -eq 1) { Write-Tag 'warn' 'Done, with a warning left: each warn line above says what is left, and what fixes it.' }
    else {
        # What changed, by name, and what was left; each step to run next is on its own line above.
        $named = { param([int] $Count, [string] $What, $Names) "$Count $What$(if ($Count) { ' (' + (@($Names) -join ', ') + ')' })" }
        $summary = (& $named $installed 'installed' $installedNames) + ', ' + (& $named $replaced 'replaced' $replacedNames)
        if ($Plan.Skipped.Count) { $summary += ', ' + (& $named $Plan.Skipped.Count 'left as asked' $Plan.Skipped) }
        Write-Tag 'ok' "Done: $summary."
    }
    $code
}

#endregion

#region ------------------------------------------------------------- The named actions

function Invoke-HooksAction {
    <# -AddHooks and -RemoveHooks: one skill's hooks, with nothing installed; a dry run without -Apply. #>
    param([string] $Destination, [string] $Add, [string] $Remove, [bool] $Applying, [bool] $Person, [switch] $NoCommand)
    $settingsPath = Get-SettingsPath $Destination
    # The command that does this action, for its dry run, a refused write and the stale check: the action and only the
    # flags it takes, so the menu's choice is never turned into an install, nor given a flag it refuses.
    $again = if ($Remove) { Get-NamedActionCommand 'RemoveHooks' $Remove } else { Get-NamedActionCommand 'AddHooks' $Add }
    if ($Remove) {
        $settings = Read-SettingsFile $settingsPath
        if ($settings.Problem) { Write-Tag 'FAIL' "$settingsPath can't be changed: $($settings.Problem)"; return 2 }
        $plan = Get-RemovalPlan $settings (Join-Path $Destination $Remove)
        if ($plan.Removed -eq 0) {
            Write-Tag 'ok' "$Remove has no hooks in ${settingsPath}: nothing to do."
            return 0
        }
        $text = Format-SettingsText $settings $plan.Root
        if (-not $Applying) {
            Write-Tag 'would' "Take ${Remove}'s hooks out of ${settingsPath}:"
            Show-SettingsChange $settings.Text $text
            Write-Tag 'ok' 'Dry run: nothing written.'
            if (-not $NoCommand) { Write-ApplyCommand 'To apply it' $again }
            return 0
        }
        Write-Tag '..' "This change takes ${Remove}'s hooks out of ${settingsPath}:"
        Show-SettingsChange $settings.Text $text
        $result = Write-SettingsUnderLock $settings $text
        if ($result.Status -ne 'written') { Write-SettingsRefusal $result $settingsPath $again; return 2 }
        Write-Tag 'ok' "Removed. The settings as they were: $($result.Backup)" -NoWrap
        return (Get-RunExitCode)
    }

    $skillDir = Join-Path $Destination $Add
    if (-not (Test-Path -LiteralPath (Join-Path $skillDir 'hooks.json') -PathType Leaf)) {
        Write-Tag 'FAIL' "$Add isn't installed in $Destination with a hooks.json, so it has no hooks to add."
        return 2
    }
    $setupScript = Join-Path $skillDir 'setup.ps1'
    if (Test-Path -LiteralPath $setupScript -PathType Leaf) {
        $checked = Invoke-SkillSetup $setupScript @('-Check') -Quiet
        if ($checked -ne 0) {
            Write-Tag 'FAIL' "$Add's setup reports something missing (exit $checked), so its hooks aren't offered yet. Run it first: $(Format-SetupCommand $setupScript)" -NoWrap
            return 2
        }
    }
    # A renamed copy's hooks may still name the folder of its source skill's name, when the run that renamed it put
    # the question off: they move too, unless a folder of that name is there, which is then another skill's.
    $former = @()
    $marker = Join-Path $skillDir $script:RenameMarker
    if (Test-Path -LiteralPath $marker -PathType Leaf) {
        $sourceName = [IO.File]::ReadAllText($marker).Trim()
        $sourceDir = Join-Path $Destination $sourceName
        if ($sourceName -and -not (Test-Path -LiteralPath $sourceDir)) { $former = @($sourceDir) }
    }
    # So may the folders of the names the skill had before the source renamed it, on the same terms.
    foreach ($earlier in @(Read-FormerNames $skillDir $Add)) {
        $earlierDir = Join-Path $Destination $earlier
        if (-not (Test-Path -LiteralPath $earlierDir)) { $former += $earlierDir }
    }
    if (-not $Applying) {
        $change = Get-HookChange $Add $skillDir $Destination $former
        Write-HookNotes $change
        if ($change.Kind -eq 'registered') { Write-Tag 'ok' "$Add's hooks are already registered: nothing to do." }
        elseif ($change.Kind -eq 'change') {
            Write-Tag 'would' "Register ${Add}'s hooks: this change $($change.What) $($change.Path):"
            Show-SettingsChange $change.Settings.Text $change.Text
        }
        Invoke-StaleHookCheck $Destination 'dry' @{}
        Write-Tag 'ok' 'Dry run: nothing written.'
        if (-not $NoCommand) { Write-ApplyCommand 'To apply it' $again }
        return 0
    }
    $result = Invoke-HookOffer $Add $skillDir $Destination 'yes' $former
    if ($result -eq 'registered') { Write-Tag 'ok' "$Add's hooks are already registered." }
    $staleMode = if ($Yes) { 'yes' } elseif ($Person) { 'ask' } else { 'report' }
    Invoke-StaleHookCheck $Destination $staleMode $again
    if ($result -eq 'not offered') { Write-RunFailure "$Add's hooks were not registered." }
    Get-RunExitCode
}

function Resolve-ConfigureSet([string] $Destination, [string] $Name) {
    <#
        -Set's values for one installed skill's settings, as -Configure and the menu's Settings take them: Values, and
        Problems, each a sentence, for a skill that isn't installed or declares none, a pair naming another skill or no
        setting, and a settings file the values can't go into, all found before anything is written.
    #>
    $skillDir = Join-Path $Destination $Name
    $problems = [Collections.Generic.List[string]]::new()
    $none = { @{ Values = @(); Problems = $problems.ToArray() } }
    if (-not (Test-Path -LiteralPath (Join-Path $skillDir 'SKILL.md') -PathType Leaf)) { $problems.Add("$Name isn't installed in $Destination."); return (& $none) }
    $declared = Get-SkillSettings $skillDir
    if ($declared.Problem) { $problems.Add("$Name's settings can't be offered: $($declared.Problem)."); return (& $none) }
    if ($declared.Names.Count -eq 0) { $problems.Add("$Name declares no settings."); return (& $none) }
    $sets = Read-SetPairs $Set
    foreach ($p in $sets.Problems) { $problems.Add($p) }
    $mine = @($sets.Pairs | Where-Object { $_.Skill -ieq $Name })
    foreach ($pair in @($sets.Pairs | Where-Object { $_.Skill -ine $Name })) { $problems.Add("-Set names $($pair.Entry), but the skill whose settings change is $Name.") }
    $values = Resolve-SetValues $mine $declared $Name
    foreach ($p in $values.Problems) { $problems.Add($p) }
    if ($values.Values.Count -gt 0) {
        $settingsPath = Get-SettingsPath $Destination
        if (Test-InGitWorkTree (Split-Path -Parent $settingsPath)) {
            $problems.Add("-Set names $Name's settings, but $settingsPath is inside a git work tree, where this machine's settings don't belong.")
        } else {
            $problem = Get-SettingsProblem (Read-SettingsFile $settingsPath) $declared.Key
            if ($problem) { $problems.Add("-Set names $Name's settings, but $settingsPath can't be changed: $problem") }
        }
    }
    @{ Values = $values.Values; Problems = $problems.ToArray() }
}

function Invoke-ConfigureAction {
    <# -Configure: one installed skill's settings, -Set's values or each asked; a dry run without -Apply. #>
    param([string] $Destination, [string] $Name, [bool] $Applying, [bool] $Person)
    $skillDir = Join-Path $Destination $Name
    $values = Resolve-ConfigureSet $Destination $Name
    if ($values.Problems.Count -gt 0) {
        foreach ($p in $values.Problems) { Write-Tag 'FAIL' $p }
        Write-Tag 'FAIL' 'Nothing changed.'
        return 2
    }
    $settingsPath = Get-SettingsPath $Destination
    if (-not $Applying) {
        if ($values.Values.Count -gt 0) { foreach ($value in $values.Values) { Write-Tag 'would' "Set $Name's $($value.Setting.Name) to $($value.Shown) in $settingsPath." } }
        elseif ($Person) { Write-Tag 'would' "Ask about each of $Name's settings, and write the change on a yes." }
        else { Write-Tag 'note' "$Name's settings would be kept: nobody is there to ask, and -Set $Name.<key>=<value> sets one." }
        Write-Tag 'ok' 'Dry run: nothing written.'
        Write-ApplyCommand 'To apply it' (Get-NamedActionCommand 'Configure' $Name)
        return 0
    }
    if ($values.Values.Count -gt 0) { $null = Invoke-SettingsOffer $Name $skillDir $Destination 'set' $values.Values }
    elseif ($Person) { $null = Invoke-SettingsOffer $Name $skillDir $Destination 'ask' }
    else { $null = Invoke-SettingsOffer $Name $skillDir $Destination 'later' }
    Get-RunExitCode
}

#endregion

#region ------------------------------------------------------------- The menu and the selection grammar

function Read-Choice {
    <#
        One of a list (section 2.3): numbered rows, their labels padded to one width, the default row's detail ending
        in (Enter). The number or the exact label is taken; anything else is told the range and asked again. Returns
        the chosen row's index, the default's on Enter or when input ends.
    #>
    param([string] $Question, [string[]] $Labels, [string[]] $Details, [int] $Default = 0)
    $width = ($Labels | Measure-Object -Property Length -Maximum).Maximum
    while ($true) {
        Write-Host ''
        Write-Tag '?' $Question
        for ($i = 0; $i -lt $Labels.Count; $i++) {
            $detail = if ($i -eq $Default) { ($Details[$i] + ' (Enter)').Trim() } else { $Details[$i] }
            Write-Host ('  ' + ($i + 1) + '  ' + $Labels[$i].PadRight($width) + ' ' + $detail)
        }
        Write-Host ((' ' * 8) + '[' + ($Default + 1) + '] > ') -NoNewline
        $reply = Read-Host
        if ($null -eq $reply) { Write-Host ''; return $Default }
        $reply = $reply.Trim()
        if (-not $reply) { return $Default }
        $number = 0
        if ([int]::TryParse($reply, [ref] $number) -and $number -ge 1 -and $number -le $Labels.Count) { return $number - 1 }
        for ($i = 0; $i -lt $Labels.Count; $i++) { if ($Labels[$i] -ieq $reply) { return $i } }
        Write-Tag 'warn' "There is no $reply; choose 1-$($Labels.Count)."
    }
}

function Resolve-Selection([string] $Text, [string[]] $Items) {
    <#
        Section 2.4's grammar over $Items: a number, a range as 2-5, an exact name (case-sensitive, and winning over a
        number), a wildcard, ! before any of them to leave it out, all or *, separated by commas or spaces. Returns
        Chosen, in the list's order, or Problem, one sentence. Pure.
    #>
    $all = 0..($Items.Count - 1)
    $take = [Collections.Generic.HashSet[int]]::new()
    $leave = [Collections.Generic.HashSet[int]]::new()
    $any = $false
    foreach ($token in @($Text -split '[,\s]+' | Where-Object { $_ })) {
        $out = $token.StartsWith('!')
        $body = if ($out) { $token.Substring(1) } else { $token }
        $found = [Collections.Generic.List[int]]::new()
        $exact = [array]::IndexOf($Items, $body)
        if ($body -in 'all', '*') { foreach ($i in $all) { $found.Add($i) } }
        elseif ($exact -ge 0) { $found.Add($exact) }
        elseif ($body -match '^\d+$') {
            # TryParse, since a number too long for an [int] is an answer like any other, not the end of the run.
            $n = 0
            if (-not [int]::TryParse($body, [ref] $n) -or $n -lt 1 -or $n -gt $Items.Count) { return @{ Chosen = @(); Problem = "There is no $body; choose 1-$($Items.Count)." } }
            $found.Add($n - 1)
        } elseif ($body -match '^(\d+)-(\d+)$') {
            $from = 0; $to = 0
            $parsed = [int]::TryParse($Matches[1], [ref] $from) -and [int]::TryParse($Matches[2], [ref] $to)
            if (-not $parsed -or $from -lt 1 -or $to -gt $Items.Count -or $from -gt $to) { return @{ Chosen = @(); Problem = "There is no $body; a range runs from a number to one no smaller, within 1-$($Items.Count)." } }
            foreach ($i in ($from - 1)..($to - 1)) { $found.Add($i) }
        } elseif ($body -match '[*?\[]') {
            # Case-sensitive, as -clike is; a [ without its ] is said, where -clike would throw.
            try {
                $pattern = [Management.Automation.WildcardPattern]::new($body, [Management.Automation.WildcardOptions]::None)
                for ($i = 0; $i -lt $Items.Count; $i++) { if ($pattern.IsMatch($Items[$i])) { $found.Add($i) } }
            } catch [Management.Automation.WildcardPatternException] {
                return @{ Chosen = @(); Problem = "'$body' isn't a pattern this takes: a [ needs its ]." }
            }
            if ($found.Count -eq 0) { return @{ Chosen = @(); Problem = "'$body' matches no skill." } }
        } else {
            return @{ Chosen = @(); Problem = "There is no skill named '$body'; names are case-sensitive." }
        }
        if ($out) { foreach ($i in $found) { [void] $leave.Add($i) } }
        else { $any = $true; foreach ($i in $found) { [void] $take.Add($i) } }
    }
    if (-not $any) { foreach ($i in $all) { [void] $take.Add($i) } }
    $chosen = @($all | Where-Object { $take.Contains($_) -and -not $leave.Contains($_) } | ForEach-Object { $Items[$_] })
    if ($chosen.Count -eq 0) { return @{ Chosen = @(); Problem = 'That leaves no skill; choose at least one.' } }
    @{ Chosen = $chosen; Problem = '' }
}

function Read-SkillChoice([string] $Question, [string[]] $Names) {
    # One installed skill of $Names, by its number or its name; $null when there is none to choose.
    if ($Names.Count -eq 0) { return $null }
    $details = @($Names | ForEach-Object { '' })
    $Names[(Read-Choice $Question $Names $details 0)]
}

function Write-GuidedCommand([hashtable] $Command) {
    Write-ApplyCommand 'Next time, without the questions' $Command
}

function Add-ApplyAnswers([hashtable] $Into) {
    <#
        Folds into $Into what a person answered during an apply that a flag can give again: the settings written, as
        -Set beside the run's own -Set; and -Yes, when every hooks offer and stale hook's removal was a yes. A mix of
        yes and no, which no flag gives, is said in a note. The run's -Set is read from InstallerBound: by PowerShell's
        dynamic scope a bare $Set here would find the caller's own $set, the menu's hashtable, first.
    #>
    if ($script:SettingAnswers.Count -gt 0) {
        $given = if ($script:InstallerBound.ContainsKey('Set')) { @(Split-ListArgument $script:InstallerBound['Set']) } else { @() }
        $Into['Set'] = @($given + @($script:SettingAnswers)) -join ','
    }
    $yes = @($script:YesAnswers | Where-Object { $_ }).Count
    $no = $script:YesAnswers.Count - $yes
    if ($yes -gt 0 -and $no -eq 0) { $Into['Yes'] = $true }
    elseif ($yes -gt 0) {
        Write-Tag 'note' "You answered yes to $yes of the questions about hooks and no to $no. No flag gives that mix: without -Yes an unattended run adds no hooks and removes none, and with it, it does every one."
    }
}

function Invoke-Guided {
    <#
        No action, and a person there: the menu, then only the questions the flags haven't answered, what would change,
        whether to apply it, defaulting to no, and the flags that would do the same next time, applied or not. Under
        -WhatIf the menu is a dry run too: each choice shows what it would change, and nothing asks whether to apply.
    #>
    param([string] $Source, [string] $Destination)
    $dry = [bool] $WhatIfPreference
    $menu = @($script:InstallerFlags | Where-Object { $_.ContainsKey('Menu') })
    $labels = @('Status') + @($menu | ForEach-Object { $_.Menu })
    $details = @('what is installed, and what an install would change; read only') + @($menu | ForEach-Object { $_.Detail })
    $choice = Read-Choice 'What now?' $labels $details 0
    if ($choice -eq 0) { return (Show-InstallStatus $Source $Destination) }
    $action = $menu[$choice - 1].Name

    if ($action -eq 'Skill') {
        $skills = Get-SourceSkills $Source
        if ($skills.Count -eq 0) { Write-Tag 'FAIL' "No skill folders (a folder containing SKILL.md) found under: $Source"; return 2 }
        $items = [string[]] @($skills.Name)
        # What a skill needs follows its name in one column, two spaces after the longest name.
        $width = [int] ($items | Measure-Object -Property Length -Maximum).Maximum
        for ($i = 0; $i -lt $items.Count; $i++) {
            $needs = Get-SkillNeeds $skills[$i].FullName
            $row = if ($needs) { '{0,3}  {1}  [needs {2}]' -f ($i + 1), $items[$i].PadRight($width), $needs } else { '{0,3}  {1}' -f ($i + 1), $items[$i] }
            Write-Tag '..' $row -NoWrap
        }
        Write-Tag '..' 'Choose by number, range as 2-5, name, wildcard as rend*, or all; ! leaves one out; commas or spaces between.'
        $answer = Read-Answer 'Which skills?' 'all' { param([string] $Typed) (Resolve-Selection $Typed $items).Problem }
        if ($null -eq $answer) { $answer = 'all' }
        $chosen = @((Resolve-Selection $answer $items).Chosen)
        # Every skill, chosen as all or *, is an install with no -Skill, which takes skills added later too; skills
        # chosen by name stay named, however many there are.
        [string[]] $skillSet = if ($answer.Trim() -in 'all', '*') { @() } else { $chosen }
        $plan = New-InstallPlan $Source $Destination $skillSet $true
        $code = Write-PlanProblems $plan
        if ($code -ne 0) { return $code }
        $null = Show-InstallDryRun $plan $true -NoCommand
        # The names typed and the skills left out with -, then the skills chosen.
        $set = Get-FoldedSet $plan
        if ($skillSet.Count -gt 0 -and -not $set.ContainsKey('Skill')) { $set['Skill'] = $skillSet -join ',' }
        $code = 0
        if ($dry) { Write-Tag 'ok' 'Under -WhatIf nothing is applied.' }
        elseif (Read-YesNo 'Apply these changes?') {
            $code = Invoke-InstallApply $plan $true (Get-ApplyCommand -Set $set)
            Add-ApplyAnswers $set
        }
        else { Write-Tag 'ok' 'Not applied: nothing written.' }
        Write-FoldedCommand 'Next time, without the questions' $set
        return $code
    }

    $installed = @(Get-InstalledCopies $Destination | ForEach-Object { $_.Folder })
    $settingsPath = Get-SettingsPath $Destination
    if ($action -in 'AddHooks', 'RemoveHooks') {
        if ($action -eq 'AddHooks') {
            $names = [string[]] @($installed | Where-Object { Test-Path -LiteralPath (Join-Path $Destination $_ 'hooks.json') -PathType Leaf })
            $name = Read-SkillChoice 'Whose hooks?' $names
            if ($null -eq $name) { Write-Tag 'ok' "No installed skill brings hooks: nothing to do."; return 0 }
            $hookArgs = @{ Destination = $Destination; Add = $name; Person = $true; NoCommand = $true }
        } else {
            $settings = Read-SettingsFile $settingsPath
            $names = [string[]] @($installed | Where-Object { -not $settings.Problem -and (Get-RemovalPlan $settings (Join-Path $Destination $_)).Removed -gt 0 })
            $name = Read-SkillChoice 'Whose hooks should come out?' $names
            if ($null -eq $name) { Write-Tag 'ok' "No installed skill's hooks are in ${settingsPath}: nothing to do."; return 0 }
            $hookArgs = @{ Destination = $Destination; Remove = $name; Person = $true; NoCommand = $true }
        }
        $code = Invoke-HooksAction @hookArgs -Applying $false
        $answers = @{}
        if ($code -eq 0 -and -not $dry -and (Read-YesNo 'Apply this change?')) {
            $code = Invoke-HooksAction @hookArgs -Applying $true
            # A stale hook's removal asked during it is a -Yes question too.
            Add-ApplyAnswers $answers
        }
        # The chosen action, with only the flags it takes: -NoSetup given for the menu doesn't follow it.
        Write-GuidedCommand (Get-NamedActionCommand $action $name $answers)
        return $code
    }
    # Settings: -Set's values, or each value asked; the change shown, and written on a yes.
    $names = [string[]] @($installed | Where-Object { (Get-SkillSettings (Join-Path $Destination $_)).Names.Count -gt 0 })
    $name = Read-SkillChoice 'Whose settings?' $names
    if ($null -eq $name) { Write-Tag 'ok' 'No installed skill declares settings: nothing to do.'; return 0 }
    $skillDir = Join-Path $Destination $name
    $answers = @{}
    if ($script:InstallerBound.ContainsKey('Set')) {
        $values = Resolve-ConfigureSet $Destination $name
        if ($values.Problems.Count -gt 0) {
            foreach ($p in $values.Problems) { Write-Tag 'FAIL' $p }
            Write-Tag 'FAIL' 'Nothing changed.'
            return 2
        }
        $null = Invoke-SettingsOffer $name $skillDir $Destination 'set' $values.Values -AskWrite -DryRun:$dry -NoCommand
    } else {
        $null = Invoke-SettingsOffer $name $skillDir $Destination 'ask' -DryRun:$dry -NoCommand
        if ($script:SettingAnswers.Count -gt 0) { $answers['Set'] = @($script:SettingAnswers) -join ',' }
    }
    Write-GuidedCommand (Get-NamedActionCommand 'Configure' $name $answers)
    Get-RunExitCode
}

#endregion

#region ------------------------------------------------------------- -Options and the run

function Get-FlagConflicts([hashtable] $Bound) {
    <#
        The flags that contradict each other, or that the action they come with would drop, each a sentence saying
        what to do instead; none when they agree. -Confirm is one: nothing here asks per change, since a run without
        -Apply already shows each one. Pure.
    #>
    $given = { param([string] $Name) $Bound.ContainsKey($Name) -and [bool] $Bound[$Name] }
    $problems = [Collections.Generic.List[string]]::new()
    if (& $given 'Confirm') {
        $problems.Add('-Confirm asks nothing here: a run without -Apply shows each change, and the menu asks before it applies one.')
    }
    $actions = @(@('AddHooks', 'RemoveHooks', 'Configure') | Where-Object { & $given $_ })
    if ($actions.Count -gt 1) { $problems.Add("-$($actions[0]) and -$($actions[1]) are two actions: name one at a time.") }
    if ($actions.Count -gt 0) {
        $takes = $script:ActionTakes[$actions[0]]
        foreach ($flag in 'Skill', 'Rename', 'AskNames', 'NoSetup', 'Setup', 'SetupAnswer', 'NoHooks', 'NoSettings', 'NoBackup', 'Force', 'Yes', 'Set') {
            if ($flag -notin $takes -and (& $given $flag)) { $problems.Add("-$flag doesn't go with -$($actions[0]), which would drop it: leave it out, or run them apart.") }
        }
    }
    foreach ($pair in @(@('Setup', 'NoSetup'), @('SetupAnswer', 'NoSetup'), @('Set', 'NoSettings'))) {
        if ((& $given $pair[0]) -and (& $given $pair[1])) { $problems.Add("-$($pair[0]) and -$($pair[1]) contradict each other: leave one out.") }
    }
    $problems.ToArray()
}

function Write-InstallerOptions {
    # The actions and flags, from the one table that describes them, and the exit codes.
    Write-Head 'Actions, each a dry run without -Apply'
    foreach ($flag in @($script:InstallerFlags | Where-Object { $_.Kind -eq 'action' })) { Write-Kv "-$($flag.Name)" $flag.Text }
    Write-Head 'Flags'
    foreach ($flag in @($script:InstallerFlags | Where-Object { $_.Kind -eq 'flag' })) { Write-Kv "-$($flag.Name)" $flag.Text }
    Write-Head 'Exit codes'
    Write-Kv '0' 'done, or nothing to do'
    Write-Kv '1' 'a warning left unresolved'
    Write-Kv '2' 'a step failed, or the flags were refused'
    Write-Kv '64' 'an answer needed, and nobody to ask'
    Write-Tag 'ok' 'Nothing written.'
}

function Invoke-Main {
    $ErrorActionPreference = 'Stop'
    Initialize-Output
    $script:RunWarnings = 0
    $script:RunFailures = 0
    $script:SettingAnswers = [Collections.Generic.List[string]]::new()
    $script:YesAnswers = [Collections.Generic.List[bool]]::new()
    if ($null -ne $Rest -and $Rest.Count) {
        Write-Tag 'FAIL' "'$($Rest[0])' is not a parameter Install-Skills takes; -Options lists them."
        return 2
    }
    if ($Options) {
        Write-InstallerOptions
        return 0
    }
    $conflicts = @(Get-FlagConflicts $script:InstallerBound)
    if ($conflicts.Count -gt 0) {
        foreach ($conflict in $conflicts) { Write-Tag 'FAIL' $conflict }
        Write-Tag 'FAIL' 'Nothing changed.'
        return 2
    }
    $person = Test-PersonThere -NonInteractiveSwitch $NonInteractive
    $applying = $Apply -and -not $WhatIfPreference
    $source = Resolve-InstallerPath $SkillSource
    $destination = Resolve-InstallerPath $SkillDestination

    if ($Configure) { return (Invoke-ConfigureAction $destination $Configure $applying $person) }
    if ($AddHooks -or $RemoveHooks) { return (Invoke-HooksAction $destination $AddHooks $RemoveHooks $applying $person) }
    if (-not ($Apply -or $script:InstallerBound.ContainsKey('Skill'))) {
        if ($person) { return (Invoke-Guided $source $destination) }
        return (Show-InstallStatus $source $destination)
    }
    # Under -WhatIf nothing is asked, so a name the flags don't give is said to be missing, as with nobody there.
    $plan = New-InstallPlan $source $destination $Skill ($person -and -not $WhatIfPreference)
    $notAsked = if ($person -and $WhatIfPreference) { '-WhatIf asks nothing' } else { 'nobody is there to give one' }
    $code = Write-PlanProblems $plan $notAsked
    if ($code -ne 0) { return $code }
    if (-not $applying) { return (Show-InstallDryRun $plan $person) }
    Invoke-InstallApply $plan $person
}

#endregion


#region ----------------------------------------------- Auto-run: verbatim from Undo-ProfileCarry.ps1, as the pack script has it

function Test-ShouldAutoRun {
    <# Same guard as the sibling scripts: VS Code F5 dot-sources the file. #>
    [OutputType([bool])]
    param([string] $InvocationName, [string] $HostName, [bool] $EditorPresent, [bool] $NoExecRequested)

    if ($NoExecRequested) { return $false }
    if ($InvocationName -ne '.') { return $true }
    return ($EditorPresent -or $HostName -like '*Visual Studio Code*')
}

$script:InEditor = ([bool] (Get-Variable -Name psEditor -Scope Global -ErrorAction SilentlyContinue)) -or
                   ($Host.Name -like '*Visual Studio Code*')

if (Test-ShouldAutoRun -InvocationName $MyInvocation.InvocationName `
                       -HostName $Host.Name `
                       -EditorPresent $script:InEditor `
                       -NoExecRequested ([bool] $env:BB_SKILLS_NOEXEC)) {
    try {
        $code = @(Invoke-Main) | Where-Object { $_ -is [int] } | Select-Object -Last 1
        if ($null -eq $code) { $code = 0 }
        if (-not $script:InEditor) { exit $code }
    } catch {
        Write-Tag 'FAIL' $_.Exception.Message
        Write-Verbose ($_.ScriptStackTrace)
        if ($script:InEditor) { throw } else { exit 2 }
    }
}

#endregion
