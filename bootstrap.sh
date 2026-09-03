#!/usr/bin/env bash
# bootstrap.sh — project-bootstrap
# Usage: cd ~/Projects && mkproj <name>
set -euo pipefail

BOOTSTRAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$BOOTSTRAP_DIR/templates"
MARKETPLACE_HOOKS="$HOME/.claude/plugins/marketplaces/dotclaude/hooks"
MARKETPLACE_RULES="$HOME/.claude/plugins/marketplaces/dotclaude/rules"
TEST_MODE=false
SETUP_LOCAL_REPO=false
BARE_REPO=""

# ─── Colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { printf "${GREEN}[bootstrap]${NC} %s\n" "$*"; }
warn() { printf "${YELLOW}[bootstrap]${NC} %s\n" "$*"; }
err()  { printf "${RED}[bootstrap]${NC} %s\n" "$*" >&2; }

# ─── Help ─────────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" || "${1:-}" == "--usage" ]]; then
    cat <<'EOF'

project-bootstrap — scaffold a complete Claude Code Python project

USAGE
  cd ~/Projects
  mkproj <name>          create ~/Projects/<name> and bootstrap it
  mkproj                 bootstrap the current directory (uses folder name)
  mkproj --test          dry run in /tmp -- all 9 phases, validate, clean up
  mkproj --help          show this message

NAME RULES
  Allowed : a-z  0-9  _  -  (lowercase only)
  Rejected: spaces, uppercase, special characters
  Examples: mkproj my-tool   mkproj ping-watch   mkproj agent2

  If your folder already exists and has an uppercase or mixed-case name
  (e.g. ~/Projects/Ping-Watch), bypass the launcher and call bootstrap
  directly from inside the folder -- it will use the folder name as-is:

    cd ~/Projects/Ping-Watch
    bash ~/Projects/project-bootstrap/bootstrap.sh

INTERACTIVE PROMPTS
  Before the 9 phases run:
  1. Local bare repo?      -- [Y/n]; creates ~/Repositories/<name>.git; default Yes
  2. Summary + Proceed?    -- shows what will be created; [Y/n] to continue; default Yes

  After the 9 phases complete:
  3. Bypass permissions?   -- adds --dangerously-skip-permissions to claude launch; default Yes
  4. Model choice          -- numbered list (haiku → best); default 2 = sonnet
  5. Effort choice         -- numbered list (low → max); default 2 = medium

  Claude launches automatically after prompt 5.

WHAT IT DOES (9 phases)
  1. Preflight      -- safety checks; refuses live projects (>1 commit)
  2. Git            -- git init on branch main; optionally creates a local
                       bare repo in ~/Repositories/<name>.git and wires remote
  3. Python         -- creates .venv, runs pip install (stub, fast)
  4. Root files     -- copies templates: README, .gitignore, .env.example, etc.
  5. Claude config  -- .claude/settings.json, marketplace hooks, 2 custom hooks, 4 rules
  6. Structure      -- src/<name>/, tests/, docs/, tasks/, responses/
  7. Global setup   -- auto-venv cd override in ~/.bashrc (idempotent)
  8. Initial commit -- "Initial project scaffold" committed locally;
                       pushed to remote if one was configured in phase 2
  9. Verify + launch -- hooks checked; .env.example copied to .env; claude launched

RE-RUNNING
  Safe to re-run any time. Every phase checks before creating -- existing
  files, dirs, and the venv are skipped. Only missing pieces are filled in.
  Use this to recover from interrupted runs or to add the bare repo later:

    cd ~/Projects/myproject
    mkproj

--test MODE
  Runs all 9 phases against a temp directory (/tmp/mkproj-test-<PID>).
  All prompts are auto-answered. No screen session is started, so all output
  is visible directly. After phase 9, a validation pass checks every expected
  file, hook, and directory. Prints PASS or FAIL with details. Cleans up on
  exit. Intended to be run from inside Claude Code so errors are visible and
  fixable without leaving the session.

