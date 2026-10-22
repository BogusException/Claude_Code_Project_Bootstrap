# Usage

## 1. Starting a new project

```bash
cd ~/Projects
mkproj myproject
```

`mkproj` accepts the project name as an argument and creates the directory if it does not exist.

### Name rules

Applies to the project directory name only. Parent directories in the path are not checked -- `/home/pat/my-projects/my_tool` is fine; only `my_tool` is validated.

- Allowed characters: `a-z`, `0-9`, `_`
- Must start with a lowercase letter
- Rejected: hyphens, uppercase letters, spaces, any other character

Hyphens are rejected specifically because the project name becomes the Python package directory (`src/<name>/__init__.py`), and hyphens are not valid Python identifiers. Use an underscore instead: `my_tool` not `my-tool`.

These rules apply uniformly regardless of how you invoke bootstrap: `mkproj blah_foo` (name as argument) and `cd blah_foo && mkproj` (name derived from current directory) both run the same check.

Valid: `my_tool`, `agent2024`, `cambium_temp`
Invalid: `my-tool` (hyphen), `MyTool` (uppercase), `2bad` (starts with digit), `my tool` (space)

What happens next:
1. A `screen` session named `myproject` is created
2. **First prompt:** confirm project name and full path -- bail out here if you ran it in the wrong place
3. Two more prompts before phases begin: bare repo? then a full summary + Proceed? (all default Yes)
4. All 9 bootstrap phases run inside the screen session
5. Three prompts after phases complete: bypass permissions? model? effort?
6. Claude Code launches automatically in the new project directory

## 2. Bootstrapping an existing empty directory

If the directory already exists (e.g. you created it manually), `cd` into it and run `mkproj` with no arguments. Bootstrap derives the project name from the current directory name and applies the same validation:

```bash
cd ~/Projects/my_tool
mkproj
```

This works for any folder with zero or one git commits. Bootstrap fills in everything that is missing and skips what already exists.

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

Bootstrap handles the setup steps automatically before launching Claude Code:

- **pip install** — runs against the empty requirements.txt stub (fast; adds your deps later)
- **.env created** — `.env.example` is copied to `.env`; fill in any API keys you need
- **Bypass permissions?** — `[Y/n]` adds `--dangerously-skip-permissions`; default Yes (permissions pre-wired in `settings.json`)
- **Model?** — `[1-8]` haiku to best; default 2 = sonnet
- **Effort?** — `[1-4]` low / medium / high / max; default 2 = medium
- Claude Code launches with your chosen flags

To add dependencies later:

```bash
# Edit requirements.txt, then:
pip install -r requirements.txt   # venv auto-activates on cd if ~/.bashrc override is in place
```

## 5. Adding git remotes

Bootstrap creates a local git repo only. To push to GitHub, a local bare repo, or another host, see [adding-remotes.md](adding-remotes.md). Remotes are optional and can be added any time after bootstrap.

## 6. What every new project receives

```
myproject/
├── .claude/
│   ├── hooks/          ← 10 hooks: 8 marketplace safety guards + save-response + auto-commit
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
- Name validation rejects hyphens, uppercase, names starting with a digit, and special characters
- Name validation accepts all legal names

Prints `PASS` or `FAIL` per check, then removes the temp project.

Use this any time you edit `bootstrap.sh` or `templates/` to confirm nothing is broken before the next real `mkproj` run.
