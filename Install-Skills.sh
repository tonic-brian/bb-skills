#!/usr/bin/env bash
# Runs a PowerShell script under PowerShell 7+, downloading the latest stable release if no
# PowerShell 7+ is available, and forwards every remaining argument to the script.
#
# Reusable: to wrap a different script, copy this file and change the block marked
# "THE SCRIPT THIS WRAPPER RUNS" below. Any copy can also run another script with
# --script PATH (or PWSH_SCRIPT).
#
# Usage:
#   ./<wrapper>.sh [wrapper-flags] [script args...]
#   bash|zsh|sh ./<wrapper>.sh [wrapper-flags] [script args...]
#
# The body is portable POSIX sh, so it runs the same under bash, zsh and sh.
# See --help for the full flag reference.

# ══ THE SCRIPT THIS WRAPPER RUNS ═════════════════════════════════════════════
# The .ps1 to run, relative to this wrapper's own directory (an absolute path also works).
default_ps_script=Install-Skills.ps1

# Help for the script's own arguments, shown by --help. Empty it in a copy if you like.
script_help() {
    cat <<'EOF'
  -Apply                  Make the changes; alone, install every skill. Without it a run writes nothing.
  -Skill NAMES            Install only these skills, comma-separated.
  -AddHooks SKILL         Add this installed skill's hooks to settings.json.
  -Configure SKILL        This installed skill's settings: -Set's values, or each asked.
  -RemoveHooks SKILL      Take this skill's hooks out of settings.json.
  -Yes                    Answer yes to each hooks offer and each stale hook's removal.
  -Set PAIRS              Settings' values: skill.key=value, comma-separated; "a, b" for a list.
  -SetupAnswer PAIRS      Setup answers: skill:item=yes, comma-separated, each passed as -Answer.
  -Rename PAIRS           Install skills under other names: old=new, comma-separated.
  -AskNames               Ask the name of every skill, not only the new ones.
  -NoSetup                Run no setup; a skill's hooks still wait for its check.
  -Setup                  Run each needed setup even with nobody there.
  -NoHooks                Offer no skill's hooks.
  -NoSettings             Offer no skill's settings.
  -NoBackup               Keep no copy of what is replaced; needs -Force.
  -Force                  With -NoBackup, replace without keeping a copy.
  -NonInteractive         Ask nothing, as when nobody is there.
  -SkillSource DIR        The folder holding the skills; this script's folder without it.
  -SkillDestination DIR   The skills folder; ~/.claude/skills without it.
  -Options                List the actions and flags, changing nothing.
  -WhatIf                 With -Apply, show what it would change and write nothing.

With no action it shows the state of things, or offers a menu at a terminal; an action without -Apply is a
dry run. -? shows the installer's full help.
EOF
}
# ═════════════════════════════════════════════════════════════════════════════

# Under zsh, behave like sh: split words and leave unmatched globs alone.
if [ -n "${ZSH_VERSION:-}" ]; then emulate sh; fi
set -eu
# pipefail is not POSIX; turn it on where the shell has it.
if (set -o pipefail) 2>/dev/null; then set -o pipefail; fi

wrapper_name=$(basename -- "$0")
script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

# Fallback when the latest release cannot be determined (offline, rate-limited, ...).
fallback_version=7.4.7
latest_release_url=https://github.com/PowerShell/PowerShell/releases/latest

info() { printf '%s\n' "$*" >&2; }
err()  { printf 'Error: %s\n' "$*" >&2; }

# ── Help ──────────────────────────────────────────────────────────────────────

