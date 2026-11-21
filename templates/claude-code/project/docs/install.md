# Install

*Bootstrap already ran. This doc covers re-setup after a fresh clone, or onboarding a new contributor.*

## 1. Prerequisites

*List anything beyond what the bootstrap scaffold provides (Python venv, git repo, etc.).*

- (example) Python 3.11+
- (example) PostgreSQL 15 running locally
- (example) A valid `.env` -- copy `.env.example` and fill in real values

## 2. Setup

*Step-by-step from clone to running. Number every step so contributors can follow along.*

1. Clone the repo: `git clone <repo-url> && cd <project>`
2. Create and activate the venv: `python -m venv .venv && source .venv/bin/activate`
3. Install dependencies: `pip install -r requirements.txt`
4. Copy env file: `cp .env.example .env` and fill in required keys (see `docs/api-keys.md`)
5. (Add any project-specific steps here)

## 3. Verifying the install

*How does a contributor confirm everything is working before they write a line of code?*

- Run the test suite: `bash test.sh` -- all tests should pass
- (example) Hit the health endpoint: `curl http://localhost:8000/health`
- (example) Run a smoke test: `python main.py --dry-run`
