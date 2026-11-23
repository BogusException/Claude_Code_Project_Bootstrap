#!/usr/bin/env bash
# update.sh -- mkproj update and scan logic

# MANIFEST_FILE is set by bootstrap.sh after BOOTSTRAP_DIR is known.
# load_manifest -- validate that the manifest is readable; warn if missing.
load_manifest() {
    if [[ -z "${MANIFEST_FILE:-}" ]]; then
        warn "MANIFEST_FILE not set; tier lookups will default to 'optional'."
        return 0
    fi
    if [[ ! -f "$MANIFEST_FILE" ]]; then
        warn "Manifest not found: $MANIFEST_FILE -- tier lookups will default to 'optional'."
        return 0
    fi
    jq empty "$MANIFEST_FILE" 2>/dev/null || {
        warn "Manifest is not valid JSON: $MANIFEST_FILE -- tier lookups will default to 'optional'."
    }
}

# file_tier REL_PATH
# Returns the tier for a path: directive | infrastructure | optional
file_tier() {
    local rel="$1"
    if [[ -n "${MANIFEST_FILE:-}" && -f "$MANIFEST_FILE" ]]; then
        local t
        t="$(jq -r --arg p "$rel" '.files[$p].tier // .default_tier // "optional"' "$MANIFEST_FILE" 2>/dev/null)"
        printf '%s\n' "${t:-optional}"
    else
        printf 'optional\n'
    fi
}

# file_update_decision PROJECT_DIR REL_PATH
# Echoes one of:
#   skip_unchanged | auto_update | skip_user_edit
#   conflict | conflict_directive
#   skip_deleted | skip_deleted_optional | skip_deleted_infra | skip_deleted_directive
#   new_file | untracked
file_update_decision() {
    local project_dir="$1" rel="$2"
    local disk_path="$project_dir/$rel"
    local status; status="$(registry_file_status "$project_dir" "$rel")"
    local tier; tier="$(file_tier "$rel")"

    # Deleted-file decisions vary by tier
    if [[ "$status" == "installed" && ! -f "$disk_path" ]]; then
        case "$tier" in
            directive)      printf 'skip_deleted_directive\n' ;;
            infrastructure) printf 'skip_deleted_infra\n' ;;
            *)              printf 'skip_deleted_optional\n' ;;
        esac
        return
    fi

    if [[ "$status" == "deferred" ]]; then
        [[ "$tier" == "directive" ]] && printf 'conflict_directive\n' || printf 'conflict\n'
        return
    fi
    if [[ "$status" == "unknown" ]]; then
        [[ -f "$disk_path" ]] && printf 'untracked\n' || printf 'new_file\n'
        return
    fi

    local hashes; hashes="$(registry_file_hashes "$project_dir" "$rel")"
    local stored_tpl_hash="${hashes%% *}"
    local stored_inst_hash="${hashes##* }"

    local cur_tpl_hash cur_disk_hash
    cur_tpl_hash="$(current_template_hash "$rel")"
    [[ -f "$disk_path" ]] && cur_disk_hash="$(sha256sum "$disk_path" | cut -d' ' -f1)" || cur_disk_hash=""

    local tpl_changed=false disk_changed=false
    [[ "$cur_tpl_hash" != "$stored_tpl_hash" ]] && tpl_changed=true
    [[ "$cur_disk_hash" != "$stored_inst_hash" ]] && disk_changed=true

    if [[ "$tpl_changed" == false && "$disk_changed" == false ]]; then
        printf 'skip_unchanged\n'
    elif [[ "$tpl_changed" == true && "$disk_changed" == false ]]; then
        # directive files are never auto-updated -- downgrade to conflict
        [[ "$tier" == "directive" ]] && printf 'conflict_directive\n' || printf 'auto_update\n'
    elif [[ "$tpl_changed" == false && "$disk_changed" == true ]]; then
        printf 'skip_user_edit\n'
    else
        [[ "$tier" == "directive" ]] && printf 'conflict_directive\n' || printf 'conflict\n'
    fi
}

