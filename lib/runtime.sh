#!/usr/bin/env bash
backup_config() {
    local path="$1" backup_dir backup
    if [[ -L "$path" ]]; then
        err "Refusing to replace a symlinked configuration: $path"; return 1
    fi
    [[ -e "$path" ]] || return 0
    [[ -f "$path" ]] || { err "Expected a regular configuration file: $path"; return 1; }
    backup_dir="$(dirname "$path")/backups"
    mkdir -p -m 700 -- "$backup_dir"
    backup="$backup_dir/$(basename "$path").$(date +%Y%m%d-%H%M%S-%N).bak"
    cp --preserve=all -- "$path" "$backup" || return
    cmp -s -- "$path" "$backup" || { err "Backup verification failed: $path"; return 1; }
    log "  backup: $backup"
}
replace_config() {
    local path="$1" content="$2" tmp
    backup_config "$path" || return
    tmp="$(mktemp "$(dirname "$path")/.mkproj-config.XXXXXXXX")"
    if [[ -f "$path" ]]; then cp --preserve=all -- "$path" "$tmp"; fi
    if ! printf '%s' "$content" > "$tmp"; then rm -- "$tmp"; return 1; fi
    mv -T -- "$tmp" "$path"
}
check_prerequisites() {
    local missing=() item
    for item in git jq python3 flock; do
        command -v "$item" >/dev/null 2>&1 || missing+=("$item")
    done
    if ! python3 -c 'import sys; sys.exit(sys.version_info < (3,12))' 2>/dev/null; then
        missing+=("Python 3.12+")
    fi
    if (( ${#missing[@]} )); then err "Missing prerequisites: ${missing[*]}"; return 1; fi
}
check_project_repo() {
    [[ ! -e "$PROJECT_DIR/.git" ]] || {
        local top branch non_scaffold
        top="$(git -C "$PROJECT_DIR" rev-parse --show-toplevel)" || return
        [[ "$(realpath "$top")" == "$(realpath "$PROJECT_DIR")" ]] || {
            err "Project is not its own Git root."; return 1;
        }
        branch="$(git -C "$PROJECT_DIR" symbolic-ref --quiet --short HEAD)" || {
            err "Refusing detached HEAD."; return 1;
        }
        [[ "$branch" == main ]] || { err "Expected main; found $branch."; return 1; }
        if git -C "$PROJECT_DIR" rev-parse HEAD >/dev/null 2>&1; then
            non_scaffold="$(git -C "$PROJECT_DIR" log --format=%s | grep -cv '^Initial project scaffold$\|^Complete project scaffold$\|^auto-commit: ' || true)"
            [[ "$non_scaffold" == 0 ]] || { err "STOP: project contains real project commits."; return 1; }
        fi
        git -C "$PROJECT_DIR" diff --cached --quiet || {
            err "Refusing a project with pre-existing staged changes."; return 1;
        }
        git -C "$PROJECT_DIR" diff --quiet || {
            err "Refusing a project with unstaged tracked changes."; return 1;
        }
        [[ ! -f "$(git -C "$PROJECT_DIR" rev-parse --absolute-git-dir)/MERGE_HEAD" ]] || {
            err "Refusing a merge in progress."; return 1;
        }
        [[ -z "$(git -C "$PROJECT_DIR" diff --name-only --diff-filter=U)" ]] || {
            err "Refusing unresolved merge conflicts."; return 1;
        }
    }
    # Never bootstrap inside a parent repository.
    if [[ ! -e "$PROJECT_DIR/.git" ]] && git -C "$(dirname "$PROJECT_DIR")" rev-parse --git-dir >/dev/null 2>&1; then
        err "Refusing to create a nested repository."; return 1
    fi
}
check_repo_destination() {
    [[ "$SETUP_LOCAL_REPO" == true ]] || return 0
    validate_project_path "$BARE_REPO" || return
    [[ "$BARE_REPO" == /* ]] || { err "Bare repository path must be absolute."; return 1; }
    local current=""
    if [[ -e "$PROJECT_DIR/.git" ]]; then
        current="$(git -C "$PROJECT_DIR" remote get-url origin 2>/dev/null || true)"
        [[ -z "$current" || "$current" == "$BARE_REPO" ]] || {
            err "Origin already points elsewhere; it will not be changed."; return 1;
        }
    fi
    if [[ -e "$BARE_REPO" || -L "$BARE_REPO" ]]; then
        [[ "$(git --git-dir="$BARE_REPO" rev-parse --is-bare-repository 2>/dev/null)" == true ]] || {
            err "Repository destination exists but is not a bare repository."; return 1;
        }
        # Resume only with the exact origin and identical ref map.
        [[ "$current" == "$BARE_REPO" ]] || {
            err "Bare repository collision; aborting without overwrite."; return 1;
        }
        [[ "$(git -C "$PROJECT_DIR" show-ref --heads --tags 2>/dev/null || true)" == "$(git --git-dir="$BARE_REPO" show-ref --heads --tags 2>/dev/null || true)" ]] || {
            err "Local and bare refs differ; resolve explicitly before resuming."; return 1;
        }
    fi
}
configure_git_guards() {
    local current
    current="$(git -C "$PROJECT_DIR" config --local --get core.hooksPath || true)"
    [[ -z "$current" || "$current" == .githooks ]] || {
        err "Existing custom hooksPath retained; integrate the private-path guards explicitly."; return 1;
    }
    local hook git_dir
    git_dir="$(git -C "$PROJECT_DIR" rev-parse --absolute-git-dir)"
    if [[ -z "$current" ]]; then
        for hook in pre-commit pre-push; do
            [[ ! -e "$git_dir/hooks/$hook" ]] || {
                err "Existing native hook retained: $hook. Integrate guards explicitly."; return 1;
            }
        done
    fi
    for hook in private-paths.sh pre-commit pre-push; do
        if [[ -e "$PROJECT_DIR/.githooks/$hook" ]] &&
           ! cmp -s "$TEMPLATES_DIR/git-hooks/$hook" "$PROJECT_DIR/.githooks/$hook"; then
            err "Existing custom Git guard retained: $hook"; return 1
        fi
    done
    for hook in private-paths.sh pre-commit pre-push; do
        copy_template "git-hooks/$hook" ".githooks/$hook"
    done
    chmod +x "$PROJECT_DIR/.githooks/pre-commit" "$PROJECT_DIR/.githooks/pre-push"
    if [[ "$current" != .githooks ]]; then
        backup_config "$(git -C "$PROJECT_DIR" rev-parse --absolute-git-dir)/config"
        git -C "$PROJECT_DIR" config --local core.hooksPath .githooks
    fi
}
verify_privacy_rules() {
    local path
    for path in responses/private.txt responses/.gitkeep backups/config.bak .claude/settings.local.json .venv/probe secrets/probe.key; do
        git -C "$PROJECT_DIR" check-ignore --no-index -q -- "$path" || {
            err "Missing ignore protection: $path"; return 1;
        }
    done
    local tracked
    source "$TEMPLATES_DIR/git-hooks/private-paths.sh"
    while IFS= read -r -d '' tracked; do
        if is_private_path "$tracked"; then
            printf 'Private path is already tracked: %q\n' "$tracked" >&2
            return 1
        fi
    done < <(git -C "$PROJECT_DIR" ls-files -z)
}
doctor() {
    local failed=false item
    for item in git jq python3 flock screen claude codex; do
        if command -v "$item" >/dev/null 2>&1; then log "OK command: $item"
        elif [[ "$item" == claude || "$item" == codex || "$item" == screen ]]; then warn "Optional command absent: $item"
        else err "Required command absent: $item"; failed=true; fi
    done
    check_prerequisites || failed=true
    if [[ -e "$PROJECT_DIR/.git" ]]; then
        log "Git root: $(git -C "$PROJECT_DIR" rev-parse --show-toplevel)"
        verify_privacy_rules || failed=true
        [[ "$(git -C "$PROJECT_DIR" config --get core.hooksPath || true)" == .githooks ]] || { err "Private-path native Git guards are not enabled."; failed=true; }
        local hook
        for hook in pre-commit pre-push; do
            [[ -x "$PROJECT_DIR/.githooks/$hook" ]] || { err "Missing executable Git guard: $hook"; failed=true; }
        done
        git -C "$PROJECT_DIR" diff --quiet || warn "Working tree has unstaged changes."
        git -C "$PROJECT_DIR" diff --cached --quiet || warn "Index has staged changes."
        local url
        while IFS= read -r url; do log "Origin push destination: $url"; done < <(git -C "$PROJECT_DIR" remote get-url --push --all origin 2>/dev/null || true)
    else
        err "No project Git repository."; failed=true
    fi
    if [[ -x "$PROJECT_DIR/.venv/bin/python" ]]; then
        "$PROJECT_DIR/.venv/bin/python" -c 'import pathlib,sys; sys.exit(pathlib.Path(sys.prefix).resolve()!=pathlib.Path(sys.argv[1]).resolve())' "$PROJECT_DIR/.venv" || { err "Venv interpreter points to another environment."; failed=true; }
    else err "Project .venv interpreter missing."; failed=true; fi
    [[ "$failed" == false ]]
}
dry_run() {
    check_prerequisites
    check_project_repo
    log "DRY RUN: no project files, repos, global configuration, or remote refs will change."
    log "Target: $PROJECT_DIR"
    log "Would create missing project files, .venv, shared directives, and private-path Git guards."
    log "Would offer optional local origin at ${MKPROJ_REPOSITORIES_DIR:-$HOME/Repositories}/$PROJECT_NAME.git."
    if [[ -e "${MKPROJ_REPOSITORIES_DIR:-$HOME/Repositories}/$PROJECT_NAME.git" ]]; then
        warn "Existing bare destination detected; normal setup will validate it and refuse a collision."
    fi
    log "Would verify before committing only generated files."
    log "Global setup is opt-in; selected agent: $LAUNCH_AGENT."
}