PREREQUISITES
  ~/bin/mkproj must exist (run: bash ~/Projects/project-bootstrap/install.sh)
  ~/bin must be on PATH (ahead of /usr/bin to avoid conflicts)

REMOTES (git)
  Bootstrap does not force a remote. The very first prompt asks whether to
  create a local bare repo in ~/Repositories/. You can skip it and add any
  remote later -- see docs/adding-remotes.md for step-by-step instructions
  covering local bare repos, GitHub, SourceForge, and dual-push.

EOF
    exit 0
fi

# ─── Test mode ────────────────────────────────────────────────────────────────
if [[ "${1:-}" == "--test" ]]; then
    TEST_MODE=true
    PROJECT_NAME="mkproj-test-$$"
    PROJECT_DIR="/tmp/$PROJECT_NAME"
    mkdir -p "$PROJECT_DIR"
    export STY="mkproj-test"   # suppress screen re-launch
fi

# ─── Name validation ──────────────────────────────────────────────────────────
validate_name() {
    local name="$1"
    if [[ ! "$name" =~ ^[a-z0-9_-]+$ ]]; then
        err "Invalid project name: '$name'"
        err ""
        err "Allowed characters: a-z  0-9  _  -  (lowercase only)"
        err "No spaces, uppercase letters, or special characters."
        err ""
        err "Valid examples:"
        err "  mkproj my-tool"
        err "  mkproj cambium_temp"
        err "  mkproj agent2024"
        exit 1
    fi
}

# ─── Project directory ────────────────────────────────────────────────────────
if [[ "$TEST_MODE" != "true" ]]; then
    if [[ -n "${1:-}" ]]; then
        validate_name "$1"
        PROJECT_NAME="$1"
        PROJECT_DIR="$PWD/$PROJECT_NAME"
        if [[ ! -d "$PROJECT_DIR" ]]; then
            mkdir "$PROJECT_DIR"
            log "Created $PROJECT_DIR"
        fi
    else
        PROJECT_DIR="$PWD"
        PROJECT_NAME="$(basename "$PROJECT_DIR")"
        validate_name "$PROJECT_NAME"
    fi
fi

# ─── Screen ───────────────────────────────────────────────────────────────────
if [[ -z "${STY:-}" ]]; then
    log "Starting screen session: $PROJECT_NAME"
    exec screen -S "$PROJECT_NAME" bash -c "cd '$PROJECT_DIR' && '$BOOTSTRAP_DIR/bootstrap.sh'; exec bash"
fi