show_help() {
    cat <<EOF
Usage: $wrapper_name [wrapper-flags] [script args...]

Runs $default_ps_script under PowerShell 7+ (bash, zsh or sh). Finds PowerShell 7+ in this
order, downloading only if needed:
  1. --pwsh-path / PWSH_PATH        (must be PowerShell 7+)
  2. pwsh on PATH                   (used only if it is PowerShell 7+)
  3. a previous auto-install        (no network needed)
  4. download the latest stable PowerShell release (or PWSH_VERSION)

Wrapper flags (consumed here, not forwarded to PowerShell):
  --help, -h          Show this help and exit
  --script PATH       Run this .ps1 instead of $default_ps_script
                      Also respected as the PWSH_SCRIPT environment variable
  --no-download       Fail instead of downloading when no PowerShell 7+ is found
  --pwsh-path PATH    Use this pwsh binary (must be PowerShell 7+)
                      Also respected as the PWSH_PATH environment variable
  --                  End of wrapper flags; everything after goes to the script

All other arguments are forwarded to the script.
EOF
    _sh_text=$(script_help)
    if [ -n "$_sh_text" ]; then
        printf '\nArguments of %s:\n%s\n' "$default_ps_script" "$_sh_text"
    fi
    cat <<'EOF'

Environment variables:
  PWSH_SCRIPT         Path to the .ps1 to run (same as --script)
  PWSH_PATH           Path to a pwsh binary (same as --pwsh-path)
  PWSH_VERSION        Pin the PowerShell version to download (default: the latest stable release)
  PWSH_INSTALL_ROOT   Where auto-installs live (default: ~/.local/share/powershell/autoinstall,
                        or %LOCALAPPDATA%\PowerShell\AutoInstall on Windows)
EOF
}

# ── Flag parsing ─────────────────────────────────────────────────────────────

# Environment variables are the baseline; flags override them.
script_override="${PWSH_SCRIPT:-}"
pwsh_override="${PWSH_PATH:-}"
no_download=false

while [ $# -gt 0 ]; do
    case "$1" in
        --help|-h)
            show_help; exit 0 ;;
        --no-download)
            no_download=true; shift ;;
        --script)
            if [ $# -lt 2 ]; then err "--script needs a value"; exit 1; fi
            script_override="$2"; shift 2 ;;
        --script=*)
            script_override="${1#*=}"; shift ;;
        --pwsh-path)
            if [ $# -lt 2 ]; then err "--pwsh-path needs a value"; exit 1; fi
            pwsh_override="$2"; shift 2 ;;
        --pwsh-path=*)
            pwsh_override="${1#*=}"; shift ;;
        --)
            shift; break ;;
        *)
            break ;;   # first unrecognised arg and everything after goes to the script
    esac
done

# ── The script to run ────────────────────────────────────────────────────────

# An override is taken as given (relative to the current directory, as on any command line);
# the built-in default is relative to this wrapper's directory.
if [ -n "$script_override" ]; then
    ps_script=$script_override
