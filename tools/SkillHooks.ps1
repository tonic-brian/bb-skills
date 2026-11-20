#Requires -Version 7.4

<#
.SYNOPSIS
    The Claude Code hooks a skill brings: read from its hooks.json, offered for a settings.json, written in only on a
    yes, and taken out again. Functions only: Install-Skills.ps1 dot-sources this file, and running it does nothing.

.DESCRIPTION
    A skill's hooks.json is shaped as the hooks object of settings.json: each event names a list of matcher groups.
    ${SKILL_DIR} stands for the installed copy's folder, written as an absolute path with forward slashes, and a
    handler in exec form, a command with args, has a bare program name resolved to its absolute path, since Claude
    Code started from a desktop app or an IDE may not see this PATH. On Windows that program must be an .exe, which
    exec form needs.

    settings.json is read and written with System.Text.Json, strictly: a file with comments, trailing commas or a
    repeated key is left alone. Key order, every number's text, the newline style and the final newline are kept, and
    the file is written two-space indented, as Claude Code writes it. A write backs the file up beside itself first,
    goes to a temporary file that is moved into place, and doesn't happen at all if the file changed since it was read.

    A handler is a skill's when its command or arguments hold the skill's installed folder as a whole path.

    A skill's settings are read here too: its mod's options from .claude-plugin/plugin.json's userConfig, and the
    variables its hooks read from env.json, each with what it takes. They are written beside what the file holds,
    a variable into env as a string and an option into pluginConfigs as its field's JSON type.
#>

$script:JsonStrict = [Text.Json.JsonDocumentOptions]::new()
$script:NoNodeOptions = [Nullable[Text.Json.Nodes.JsonNodeOptions]] $null
$script:MinimumArgsVersion = [version] '2.1.139'

function Read-JsonStrict([string] $Text) {
    # Parses $Text, or throws on comments, trailing commas or a repeated key. The node comes back in a wrapper,
    # because a JsonObject returned bare is unrolled into its properties by the pipeline.
    $node = [Text.Json.Nodes.JsonNode]::Parse($Text, $script:NoNodeOptions, $script:JsonStrict)
    if ($null -ne $node) { $null = $node.ToJsonString() }   # a repeated key throws only once values are read
    [pscustomobject] @{ Node = $node }
}

function ConvertTo-JsonText($Node, [string] $NewLine) {
    $options = [Text.Json.JsonSerializerOptions]::new()
    $options.WriteIndented = $true
    $options.Encoder = [Text.Encodings.Web.JavaScriptEncoder]::UnsafeRelaxedJsonEscaping
    $options.NewLine = $NewLine
    $Node.ToJsonString($options)
}

function Get-Sha256([byte[]] $Bytes) {
    if ($null -eq $Bytes) { return '' }
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes))
}

function Read-SettingsFile([string] $Path) {
    # The settings file as found: its bytes, its newline style, and its root object; or Problem, saying why it can't
    # be changed. A missing file reads as an empty object, to be created.
    $settings = [pscustomobject] @{
        Path = $Path; Exists = $false; Hash = ''; Bom = $false; NewLine = "`n"; FinalNewLine = $true
        Root = [Text.Json.Nodes.JsonObject]::new(); Text = ''; Problem = $null
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $settings }
    $bytes = [IO.File]::ReadAllBytes($Path)
    $settings.Exists = $true
    $settings.Hash = Get-Sha256 $bytes
    $settings.Bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $text = [Text.UTF8Encoding]::new($false).GetString($bytes)
    if ($settings.Bom) { $text = $text.Substring(1) }
    $settings.Text = $text
    $settings.NewLine = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $settings.FinalNewLine = $text.EndsWith("`n")
    try {
        $parsed = (Read-JsonStrict $text).Node
    } catch {
        $settings.Problem = "it isn't strict JSON, so it is left alone: $($_.Exception.Message)"
        return $settings
    }
    if ($parsed -isnot [Text.Json.Nodes.JsonObject]) {
        $settings.Problem = "it doesn't hold a JSON object, so it is left alone"
        return $settings
    }
    $settings.Root = $parsed
    $settings
}

function Format-SettingsText($Settings, $Root) {
    # The text $Root would be written as, in the file's own newline style, with its final newline and BOM if it had them.
    $text = ConvertTo-JsonText $Root $Settings.NewLine
    if ($Settings.FinalNewLine) { $text += $Settings.NewLine }
    $text
}

