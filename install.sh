#!/usr/bin/env bash
# install.sh — check/install prerequisites, then create ~/bin/mkproj launcher
set -euo pipefail

BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/bin"
LAUNCHER="$BIN_DIR/mkproj"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { printf "${GREEN}[install]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[install]${NC} %s\n" "$*"; }
err()  { printf "${RED}[install]${NC} %s\n" "$*" >&2; }

source "$BOOTSTRAP_DIR/lib/runtime.sh"
install_launcher() {
    mkdir -p -- "$BIN_DIR"
    if [[ -L "$LAUNCHER" ]]; then err "Refusing to overwrite a symlinked launcher."; return 1; fi
    local launcher_command candidate content
    printf -v launcher_command 'exec %q "$@"' "$BOOTSTRAP_DIR/bootstrap.sh"
    content=$'#!/usr/bin/env bash\n'"$launcher_command"$'\n'
    candidate="$(mktemp "$BIN_DIR/.mkproj-launcher.XXXXXXXX")"
    printf '%s' "$content" > "$candidate"
    if ! bash "$candidate" --help >/dev/null; then
        rm -- "$candidate"
        err "Candidate launcher failed its smoke test; existing launcher retained."
        return 1
    fi
    rm -- "$candidate"
    replace_config "$LAUNCHER" "$content"
    chmod u+x "$LAUNCHER"
    log "Installed launcher: $LAUNCHER"
}

main_install() {
if (( $# > 1 )); then err "Use install.sh [--check|--help]."; exit 1; fi
case "${1:-}" in
    --help) echo "Usage: bash install.sh [--check]. --check performs no installation or writes."; exit 0 ;;
    --check) check_prerequisites; command -v screen >/dev/null; echo "Prerequisites satisfied."; exit 0 ;;
    "") ;;
    *) err "Unknown installer option."; exit 1 ;;
esac

echo ""
log "project-bootstrap installer"
echo ""

# ── Detect package manager ─────────────────────────────────────────────────────
APT=""
if command -v apt-get &>/dev/null; then APT="apt-get"
elif command -v apt    &>/dev/null; then APT="apt"
fi

# ── Prerequisite checks ────────────────────────────────────────────────────────
MISSING_PKGS=()

log "Checking prerequisites..."
echo ""

# git
if command -v git &>/dev/null; then
    log "  git       ✓  $(git --version)  ($(which git))"
else
    warn "  git       ✗  not found"
    MISSING_PKGS+=("git")
fi

# Python 3.12+
if python3 --version 2>/dev/null | grep -qE "3\.(1[2-9]|[2-9][0-9])"; then
    log "  python3   ✓  $(python3 --version)  ($(which python3))"
else
    PY_VER=$(python3 --version 2>/dev/null || echo "not found")
    warn "  python3   ✗  $PY_VER  (need 3.12+)"
    MISSING_PKGS+=("python3.12" "python3.12-venv")
fi

# jq
if command -v jq &>/dev/null; then
    log "  jq        ✓  $(jq --version)  ($(which jq))"
else
    warn "  jq        ✗  not found"
    MISSING_PKGS+=("jq")
fi

# flock is provided by util-linux on the supported apt-based Linux installer.
if ! command -v flock >/dev/null 2>&1; then MISSING_PKGS+=("util-linux"); fi

# screen
if command -v screen &>/dev/null; then
    log "  screen    ✓  $(screen --version | head -1)  ($(which screen))"
else
    warn "  screen    ✗  not found"
    MISSING_PKGS+=("screen")
fi

echo ""

# ── Install missing packages ───────────────────────────────────────────────────
if [[ ${#MISSING_PKGS[@]} -gt 0 ]]; then
    log "Missing: ${MISSING_PKGS[*]}"
    echo ""

    if [[ -z "$APT" ]]; then
        err "No apt/apt-get found — install the above packages manually, then re-run install.sh"
        exit 1
    fi

    log "Running sudo $APT update..."
    sudo "$APT" update -q
    echo ""

    for pkg in "${MISSING_PKGS[@]}"; do
        log "Installing $pkg..."
        if ! sudo "$APT" install -y "$pkg" 2>/dev/null; then
            if [[ "$pkg" == python3.12* ]]; then
                err "python3.12 not available in current apt sources."
                err "Add the deadsnakes PPA, then re-run install.sh:"
                err "  sudo add-apt-repository ppa:deadsnakes/ppa"
                err "  sudo apt update"
                err "  sudo apt install python3.12 python3.12-venv"
            else
                err "Failed to install $pkg — install manually, then re-run install.sh"
            fi
            exit 1
        fi
        log "  installed $pkg"
    done
    echo ""

    # Re-verify everything after install
    log "Re-verifying after install..."
    STILL_MISSING=()
    command -v git    &>/dev/null || STILL_MISSING+=("git")
    command -v jq     &>/dev/null || STILL_MISSING+=("jq")
    command -v screen &>/dev/null || STILL_MISSING+=("screen")
    command -v flock  &>/dev/null || STILL_MISSING+=("util-linux")
    python3 --version 2>/dev/null | grep -qE "3\.(1[2-9]|[2-9][0-9])" || STILL_MISSING+=("python3.12")

    if [[ ${#STILL_MISSING[@]} -gt 0 ]]; then
        err "Still missing after install: ${STILL_MISSING[*]}"
        err "Resolve the errors above and re-run install.sh"
        exit 1
    fi
    log "  All prerequisites now satisfied."
    echo ""
else
    log "All prerequisites satisfied."
    echo ""
fi

install_launcher

# ── PATH check ─────────────────────────────────────────────────────────────────
if echo "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
    log "~/bin is in PATH ✓"
else
    warn "~/bin is not in PATH. Add this line to ~/.bashrc, then run: source ~/.bashrc"
    warn ""
    warn "  export PATH=\"\$HOME/bin:\$PATH\""
    echo ""
fi

# ── Smoke test ─────────────────────────────────────────────────────────────────
echo ""
log "Smoke test: mkproj --help..."
if "$LAUNCHER" --help &>/dev/null; then
    log "  mkproj --help ✓"
else
    err "mkproj --help failed — check $LAUNCHER and $BOOTSTRAP_DIR/bootstrap.sh"
    exit 1
fi

echo ""
log "Install complete."
log "  Run: mkproj <name>   to create a new project"
log "  Run: mkproj --help   for full usage"
echo ""

}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main_install "$@"; fi
