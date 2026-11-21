# Running

## 1. Quick start

*The single command that gets the project running from a clean terminal.*

```bash
source .venv/bin/activate && bash run.sh
```

*Update the command above if this project starts differently.*

## 2. Common tasks

*The commands a developer reaches for every day. Keep this table current.*

| Task | Command |
|------|---------|
| Run tests | `bash test.sh` |
| Lint | (e.g. `ruff check .`) |
| Format | (e.g. `ruff format .`) |
| Build | (e.g. `python build.py`) |
| Deploy | (e.g. `fly deploy`) |

## 3. Environment modes

*Describe differences between dev, staging, and production if they exist. If this project has no staging environment, say so.*

- **Dev:** Uses `.env` locally. Hot-reload on if applicable.
- **Staging:** (describe differences -- e.g. points to staging database, uses test API keys)
- **Prod:** (describe differences -- e.g. `ENV=production` disables debug output)
- If no modes: This project runs the same way in all environments.
