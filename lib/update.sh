#!/usr/bin/env bash
# update.sh -- mkproj update and scan logic

# file_update_decision PROJECT_DIR REL_PATH
# Echoes one of: skip_unchanged | auto_update | skip_user_edit |
#                conflict | skip_deleted | new_file | untracked
file_update_decision() {
    local project_dir="$1" rel="$2"
    local disk_path="$project_dir/$rel"
    local status; status="$(registry_file_status "$project_dir" "$rel")"

    if [[ "$status" == "installed" && ! -f "$disk_path" ]]; then
        printf 'skip_deleted\n'; return
    fi
    if [[ "$status" == "deferred" ]]; then
        printf 'conflict\n'; return
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
        printf 'auto_update\n'
    elif [[ "$tpl_changed" == false && "$disk_changed" == true ]]; then
        printf 'skip_user_edit\n'
    else
        printf 'conflict\n'
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
project_to_template_path() {
    local rel="$1"
    case "$rel" in
        .claude/hooks/*) printf '%s/hooks/%s\n' "$TEMPLATES_DIR" "${rel#.claude/hooks/}" ;;
        .claude/rules/*) printf '%s/rules/%s\n' "$TEMPLATES_DIR" "${rel#.claude/rules/}" ;;
        .git/hooks/*)    printf '%s/git-hooks/%s\n' "$TEMPLATES_DIR" "${rel#.git/hooks/}" ;;
        docs/*)          printf '%s/%s\n' "$TEMPLATES_DIR" "$rel" ;;
        tasks/*)         printf '%s/%s\n' "$TEMPLATES_DIR" "$rel" ;;
        *)               printf '%s/%s\n' "$TEMPLATES_DIR" "$rel" ;;
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

    local tpl_hash disk_hash
    tpl_hash="$(current_template_hash "$rel")"
    disk_hash="$(sha256sum "$disk_path" | cut -d' ' -f1)"
    registry_set_file "$project_dir" "$rel" "$tpl_hash" "$disk_hash" "installed"
}

# show_conflict_ui PROJECT_DIR REL_PATH
# Returns choice: u | k | d | s
show_conflict_ui() {
    local project_dir="$1" rel="$2"
    local disk_path="$project_dir/$rel"
    local tpl_path; tpl_path="$(project_to_template_path "$rel")"

    printf '\n%s\n' "-----------------------------------------------------"
    printf '  [conflict]  %s\n' "$rel"
    printf '  Project:    %s\n' "$project_dir"
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
    done < <(find "$TEMPLATES_DIR" -type f \( ! -path "*/backups/*" ! -name "*.bak" \) -print0)
    all_template_files+=(".claude/settings.json")

    for rel in "${all_template_files[@]}"; do
        [[ "$stopped" == true ]] && break
        local decision; decision="$(file_update_decision "$project_dir" "$rel")"

        case "$decision" in
            skip_unchanged)
                [[ "$VERBOSE" == true ]] && log "  up to date: $rel" ;;
            auto_update)
                log "  updating: $rel"
                apply_template_file "$project_dir" "$rel" ;;
            skip_user_edit)
                [[ "$VERBOSE" == true ]] && log "  kept (user edits): $rel" ;;
            skip_deleted)
                [[ "$QUIET" != true ]] && log "  skipped (user deleted): $rel" ;;
            new_file)
                log "  installing new file: $rel"
                apply_template_file "$project_dir" "$rel" ;;
            untracked)
                [[ "$VERBOSE" == true ]] && log "  untracked (exists, not from template): $rel" ;;
            conflict)
                had_conflict=true
                if [[ "$YES_MODE" == true ]]; then
                    log "  kept (conflict, --yes): $rel"
                    registry_set_file "$project_dir" "$rel" \
                        "$(current_template_hash "$rel")" \
                        "$(sha256sum "$project_dir/$rel" | cut -d' ' -f1)" "installed"
                else
                    local choice; choice="$(show_conflict_ui "$project_dir" "$rel")"
                    case "$choice" in
                        u) apply_template_file "$project_dir" "$rel" ;;
                        k) registry_set_file "$project_dir" "$rel" \
                               "$(current_template_hash "$rel")" \
                               "$(sha256sum "$project_dir/$rel" | cut -d' ' -f1)" "installed" ;;
                        d) registry_set_file "$project_dir" "$rel" \
                               "$(current_template_hash "$rel")" \
                               "$(sha256sum "$project_dir/$rel" | cut -d' ' -f1)" "deferred" ;;
                        s) stopped=true ;;
                    esac
                fi ;;
        esac
    done

    registry_touch_updated "$project_dir"
    [[ "$had_conflict" == false && "$stopped" == false ]]
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
    done < <(find "$root" \
        \( -name ".git" -o -name ".venv" -o -name "node_modules" \
           -o -name "__pycache__" -o -name "backups" -o -name "responses" \) \
        -prune -o \
        -name ".mkproj" -print0 2>/dev/null)

    while IFS= read -r -d '' item; do
        local dir; dir="$(dirname "$item")"
        [[ -f "$dir/.mkproj" ]] && continue
        printf 'unmanaged:%s\n' "$dir"
    done < <(find "$root" \
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

    if [[ ! -f "$project_dir/AGENTS.md" ]]; then
        cp "$TEMPLATES_DIR/AGENTS.md" "$project_dir/AGENTS.md"
        registry_set_file "$project_dir" "AGENTS.md" \
            "$(sha256sum "$TEMPLATES_DIR/AGENTS.md" | cut -d' ' -f1)" \
            "$(sha256sum "$project_dir/AGENTS.md" | cut -d' ' -f1)" "installed"
    fi

    log "  adopted: $project_dir"
}