function Write-SettingsFile {
    # Writes $Text over the file read as $Settings: a backup beside it first, then a temporary file moved into place,
    # through a symbolic link to the file it names.
    # Returns the backup's path, '' when there was no file to back up, or $null when nothing was written: the file
    # changed since it was read, or -WhatIf.
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param($Settings, [string] $Text)
    $path = $Settings.Path
    $now = if (Test-Path -LiteralPath $path -PathType Leaf) { Get-Sha256 ([IO.File]::ReadAllBytes($path)) } else { '' }
    if ($now -ne $Settings.Hash) { return $null }
    if (-not $PSCmdlet.ShouldProcess($path, 'Write the settings, after a backup beside them')) { return $null }
    $bytes = [Text.UTF8Encoding]::new($Settings.Bom).GetPreamble() + [Text.UTF8Encoding]::new($false).GetBytes($Text)
    $backup = ''
    if ($Settings.Exists) {
        $backup = '{0}.bak-{1}' -f $path, (Get-Date -Format 'yyyyMMdd-HHmmss')
        $n = 1
        while (Test-Path -LiteralPath $backup) { $backup = '{0}.bak-{1}-{2}' -f $path, (Get-Date -Format 'yyyyMMdd-HHmmss'), (++$n) }
        [IO.File]::Copy($path, $backup)
    }
    # A symbolic link is written through: the temporary file goes beside the file it names and is moved over that file,
    # so the link stays a link. The backup stays beside the name that was read.
    $written = $path
    $item = Get-Item -LiteralPath $path -Force -ErrorAction Ignore
    if ($item -and $item.LinkType -eq 'SymbolicLink') { $written = $item.ResolveLinkTarget($true).FullName }
    $temporary = '{0}.tmp-{1}' -f $written, [guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllBytes($temporary, [byte[]] $bytes)
        $now = if (Test-Path -LiteralPath $path -PathType Leaf) { Get-Sha256 ([IO.File]::ReadAllBytes($path)) } else { '' }
        if ($now -ne $Settings.Hash) {
            if ($backup) { Remove-Item -LiteralPath $backup -Force }
            return $null
        }
        [IO.File]::Move($temporary, $written, $true)
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
    }
    $backup
}

