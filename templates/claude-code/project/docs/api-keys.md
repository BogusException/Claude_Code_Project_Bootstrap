# API Keys

## 1. Required keys

*Every key in this table must be present for the project to run. Copy the variable names exactly into `.env`.*

| Key name | Service | Where to get it | `.env` variable |
|----------|---------|-----------------|-----------------|
| (example) | OpenAI | platform.openai.com | `OPENAI_API_KEY` |

## 2. Optional keys

*These keys enable additional features but are not required for basic operation.*

| Key name | Service | What it enables | `.env` variable |
|----------|---------|-----------------|-----------------|
| (example) | Sentry | Error tracking | `SENTRY_DSN` |

## 3. Rotating keys

*Describe the rotation policy for this project. Who rotates, how often, and how to update deployed environments.*

- Rotate every: (e.g. 90 days, or on team member departure)
- Update: `.env` locally, plus any deployment secrets (e.g. GitHub Secrets, Fly.io secrets)
- Never commit key values to git. If a key is accidentally committed, revoke it immediately.