else
    case "$default_ps_script" in
        /*) ps_script=$default_ps_script ;;
        *)  ps_script="$script_dir/$default_ps_script" ;;
    esac
fi

# Check before any PowerShell discovery or download, so a typo fails fast.
if [ ! -f "$ps_script" ]; then
    err "PowerShell script not found: $ps_script"; exit 1
fi

# ── PowerShell version checks ────────────────────────────────────────────────

# Prints the major version of a pwsh binary ("PowerShell 7.4.7" -> 7); fails if unreadable.
pwsh_major() {
    _pm_out=$("$1" --version 2>/dev/null) || return 1
    _pm_out=${_pm_out#*PowerShell }
    _pm_out=${_pm_out%%.*}
    case "$_pm_out" in ''|*[!0-9]*) return 1 ;; esac
    printf '%s\n' "$_pm_out"
}

pwsh_is_7plus() {
    _p7_major=$(pwsh_major "$1") || return 1
    [ "$_p7_major" -ge 7 ]
}

# ── 1. Explicit binary (--pwsh-path / PWSH_PATH) ─────────────────────────────

if [ -n "$pwsh_override" ]; then
    if [ ! -x "$pwsh_override" ]; then
        err "pwsh binary not executable: $pwsh_override"; exit 1
    fi
    if ! pwsh_is_7plus "$pwsh_override"; then
        err "$pwsh_override is not PowerShell 7 or newer; PowerShell 7+ is required."; exit 1
    fi
    exec "$pwsh_override" -NoProfile -File "$ps_script" "$@"
fi

# ── 2. pwsh on PATH, when it is 7+ ───────────────────────────────────────────

if command -v pwsh >/dev/null 2>&1; then
    if pwsh_is_7plus pwsh; then
        exec pwsh -NoProfile -File "$ps_script" "$@"
    fi
    info "pwsh on PATH is older than PowerShell 7; looking for PowerShell 7+ elsewhere."
fi

# ── Platform and install location ────────────────────────────────────────────

platform=$(uname -s)
arch=$(uname -m)

case "$arch" in
    x86_64|amd64)  arch_suffix=x64 ;;
    aarch64|arm64) arch_suffix=arm64 ;;
    *)             arch_suffix= ;;      # only matters if a download is needed
esac

case "$platform" in
    Linux*)               os=linux; pwsh_exe=pwsh ;;
    Darwin*)              os=osx;   pwsh_exe=pwsh ;;
    CYGWIN*|MINGW*|MSYS*) os=win;   pwsh_exe=pwsh.exe ;;
    *)                    err "Unsupported platform: $platform"; exit 1 ;;
esac

if [ -n "${PWSH_INSTALL_ROOT:-}" ]; then
    install_root=$PWSH_INSTALL_ROOT
elif [ "$os" = win ]; then
    local_app_data=${LOCALAPPDATA:-}
    if [ -n "$local_app_data" ] && command -v cygpath >/dev/null 2>&1; then
        local_app_data=$(cygpath -u "$local_app_data")
    fi
    if [ -z "$local_app_data" ]; then local_app_data="$HOME/AppData/Local"; fi
    install_root="$local_app_data/PowerShell/AutoInstall"
else
    install_root="${XDG_DATA_HOME:-$HOME/.local/share}/powershell/autoinstall"
fi

# Where earlier versions of this wrapper installed (with sudo); still honoured if present.
legacy_root=
if [ "$os" != win ] && [ -z "${PWSH_INSTALL_ROOT:-}" ]; then
    legacy_root=/usr/local/tmp/microsoft/powershell
fi

# ── 3. A previous auto-install (no network) ──────────────────────────────────

# Prints the path of an installed PowerShell 7+ under the install roots; fails if none.
# Uses find rather than a glob: a glob that matches nothing is an error under zsh.
find_installed_pwsh() {
    _fi_best=
    for _fi_root in "$install_root" "$legacy_root"; do
        if [ -z "$_fi_root" ] || [ ! -d "$_fi_root" ]; then continue; fi
        if [ -n "${PWSH_VERSION:-}" ]; then
            _fi_list="$_fi_root/$PWSH_VERSION"
        else
            _fi_list=$(find "$_fi_root" -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true)
        fi
        while IFS= read -r _fi_dir; do
            if [ -z "$_fi_dir" ]; then continue; fi
            if [ -f "$_fi_dir/$pwsh_exe" ] && pwsh_is_7plus "$_fi_dir/$pwsh_exe"; then
                _fi_best="$_fi_dir/$pwsh_exe"
            fi
        done <<EOF
$_fi_list
EOF
    done
    if [ -z "$_fi_best" ]; then return 1; fi
    printf '%s\n' "$_fi_best"
}

if installed=$(find_installed_pwsh); then
    exec "$installed" -NoProfile -File "$ps_script" "$@"
fi

# ── 4. Download ──────────────────────────────────────────────────────────────

if [ "$no_download" = true ]; then
    err "No PowerShell 7+ found and --no-download was specified."
    info "Install PowerShell 7+ from https://github.com/PowerShell/PowerShell/releases"
    info "or use --pwsh-path to point at an existing PowerShell 7+ binary."
    exit 1
fi

if [ -z "$arch_suffix" ]; then
    err "Unsupported architecture for the PowerShell download: $arch"; exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
    err "curl is required to download PowerShell but was not found on PATH."
    info "Install curl, or put PowerShell 7+ on PATH / use --pwsh-path to skip the download."
    exit 1
fi

# Prints the latest stable PowerShell release's version (7.x or later), from where the
# releases/latest page redirects (.../releases/tag/v7.5.4); fails if it cannot tell.
resolve_latest_version() {
    _rl_url=$(curl -fsSL -o /dev/null -w '%{url_effective}' "$latest_release_url") || return 1
    _rl_tag=${_rl_url##*/}
    _rl_tag=${_rl_tag#v}
    case "$_rl_tag" in [0-9]*.[0-9]*.[0-9]*) ;; *) return 1 ;; esac
    _rl_major=${_rl_tag%%.*}
    case "$_rl_major" in ''|*[!0-9]*) return 1 ;; esac
    if [ "$_rl_major" -lt 7 ]; then return 1; fi
    printf '%s\n' "$_rl_tag"
}

