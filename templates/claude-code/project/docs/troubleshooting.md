# Troubleshooting

## 1. Common errors

*Add a row each time you hit an error worth documenting. Future you will thank present you.*

| Error message | Likely cause | Fix |
|---------------|-------------|-----|
| `ModuleNotFoundError` | venv not active or deps not installed | `source .venv/bin/activate && pip install -r requirements.txt` |
| `KeyError: 'SOME_VAR'` | Missing `.env` variable | Copy `.env.example`, fill in the missing key |
| (add more as you encounter them) | | |

## 2. Logs

*Where logs live and how to read them.*

- Default log output: stdout (visible in the terminal)
- (example) Persistent logs: `logs/app.log` -- rotated daily, kept for 7 days
- (example) To increase verbosity: set `LOG_LEVEL=DEBUG` in `.env`

## 3. Getting help

*Who to ask and what to include in a bug report.*

- Open an issue in the project repo with:
  - What you expected to happen
  - What actually happened (paste the full error, not just the last line)
  - Steps to reproduce
  - Output of `python --version`, `pip list`, and your OS
- (example) For urgent issues: ping @owner in Slack #project-channel
