#!/usr/bin/env bash
# registry.sh -- manage .mkproj identity files

MKPROJ_FILE=".mkproj"

# registry_path PROJECT_DIR
registry_path() { printf '%s/%s\n' "$1" "$MKPROJ_FILE"; }

# registry_exists PROJECT_DIR
registry_exists() {
    local f; f="$(registry_path "$1")"
    [[ -f "$f" ]] && jq empty "$f" 2>/dev/null
}

# registry_read PROJECT_DIR JQ_EXPR
registry_read() { jq -r "$2" "$(registry_path "$1")"; }

# registry_create PROJECT_DIR MKPROJ_VERSION COMPONENTS_JSON
registry_create() {
    local project_dir="$1" version="$2" components="$3"
    local now; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    jq -n \
        --arg v "$version" \
        --arg t "$now" \
        --argjson c "$components" \
        '{format:1, mkproj_version:$v, installed_at:$t, updated_at:$t,
          files:{}, components:$c}' \
        > "$(registry_path "$project_dir")"
}

# registry_set_file PROJECT_DIR REL_PATH TEMPLATE_HASH INSTALLED_HASH STATUS
registry_set_file() {
    local project_dir="$1" rel="$2" th="$3" ih="$4" st="$5"
    local f; f="$(registry_path "$project_dir")"
    local now; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    local tmp; tmp="$(mktemp "$(dirname "$f")/.mkproj.XXXXXXXX")"
    jq --arg p "$rel" --arg th "$th" --arg ih "$ih" --arg st "$st" --arg t "$now" \
        '.files[$p] = {template_hash:$th, installed_hash:$ih, status:$st}
         | .updated_at = $t' "$f" > "$tmp"
    mv -T -- "$tmp" "$f"
}

# registry_touch_updated PROJECT_DIR
registry_touch_updated() {
    local f; f="$(registry_path "$1")"
    local now; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    local tmp; tmp="$(mktemp "$(dirname "$f")/.mkproj.XXXXXXXX")"
    jq --arg t "$now" '.updated_at = $t' "$f" > "$tmp"
    mv -T -- "$tmp" "$f"
}

# registry_file_status PROJECT_DIR REL_PATH
registry_file_status() {
    jq -r --arg p "$2" '.files[$p].status // "unknown"' "$(registry_path "$1")"
}

# registry_file_hashes PROJECT_DIR REL_PATH
# Echoes "TEMPLATE_HASH INSTALLED_HASH" space-separated.
registry_file_hashes() {
    jq -r --arg p "$2" '
        (.files[$p].template_hash // "")
        + " " +
        (.files[$p].installed_hash // "")
    ' "$(registry_path "$1")"
}

# registry_all_files PROJECT_DIR
registry_all_files() {
    jq -r '.files | keys[]' "$(registry_path "$1")"
}

# registry_stamp_from_disk PROJECT_DIR
# Creates .mkproj by computing hashes from files currently on disk.
registry_stamp_from_disk() {
    local project_dir="$1"
    registry_create "$project_dir" "$MKPROJ_VERSION" '["adopted"]'
    local tpl_file rel tpl_hash disk_hash
    while IFS= read -r -d '' tpl_file; do
        rel="$(template_to_project_path "$tpl_file")"
        [[ -n "$rel" ]] || continue
        [[ -f "$project_dir/$rel" ]] || continue
        tpl_hash="$(sha256sum "$tpl_file" | cut -d' ' -f1)"
        disk_hash="$(sha256sum "$project_dir/$rel" | cut -d' ' -f1)"
        registry_set_file "$project_dir" "$rel" "$tpl_hash" "$disk_hash" "installed"
    done < <(find "$TEMPLATES_DIR" -type f \( \
        ! -path "*/backups/*" ! -name "*.bak" \
        \) -print0)
}

# template_to_project_path TEMPLATE_ABSOLUTE_PATH
# Maps a template file's absolute path to the project-relative install path.
template_to_project_path() {
    local abs="$1"
    local rel="${abs#"$TEMPLATES_DIR/"}"
    case "$rel" in
        hooks/*)     printf '.claude/%s\n' "$rel" ;;
        rules/*)     printf '.claude/%s\n' "$rel" ;;
        git-hooks/*) printf '.git/hooks/%s\n' "${rel#git-hooks/}" ;;
        docs/*)      printf '%s\n' "$rel" ;;
        tasks/*)     printf '%s\n' "$rel" ;;
        backups/*)   ;;
        *.bak)       ;;
        *)           printf '%s\n' "$rel" ;;
    esac
}