if [ -n "${PWSH_VERSION:-}" ]; then
    version=$PWSH_VERSION
elif version=$(resolve_latest_version); then
    :
else
    info "Could not determine the latest PowerShell release; using $fallback_version."
    version=$fallback_version
fi

if [ "$os" = win ]; then
    asset="PowerShell-${version}-win-${arch_suffix}.zip"
else
    asset="powershell-${version}-${os}-${arch_suffix}.tar.gz"
fi
url="https://github.com/PowerShell/PowerShell/releases/download/v${version}/${asset}"
target_dir="$install_root/$version"

tmp_dir=$(mktemp -d 2>/dev/null || mktemp -d -t pwshwrap)
trap 'rm -rf "$tmp_dir"' EXIT
trap 'rm -rf "$tmp_dir"; exit 130' INT
trap 'rm -rf "$tmp_dir"; exit 143' TERM

archive="$tmp_dir/$asset"
staging="$tmp_dir/extract"

info ""
info "Running on $platform ($arch)"
info "Downloading PowerShell $version..."
info "  URL: $url"
curl -fSL -o "$archive" "$url"

mkdir -p "$staging"
info "Extracting..."
case "$asset" in
    *.tar.gz)
        tar -xzf "$archive" -C "$staging" ;;
    *.zip)
        if command -v unzip >/dev/null 2>&1; then
            unzip -qo "$archive" -d "$staging"
        else
            # Extract with Windows' own PowerShell; quote paths for a single-quoted string.
            win_archive=$(cygpath -w "$archive" | sed "s/'/''/g")
            win_staging=$(cygpath -w "$staging" | sed "s/'/''/g")
            powershell.exe -NoLogo -NoProfile -Command \
                "Add-Type -AssemblyName System.IO.Compression.FileSystem; [IO.Compression.ZipFile]::ExtractToDirectory('$win_archive', '$win_staging')"
        fi ;;
esac

if [ ! -f "$staging/$pwsh_exe" ]; then
    err "The download did not contain $pwsh_exe: $url"; exit 1
fi
if [ "$os" != win ]; then chmod +x "$staging/$pwsh_exe"; fi

# Move into place only once the extraction is complete, so a failed run never leaves a
# half-extracted install that a later run would trust.
mkdir -p "$install_root"
rm -rf "$target_dir"
mv "$staging" "$target_dir"

if ! pwsh_is_7plus "$target_dir/$pwsh_exe"; then
    err "The downloaded PowerShell at $target_dir does not run as PowerShell 7+."; exit 1
fi

info "Installed PowerShell $version to $target_dir"
info "PowerShell is starting for the first time, please wait a moment..."
info ""

rm -rf "$tmp_dir"
trap - EXIT INT TERM
exec "$target_dir/$pwsh_exe" -NoProfile -File "$ps_script" "$@"