# ─── Phase 1: Preflight ───────────────────────────────────────────────────────
phase1_preflight() {
    log "=== Phase 1: Preflight ==="

    # Prerequisites
    local missing=()
    if ! python3 --version 2>/dev/null | grep -qE "3\.(1[2-9]|[2-9][0-9])"; then
        missing+=("Python 3.12+")
    fi
    command -v git &>/dev/null || missing+=("git")
    command -v jq  &>/dev/null || missing+=("jq")
    if [[ ${#missing[@]} -gt 0 ]]; then
        err "Missing prerequisites: ${missing[*]}"
        exit 1
    fi

    # Detect project work already in progress — always a mistake to run bootstrap then.
    # Exception: scaffold commit + auto-commits are recoverable (bootstrap was interrupted
    # and Claude ran in the project before it was fully set up).
    if git -C "$PROJECT_DIR" rev-parse --git-dir &>/dev/null 2>&1; then
        local count
        count=$(git -C "$PROJECT_DIR" rev-list --count HEAD 2>/dev/null || echo 0)
        if [[ "$count" -gt 0 ]]; then
            # Check whether every commit is a scaffold or auto-commit message
            local non_bootstrap
            non_bootstrap=$(git -C "$PROJECT_DIR" log --format="%s" \
                | grep -cv "^Initial project scaffold$\|^auto-commit: " || true)
            if [[ "$non_bootstrap" -gt 0 ]]; then
                err "STOP: $PROJECT_NAME has real project commits — cannot re-bootstrap."
                err "Recent commits:"
                git -C "$PROJECT_DIR" log --oneline -5 >&2
                err ""
                err "bootstrap is for initial setup only. Running it now would be a mistake."
                exit 1
            fi
            warn "Found $count scaffold/auto-commit(s) — recovering from incomplete bootstrap."
            warn "Continuing idempotently."
        fi
    fi

    if [[ "$TEST_MODE" == "true" ]]; then
        SETUP_LOCAL_REPO=true
        BARE_REPO="$HOME/Repositories/$PROJECT_NAME.git"
        return
    fi

    # Ask about bare repo first, so the summary can reflect the choice
    echo ""
    read -r -p "Set up a local bare repo in ~/Repositories/$PROJECT_NAME.git? [Y/n]: " local_repo_ans
    if [[ "${local_repo_ans,,}" != "n" ]]; then
        SETUP_LOCAL_REPO=true
        BARE_REPO="$HOME/Repositories/$PROJECT_NAME.git"
    fi

    # Summary of what will be created
    echo ""
    log "What will be set up:"
    log "  Project : $PROJECT_NAME"
    log "  Dir     : $PROJECT_DIR"
    log "  Git     : branch main"
    if [[ "$SETUP_LOCAL_REPO" == "true" ]]; then
        log "  Remote  : ~/Repositories/$PROJECT_NAME.git  (bare repo)"
    else
        log "  Remote  : none  (add later — docs/adding-remotes.md)"
    fi
    log "  Python  : .venv + requirements.txt stub"
    log "  Files   : CLAUDE.md  README.md  .gitignore  .env.example  run.sh  test.sh"
    log "  Claude  : settings.json + $(ls "$MARKETPLACE_HOOKS"/*.sh 2>/dev/null | wc -l | tr -d ' ') marketplace hooks + 2 custom hooks + 4 rules"
    log "  Dirs    : src/$PROJECT_NAME/  tests/  docs/  tasks/  responses/"
    log "  Finish  : pip install  •  copy .env  •  choose model  •  launch claude"
    echo ""

    read -r -p "Proceed? [Y/n]: " confirm
    [[ "${confirm,,}" == "n" ]] && { err "Aborted."; exit 1; }
    echo ""
}

# ─── Phase 2: Git ─────────────────────────────────────────────────────────────
phase2_git() {
    log "=== Phase 2: Git ==="

    if [[ ! -d "$PROJECT_DIR/.git" ]]; then
        git -C "$PROJECT_DIR" init -q
        git -C "$PROJECT_DIR" checkout -qb main
        log "  Initialised repo on branch main"
    else
        log "  .git exists — skipping init"
    fi

    if [[ "$SETUP_LOCAL_REPO" == "true" ]]; then
        mkdir -p "$HOME/Repositories"
        if [[ ! -d "$BARE_REPO" ]]; then
            git init --bare -q "$BARE_REPO"
            log "  Created bare repo: $BARE_REPO"
        else
            log "  Bare repo exists — skipping init"
        fi
        if git -C "$PROJECT_DIR" remote get-url origin &>/dev/null 2>&1; then
            git -C "$PROJECT_DIR" remote set-url origin "$BARE_REPO"
        else
            git -C "$PROJECT_DIR" remote add origin "$BARE_REPO"
        fi
        log "  Remote origin → $BARE_REPO"
    else
        log "  No remote configured — add one later (see docs/adding-remotes.md)"
    fi
}

# ─── Phase 3: Python ──────────────────────────────────────────────────────────
phase3_python() {
    log "=== Phase 3: Python ==="

    if [[ ! -d "$PROJECT_DIR/.venv" ]]; then
        python3 -m venv "$PROJECT_DIR/.venv"
        log "  Created .venv"
    else
        log "  .venv exists — skipping"
    fi

    if [[ ! -f "$PROJECT_DIR/requirements.txt" ]]; then
        cp "$TEMPLATES_DIR/requirements.txt" "$PROJECT_DIR/requirements.txt"
        log "  Created requirements.txt"
    else
        log "  requirements.txt exists — skipping"
    fi
}

# ─── Phase 4: Root files ──────────────────────────────────────────────────────
copy_template() {
    local src="$TEMPLATES_DIR/$1" dst="$PROJECT_DIR/$2"
    if [[ -f "$dst" ]]; then
        log "  exists — $2"
        return
    fi
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    log "  created — $2"
}

phase4_root_files() {
    log "=== Phase 4: Root files ==="

    copy_template ".gitignore"     ".gitignore"
    copy_template ".gitattributes" ".gitattributes"
    copy_template ".env.example"   ".env.example"

    for f in CLAUDE.md README.md; do
        local dst="$PROJECT_DIR/$f"
        if [[ ! -f "$dst" ]]; then
            sed "s/{{PROJECT_NAME}}/$PROJECT_NAME/g" "$TEMPLATES_DIR/$f" > "$dst"
            log "  created — $f"
        else
            log "  exists — $f"
        fi
    done
}

# ─── Phase 5: Claude Code config ──────────────────────────────────────────────
phase5_claude_config() {
    log "=== Phase 5: Claude Code config ==="

    mkdir -p "$PROJECT_DIR/.claude/hooks"
    mkdir -p "$PROJECT_DIR/.claude/rules"
    mkdir -p "$PROJECT_DIR/.claude/skills"

    # Disable branch protection by default (single-developer workflow)
    if [[ ! -f "$PROJECT_DIR/.claude/protected-branches" ]]; then
        touch "$PROJECT_DIR/.claude/protected-branches"
        log "  created .claude/protected-branches (branch protection disabled)"
    fi

    # 8 dotclaude marketplace hooks
    local hook_count=0
    if [[ -d "$MARKETPLACE_HOOKS" ]]; then
        while IFS= read -r -d '' hook; do
            local name; name="$(basename "$hook")"
            local dst="$PROJECT_DIR/.claude/hooks/$name"
            if [[ ! -f "$dst" ]]; then
                cp "$hook" "$dst"
                chmod +x "$dst"
                log "  hook (marketplace): $name"
                ((hook_count++)) || true
            fi
        done < <(find "$MARKETPLACE_HOOKS" -maxdepth 1 -name "*.sh" -print0 2>/dev/null)
    else
        warn "  Marketplace hooks not found: $MARKETPLACE_HOOKS"
    fi

    # 2 custom hooks bundled with project-bootstrap
    for hook in save-response.sh auto-commit.sh; do
        local dst="$PROJECT_DIR/.claude/hooks/$hook"
        if [[ ! -f "$dst" ]]; then
            cp "$TEMPLATES_DIR/hooks/$hook" "$dst"
            chmod +x "$dst"
            log "  hook (custom): $hook"
            ((hook_count++)) || true
        fi
    done

    [[ $hook_count -eq 0 ]] && log "  all hooks already present — skipping"

    # 4 rules from marketplace
    local rule_count=0
    for rule in code-quality.md database.md error-handling.md security.md; do
        local src="$MARKETPLACE_RULES/$rule"
        local dst="$PROJECT_DIR/.claude/rules/$rule"
        if [[ -f "$src" && ! -f "$dst" ]]; then
            cp "$src" "$dst"
            log "  rule: $rule"
            ((rule_count++)) || true
        elif [[ ! -f "$src" ]]; then
            warn "  rule not found in marketplace: $rule"
        fi
    done
    [[ $rule_count -eq 0 ]] && log "  all rules already present — skipping"

    # settings.json
    if [[ ! -f "$PROJECT_DIR/.claude/settings.json" ]]; then
        generate_settings_json > "$PROJECT_DIR/.claude/settings.json"
        log "  generated settings.json"
    else
        log "  settings.json exists — skipping"
    fi
}

generate_settings_json() {
    cat <<'EOF'
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "allow": [
      "Bash(git add *)",
      "Bash(git commit *)",
      "Bash(git push *)",
      "Bash(git push)",
      "Bash(git status)",
      "Bash(git diff *)",
      "Bash(git log *)",
      "Bash(git branch *)",
      "Bash(git stash *)",
      "Bash(git fetch *)",
      "Bash(git checkout *)",
      "Bash(git switch *)",
      "Bash(git remote *)",
      "Bash(git init *)",
      "Bash(git mv *)",
      "Bash(chmod +x *)",
      "Bash(python3 *)",
      "Bash(python *)",
      "Bash(find *)",
      "Bash(grep *)",
      "Bash(ls *)",
      "Bash(mkdir *)",
      "Bash(touch *)",
      "Bash(.claude/hooks/*.sh)"
    ],
    "deny": [
      "Read(**/.env)",
      "Read(**/.env.*)",
      "Read(**/secrets/**)",
      "Read(**/*.pem)",
      "Read(**/*.key)",
      "Write(**/.env)",
      "Write(**/.env.*)",
      "Write(**/secrets/**)",
      "Write(**/*.pem)",
      "Write(**/*.key)",
      "Edit(**/.env)",
      "Edit(**/.env.*)",
      "Edit(**/secrets/**)",
      "Edit(**/*.pem)",
      "Edit(**/*.key)"
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/protect-files.sh",        "timeout": 10, "statusMessage": "Checking file protections..."},
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/warn-large-files.sh",     "timeout": 10, "statusMessage": "Checking for build artifacts..."},
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/scan-secrets.sh",         "timeout": 10, "statusMessage": "Scanning for secrets..."}
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/block-dangerous-commands.sh", "timeout": 10, "statusMessage": "Checking command safety..."}
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/auto-test.sh",            "timeout": 30, "statusMessage": "Running tests..."},
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/format-on-save.sh",       "timeout": 10, "statusMessage": "Formatting..."}
        ]
      }
    ],
    "SessionStart": [
      {
        "matcher": "",
        "hooks": [
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/session-start.sh",        "timeout": 10, "statusMessage": "Loading project context..."}
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/notify.sh",               "timeout": 10}
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/save-response.sh",        "timeout": 15, "statusMessage": "Saving response..."},
          {"type": "command", "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/auto-commit.sh",          "timeout": 30, "statusMessage": "Auto-committing changes..."}
        ]
      }
    ]
  }
}
EOF
}