function Test-NamesFolder([string] $Text, [string] $Folder) {
    # True when $Text holds $Folder as a whole path: what follows it is the end, a separator, a quote or a space, so
    # skills/foo never matches inside skills/foo-bar. Separators are compared as /, and on Windows case is ignored.
    if (-not $Text -or -not $Folder) { return $false }
    $haystack = $Text.Replace('\', '/')
    $needle = $Folder.Replace('\', '/').TrimEnd('/')
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $at = $haystack.IndexOf($needle, $comparison)
    while ($at -ge 0) {
        $end = $at + $needle.Length
        if ($end -eq $haystack.Length -or $haystack[$end] -in [char[]] @('/', '"', "'", ' ')) { return $true }
        $at = $haystack.IndexOf($needle, $at + 1, $comparison)
    }
    $false
}

function Get-HandlerStrings($Handler) {
    # The command and each argument of a handler, as plain strings.
    $strings = [Collections.Generic.List[string]]::new()
    if ($Handler -isnot [Text.Json.Nodes.JsonObject]) { return $strings.ToArray() }
    $command = $Handler['command']
    if ($command -is [Text.Json.Nodes.JsonValue] -and $command.GetValueKind() -eq 'String') { $strings.Add($command.GetValue[string]()) }
    $arguments = $Handler['args']
    if ($arguments -is [Text.Json.Nodes.JsonArray]) {
        foreach ($argument in $arguments) {
            if ($argument -is [Text.Json.Nodes.JsonValue] -and $argument.GetValueKind() -eq 'String') { $strings.Add($argument.GetValue[string]()) }
        }
    }
    $strings.ToArray()
}

function Get-Handlers($Root) {
    # Every handler under $Root's hooks, each with where it sits: the event, the group, and the group's matcher.
    $found = [Collections.Generic.List[object]]::new()
    $hooks = $Root['hooks']
    if ($hooks -isnot [Text.Json.Nodes.JsonObject]) { return $found.ToArray() }
    foreach ($eventName in @($hooks | ForEach-Object { $_.Key })) {
        $groups = $hooks[$eventName]
        if ($groups -isnot [Text.Json.Nodes.JsonArray]) { continue }
        foreach ($group in $groups) {
            if ($group -isnot [Text.Json.Nodes.JsonObject]) { continue }
            $handlers = $group['hooks']
            if ($handlers -isnot [Text.Json.Nodes.JsonArray]) { continue }
            $matcher = $group['matcher']
            $matcherText = if ($matcher -is [Text.Json.Nodes.JsonValue] -and $matcher.GetValueKind() -eq 'String') { $matcher.GetValue[string]() } else { '' }
            foreach ($handler in $handlers) {
                $found.Add([pscustomobject] @{ Event = $eventName; Group = $group; Matcher = $matcherText; Handler = $handler })
            }
        }
    }
    $found.ToArray()
}

function Remove-Handlers($Root, [scriptblock] $Where) {
    # Takes out every handler for which $Where, given the handler, is true; then any group left with no handlers, any
    # event left with no groups, and the hooks object if nothing is left in it. Returns how many were taken out.
    $removed = 0
    $hooks = $Root['hooks']
    if ($hooks -isnot [Text.Json.Nodes.JsonObject]) { return 0 }
    foreach ($eventName in @($hooks | ForEach-Object { $_.Key })) {
        $groups = $hooks[$eventName]
        if ($groups -isnot [Text.Json.Nodes.JsonArray]) { continue }
        for ($g = $groups.Count - 1; $g -ge 0; $g--) {
            $group = $groups[$g]
            if ($group -isnot [Text.Json.Nodes.JsonObject]) { continue }
            $handlers = $group['hooks']
            if ($handlers -isnot [Text.Json.Nodes.JsonArray]) { continue }
            $before = $handlers.Count
            for ($h = $handlers.Count - 1; $h -ge 0; $h--) {
                if (& $Where $handlers[$h]) { $handlers.RemoveAt($h); $removed++ }
            }
            if ($before -gt 0 -and $handlers.Count -eq 0) { $groups.RemoveAt($g) }
        }
        if ($groups.Count -eq 0) { [void] $hooks.Remove($eventName) }
    }
    if ($hooks.Count -eq 0) { [void] $Root.Remove('hooks') }
    $removed
}

function Get-SkillHooks([string] $SkillDir, [string] $InstalledDir = '') {
    # The hooks $SkillDir's hooks.json declares, ready to register: ${SKILL_DIR} written in, as $InstalledDir where a
    # dry run reads a skill's source for the copy it would make, and each exec-form handler's bare program resolved.
    # Hooks is null and Problem says why when they can't be. UsesArgs says whether any handler is in exec form, which
    # needs Claude Code 2.1.139 or later.
    $result = [pscustomobject] @{ Hooks = $null; UsesArgs = $false; Problem = $null }
    $file = Join-Path $SkillDir 'hooks.json'
    $folder = [IO.Path]::GetFullPath($(if ($InstalledDir) { $InstalledDir } else { $SkillDir })).Replace('\', '/').TrimEnd('/')
    # Written into the JSON text as a JSON string's contents, so a quote or backslash in a path can't break it.
    $escaped = [Text.Json.Nodes.JsonValue]::Create($folder).ToJsonString()
    $escaped = $escaped.Substring(1, $escaped.Length - 2)
    try {
        $text = [IO.File]::ReadAllText($file).Replace('${SKILL_DIR}', $escaped)
        $declared = (Read-JsonStrict $text).Node
    } catch {
        $result.Problem = "its hooks.json isn't strict JSON: $($_.Exception.Message)"
        return $result
    }
    if ($declared -isnot [Text.Json.Nodes.JsonObject] -or $declared.Count -eq 0) {
        $result.Problem = "its hooks.json doesn't map events to their hooks"
        return $result
    }
    $wrapper = [Text.Json.Nodes.JsonObject]::new()
    $wrapper['hooks'] = $declared
    $handlers = @(Get-Handlers $wrapper)
    $shapeOk = $handlers.Count -gt 0
    foreach ($eventName in @($declared | ForEach-Object { $_.Key })) {
        if ($declared[$eventName] -isnot [Text.Json.Nodes.JsonArray]) { $shapeOk = $false }
    }
    if (-not $shapeOk) {
        $result.Problem = "its hooks.json doesn't map events to lists of { matcher, hooks } groups"
        return $result
    }
    foreach ($entry in $handlers) {
        $handler = $entry.Handler
        if ($handler -isnot [Text.Json.Nodes.JsonObject] -or $handler['args'] -isnot [Text.Json.Nodes.JsonArray]) { continue }
        $result.UsesArgs = $true
        $command = @(Get-HandlerStrings $handler)[0]
        if (-not $command) { $result.Problem = 'a hook in its hooks.json has args but no command'; return $result }
        if ([IO.Path]::IsPathRooted($command)) { continue }
        if ($command.Contains('/') -or $command.Contains('\')) {
            $result.Problem = "a hook's command, $command, is neither a program's name nor an absolute path"
            return $result
        }
        $program = Get-Command -Name $command -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $program) {
            $result.Problem = "its hooks run $command, which isn't on PATH"
            return $result
        }
        if ($IsWindows -and [IO.Path]::GetExtension($program.Source) -ne '.exe') {
            $result.Problem = "its hooks run $command, which here is $($program.Source), not an .exe, and a hook in exec form needs one"
            return $result
        }
        $handler['command'] = [Text.Json.Nodes.JsonValue]::Create($program.Source.Replace('\', '/'))
    }
    $result.Hooks = $declared
    $result
}

function Get-HookPlan($Settings, $Declared, [string] $SkillDir, [string[]] $FormerDirs = @()) {
    # What registering $Declared, a skill's resolved hooks, would make of the settings: its handlers already there are
    # taken out and the declared groups added at the end of each event's list. State is 'registered' when the skill's
    # groups there are exactly the declared ones, 'replace' when some of its handlers are there but differ, else 'add'.
    # A renamed skill's handlers naming $FormerDirs, where its copy was, are its own too, and Moved says there were.
    $formerList = @($FormerDirs | Where-Object { $_ })
    $ownDirs = @($SkillDir) + $formerList
    $names = {
        param($handler, $dirList)
        foreach ($text in @(Get-HandlerStrings $handler)) {
            foreach ($dir in $dirList) { if (Test-NamesFolder $text $dir) { return $true } }
        }
        $false
    }
    $owned = { param($handler) & $names $handler $ownDirs }
    $root = $Settings.Root.DeepClone()

    $present = [Collections.Generic.List[string]]::new()
    $seen = [Collections.Generic.HashSet[object]]::new()
    $moved = $false
    foreach ($entry in @(Get-Handlers $root)) {
        if ((& $owned $entry.Handler) -and $seen.Add($entry.Group)) { $present.Add($entry.Event + ' ' + $entry.Group.ToJsonString()) }
        if ($formerList.Count -gt 0 -and (& $names $entry.Handler $formerList)) { $moved = $true }
    }
    $wanted = [Collections.Generic.List[string]]::new()
    foreach ($eventName in @($Declared | ForEach-Object { $_.Key })) {
        foreach ($group in $Declared[$eventName]) { $wanted.Add($eventName + ' ' + $group.ToJsonString()) }
    }
    $present.Sort([StringComparer]::Ordinal)
    $wanted.Sort([StringComparer]::Ordinal)
    $state = 'replace'
    if ($present.Count -eq 0) { $state = 'add' }
    elseif (($present -join "`n") -ceq ($wanted -join "`n")) { $state = 'registered' }

    $null = Remove-Handlers $root $owned
    if ($root['hooks'] -isnot [Text.Json.Nodes.JsonObject]) { $root['hooks'] = [Text.Json.Nodes.JsonObject]::new() }
    $hooks = $root['hooks']
    foreach ($eventName in @($Declared | ForEach-Object { $_.Key })) {
        if ($hooks[$eventName] -isnot [Text.Json.Nodes.JsonArray]) { $hooks[$eventName] = [Text.Json.Nodes.JsonArray]::new() }
        foreach ($group in $Declared[$eventName]) { $hooks[$eventName].Add([Text.Json.Nodes.JsonNode] $group.DeepClone()) }
    }
    [pscustomobject] @{ State = $state; Root = $root; Moved = $moved }
}

function Get-RemovalPlan($Settings, [string] $SkillDir) {
    # The settings with every handler of the skill in $SkillDir taken out, and how many that was.
    $root = $Settings.Root.DeepClone()
    $removed = Remove-Handlers $root { param($handler) @(Get-HandlerStrings $handler | Where-Object { Test-NamesFolder $_ $SkillDir }).Count -gt 0 }
    [pscustomobject] @{ Removed = $removed; Root = $root }
}

function Get-MissingPaths($Handler, [string] $Destination) {
    # The paths a handler names under $Destination that no longer exist, and its exec-form program if that is gone.
    $missing = [Collections.Generic.List[string]]::new()
    $strings = @(Get-HandlerStrings $Handler)
    $underDestination = @($strings | Where-Object { Test-NamesFolder $_ $Destination })
    if ($underDestination.Count -eq 0) { return $missing.ToArray() }
    $needle = $Destination.Replace('\', '/').TrimEnd('/')
    $comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $execForm = $Handler['args'] -is [Text.Json.Nodes.JsonArray]
    foreach ($text in $underDestination) {
        $plain = $text.Replace('\', '/')
        # The first place the folder appears as a whole path, as Test-NamesFolder finds it.
        $at = $plain.IndexOf($needle, $comparison)
        while ($at -ge 0) {
            $after = $at + $needle.Length
            if ($after -eq $plain.Length -or $plain[$after] -in [char[]] @('/', '"', "'", ' ')) { break }
            $at = $plain.IndexOf($needle, $at + 1, $comparison)
        }
        if ($at -lt 0) { continue }
        # In exec form each string is one whole argument, so the path runs to its end. In a shell-form command it
        # ends at the first quote or space after the skills folder, whose own path may hold a space.
        $end = if ($execForm) { -1 } else { $plain.IndexOfAny([char[]] @('"', "'", ' '), $at + $needle.Length) }
        $path = if ($end -lt 0) { $plain.Substring($at) } else { $plain.Substring($at, $end - $at) }
        if (-not (Test-Path -LiteralPath $path)) { $missing.Add($path) }
    }
    if ($execForm) {
        $command = $strings[0]
        if ($command -and [IO.Path]::IsPathRooted($command) -and -not (Test-Path -LiteralPath $command -PathType Leaf)) { $missing.Add($command) }
    }
    $missing.ToArray()
}

function Get-StaleHandlers($Settings, [string] $Destination) {
    # Handlers that name something under the skills folder $Destination which no longer exists, or whose program is
    # gone: each fails on every tool call it matches.
    $stale = [Collections.Generic.List[object]]::new()
    foreach ($entry in @(Get-Handlers $Settings.Root)) {
        $missing = @(Get-MissingPaths $entry.Handler $Destination)
        if ($missing.Count -gt 0) {
            $stale.Add([pscustomobject] @{ Event = $entry.Event; Matcher = $entry.Matcher; Missing = $missing })
        }
    }
    $stale.ToArray()
}

function Get-StaleRemovalPlan($Settings, [string] $Destination) {
    $root = $Settings.Root.DeepClone()
    $removed = Remove-Handlers $root { param($handler) @(Get-MissingPaths $handler $Destination).Count -gt 0 }
    [pscustomobject] @{ Removed = $removed; Root = $root }
}

function Get-LineDiff([string] $Old, [string] $New, [int] $Context = 3) {
    # A unified-style diff of two texts by line: '-' for a line taken out, '+' for one added, the lines a change takes
    # out before those it adds, as git prints them, and up to $Context unchanged lines around each change, with '...'
    # between distant changes.
    $a = @($Old -split '\r?\n')
    $b = @($New -split '\r?\n')
    $n = $a.Count; $m = $b.Count
    $lcs = [int[,]]::new($n + 1, $m + 1)
    for ($i = $n - 1; $i -ge 0; $i--) {
        for ($j = $m - 1; $j -ge 0; $j--) {
            if ($a[$i] -ceq $b[$j]) { $lcs[$i, $j] = $lcs[($i + 1), ($j + 1)] + 1 }
            else { $lcs[$i, $j] = [Math]::Max([double] $lcs[($i + 1), $j], [double] $lcs[$i, ($j + 1)]) }
        }
    }
    $ops = [Collections.Generic.List[object]]::new()
    $i = 0; $j = 0
    while ($i -lt $n -or $j -lt $m) {
        if ($i -lt $n -and $j -lt $m -and $a[$i] -ceq $b[$j]) { $ops.Add(@(' ', $a[$i])); $i++; $j++ }
        elseif ($j -lt $m -and ($i -ge $n -or $lcs[$i, ($j + 1)] -gt $lcs[($i + 1), $j])) { $ops.Add(@('+', $b[$j])); $j++ }
        else { $ops.Add(@('-', $a[$i])); $i++ }
    }
    $show = [bool[]]::new($ops.Count)
    for ($k = 0; $k -lt $ops.Count; $k++) {
        if ($ops[$k][0] -ne ' ') {
            for ($c = [Math]::Max(0, $k - $Context); $c -le [Math]::Min($ops.Count - 1, $k + $Context); $c++) { $show[$c] = $true }
        }
    }
    $lines = [Collections.Generic.List[string]]::new()
    $gap = $false
    for ($k = 0; $k -lt $ops.Count; $k++) {
        if (-not $show[$k]) { $gap = $true; continue }
        if ($gap -and $lines.Count -gt 0) { $lines.Add('  ...') }
        $gap = $false
        $lines.Add($ops[$k][0] + ' ' + $ops[$k][1])
    }
    $lines.ToArray()
}

function Get-ClaudeVersion {
    # The version `claude --version` reports, or $null when there is no claude on PATH or its answer has no version.
    # BB_SKILLS_CLAUDE_VERSION is a test seam: a version to use instead, or 'none' for one that can't be read.
    if ($env:BB_SKILLS_CLAUDE_VERSION) {
        if ($env:BB_SKILLS_CLAUDE_VERSION -eq 'none') { return $null }
        return [version] $env:BB_SKILLS_CLAUDE_VERSION
    }
    $claude = Get-Command -Name 'claude' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $claude) { return $null }
    $text = & $claude.Source --version 2> $null | Out-String
    if ($LASTEXITCODE -ne 0) { return $null }
    if ($text -match '(\d+)\.(\d+)\.(\d+)') { return [version] "$($Matches[1]).$($Matches[2]).$($Matches[3])" }
    $null
}

function Test-InGitWorkTree([string] $Folder) {
    # True when $Folder or a folder above it holds .git, a work tree's mark, as a folder or as a worktree's file.
    $dir = [IO.Path]::GetFullPath($Folder)
    while ($dir) {
        if (Test-Path -LiteralPath (Join-Path $dir '.git')) { return $true }
        $parent = [IO.Path]::GetDirectoryName($dir)
        if ($parent -eq $dir) { break }
        $dir = $parent
    }
    $false
}

# The pluginConfigs key Claude Code reads the options of a mod in a skills folder under: its plugin.json name, then
# this. Seen in plan 00008's step 1b, where /config wrote it for a mod in ~/.claude/skills.
$script:SkillsDirSuffix = '@skills-dir'
$script:OptionTypes = @('string', 'number', 'boolean', 'directory', 'file')

function Get-JsonText($Node) {
    # A JSON string's text, or $null for anything else.
    if ($Node -is [Text.Json.Nodes.JsonValue] -and $Node.GetValueKind() -eq 'String') { return $Node.GetValue[string]() }
    $null
}

function Get-JsonDecimal($Node) {
    # A JSON number's value, or $null for anything else.
    if ($Node -is [Text.Json.Nodes.JsonValue] -and $Node.GetValueKind() -eq 'Number') { return $Node.GetValue[decimal]() }
    $null
}

function Format-SettingNode($Node) {
    # A setting's value as the question shows it: a string's text, a list's items comma-separated, else its JSON.
    $text = Get-JsonText $Node
    if ($null -ne $text) { return $text }
    if ($Node -is [Text.Json.Nodes.JsonArray]) { return (@($Node | ForEach-Object { Format-SettingNode $_ }) -join ', ') }
    $Node.ToJsonString()
}

function Get-SettingTakes($Setting) {
    # What a setting takes, in words: "true or false", "a whole number from 1 to 100", and so on.
    $range = ''
    if ($null -ne $Setting.Min -and $null -ne $Setting.Max) { $range = " from $($Setting.Min) to $($Setting.Max)" }
    elseif ($null -ne $Setting.Min) { $range = " of $($Setting.Min) or more" }
    elseif ($null -ne $Setting.Max) { $range = " of $($Setting.Max) or less" }
    $takes = switch ($Setting.Kind) {
        'boolean' { 'true or false' }
        'number' { "a number$range" }
        'whole' { "a whole number$range" }
        'list' { 'values separated by commas' }
        default { if ($Setting.Choices) { 'one of ' + ($Setting.Choices -join ', ') } else { 'text' } }
    }
    if ($Setting.Pattern -and $Setting.Kind -notin 'whole', 'number') { $takes += " matching $($Setting.Pattern)" }
    $takes
}

function Get-SkillSettings([string] $SkillDir) {
    # The settings $SkillDir declares, each in the order declared: Options, its mod's, from .claude-plugin/plugin.json's
    # userConfig, read under pluginConfigs[Key]; and Variables, its hooks', from env.json, read under env. Names holds
    # each as where it goes and its name, to tell a setting new to a skill from those its installed copy declared.
    # Problem says why they can't be offered.
    $result = [pscustomobject] @{ Key = $null; Options = @(); Variables = @(); Names = [string[]] @(); Problem = $null }
    $options = [Collections.Generic.List[object]]::new()
    $variables = [Collections.Generic.List[object]]::new()
    $manifest = Join-Path $SkillDir '.claude-plugin' 'plugin.json'
    if (Test-Path -LiteralPath $manifest -PathType Leaf) {
        try { $plugin = (Read-JsonStrict ([IO.File]::ReadAllText($manifest))).Node }
        catch { $result.Problem = "its plugin.json isn't strict JSON: $($_.Exception.Message)"; return $result }
        # Assigned, not output: an object written to the pipeline comes out as its properties.
        $config = $null
        if ($plugin -is [Text.Json.Nodes.JsonObject]) { $config = $plugin['userConfig'] }
        if ($null -ne $config) {
            $pluginName = Get-JsonText $plugin['name']
            if (-not $pluginName -or $config -isnot [Text.Json.Nodes.JsonObject]) {
                $result.Problem = "its plugin.json doesn't name the plugin and map userConfig's fields"
                return $result
            }
            $result.Key = $pluginName + $script:SkillsDirSuffix
            foreach ($fieldName in @($config | ForEach-Object { $_.Key })) {
                $field = $config[$fieldName]
                $type = if ($field -is [Text.Json.Nodes.JsonObject]) { Get-JsonText $field['type'] } else { $null }
                if ($type -notin $script:OptionTypes) {
                    $result.Problem = "its plugin.json's userConfig field $fieldName has no type Claude Code knows"
                    return $result
                }
                $multiple = $field['multiple'] -is [Text.Json.Nodes.JsonValue] -and $field['multiple'].GetValueKind() -eq 'True'
                $kind = if ($type -in 'boolean', 'number') { $type } elseif ($multiple) { 'list' } else { 'string' }
                $choices = if ($field['options'] -is [Text.Json.Nodes.JsonArray]) { [string[]] @($field['options'] | ForEach-Object { Get-JsonText $_ }) } else { $null }
                $default = $field['default']
                $options.Add([pscustomobject] @{
                    Name = $fieldName; Where = 'pluginConfigs'; Kind = $kind; Description = Get-JsonText $field['description']
                    Unset = if ($null -ne $default) { Format-SettingNode $default } else { '' }
                    Sensitive = $field['sensitive'] -is [Text.Json.Nodes.JsonValue] -and $field['sensitive'].GetValueKind() -eq 'True'
                    Choices = $choices; Min = Get-JsonDecimal $field['min']; Max = Get-JsonDecimal $field['max']; Pattern = $null
                })
            }
        }
    }
    $envFile = Join-Path $SkillDir 'env.json'
    if (Test-Path -LiteralPath $envFile -PathType Leaf) {
        try { $declared = (Read-JsonStrict ([IO.File]::ReadAllText($envFile))).Node }
        catch { $result.Problem = "its env.json isn't strict JSON: $($_.Exception.Message)"; return $result }
        if ($declared -isnot [Text.Json.Nodes.JsonObject]) {
            $result.Problem = "its env.json doesn't map variables to what they take"
            return $result
        }
        foreach ($variableName in @($declared | ForEach-Object { $_.Key })) {
            $entry = $declared[$variableName]
            if ($entry -isnot [Text.Json.Nodes.JsonObject]) {
                $result.Problem = "its env.json doesn't say what $variableName takes"
                return $result
            }
            $min = Get-JsonDecimal $entry['min']
            $max = Get-JsonDecimal $entry['max']
            $variables.Add([pscustomobject] @{
                Name = $variableName; Where = 'env'; Kind = if ($null -ne $min -or $null -ne $max) { 'whole' } else { 'text' }
                Description = Get-JsonText $entry['description']; Unset = [string] (Get-JsonText $entry['whenUnset'])
                Sensitive = $false; Choices = $null; Min = $min; Max = $max; Pattern = Get-JsonText $entry['pattern']
            })
        }
    }
    $result.Options = $options.ToArray()
    $result.Variables = $variables.ToArray()
    $result.Names = [string[]] @($result.Options + $result.Variables | ForEach-Object { $_.Where + '.' + $_.Name })
    $result
}

function ConvertTo-SettingValue($Setting, [string] $Reply) {
    # $Reply as the JSON value $Setting is written as: a variable's as a string, as env holds them, and a mod's option
    # as its field's type. Problem says what it takes instead, when $Reply doesn't fit.
    $result = [pscustomobject] @{ Value = $null; Problem = $null }
    $invariant = [Globalization.CultureInfo]::InvariantCulture
    $fits = switch ($Setting.Kind) {
        'boolean' { $Reply -in 'true', 'false' }
        'number' { $Reply -match '^-?(0|[1-9][0-9]*)(\.[0-9]+)?$' }
        'whole' { $Reply -match '^-?[0-9]+$' }
        'list' { $true }
        default { -not $Setting.Choices -or $Reply -cin $Setting.Choices }
    }
    if ($fits -and $Setting.Kind -in 'number', 'whole' -and ($null -ne $Setting.Min -or $null -ne $Setting.Max)) {
        # TryParse, since a number too long for a [decimal] is an answer that doesn't fit, not the end of the run.
        $number = [decimal]::Zero
        $fits = [decimal]::TryParse($Reply, [Globalization.NumberStyles]::Number, $invariant, [ref] $number) -and
            ($null -eq $Setting.Min -or $number -ge $Setting.Min) -and ($null -eq $Setting.Max -or $number -le $Setting.Max)
    }
    if ($fits -and $Setting.Pattern) { $fits = [regex]::IsMatch($Reply, $Setting.Pattern) }
    if (-not $fits) {
        $result.Problem = 'it takes ' + (Get-SettingTakes $Setting)
        return $result
    }
    $result.Value = switch ($Setting.Kind) {
        'boolean' { [Text.Json.Nodes.JsonValue]::Create([bool] ($Reply -eq 'true')) }
        'number' { [Text.Json.Nodes.JsonNode]::Parse($Reply) }
        'list' {
            $list = [Text.Json.Nodes.JsonArray]::new()
            foreach ($item in @($Reply -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
                $list.Add([Text.Json.Nodes.JsonNode] [Text.Json.Nodes.JsonValue]::Create([string] $item))
            }
            , $list
        }
        default { [Text.Json.Nodes.JsonValue]::Create([string] $Reply) }
    }
    $result
}

function Get-SettingsShapeProblem($Root, [string] $Key) {
    # Why the settings' env, or the pluginConfigs entry $Key names, can't take a skill's settings, or $null when they
    # can. Each object on the way may be missing, to be made, but not something else.
    $environment = $Root['env']
    if ($null -ne $environment -and $environment -isnot [Text.Json.Nodes.JsonObject]) { return "its env isn't an object" }
    if (-not $Key) { return $null }
    $holder = $Root['pluginConfigs']
    $where = 'pluginConfigs'
    foreach ($step in @($Key, 'options', $null)) {
        if ($null -eq $holder) { return $null }
        if ($holder -isnot [Text.Json.Nodes.JsonObject]) { return "its $where isn't an object" }
        if ($null -eq $step) { return $null }
        $holder = $holder[$step]
        $where += " $step"
    }
    $null
}

function Get-SettingNode($Root, $Setting, [string] $Key) {
    # The value the settings hold for $Setting, or $null when it is unset.
    if ($Setting.Where -eq 'env') {
        $holder = $Root['env']
    } else {
        $holder = $Root['pluginConfigs']
        if ($holder -is [Text.Json.Nodes.JsonObject]) { $holder = $holder[$Key] }
        if ($holder -is [Text.Json.Nodes.JsonObject]) { $holder = $holder['options'] }
    }
    if ($holder -isnot [Text.Json.Nodes.JsonObject]) { return $null }
    $value = $holder[$Setting.Name]
    if ($null -eq $value) { return $null }
    # In a one-item array, which the pipeline unrolls once: a list comes out whole, not as its items. Write-Output
    # -NoEnumerate would hand back a single value inside a List[object].
    , $value
}

function Set-SettingNode($Root, $Setting, [string] $Key, $Value) {
    # Sets $Setting in $Root to $Value beside what is there, or takes it out when $Value is $null, along with the
    # objects holding it that this leaves empty.
    $path = if ($Setting.Where -eq 'env') { @('env') } else { @('pluginConfigs', $Key, 'options') }
    $holders = [Collections.Generic.List[object]]::new()
    $holder = $Root
    foreach ($step in $path) {
        if ($holder[$step] -isnot [Text.Json.Nodes.JsonObject]) {
            if ($null -eq $Value) { return }
            $holder[$step] = [Text.Json.Nodes.JsonObject]::new()
        }
        $holders.Add($holder)
        $holder = $holder[$step]
    }
    if ($null -ne $Value) {
        # A copy: the same answers may be set again, in a file read afresh after it changed.
        $holder[$Setting.Name] = $Value.DeepClone()
        return
    }
    if (-not $holder.Remove($Setting.Name)) { return }
    for ($i = $path.Count - 1; $i -ge 0 -and $holder.Count -eq 0; $i--) {
        [void] $holders[$i].Remove($path[$i])
        $holder = $holders[$i]
    }
}
