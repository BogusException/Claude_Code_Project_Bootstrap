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

# registry_set_file PROJECT_DIR REL_PATH TEMPLATE_HASH INSTALLED_HASH STATUS [TIER]
registry_set_file() {
    local project_dir="$1" rel="$2" th="$3" ih="$4" st="$5" tier="${6:-}"
    local f; f="$(registry_path "$project_dir")"
    local now; now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    local tmp; tmp="$(mktemp "$(dirname "$f")/.mkproj.XXXXXXXX")"
    # Resolve tier from manifest if not supplied
    if [[ -z "$tier" && -n "${MANIFEST_FILE:-}" && -f "$MANIFEST_FILE" ]]; then
        tier="$(jq -r --arg p "$rel" \
            '.files[$p].tier // .default_tier // "optional"' "$MANIFEST_FILE")"
    fi
    [[ -z "$tier" ]] && tier="optional"
    jq --arg p "$rel" --arg th "$th" --arg ih "$ih" --arg st "$st" \
       --arg ti "$tier" --arg t "$now" \
        '.files[$p] = {template_hash:$th, installed_hash:$ih, status:$st, tier:$ti}
         | .updated_at = $t' "$f" > "$tmp"
    mv -T -- "$tmp" "$f"
}

# registry_file_tier PROJECT_DIR REL_PATH
# Reads tier from .mkproj; falls back to manifest; falls back to "optional".
registry_file_tier() {
    local project_dir="$1" rel="$2"
    local stored
    stored="$(jq -r --arg p "$2" '.files[$p].tier // empty' "$(registry_path "$1")" 2>/dev/null)"
    if [[ -n "$stored" ]]; then
        printf '%s\n' "$stored"
        return
    fi
    # Fall back to manifest
    if [[ -n "${MANIFEST_FILE:-}" && -f "$MANIFEST_FILE" ]]; then
        jq -r --arg p "$rel" '.files[$p].tier // .default_tier // "optional"' "$MANIFEST_FILE"
    else
        printf 'optional\n'
    fi
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
    local tpl_file rel tpl_hash disk_hash tier
    while IFS= read -r -d '' tpl_file; do
        rel="$(template_to_project_path "$tpl_file")"
        [[ -n "$rel" ]] || continue
        [[ -f "$project_dir/$rel" ]] || continue
        tpl_hash="$(sha256sum "$tpl_file" | cut -d' ' -f1)"
        disk_hash="$(sha256sum "$project_dir/$rel" | cut -d' ' -f1)"
        tier=""
        if [[ -n "${MANIFEST_FILE:-}" && -f "$MANIFEST_FILE" ]]; then
            tier="$(jq -r --arg p "$rel" \
                '.files[$p].tier // .default_tier // "optional"' "$MANIFEST_FILE")"
        fi
        registry_set_file "$project_dir" "$rel" "$tpl_hash" "$disk_hash" "installed" "$tier"
    done < <(find "$TEMPLATES_DIR" -type f \( \
        ! -path "*/backups/*" ! -name "*.bak" \
        ! -name ".mkproj-manifest.json" \
        \) -print0)
}

# template_to_project_path TEMPLATE_ABSOLUTE_PATH
# Maps a template file's absolute path to the project-relative install path.
# Understands the multi-template tree: <template>/project/, <template>/claude/, <template>/git-hooks/
template_to_project_path() {
    local abs="$1"
    [[ "$(basename "$abs")" != ".gitkeep" ]] || return 0
    local rel="${abs#"$TEMPLATE_DIR/"}"
    case "$rel" in
        project/*)        printf '%s\n' "${rel#project/}" ;;
        claude/hooks/*)   printf '.claude/hooks/%s\n' "$(basename "$abs")" ;;
        claude/rules/*)   printf '.claude/rules/%s\n' "$(basename "$abs")" ;;
        claude/skills/*)  printf '.claude/skills/%s\n' "$(basename "$abs")" ;;
        git-hooks/*)      printf '.githooks/%s\n' "$(basename "$abs")" ;;
    esac
}
