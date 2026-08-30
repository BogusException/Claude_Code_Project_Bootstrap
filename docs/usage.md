# Usage

## 1. Starting a new project

```bash
cd ~/Projects
mkproj myproject
```

`mkproj` accepts the project name as an argument and creates the directory if it does not exist. Name rules: lowercase letters, digits, hyphens, underscores only (`my-tool`, `agent2`, `cambium_temp`).

What happens next:
1. A `screen` session named `myproject` is created
2. All 9 bootstrap phases run inside it
3. You land in a live bash shell in that screen session, ready to work

## 2. Bootstrapping an existing or mixed-case directory

`mkproj <name>` enforces lowercase names. If your folder already exists and has uppercase or mixed-case characters (e.g. `Ping-Watch`), run bootstrap directly from inside it -- the launcher is bypassed and the folder name is used as-is:

```bash
cd ~/Projects/Ping-Watch
bash ~/Projects/project-bootstrap/bootstrap.sh
```

This works for any folder that has zero or one git commits. Bootstrap fills in everything that is missing and skips what already exists.

## 3. Re-running to fill gaps

Bootstrap is fully idempotent -- every phase checks before creating. You can re-run it any time to:

- Recover from an interrupted run
- Add the local bare repo if you skipped it the first time
- Pick up new hooks or template changes after updating project-bootstrap

```bash
cd ~/Projects/myproject
mkproj
```

Only missing pieces are created. Existing files, the venv, and the git repo are left untouched.

The one hard stop: if the project already has more than one git commit, bootstrap refuses. That means real project work is present -- running bootstrap on a live project is always a mistake.

## 4. After bootstrap completes

```bash
# Activate venv (auto-activated on cd if ~/.bashrc override is in place)
source .venv/bin/activate

# Add dependencies to requirements.txt, then install
pip install -r requirements.txt

# Copy and fill in API keys
cp .env.example .env

# Start Claude Code
claude
```

## 5. Adding git remotes

Bootstrap creates a local git repo only. To push to GitHub, a local bare repo, or another host, see [adding-remotes.md](adding-remotes.md). Remotes are optional and can be added any time after bootstrap.

## 6. What every new project receives

```
myproject/
├── .claude/
│   ├── hooks/          ← 11 hooks: safety guards, save-response, auto-commit, auto-import-skill
│   ├── rules/          ← 4 dotclaude code-quality rules
│   ├── skills/         ← auto-populated by auto-import-skill hook as skills are used
│   └── settings.json   ← permissions + full hook wiring
├── .venv/              ← Python virtual environment
├── docs/               ← 8 stub docs (fill in as the project evolves)
├── responses/          ← one .txt file per Claude exchange (gitignored content)
│   └── .gitkeep
├── tasks/
│   ├── todo.md         ← project task list
│   └── skills-manifest.md ← auto-updated by auto-import-skill
├── .env.example        ← template for API keys (copy to .env, never commit .env)
├── .gitattributes      ← LF line ending normalisation
├── .gitignore          ← covers Python, secrets, Claude responses, editor files
├── CLAUDE.md           ← standing instructions Claude reads every session
├── README.md           ← project overview stub
├── requirements.txt    ← Python dependency stub
├── run.sh              ← activates venv and runs main.py
└── test.sh             ← activates venv and runs tools/startup_tests.py
```

## 7. Testing the bootstrap itself

`mkproj --test` runs all 9 phases against a throw-away directory in `/tmp`, then validates the result and cleans up. No screen session is started, so all output appears directly in the terminal (or in Claude Code's Bash tool output).

```bash
mkproj --test
```

This is designed to be run **from inside a Claude Code session**. Claude sees every line of output in real time and can spot and fix failures without you leaving the session.

What it checks after the phases complete:

- Every expected file and directory exists (CLAUDE.md, .gitignore, .venv, hooks, rules, docs, tasks, responses, src/)
- Every hook script is executable
- `settings.json` is valid JSON

Prints `PASS` or `FAIL` per check, then removes the temp project.

Use this any time you edit `bootstrap.sh` or `templates/` to confirm nothing is broken before the next real `mkproj` run.