# ─── Phase 6: Project structure ───────────────────────────────────────────────
phase6_structure() {
    log "=== Phase 6: Project structure ==="

    # src/<name>/ and tests/
    if [[ ! -d "$PROJECT_DIR/src/$PROJECT_NAME" ]]; then
        mkdir -p "$PROJECT_DIR/src/$PROJECT_NAME"
        touch "$PROJECT_DIR/src/$PROJECT_NAME/__init__.py"
        log "  created src/$PROJECT_NAME/"
    else
        log "  src/$PROJECT_NAME/ exists — skipping"
    fi
    if [[ ! -d "$PROJECT_DIR/tests" ]]; then
        mkdir -p "$PROJECT_DIR/tests"
        touch "$PROJECT_DIR/tests/.gitkeep"
        log "  created tests/"
    else
        log "  tests/ exists — skipping"
    fi

    # responses/ — git tracks the dir but never the content
    mkdir -p "$PROJECT_DIR/responses"
    if [[ ! -f "$PROJECT_DIR/responses/.gitkeep" ]]; then
        touch "$PROJECT_DIR/responses/.gitkeep"
        log "  created responses/"
    else
        log "  responses/ exists — skipping"
    fi

    copy_template "tasks/todo.md"            "tasks/todo.md"
    copy_template "tasks/skills-manifest.md" "tasks/skills-manifest.md"

    for doc in install running api-keys architecture customizing adding-agents privacy-and-security troubleshooting doc-index; do
        copy_template "docs/$doc.md" "docs/$doc.md"
    done

    for script in run.sh test.sh; do
        local dst="$PROJECT_DIR/$script"
        if [[ ! -f "$dst" ]]; then
            cp "$TEMPLATES_DIR/$script" "$dst"
            chmod +x "$dst"
            log "  created $script (executable)"
        else
            log "  exists — $script"
        fi
    done
}

