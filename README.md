# project-bootstrap

One command that turns an empty folder into a fully configured [Claude Code](https://claude.ai/code) Python development environment.

```bash
cd ~/Projects
mkproj myproject
```

That's it. A named `screen` session opens, 9 setup phases run, and you land in a ready-to-use project.

---

## What you get

| Category | What's created |
|----------|---------------|
| **Version control** | Local git repo (remotes optional -- add any time; see [docs/adding-remotes.md](docs/adding-remotes.md)) |
| **Python** | `.venv`, `requirements.txt` stub |
| **Claude Code** | `settings.json`, 10 hooks, 4 code-quality rules |
| **Project structure** | `docs/`, `tasks/`, `responses/`, `run.sh`, `test.sh` |
| **Standing instructions** | `CLAUDE.md` with git workflow, response format, and behavioural rules |
| **Shell** | Named `screen` session, auto-venv `cd` override in `~/.bashrc` |

---

## Requirements

- Linux (SSH-based workflow)
- bash, git, Python 3.12+, jq, screen

---

## Install

```bash
cd ~/Projects
git clone https://github.com/BogusException/project-bootstrap
cd project-bootstrap
bash install.sh
# Add ~/bin to PATH if prompted, then: source ~/.bashrc
```

See [docs/install.md](docs/install.md) for full details.

---

## Usage

```bash
mkproj myproject          # creates ~/Projects/myproject and bootstraps it
mkproj --help             # full usage and phase list
```

Re-running `mkproj` on an interrupted setup is safe — every step is idempotent. Running it on a project with real commits is refused (intentionally).

See [docs/usage.md](docs/usage.md) for the full walkthrough, including what every new project's directory looks like.

---

## How it works

Bootstrap runs 9 sequential phases inside a `screen` session:

1. **Preflight** — checks prereqs, refuses live projects, handles bare-repo collisions
2. **Git** -- `git init` on branch main (remotes optional, configured separately)
3. **Python** — `.venv` created
4. **Root files** — `.gitignore`, `.gitattributes`, `.env.example`, `CLAUDE.md`, `README.md`
5. **Claude config** — hooks, rules, `settings.json`
6. **Structure** — `docs/`, `tasks/`, `responses/`, `run.sh`, `test.sh`
7. **Global setup** — `~/.bashrc` entries, global Claude hook (idempotent)
8. **Initial commit** — "Initial project scaffold" committed locally (pushed if a remote exists)
9. **Verify** — hook permissions, next-steps summary

See [docs/how-it-works.md](docs/how-it-works.md) for internals, hook inventory, and `settings.json` structure.

---

## Customizing

Edit files in `templates/` to change what new projects receive. Edit phase functions in `bootstrap.sh` to change setup behaviour. Changes take effect immediately on the next `mkproj` run.

See [docs/customizing.md](docs/customizing.md).

---

## Documentation

| Doc | Contents |
|-----|----------|
| [docs/overview.md](docs/overview.md) | What this tool is and why it exists |
| [docs/install.md](docs/install.md) | First-time setup |
| [docs/usage.md](docs/usage.md) | Day-to-day use and project directory layout |
| [docs/how-it-works.md](docs/how-it-works.md) | Internals: phases, hooks, settings.json |
| [docs/customizing.md](docs/customizing.md) | Modifying templates and phases |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Common problems and fixes |
| [docs/adding-remotes.md](docs/adding-remotes.md) | Setting up local bare repo, GitHub, and other remotes |
| [docs/doc-index.md](docs/doc-index.md) | Alphabetical index of all topics |
