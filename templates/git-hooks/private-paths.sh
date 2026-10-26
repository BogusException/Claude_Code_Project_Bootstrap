#!/usr/bin/env bash
set -euo pipefail
is_private_path() {
    case "$1" in
        responses/*|*/responses/*|backups/*|*/backups/*|.venv/*|*/.venv/*|venv/*|*/venv/*|secrets/*|*/secrets/*|.claude/settings.local.json|*/.claude/settings.local.json|.codex/auth.json|*/.codex/auth.json|.codex/sessions/*|*/.codex/sessions/*|.codex/log/*|*/.codex/log/*|*.pem|*.key|*.p12|*.pfx) return 0 ;;
        .env.example|*/.env.example) return 1 ;;
        .env|*/.env|.env.*|*/.env.*) return 0 ;;
    esac
    return 1
}
guard_path() {
    local blocked=false result
    if is_private_path "$1"; then
        blocked=true
    elif git check-ignore --no-index -q -- "$1"; then
        blocked=true
    else
        result=$?
        [[ "$result" == 1 ]] || return "$result"
    fi
    if [[ "$blocked" == true ]]; then
        printf 'Refusing private path in Git: %q\n' "$1" >&2
        return 1
    fi
}
