#!/usr/bin/env bash
readonly MKPROJ_NAME_MAX=64
readonly MKPROJ_PATH_MAX=2048

validate_name() {
    local LC_ALL=C name="$1"
    if (( ${#name} < 1 || ${#name} > MKPROJ_NAME_MAX )); then
        err "Project name must contain 1-$MKPROJ_NAME_MAX ASCII characters."
        return 1
    fi
    if [[ ! "$name" =~ ^[a-z][a-z0-9_]*$ ]]; then
        err "Project name must start with a-z and contain only a-z, 0-9, and underscore."
        return 1
    fi
    case "$name" in
        and|as|assert|async|await|break|class|continue|def|del|elif|else|except|finally|for|from|global|if|import|in|is|lambda|nonlocal|not|or|pass|raise|return|try|while|with|yield)
            err "Project name must not be a Python reserved keyword."
            return 1 ;;
    esac
}

validate_cli_args() {
    if (( $# > 1 )); then
        err "Expected zero or one argument: project name, --help, or --test."
        return 1
    fi
    (( $# == 0 )) && return 0
    case "$1" in
        --help|-h|--usage|--test) return 0 ;;
        -*) err "Unknown option. Use --help for usage."; return 1 ;;
        *) validate_name "$1" ;;
    esac
}

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
