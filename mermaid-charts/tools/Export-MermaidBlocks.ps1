<#
.SYNOPSIS
    Writes each Mermaid chart in a Markdown document to its own .mmd file and, with -Preview, renders each to a
    PNG beside it: the PowerShell twin of export_blocks.py, which reads, writes and exits as it does.

.DESCRIPTION
    Each chart becomes block-NN-line-L.mmd in the out folder, NN counting the document's charts from 01 and L
    being the line of its opening fence, in UTF-8 with LF line endings. The folder is made when it is missing.
    This tool's own files from an earlier run, block-NN-line-L.mmd and .png, are removed first, since a chart the
    document has since lost would read as current; anything else in the folder is left alone.

    A fence is read as CommonMark reads one: three or more backticks or tildes, indented at most three spaces,
    whose info string's first word is mermaid, in any case, where a backtick fence's info string holds no
    backtick; closed by a fence of the same character, at least as long, with nothing after it but spaces or
    tabs. A chart loses as many spaces from the start of each line as its fence is indented. A Mermaid example
    inside a longer fence is an example, not a chart, and a fence inside a block quote, or indented four spaces
    or more, is not read. HTML blocks are not recognised: a fence inside <!-- --> or <pre>, or after a <details>
    line with no blank line between, is read as a chart though a renderer shows it as HTML, and a lone fence
    line inside one can hide the charts after it. The document is read as UTF-8, and one that is not is refused.

    -Preview renders each chart with preview_png.py, beside this file, so with mermaid-svg's pinned install:
    block-NN-line-L.png beside its .mmd. Python runs as py -3 on Windows and as python3 elsewhere. Without an
    install it says how to make one, and renders nothing. It says how wide each chart is, half its preview's
    width, since the preview is drawn at twice the chart's size; after the previews, and so after any that
    failed, it names each chart wider than -MaxWidth, 1250 px unless given, which on GitHub or a projector
    shrinks until it can't be read (LESSONS.md, lesson 33). -MaxWidth 0 measures without a limit.

    It exits 0 once every chart is written and, with -Preview, every preview rendered and none wider than the
    limit. It exits 1 on a fence never closed, which leaves the rest of the document unread, on a preview that
    failed, on a chart wider than the limit, and on a usage error, PowerShell's own for a parameter it does not
    know or one given no value.

.PARAMETER Path
    The Markdown document to read.

.PARAMETER OutDir
    The folder to write the charts in, kept out of the project as previews are.

.PARAMETER Preview
    Render a PNG of each chart beside it as well, and say how wide each chart is.

.PARAMETER MaxWidth
    The widest a chart may be, in pixels, with -Preview: 1250 unless given, and 0 for no limit. A whole number,
    taken as text so that 1.5 is refused rather than rounded.

.EXAMPLE
    pwsh -NoProfile -File Export-MermaidBlocks.ps1 doc.md ../scratch/charts -Preview
#>
#Requires -Version 7.0
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0)] [string] $Path,
    [Parameter(Position = 1)] [string] $OutDir,
    [switch] $Preview,
    [string] $MaxWidth = '1250'
)

$script:Tools = $PSScriptRoot
$script:OwnFile = '^block-\d{2,}-line-\d+\.(mmd|png)$'
$script:Usage = 'Usage:  pwsh -NoProfile -File Export-MermaidBlocks.ps1 [-Path] <document.md> [-OutDir] <out folder> [-Preview] [-MaxWidth <px>]'
$script:Shown = 6  # lines of a failed preview's output shown, from the first, where mermaid-cli says what went wrong
$script:Scale = 2  # preview_png.py's SCALE: the PNG's pixels to each of the chart's

function Write-Line([string] $Text) {
    # Straight to stdout: a function's pipeline output would join the value it returns.
    [Console]::Out.WriteLine($Text)
}

function Write-Problem([string] $Text) {
    [Console]::Error.WriteLine('Export-MermaidBlocks: ' + $Text)
}

function Open-Fence([int] $Number, [string] $Text) {
    # The fence a line opens, or $null.
    $match = [regex]::Match($Text, '^( {0,3})(`{3,}|~{3,})(.*)$')
    if (-not $match.Success) { return $null }
    $run = $match.Groups[2].Value
    $info = $match.Groups[3].Value
    if ($run[0] -eq '`' -and $info.Contains('`')) { return $null }
    # The first word ends at ASCII whitespace alone, as GitHub's cmark reads it: a no-break space is part of the word.
    $first = ($info.Trim([char[]] @(' ', "`t", "`v", "`f")) -split '[ \t\v\f]+')[0]
    [pscustomobject]@{
        Line   = $Number
        Indent = $match.Groups[1].Value.Length
        Char   = $run[0]
        Length = $run.Length
        Chart  = [string]::Equals($first, 'mermaid', [StringComparison]::OrdinalIgnoreCase)
        Body   = [Collections.Generic.List[string]]::new()
    }
}