# ─── Phase 7: Global setup (idempotent) ───────────────────────────────────────
phase7_global() {
    log "=== Phase 7: Global setup ==="

    # auto-import-skill.sh global hook
    local global_hook="$HOME/.claude/hooks/auto-import-skill.sh"
    if [[ ! -f "$global_hook" ]]; then
        mkdir -p "$(dirname "$global_hook")"
        cp "$TEMPLATES_DIR/hooks/auto-import-skill.sh" "$global_hook"
        chmod +x "$global_hook"
        log "  installed ~/.claude/hooks/auto-import-skill.sh"
    else
        log "  auto-import-skill.sh already installed"
    fi

    # Global settings.json — wire PostToolUse/Skill if missing
    local global_settings="$HOME/.claude/settings.json"
    if [[ -f "$global_settings" ]]; then
        if ! jq -e '.hooks.PostToolUse[]? | select(.matcher == "Skill") | .hooks[]? | select(.command | contains("auto-import-skill"))' \
                "$global_settings" &>/dev/null 2>&1; then
            local tmp; tmp="$(mktemp)"
            jq '.hooks.PostToolUse += [{"matcher":"Skill","hooks":[{"type":"command","command":"~/.claude/hooks/auto-import-skill.sh","timeout":15,"statusMessage":"Checking skill locality..."}]}]' \
                "$global_settings" > "$tmp" && mv "$tmp" "$global_settings"
            log "  wired auto-import-skill in global settings.json"
        else
            log "  global auto-import-skill already wired"
        fi
    else
        warn "  ~/.claude/settings.json not found — skipping global hook wiring"
    fi

    # ~/.bashrc: CLAUDE_PROTECTED_BRANCHES
    local bashrc="$HOME/.bashrc"
    if ! grep -q "CLAUDE_PROTECTED_BRANCHES" "$bashrc" 2>/dev/null; then
        printf '\nexport CLAUDE_PROTECTED_BRANCHES=""\n' >> "$bashrc"
        log "  added CLAUDE_PROTECTED_BRANCHES to ~/.bashrc"
    else
        log "  CLAUDE_PROTECTED_BRANCHES already in ~/.bashrc"
    fi

    # ~/.bashrc: auto-venv cd override
    if ! grep -q "auto-venv cd override" "$bashrc" 2>/dev/null; then
        cat >> "$bashrc" <<'BASHRC'

# auto-venv cd override
cd() {
    builtin cd "$@"
    if [[ -f ".venv/bin/activate" && -z "${VIRTUAL_ENV:-}" ]]; then
        source .venv/bin/activate
    fi
}
BASHRC
        log "  added auto-venv cd override to ~/.bashrc"
    else
        log "  auto-venv cd override already in ~/.bashrc"
    fi
}

