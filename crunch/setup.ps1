#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Checks for what crunch's optional hook needs, Node.js 18 or later, and names it when it is missing.
    It installs nothing.

.DESCRIPTION
    The skill itself needs nothing. Its hook runs on Node.js 18 or later, the floor of the project it comes from, and
    the installer offers it only once this setup finds nothing missing. Node.js is named, not installed: install it
    from nodejs.org or with a version manager, then install the skill again to be offered the hook.

    It exits 0 whatever it finds, since it runs nothing that could fail.

.PARAMETER Check
    Ask nothing: exit 0 when Node.js 18 or later is on PATH, 1 when it isn't, and 2 on an error.

.PARAMETER Answer
    Taken for the setup contract every skill's setup shares; there is nothing here to answer.

.EXAMPLE
    pwsh -NoProfile -File setup.ps1 -Check
#>
[CmdletBinding()]
param(
    [switch] $Check,
    [string[]] $Answer
)

$script:MinimumNode = [version] '18.0.0'

function Get-NodeVersion {
    # The version of the node on PATH, or $null when there is none or it doesn't say. Scripts count as well as
    # programs, so a test's stand-in on PATH is found the way a real node is.
    $node = Get-Command -Name 'node' -CommandType Application, ExternalScript -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $node) { return $null }
    $text = & $node.Source --version 2> $null | Out-String
    if ($text -match 'v?(\d+)\.(\d+)\.(\d+)') { return [version] "$($Matches[1]).$($Matches[2]).$($Matches[3])" }
    $null
}

function Invoke-CrunchSetup {
    param([switch] $CheckOnly)
    $ErrorActionPreference = 'Stop'
    $version = Get-NodeVersion
    $ready = $null -ne $version -and $version -ge $script:MinimumNode
    if ($CheckOnly) { return [int] (-not $ready) }

    Write-Host ''
    Write-Host 'crunch setup:'
    if ($ready) {
        Write-Host "  Node.js    already there ($version)"
        return 0
    }
    $have = if ($version) { "Node.js $version is too old" } else { 'there is no Node.js on PATH' }
    Write-Host ('  Node.js    named: {0}, and the hook needs {1} or later. Install it from https://nodejs.org/en/download or with nvm, then install the skill again to be offered the hook.' -f $have, $script:MinimumNode.Major)
    0
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
        $code = Invoke-CrunchSetup -CheckOnly:$Check
    } catch {
        Write-Host "crunch setup: $($_.Exception.Message)"
        $code = 2
    }
    Exit-Script $code
}