function Test-Closing([object] $Fence, [string] $Text) {
    $match = [regex]::Match($Text, '^ {0,3}(`{3,}|~{3,})[ \t]*$')
    $match.Success -and $match.Groups[1].Value[0] -eq $Fence.Char -and $match.Groups[1].Value.Length -ge $Fence.Length
}

function Read-Chart([string[]] $Lines) {
    # Each chart, as the line of its opening fence and its lines, and the line of a fence never closed, or 0.
    $charts = [Collections.Generic.List[object]]::new()
    $fence = $null
    for ($index = 0; $index -lt $Lines.Count; $index++) {
        $text = $Lines[$index]
        if ($null -eq $fence) {
            $fence = Open-Fence ($index + 1) $text
        } elseif (Test-Closing $fence $text) {
            if ($fence.Chart) { $charts.Add([pscustomobject]@{ Line = $fence.Line; Body = $fence.Body }) }
            $fence = $null
        } elseif ($fence.Chart) {
            $spaces = $text.Length - $text.TrimStart(' ').Length
            $fence.Body.Add($text.Substring([Math]::Min($spaces, $fence.Indent)))
        }
    }
    [pscustomobject]@{ Charts = $charts; Unclosed = $(if ($null -eq $fence) { 0 } else { $fence.Line }) }
}

function Get-Shown([string] $Text) {
    # A path as a command line can take it: quoted only when it holds a space.
    if ($Text -match '\s') { '"' + $Text + '"' } else { $Text }
}

function Get-ChartWidth([string] $Png) {
    # The chart's width in pixels, from the width in its preview's header, or 0 where the preview is no PNG.
    try {
        $stream = [IO.File]::OpenRead($Png)
        try {
            $head = [byte[]]::new(24)
            $read = $stream.Read($head, 0, 24)
        } finally {
            $stream.Dispose()
        }
    } catch {
        return 0
    }
    if ($read -lt 24 -or [BitConverter]::ToString($head, 0, 8) -ne '89-50-4E-47-0D-0A-1A-0A' -or
        [Text.Encoding]::ASCII.GetString($head, 12, 4) -cne 'IHDR') { return 0 }
    $pixels = ([long] $head[16] -shl 24) -bor ([long] $head[17] -shl 16) -bor ([long] $head[18] -shl 8) -bor [long] $head[19]
    [long] [Math]::Ceiling($pixels / [double] $script:Scale)
}

function Invoke-Preview([object] $Written, [long] $Limit) {
    # Renders a PNG beside each chart, saying how each went and how wide each chart is, then names each chart wider
    # than the limit, 0 being none; $true when every one rendered and none is wider.
    # Wrapped at the assignment: an if hands back a one-element array as the bare string.
    $python = @(if ($IsWindows) { 'py', '-3' } else { 'python3' })
    if (-not (Get-Command -Name $python[0] -CommandType Application -ErrorAction SilentlyContinue)) {
        Write-Problem ('there is no ' + $python[0] + ' to run preview_png.py with; mermaid-charts'' setup.ps1 offers Python')
        return $false
    }
    $rest = @($python | Select-Object -Skip 1)
    $renderer = Join-Path $script:Tools 'mermaid-svg' 'mermaid_svg.py'
    $fix = ($python -join ' ') + ' ' + (Get-Shown $renderer) + ' setup'
    # Each native call runs where ErrorActionPreference is Continue: its exit code decides, never its stderr.
    $planText = & { $ErrorActionPreference = 'Continue'; & $python[0] @rest $renderer 'plan' 2> $null } | Out-String
    if ($LASTEXITCODE -ne 0) {
        Write-Problem ('mermaid_svg.py plan exited ' + $LASTEXITCODE)
        return $false
    }
    $install = ($planText | ConvertFrom-Json).install
    if ($install.state -eq 'error') {
        Write-Problem $install.error
        return $false
    }
    if ($install.state -eq 'missing') {
        Write-Problem ('mermaid-svg is not installed in ' + $install.folder + '; install it with ' + $fix + ', then preview again')
        return $false
    }
    if ($install.state -eq 'stale') {
        Write-Problem ('mermaid-svg in ' + $install.folder + ' was installed from other pins; update it with ' + $fix)
    }
    $previewer = Join-Path $script:Tools 'preview_png.py'
    $rendered = 0
    $wide = [Collections.Generic.List[string]]::new()
    foreach ($block in $Written) {
        $png = [IO.Path]::ChangeExtension($block.Mmd, '.png')
        $output = & { $ErrorActionPreference = 'Continue'; & $python[0] @rest $previewer $block.Mmd $png 2>&1 }
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $png -PathType Leaf)) {
            $said = @($output | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
            $why = if ($said.Count -gt 0) { ($said | Select-Object -First $script:Shown) -join ' / ' } else { 'preview_png.py exited ' + $LASTEXITCODE }
            Write-Line ('line {0}: FAILED: {1}' -f $block.Line, $why)
            continue
        }
        $width = Get-ChartWidth $png
        if ($width -eq 0) {
            Write-Line ('line {0}: FAILED: the preview is not a PNG' -f $block.Line)
            continue
        }
        $rendered++
        Write-Line ('line {0}: {1}, {2} px wide' -f $block.Line, $png, $width)
        if ($Limit -gt 0 -and $width -gt $Limit) { $wide.Add(('line {0}, {1} px' -f $block.Line, $width)) }
    }
    Write-Line ('{0} of {1} previews rendered.' -f $rendered, $Written.Count)
    if ($wide.Count -gt 0) {
        $plural = if ($wide.Count -eq 1) { '' } else { 's' }
        Write-Line ('{0} chart{1} wider than {2} px: {3}. Lay a long chain out top to bottom, or fold it into rows (LESSONS.md, lessons 13 and 33).' -f
            $wide.Count, $plural, $Limit, ($wide -join '; '))
    }
    $rendered -eq $Written.Count -and $wide.Count -eq 0
}

