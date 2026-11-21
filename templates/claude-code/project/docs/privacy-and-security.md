# Privacy and Security

## 1. Data handled

*Describe what personal or sensitive data this project processes, stores, or transmits. If none, say so explicitly.*

- (example) Email addresses collected during signup -- stored in the database, never logged.
- (example) No personal data handled by this project.

## 2. Secret management

*Which `.env` keys are sensitive, how often they rotate, and what the never-commit rules are.*

- Sensitive keys: (list them -- e.g. `DATABASE_URL`, `STRIPE_SECRET_KEY`)
- Rotation policy: (e.g. rotate every 90 days or on team member departure)
- Rule: never commit `.env` to git. If a secret is exposed, revoke it immediately and create a new one.

## 3. Access controls

*Who or what can access this system, and how is that access managed.*

- (example) Admin panel requires a valid session token.
- (example) API endpoints are public except `/admin/*` which requires `ADMIN_TOKEN` header.
- (example) Production database access is restricted to the deploy server by firewall rule.

## 4. Claude Code boundaries

*Any project-specific restrictions on what Claude Code can do beyond the defaults in `.claude/settings.json`.*

- (example) Claude must not read or write files in `data/private/`.
- (example) Claude must not call external APIs without explicit user instruction.
- If none, write: No additional restrictions beyond defaults.
