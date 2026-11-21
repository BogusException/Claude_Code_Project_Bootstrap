#!/usr/bin/env bash
readonly MKPROJ_NAME_MAX=64
readonly MKPROJ_PATH_MAX=2048

validate_name() {
    local LC_ALL=C name="$1"
    if (( ${#name} < 1 || ${#name} > MKPROJ_NAME_MAX )); then
        err "Project name must contain 1-$MKPROJ_NAME_MAX ASCII characters."
        return 1
    fi
    if [[ ! "$name" =~ ^[a-z][a-z0-9_-]*$ ]]; then
        err "Project name must start with a-z and contain only a-z, 0-9, underscore, or hyphen."
        return 1
    fi
    if [[ "$name" == *- ]]; then
        err "Project name must not end with a hyphen."
        return 1
    fi
    if [[ "$name" == *--* ]]; then
        err "Project name must not contain consecutive hyphens."
        return 1
    fi
    case "$name" in
        and|as|assert|async|await|break|class|continue|def|del|elif|else|except|finally|for|from|global|if|import|in|is|lambda|nonlocal|not|or|pass|raise|return|try|while|with|yield)
            err "Project name must not be a Python reserved keyword."
            return 1 ;;
    esac
}

parse_args() {
    MODE=setup
    PROJECT_ARG=""
    HAS_PROJECT_ARG=false
    LAUNCH_AGENT=ask
    NO_GLOBAL=false
    INSTALL_KEYBINDINGS=false
    SCAN_DIR=""
    YES_MODE=false
    QUIET=false
    VERBOSE=false
    FORCE_FILE=""
    ACCEPT_FILE=""
    local arg mode_seen=false agent_seen=false next_is_force=false next_is_file=false
    for arg in "$@"; do
        # Handle values for --force-file and --file
        if [[ "$next_is_force" == true ]]; then
            FORCE_FILE="$arg"
            next_is_force=false
            continue
        fi
        if [[ "$next_is_file" == true ]]; then
            ACCEPT_FILE="$arg"
            next_is_file=false
            continue
        fi
        case "$arg" in
            --help|-h|--usage|--test|--doctor|--dry-run|--update|--scan|--status|\
            --pending|--adopt|--version|--safe-update|--check|--report|--accept|\
            --restore-infra|--list-tiers)
                [[ "$mode_seen" == false ]] || { err "Choose one command mode."; return 1; }
                mode_seen=true
                case "$arg" in
                    --help|-h|--usage)  MODE=help ;;
                    --test)             MODE=test ;;
                    --doctor)           MODE=doctor ;;
                    --dry-run)          MODE=dry-run ;;
                    --update)           MODE=update ;;
                    --scan)             MODE=scan ;;
                    --status)           MODE=status ;;
                    --pending)          MODE=pending ;;
                    --adopt)            MODE=adopt ;;
                    --version)          MODE=version ;;
                    --safe-update)      MODE=safe-update ;;
                    --check)            MODE=check ;;
                    --report)           MODE=report ;;
                    --accept)           MODE=accept ;;
                    --restore-infra)    MODE=restore-infra ;;
                    --list-tiers)       MODE=list-tiers ;;
                esac ;;
            --agent=claude|--agent=codex|--agent=none)
                [[ "$agent_seen" == false ]] || { err "Duplicate agent option."; return 1; }
                LAUNCH_AGENT="${arg#--agent=}"; agent_seen=true ;;
            --no-global)
                [[ "$NO_GLOBAL" == false ]] || { err "Duplicate --no-global."; return 1; }
                NO_GLOBAL=true ;;
            --keybindings)   INSTALL_KEYBINDINGS=true ;;
            --yes|-y)        YES_MODE=true ;;
            --quiet|-q)      QUIET=true ;;
            --verbose|-v)    VERBOSE=true ;;
            --force-file)    next_is_force=true ;;
            --file)          next_is_file=true ;;
            -*)
                err "Unknown option: $arg. Use --help."; return 1 ;;
            *)
                [[ "$HAS_PROJECT_ARG" == false ]] || { err "Only one project name/path is allowed."; return 1; }
                PROJECT_ARG="$arg"; HAS_PROJECT_ARG=true ;;
        esac
    done

    # Handle dangling value flags
    [[ "$next_is_force" == false ]] || { err "--force-file requires a file path argument."; return 1; }
    [[ "$next_is_file" == false ]]  || { err "--file requires a file path argument."; return 1; }

    if [[ "$MODE" == help || "$MODE" == test || "$MODE" == version ]]; then
        (( $# == 1 )) || { err "This mode takes no additional arguments."; return 1; }
    fi
    if [[ "$MODE" == doctor && ( "$agent_seen" == true || "$NO_GLOBAL" == true ) ]]; then
        err "--doctor takes only an optional project name."; return 1
    fi
    if [[ -n "$FORCE_FILE" && "$MODE" != update ]]; then
        err "--force-file is only valid with --update."; return 1
    fi
    if [[ -n "$FORCE_FILE" && "$YES_MODE" == true ]]; then
        err "--force-file cannot be combined with --yes."; return 1
    fi
    if [[ "$MODE" == accept && -z "$ACCEPT_FILE" ]]; then
        err "--accept requires --file REL_PATH."; return 1
    fi

    # scan/status/pending/check/safe-update/report/restore-infra/list-tiers
    # accept a dir arg (not validated as a project name)
    case "$MODE" in
        scan|status|pending|check|safe-update|report|restore-infra|list-tiers)
            if [[ "$HAS_PROJECT_ARG" == true ]]; then
                SCAN_DIR="$PROJECT_ARG"
                HAS_PROJECT_ARG=false
                PROJECT_ARG=""
            fi
            [[ -z "$SCAN_DIR" ]] && SCAN_DIR="$PWD"
            ;;
    esac
}
validate_cli_args() { parse_args "$@"; }

validate_project_path() {
    local LC_ALL=C path="$1"
    if (( ${#path} > MKPROJ_PATH_MAX )); then
        err "Project path exceeds the $MKPROJ_PATH_MAX-byte application limit."
        return 1
    fi
    if [[ "$path" =~ [[:cntrl:]] ]]; then
        err "Project path must not contain control characters."
        return 1
    fi
    if [[ ( -e "$path" || -L "$path" ) && ! -d "$path" ]]; then
        err "Project path exists but is not a directory."
        return 1
    fi
}

# Detect overflow with a bounded read; never truncate an answer into validity.
read_choice() {
    local -n choice_target="$1"
    local prompt="$2" default="$3" allowed="$4"
    local LC_ALL=C reply discard
    while true; do
        reply=""
        if ! IFS= read -r -n 2 -p "$prompt" reply; then
            err "Input ended before a complete answer; aborted."
            return 1
        fi
        if (( ${#reply} > 1 )); then
            while IFS= read -r -n 1024 discard && (( ${#discard} == 1024 )); do :; done
            err "Enter one of [$allowed], or press Enter for $default."
            continue
        fi
        [[ -n "$reply" ]] || reply="$default"
        if [[ "$allowed" == *"$reply"* ]]; then
            choice_target="${reply,,}"
            return 0
        fi
        err "Enter one of [$allowed], or press Enter for $default."
    done
}