function Invoke-Export([string] $Document, [string] $Folder, [bool] $WithPreview, [string] $Widest) {
    $ErrorActionPreference = 'Stop'
    if (-not $Document -or -not $Folder -or $Widest -cnotmatch '^[0-9]+$') {
        [Console]::Error.WriteLine($script:Usage)
        return 1
    }
    $limit = [long] $Widest
    $source = [IO.Path]::GetFullPath($Document, $PWD.ProviderPath)
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        Write-Problem ('there is no document at ' + $source)
        return 1
    }
    try {
        # As export_blocks.py reads it: UTF-8, a byte order mark dropped, and bytes that are not UTF-8 refused.
        $bytes = [IO.File]::ReadAllBytes($source)
        $skip = if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { 3 } else { 0 }
        $lines = [Text.UTF8Encoding]::new($false, $true).GetString($bytes, $skip, $bytes.Length - $skip) -split '\r\n|\r|\n'
    } catch {
        Write-Problem ($source + ' could not be read: ' + $_.Exception.Message)
        return 1
    }
    $found = Read-Chart $lines
    $out = [IO.Path]::GetFullPath($Folder, $PWD.ProviderPath)
    $written = [Collections.Generic.List[object]]::new()
    try {
        [IO.Directory]::CreateDirectory($out) | Out-Null
        # A chart left by an earlier run, of a document that has since lost one, would read as current. Only this
        # tool's own files go: anything else in the folder is somebody's.
        Get-ChildItem -LiteralPath $out -File -Force | Where-Object { $_.Name -cmatch $script:OwnFile } |
            ForEach-Object { [IO.File]::Delete($_.FullName) }
        foreach ($chart in $found.Charts) {
            $mmd = Join-Path $out ('block-{0:D2}-line-{1}.mmd' -f ($written.Count + 1), $chart.Line)
            [IO.File]::WriteAllText($mmd, ($chart.Body -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
            $written.Add([pscustomobject]@{ Line = $chart.Line; Mmd = $mmd })
        }
    } catch {
        Write-Problem $_.Exception.Message
        return 1
    }
    $plural = if ($written.Count -eq 1) { '' } else { 's' }
    Write-Line ('{0} mermaid block{1} from {2}, written to {3}' -f $written.Count, $plural, $source, $out)
    if ($found.Unclosed -gt 0) {
        Write-Problem ('the fence opened at line ' + $found.Unclosed + ' is never closed, so nothing after it was read as a chart')
    }
    $previewed = $true
    if ($WithPreview -and $written.Count -gt 0) { $previewed = Invoke-Preview $written $limit }
    if ($previewed -and $found.Unclosed -eq 0) { 0 } else { 1 }
}

function Exit-Script([int] $Code) {
    # A bare exit would close an editor's host that dot-sourced this file; there a failure throws instead.
    if ($Host.Name -like '*Visual Studio Code*') {
        if ($Code -ne 0) { throw "Export-MermaidBlocks finished with exit code $Code" }
        return
    }
    exit $Code
}

if (-not $env:BB_SKILLS_NOEXEC) {
    $encoding = $env:PYTHONIOENCODING
    $console = [Console]::OutputEncoding
    try {
        # Python's messages, and every path printed here, reach whoever reads them whole.
        $env:PYTHONIOENCODING = 'utf-8'
        [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
        $code = Invoke-Export $Path $OutDir $Preview.IsPresent $MaxWidth
    } catch {
        Write-Problem $_.Exception.Message
        $code = 1
    } finally {
        $env:PYTHONIOENCODING = $encoding
        [Console]::OutputEncoding = $console
    }
    Exit-Script $code
}