# current_template_hash REL_PATH
current_template_hash() {
    local rel="$1"
    if [[ "$rel" == ".claude/settings.json" ]]; then
        generate_settings_json | sha256sum | cut -d' ' -f1
        return
    fi
    local tpl_path; tpl_path="$(project_to_template_path "$rel")"
    [[ -f "$tpl_path" ]] && sha256sum "$tpl_path" | cut -d' ' -f1 || printf '\n'
}

# project_to_template_path REL_PATH
# Exact inverse of template_to_project_path in lib/registry.sh.
project_to_template_path() {
    local rel="$1"
    case "$rel" in
        .claude/hooks/*)   printf '%s/claude/hooks/%s\n'  "$TEMPLATE_DIR" "$(basename "$rel")" ;;
        .claude/rules/*)   printf '%s/claude/rules/%s\n'  "$TEMPLATE_DIR" "$(basename "$rel")" ;;
        .claude/skills/*)  printf '%s/claude/skills/%s\n' "$TEMPLATE_DIR" "$(basename "$rel")" ;;
        .githooks/*)       printf '%s/git-hooks/%s\n'     "$TEMPLATE_DIR" "$(basename "$rel")" ;;
        *)                 printf '%s/project/%s\n'       "$TEMPLATE_DIR" "$rel" ;;
    esac
}

# apply_template_file PROJECT_DIR REL_PATH
apply_template_file() {
    local project_dir="$1" rel="$2"
    local project_name; project_name="$(basename "$project_dir")"
    local disk_path="$project_dir/$rel"
    mkdir -p "$(dirname "$disk_path")"

    if [[ "$rel" == ".claude/settings.json" ]]; then
        generate_settings_json > "$disk_path"
    else
        local tpl_path; tpl_path="$(project_to_template_path "$rel")"
        [[ -f "$tpl_path" ]] || { err "Template not found: $tpl_path"; return 1; }
        sed "s/{{PROJECT_NAME}}/$project_name/g" "$tpl_path" > "$disk_path"
    fi

    local tpl_hash disk_hash tier
    tpl_hash="$(current_template_hash "$rel")"
    disk_hash="$(sha256sum "$disk_path" | cut -d' ' -f1)"
    tier="$(file_tier "$rel")"
    registry_set_file "$project_dir" "$rel" "$tpl_hash" "$disk_hash" "installed" "$tier"
}

# show_conflict_ui PROJECT_DIR REL_PATH
# Returns choice: u | k | d | s
show_conflict_ui() {
    local project_dir="$1" rel="$2"
    local disk_path="$project_dir/$rel"
    local tpl_path; tpl_path="$(project_to_template_path "$rel")"
    local tier; tier="$(file_tier "$rel")"

    printf '\n%s\n' "-----------------------------------------------------"
    printf '  [conflict]  %s\n' "$rel"
    printf '  Project:    %s\n' "$project_dir"

    # Tier consequence line
    case "$tier" in
        directive)
            printf '  \033[1;33m WARNING: This is a directive file. Changes affect agent behavior. Review the diff carefully.\033[0m\n' ;;
        infrastructure)
            printf '  This is an infrastructure file. Updating is generally safe.\n' ;;
    esac

    printf '  %s\n' "---------"

    local diff_output
    if [[ "$rel" == ".claude/settings.json" ]]; then
        diff_output="$(diff -u <(generate_settings_json) "$disk_path" 2>/dev/null || true)"
    else
        diff_output="$(diff -u "$tpl_path" "$disk_path" 2>/dev/null || true)"
    fi

    local line_count; line_count="$(printf '%s\n' "$diff_output" | wc -l)"
    if (( line_count > 20 )); then
        printf '%s\n' "$diff_output" | head -20
        printf '  ... (%d more lines)\n' "$(( line_count - 20 ))"
    else
        printf '%s\n' "$diff_output"
    fi

    printf '  %s\n' "---------"
    printf '  [u] Update to new template version\n'
    printf '  [k] Keep your version unchanged\n'
    printf '  [d] Defer this decision (revisit with --pending)\n'
    printf '  [s] Stop reviewing; leave all remaining for later\n\n'

    local choice
    read_choice choice "  Choice [u/k/d/s, default=d]: " d ukdsUKDS
    printf '%s\n' "${choice,,}"
}

# _handle_update_decision PROJECT_DIR REL_PATH DECISION
# Returns: 0 (continue), 1 (stopped)
# Sets had_conflict=true when needed.
_handle_update_decision() {
    local project_dir="$1" rel="$2" decision="$3"
    local tier; tier="$(file_tier "$rel")"

    case "$decision" in
        skip_unchanged)
            [[ "$VERBOSE" == true ]] && log "  up to date: $rel" ;;

        auto_update)
            # In safe mode, only apply infrastructure tier auto-updates
            if [[ "${SAFE_MODE:-false}" == true && "$tier" != "infrastructure" ]]; then
                [[ "$VERBOSE" == true ]] && log "  skipped (safe-mode, tier=$tier): $rel"
                return 0
            fi
            log "  updating: $rel"
            apply_template_file "$project_dir" "$rel" ;;

        skip_user_edit)
            [[ "$VERBOSE" == true ]] && log "  kept (user edits): $rel" ;;

        skip_deleted_optional)
            # truly silent
            : ;;

        skip_deleted_infra)
            [[ "$QUIET" != true ]] && warn "  infrastructure file deleted: $rel  (run --restore-infra to recover)" ;;

        skip_deleted_directive)
            err "  DIRECTIVE FILE DELETED: $rel -- agent behavior may be broken. Run --report for details."
            had_conflict=true ;;

        skip_deleted)
            # Legacy path -- should not normally be reached now, treat as optional
            [[ "$QUIET" != true ]] && log "  skipped (user deleted): $rel" ;;

        new_file)
            log "  installing new file: $rel"
            apply_template_file "$project_dir" "$rel" ;;

        untracked)
            [[ "$VERBOSE" == true ]] && log "  untracked (exists, not from template): $rel" ;;

        conflict_directive)
            had_conflict=true
            if [[ "${CHECK_MODE:-false}" == true ]]; then
                err "  [ERROR] directive conflict: $rel"
                return 0
            fi
            if [[ "$YES_MODE" == true ]]; then
                # Keep existing -- never auto-overwrite directives
                log "  kept (directive conflict, --yes keeps existing): $rel"
                registry_set_file "$project_dir" "$rel" \
                    "$(current_template_hash "$rel")" \
                    "$(sha256sum "$project_dir/$rel" | cut -d' ' -f1)" "installed" "$tier"
            else
                local choice; choice="$(show_conflict_ui "$project_dir" "$rel")"
                case "$choice" in
                    u) apply_template_file "$project_dir" "$rel" ;;
                    k) registry_set_file "$project_dir" "$rel" \
                           "$(current_template_hash "$rel")" \
                           "$(sha256sum "$project_dir/$rel" | cut -d' ' -f1)" "installed" "$tier" ;;
                    d) registry_set_file "$project_dir" "$rel" \
                           "$(current_template_hash "$rel")" \
                           "$(sha256sum "$project_dir/$rel" | cut -d' ' -f1)" "deferred" "$tier" ;;
                    s) return 1 ;;
                esac
            fi ;;

        conflict)
            had_conflict=true
            if [[ "${CHECK_MODE:-false}" == true ]]; then
                warn "  [WARNING] conflict: $rel (tier=$tier)"
                return 0
            fi
            if [[ "$YES_MODE" == true ]]; then
                log "  kept (conflict, --yes): $rel"
                registry_set_file "$project_dir" "$rel" \
                    "$(current_template_hash "$rel")" \
                    "$(sha256sum "$project_dir/$rel" | cut -d' ' -f1)" "installed" "$tier"
            else
                local choice; choice="$(show_conflict_ui "$project_dir" "$rel")"
                case "$choice" in
                    u) apply_template_file "$project_dir" "$rel" ;;
                    k) registry_set_file "$project_dir" "$rel" \
                           "$(current_template_hash "$rel")" \
                           "$(sha256sum "$project_dir/$rel" | cut -d' ' -f1)" "installed" "$tier" ;;
                    d) registry_set_file "$project_dir" "$rel" \
                           "$(current_template_hash "$rel")" \
                           "$(sha256sum "$project_dir/$rel" | cut -d' ' -f1)" "deferred" "$tier" ;;
                    s) return 1 ;;
                esac
            fi ;;
    esac
    return 0
}

# update_project PROJECT_DIR
update_project() {
    local project_dir="$1"
    local had_conflict=false stopped=false

    if ! registry_exists "$project_dir"; then
        if _is_claude_project "$project_dir"; then
            log "  stamping $project_dir (no .mkproj found)"
            registry_stamp_from_disk "$project_dir"
        else
            err "$project_dir is not a mkproj project."
            return 1
        fi
    fi

    local all_template_files=()
    while IFS= read -r -d '' f; do
        local rel; rel="$(template_to_project_path "$f")"
        [[ -n "$rel" ]] || continue
        all_template_files+=("$rel")
    done < <(find "$TEMPLATES_DIR" -type f \( \
        ! -path "*/backups/*" ! -name "*.bak" \
        ! -name ".mkproj-manifest.json" \
        \) -print0)
    all_template_files+=(".claude/settings.json")

    local directive_issues=0
    for rel in "${all_template_files[@]}"; do
        [[ "$stopped" == true ]] && break
        local decision; decision="$(file_update_decision "$project_dir" "$rel")"

        _handle_update_decision "$project_dir" "$rel" "$decision" || { stopped=true; break; }

        # Count directive problems for safe-mode exit code
        case "$decision" in
            skip_deleted_directive|conflict_directive) (( directive_issues++ )) || true ;;
        esac
    done

    registry_touch_updated "$project_dir"

    # In safe mode, exit non-zero if any directive problems exist
    if [[ "${SAFE_MODE:-false}" == true && "$directive_issues" -gt 0 ]]; then
        err "  $directive_issues directive issue(s) found. Run mkproj --report $project_dir for details."
        return 1
    fi

    [[ "$had_conflict" == false && "$stopped" == false ]]
}

# check_project PROJECT_DIR
# Read-only: walk tracked files and report issues by tier.
# Exit: 0 clean, 1 warnings, 2 errors
check_project() {
    local project_dir="$1"
    local errors=0 warnings=0

    if ! registry_exists "$project_dir"; then
        err "Not a mkproj project: $project_dir"
        return 2
    fi

    local all_template_files=()
    while IFS= read -r -d '' f; do
        local rel; rel="$(template_to_project_path "$f")"
        [[ -n "$rel" ]] || continue
        all_template_files+=("$rel")
    done < <(find "$TEMPLATES_DIR" -type f \( \
        ! -path "*/backups/*" ! -name "*.bak" \
        ! -name ".mkproj-manifest.json" \
        \) -print0)
    all_template_files+=(".claude/settings.json")

    for rel in "${all_template_files[@]}"; do
        local decision; decision="$(file_update_decision "$project_dir" "$rel")"
        case "$decision" in
            skip_deleted_directive)
                err "  [ERROR]   $rel -- directive file deleted"
                (( errors++ )) || true ;;
            conflict_directive)
                err "  [ERROR]   $rel -- directive conflict requires human review"
                (( errors++ )) || true ;;
            skip_deleted_infra)
                warn "  [WARNING] $rel -- infrastructure file deleted"
                (( warnings++ )) || true ;;
            conflict)
                local tier; tier="$(file_tier "$rel")"
                if [[ "$tier" == "infrastructure" ]]; then
                    warn "  [WARNING] $rel -- infrastructure conflict"
                    (( warnings++ )) || true
                fi ;;
            skip_deleted_optional|skip_unchanged|skip_user_edit|auto_update|new_file|untracked)
                [[ "$VERBOSE" == true ]] && log "  [ok]      $rel ($decision)" ;;
        esac
    done

    if (( errors > 0 )); then return 2
    elif (( warnings > 0 )); then return 1
    else return 0
    fi
}

# _report_risk_sentence DECISION TIER
_report_risk_sentence() {
    local decision="$1" tier="$2"
    case "$decision" in
        skip_deleted_directive)
            printf 'Agent behavior is undefined without this file; hooks or permissions may malfunction.' ;;
        conflict_directive)
            printf 'Diverged directive files cause agent behavior to differ from the project standard.' ;;
        skip_deleted_infra)
            printf 'Missing infrastructure file may break hooks, git checks, or code formatting on save.' ;;
        conflict)
            printf 'Out-of-sync infrastructure file may miss bug fixes or security improvements.' ;;
        *)
            printf 'No known risk.' ;;
    esac
}

# generate_report PROJECT_DIR
# Writes mkproj-issues-YYYYMMDD-HHMMSS.md to the project directory.
generate_report() {
    local project_dir="$1"
    local timestamp; timestamp="$(date +%Y%m%d-%H%M%S)"
    local report_file="$project_dir/mkproj-issues-$timestamp.md"
    local tmp; tmp="$(mktemp "$project_dir/.mkproj-report.XXXXXXXX")"

    if ! registry_exists "$project_dir"; then
        err "Not a mkproj project: $project_dir"
        return 1
    fi

    {
        printf '# mkproj issues report\n\n'
        printf 'Project: `%s`  \n' "$project_dir"
        printf 'Generated: %s  \n\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >> "$tmp"

    local all_template_files=()
    while IFS= read -r -d '' f; do
        local rel; rel="$(template_to_project_path "$f")"
        [[ -n "$rel" ]] || continue
        all_template_files+=("$rel")
    done < <(find "$TEMPLATES_DIR" -type f \( \
        ! -path "*/backups/*" ! -name "*.bak" \
        ! -name ".mkproj-manifest.json" \
        \) -print0)
    all_template_files+=(".claude/settings.json")

    local issue_count=0
    for rel in "${all_template_files[@]}"; do
        local decision; decision="$(file_update_decision "$project_dir" "$rel")"
        local tier; tier="$(file_tier "$rel")"
        local severity="" status_label=""

        case "$decision" in
            skip_deleted_directive)   severity="ERROR";   status_label="deleted" ;;
            conflict_directive)       severity="ERROR";   status_label="conflict" ;;
            skip_deleted_infra)       severity="WARNING"; status_label="deleted" ;;
            conflict)
                [[ "$tier" == "infrastructure" ]] || continue
                severity="WARNING"; status_label="conflict" ;;
            *) continue ;;
        esac

        (( issue_count++ )) || true
        local risk; risk="$(_report_risk_sentence "$decision" "$tier")"
        local brief_desc=""
        case "$status_label" in
            deleted)  brief_desc="file was deleted from the project" ;;
            conflict) brief_desc="template and project versions have both changed" ;;
        esac

        {
            printf '## [%s] %s -- %s\n\n' "$severity" "$rel" "$brief_desc"
            printf '**Tier:** %s  \n' "$tier"
            printf '**Status:** %s  \n' "$status_label"
            printf '**Risk if left unresolved:** %s\n\n' "$risk"
            printf '**To auto-fix (overwrites your version):**\n'
            printf '```\n'
            printf 'mkproj --update %s --force-file %s\n' "$project_dir" "$rel"
            printf '```\n\n'
            printf '**To keep your version and silence this warning:**\n'
            printf '```\n'
            printf 'mkproj --accept %s --file %s\n' "$project_dir" "$rel"
            printf '```\n\n'
            case "$status_label" in
                deleted)
                    printf '**Manual steps:** Restore the file from git history (`git show HEAD:%s`) or run `mkproj --restore-infra %s` for infrastructure files.\n\n' "$rel" "$project_dir" ;;
                conflict)
                    printf '**Manual steps:** Review the diff with `diff <(mkproj --print-template %s) %s/%s`, then choose update or accept.\n\n' "$rel" "$project_dir" "$rel" ;;
            esac
        } >> "$tmp"
    done

    if (( issue_count == 0 )); then
        printf '_No issues found._\n' >> "$tmp"
    fi

    mv -T -- "$tmp" "$report_file"
    printf '%s\n' "$report_file"
}

# restore_infra PROJECT_DIR
# Restores deleted infrastructure-tier files. Always interactive; no --yes override.
restore_infra() {
    local project_dir="$1"

    if ! registry_exists "$project_dir"; then
        err "Not a mkproj project: $project_dir"
        return 1
    fi

    local all_template_files=()
    while IFS= read -r -d '' f; do
        local rel; rel="$(template_to_project_path "$f")"
        [[ -n "$rel" ]] || continue
        all_template_files+=("$rel")
    done < <(find "$TEMPLATES_DIR" -type f \( \
        ! -path "*/backups/*" ! -name "*.bak" \
        ! -name ".mkproj-manifest.json" \
        \) -print0)

    local to_restore=()
    for rel in "${all_template_files[@]}"; do
        local decision; decision="$(file_update_decision "$project_dir" "$rel")"
        [[ "$decision" == "skip_deleted_infra" ]] || continue
        to_restore+=("$rel")
    done

    if (( ${#to_restore[@]} == 0 )); then
        log "No deleted infrastructure files found in $project_dir."
        return 0
    fi

    printf '\nInfrastructure files that will be restored:\n'
    for rel in "${to_restore[@]}"; do
        printf '  %s\n' "$rel"
    done
    printf '\n'

    local confirm
    read_choice confirm "Restore these files? [y/N]: " n yYnN
    [[ "${confirm,,}" == "y" ]] || { log "Restore cancelled."; return 0; }

    for rel in "${to_restore[@]}"; do
        apply_template_file "$project_dir" "$rel"
        log "  restored: $rel"
    done
}

# list_tiers PROJECT_DIR
# Prints a table of all tracked files with tier, status, and updated_at.
list_tiers() {
    local project_dir="$1"

    if ! registry_exists "$project_dir"; then
        err "Not a mkproj project: $project_dir"
        return 1
    fi

    printf '%-50s  %-16s  %-16s  %s\n' "FILE" "TIER" "STATUS" "UPDATED"
    printf '%-50s  %-16s  %-16s  %s\n' \
        "--------------------------------------------------" \
        "----------------" "----------------" "-------------------"

    while IFS= read -r rel; do
        local tier; tier="$(registry_file_tier "$project_dir" "$rel")"
        local status; status="$(registry_file_status "$project_dir" "$rel")"
        local updated; updated="$(jq -r --arg p "$rel" \
            '.files[$p].updated_at // .updated_at // "-"' \
            "$(registry_path "$project_dir")" 2>/dev/null)"
        # Overlay live decision for more useful status
        local decision; decision="$(file_update_decision "$project_dir" "$rel")"
        local display_status="$status"
        case "$decision" in
            auto_update)              display_status="needs-update" ;;
            conflict|conflict_directive) display_status="conflict" ;;
            skip_deleted_*)           display_status="deleted" ;;
            skip_unchanged)           display_status="ok" ;;
        esac
        printf '%-50s  %-16s  %-16s  %s\n' "$rel" "$tier" "$display_status" "${updated:0:19}"
    done < <(registry_all_files "$project_dir" | sort)
}

# _is_claude_project DIR
_is_claude_project() {
    [[ -f "$1/.claude/settings.json" || -f "$1/CLAUDE.md" ]]
}

# scan_projects ROOT_DIR
# Echoes lines: "managed:PATH" or "unmanaged:PATH"
scan_projects() {
    local root="$1"
    while IFS= read -r -d '' item; do
        printf 'managed:%s\n' "$(dirname "$item")"
    done < <(find -L "$root" \
        \( -name ".git" -o -name ".venv" -o -name "node_modules" \
           -o -name "__pycache__" -o -name "backups" -o -name "responses" \) \
        -prune -o \
        -name ".mkproj" -print0 2>/dev/null)

    while IFS= read -r -d '' item; do
        local dir; dir="$(dirname "$item")"
        [[ -f "$dir/.mkproj" ]] && continue
        printf 'unmanaged:%s\n' "$dir"
    done < <(find -L "$root" \
        \( -name ".git" -o -name ".venv" -o -name "node_modules" \
           -o -name "__pycache__" -o -name "backups" -o -name "responses" \) \
        -prune -o \
        -name "CLAUDE.md" -print0 2>/dev/null)
}

# adopt_project PROJECT_DIR
adopt_project() {
    local project_dir="$1"
    registry_create "$project_dir" "$MKPROJ_VERSION" '["adopted"]'

    local gitignore="$project_dir/.gitignore"
    local guard_lines=(
        "responses/" "backups/" ".env" ".venv/" "*.pyc" "__pycache__/"
        ".mkproj"
    )
    for line in "${guard_lines[@]}"; do
        grep -qxF "$line" "$gitignore" 2>/dev/null || printf '%s\n' "$line" >> "$gitignore"
    done

    # Record whichever directive files already exist. Do NOT install new ones.
    # The old code unconditionally installed AGENTS.md from a stale v2 template
    # path ($TEMPLATES_DIR/AGENTS.md, which v3 does not have) and violated the
    # agent-choice principle by forcing Codex's directive file into every
    # project. (G-011, TODO-D)
    local tmpl_dir="$TEMPLATES_DIR/claude-code/project"
    for f in CLAUDE.md AGENTS.md; do
        if [[ -f "$project_dir/$f" && -f "$tmpl_dir/$f" ]]; then
            registry_set_file "$project_dir" "$f" \
                "$(sha256sum "$tmpl_dir/$f" | cut -d' ' -f1)" \
                "$(sha256sum "$project_dir/$f" | cut -d' ' -f1)" "installed" "directive"
        fi
    done

    log "  adopted: $project_dir"
}

# _migrate_tier REL_PATH STORED_TIER
# Returns the tier to use: stored tier if set, otherwise derives from path.
_migrate_tier() {
    local rel="$1" stored="$2"
    [[ -n "$stored" && "$stored" != "null" ]] && { printf '%s\n' "$stored"; return; }
    case "$rel" in
        CLAUDE.md|AGENTS.md)              printf 'directive\n' ;;
        .claude/hooks/*.sh|\
        .claude/rules/*.md|\
        .claude/settings.json|\
        .githooks/*)                      printf 'infrastructure\n' ;;
        *)                                printf 'optional\n' ;;
    esac
}

# migrate_project PROJECT_DIR [--apply]
# Dry-run by default. Classifies each .mkproj entry and optionally stamps
# current template hashes and tier fields. Never touches project files.
migrate_project() {
    local project_dir="$1" apply=false
    [[ "${2:-}" == "--apply" ]] && apply=true

    local registry; registry="$(registry_path "$project_dir")"
    if [[ ! -f "$registry" ]]; then
        err "No .mkproj found in $project_dir"; return 1
    fi

    local ver; ver="$(jq -r '.mkproj_version // "0"' "$registry")"
    # Version compare: if major >= 3, skip
    if [[ "${ver%%.*}" -ge 3 ]] 2>/dev/null; then
        log "  already v3 ($ver), nothing to do: $project_dir"
        return 0
    fi

    if [[ "$apply" == true ]]; then
        local backup_dir="$project_dir/backups"
        mkdir -p "$backup_dir"
        local backup="$backup_dir/mkproj-$(date -u +%Y%m%d-%H%M%S).mkproj"
        cp "$registry" "$backup"
        cmp -s "$registry" "$backup" || { err "Backup verify failed: $backup"; return 1; }
    fi

    printf '\n%-55s  %-18s  %-9s\n' "file" "classification" "tier"
    printf '%s\n' "----------------------------------------------------------------------"

    local unchanged=0 template_changed=0 user_edit=0 both_changed=0 gone=0 orphan=0
    local all_unchanged=true

    # Build new files object for --apply
    local new_files='{}'

    while IFS= read -r rel; do
        local entry
        entry="$(jq -c --arg p "$rel" '.files[$p]' "$registry")"
        local stored_th stored_ih stored_tier stored_status
        stored_th="$(jq -r '.template_hash // ""' <<< "$entry")"
        stored_ih="$(jq -r '.installed_hash // ""' <<< "$entry")"
        stored_tier="$(jq -r '.tier // ""' <<< "$entry")"
        stored_status="$(jq -r '.status // "installed"' <<< "$entry")"

        local tpl_path; tpl_path="$(project_to_template_path "$rel")"
        local disk_path="$project_dir/$rel"

        local cur_tpl_hash="" disk_hash="" classification tier
        tier="$(_migrate_tier "$rel" "$stored_tier")"

        if [[ ! -f "$tpl_path" ]]; then
            classification="orphan"
            ((orphan++)) || true
        elif [[ ! -f "$disk_path" ]]; then
            classification="gone_on_disk"
            cur_tpl_hash="$(sha256sum "$tpl_path" | cut -d' ' -f1)"
            ((gone++)) || true
        else
            cur_tpl_hash="$(sha256sum "$tpl_path" | cut -d' ' -f1)"
            disk_hash="$(sha256sum "$disk_path" | cut -d' ' -f1)"
            local tpl_same=false disk_same=false
            [[ "$cur_tpl_hash" == "$stored_th" ]] && tpl_same=true
            [[ "$disk_hash" == "$stored_ih" ]] && disk_same=true
            if $tpl_same && $disk_same; then
                classification="unchanged"
                ((unchanged++)) || true
            elif $tpl_same && ! $disk_same; then
                classification="user_edit"
                ((user_edit++)) || true
                all_unchanged=false
            elif ! $tpl_same && $disk_same; then
                classification="template_changed"
                ((template_changed++)) || true
                all_unchanged=false
            else
                classification="both_changed"
                ((both_changed++)) || true
                all_unchanged=false
            fi
        fi
        [[ "$classification" != "unchanged" ]] && all_unchanged=false

        printf '%-55s  %-18s  %s\n' "$rel" "$classification" "$tier"

        if [[ "$apply" == true ]]; then
            # For unchanged: refresh template_hash (same value, ensures accuracy).
            # For others: keep stored hashes; only update tier if missing.
            local use_th="$stored_th" use_ih="$stored_ih"
            [[ "$classification" == "unchanged" && -n "$cur_tpl_hash" ]] && use_th="$cur_tpl_hash"
            new_files="$(jq --arg p "$rel" --arg th "$use_th" --arg ih "$use_ih" \
                --arg st "$stored_status" --arg ti "$tier" \
                '.[$p] = {template_hash:$th, installed_hash:$ih, status:$st, tier:$ti}' \
                <<< "$new_files")"
        fi
    done < <(jq -r '.files | keys[]' "$registry")

    printf '\n'
    printf 'unchanged=%d  template_changed=%d  user_edit=%d  both_changed=%d  gone=%d  orphan=%d\n' \
        "$unchanged" "$template_changed" "$user_edit" "$both_changed" "$gone" "$orphan"

    if [[ "$apply" == true ]]; then
        local now; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        local tmp; tmp="$(mktemp "$(dirname "$registry")/.mkproj.XXXXXXXX")"
        jq --argjson f "$new_files" --arg v "$MKPROJ_VERSION" --arg t "$now" \
            '.files = $f | .mkproj_version = $v | .updated_at = $t' \
            "$registry" > "$tmp"
        mv -T -- "$tmp" "$registry"
        log "  applied: $project_dir  (v$ver -> v$MKPROJ_VERSION)"

        # Write per-project migration audit log so other sessions can track what changed.
        local log_dir="$BOOTSTRAP_DIR/responses/internal"
        local proj_name; proj_name="$(basename "$project_dir")"
        local log_file="$log_dir/migration-changelog-${proj_name}.txt"
        mkdir -p "$log_dir"
        printf '[%s] ACTION: MODIFIED %s/.mkproj\nREASON: mkproj migrate --apply bumped version %s -> %s, stamped tier fields\nCLASSIFICATION_SUMMARY: unchanged=%d template_changed=%d user_edit=%d both_changed=%d gone=%d orphan=%d\n\n' \
            "$now" "$project_dir" "$ver" "$MKPROJ_VERSION" \
            "$unchanged" "$template_changed" "$user_edit" "$both_changed" "$gone" "$orphan" \
            >> "$log_file"
    else
        log "  dry-run: pass --apply to write changes"
    fi

    $all_unchanged && return 0 || return 1
}