# ─── Phase 8: Initial commit ──────────────────────────────────────────────────
phase8_commit() {
    log "=== Phase 8: Initial commit ==="

    if git -C "$PROJECT_DIR" rev-parse HEAD &>/dev/null 2>&1; then
        log "  already committed — skipping"
        return
    fi

    git -C "$PROJECT_DIR" add -A
    git -C "$PROJECT_DIR" commit -q -m "Initial project scaffold"
    log "  committed locally"
    if git -C "$PROJECT_DIR" remote get-url origin &>/dev/null 2>&1; then
        git -C "$PROJECT_DIR" push -u origin main -q
        log "  pushed to $(git -C "$PROJECT_DIR" remote get-url origin)"
    else
        log "  no remote configured — skipping push (see docs/adding-remotes.md)"
    fi
}

# ─── Phase 9: Verify ──────────────────────────────────────────────────────────
phase9_verify() {
    log "=== Phase 9: Verify ==="

    local ok=true

    # All hooks must be executable — fix silently if not
    while IFS= read -r -d '' hook; do
        if [[ ! -x "$hook" ]]; then
            chmod +x "$hook"
            warn "  Fixed missing +x: $(basename "$hook")"
        fi
    done < <(find "$PROJECT_DIR/.claude/hooks" -type f -name "*.sh" -print0 2>/dev/null)
    log "  All hooks executable"

    echo ""
    log "Bootstrap complete. $PROJECT_NAME is ready."

    # Install dependencies (empty stub — runs fast; venv already created in phase 3)
    echo ""
    log "Installing dependencies..."
    "$PROJECT_DIR/.venv/bin/pip" install -r "$PROJECT_DIR/requirements.txt" -q
    log "  Done"

    # Copy .env.example → .env so the project is ready for API keys
    if [[ ! -f "$PROJECT_DIR/.env" ]]; then
        cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env"
        log "  Copied .env.example → .env  (fill in any API keys before starting)"
    else
        log "  .env already exists — skipping copy"
    fi

    # ── Claude Code launch options ────────────────────────────────────────────
    echo ""
    log "Configure Claude Code launch:"
    echo ""

    # Bypass permission prompts?
    read -r -p "  Bypass permission prompts? [Y/n]: " bypass_ans
    local bypass=false
    [[ "${bypass_ans,,}" != "n" ]] && bypass=true

    # Model selection
    echo ""
    log "  Model:"
    log "    1) haiku        — fast, lightweight tasks"
    log "    2) sonnet       — standard daily coding  [default]"
    log "    3) sonnet[1m]   — sonnet with 1M context window"
    log "    4) opus         — complex architectural tasks"
    log "    5) opusplan     — opus for planning, sonnet for execution"
    log "    6) fable        — deep reasoning, long autonomous sessions"
    log "    7) fable[1m]    — fable with 1M context window"
    log "    8) best         — latest fable or opus (plan-dependent)"
    echo ""
    read -r -p "  Choose model [1-8, default 2]: " model_choice
    local model_val
    case "${model_choice:-2}" in
        1) model_val="haiku" ;;
        2) model_val="sonnet" ;;
        3) model_val="sonnet[1m]" ;;
        4) model_val="opus" ;;
        5) model_val="opusplan" ;;
        6) model_val="fable" ;;
        7) model_val="fable[1m]" ;;
        8) model_val="best" ;;
        *) model_val="sonnet" ;;
    esac

    # Effort selection
    echo ""
    log "  Effort:"
    log "    1) low"
    log "    2) medium   [default]"
    log "    3) high"
    log "    4) max"
    echo ""
    read -r -p "  Choose effort [1-4, default 2]: " effort_choice
    local effort_val
    case "${effort_choice:-2}" in
        1) effort_val="low" ;;
        2) effort_val="medium" ;;
        3) effort_val="high" ;;
        4) effort_val="max" ;;
        *) effort_val="medium" ;;
    esac

    # Build command array (array avoids glob expansion on brackets in model names)
    local cmd_args=("claude")
    [[ "$bypass" == "true" ]] && cmd_args+=("--dangerously-skip-permissions")
    cmd_args+=("--model" "$model_val")
    cmd_args+=("--effort" "$effort_val")

    echo ""
    log "Launching: ${cmd_args[*]}"
    echo ""

    cd "$PROJECT_DIR"
    exec "${cmd_args[@]}"
}

# ─── Test validation ──────────────────────────────────────────────────────────
phase9_test_validate() {
    echo ""
    log "=== Test validation ==="
    local pass=true

    check() {
        local label="$1" path="$2" kind="${3:-f}"
        if [[ "$kind" == "f" && -f "$path" ]]; then
            log "  PASS  $label"
        elif [[ "$kind" == "d" && -d "$path" ]]; then
            log "  PASS  $label"
        elif [[ "$kind" == "x" && -x "$path" ]]; then
            log "  PASS  $label"
        else
            err "  FAIL  $label  ($path)"
            pass=false
        fi
    }

    # Root files
    check ".gitignore"          "$PROJECT_DIR/.gitignore"
    check ".gitattributes"      "$PROJECT_DIR/.gitattributes"
    check "CLAUDE.md"           "$PROJECT_DIR/CLAUDE.md"
    check "README.md"           "$PROJECT_DIR/README.md"
    check "requirements.txt"    "$PROJECT_DIR/requirements.txt"
    check "run.sh"              "$PROJECT_DIR/run.sh"
    check "test.sh"             "$PROJECT_DIR/test.sh"
    check ".env.example"        "$PROJECT_DIR/.env.example"

    # Directories
    check "src/$PROJECT_NAME/"  "$PROJECT_DIR/src/$PROJECT_NAME" d
    check "tests/"              "$PROJECT_DIR/tests"             d
    check "docs/"               "$PROJECT_DIR/docs"              d
    check "tasks/"              "$PROJECT_DIR/tasks"             d
    check "responses/"          "$PROJECT_DIR/responses"         d
    check ".venv/"              "$PROJECT_DIR/.venv"             d

    # Claude config
    check "settings.json"       "$PROJECT_DIR/.claude/settings.json"
    check "hooks/ dir"          "$PROJECT_DIR/.claude/hooks"         d
    check "rules/ dir"          "$PROJECT_DIR/.claude/rules"         d

    # Hooks executable
    for hook in "$PROJECT_DIR/.claude/hooks/"*.sh; do
        [[ -e "$hook" ]] || continue
        check "hook +x $(basename "$hook")" "$hook" x
    done

    # settings.json valid JSON
    if jq empty "$PROJECT_DIR/.claude/settings.json" 2>/dev/null; then
        log "  PASS  settings.json valid JSON"
    else
        err "  FAIL  settings.json invalid JSON"
        pass=false
    fi

    # tasks stubs
    check "tasks/todo.md"           "$PROJECT_DIR/tasks/todo.md"
    check "tasks/skills-manifest.md" "$PROJECT_DIR/tasks/skills-manifest.md"

    # Local repo has scaffold commit
    if git -C "$PROJECT_DIR" log --oneline 2>/dev/null | grep -q "Initial project scaffold"; then
        log "  PASS  local repo scaffold commit"
    else
        err "  FAIL  local repo missing scaffold commit"
        pass=false
    fi

    echo ""
    if [[ "$pass" == "true" ]]; then
        log "All checks passed. Bootstrap is working correctly."
    else
        err "One or more checks failed — see above."
    fi

    echo ""
    log "Cleaning up test artifacts..."
    rm -rf "$PROJECT_DIR"
    log "  Removed $PROJECT_DIR"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
main() {
    echo ""
    log "project-bootstrap — setting up '$PROJECT_NAME'"
    log "Scaffolds a complete Claude Code Python project from scratch."
    echo ""

    phase1_preflight
    phase2_git
    phase3_python
    phase4_root_files
    phase5_claude_config
    phase6_structure
    phase7_global
    phase8_commit
    if [[ "$TEST_MODE" == "true" ]]; then
        phase9_test_validate
    else
        phase9_verify
    fi
}

main "$@"
