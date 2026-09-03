# Install

## 1. Prerequisites

`install.sh` checks for each prerequisite, reports found/not found, and installs anything
missing automatically via `apt`. You do not need to install these manually first.

| Tool | Minimum | Purpose |
|------|---------|---------|
| `git` | any | version control for bootstrapped projects |
| `python3` | 3.12+ | virtual environment and project runtime |
| `jq` | any | reads and writes `settings.json` safely |
| `screen` | any | named terminal session per project |
| `~/bin` in PATH | — | so `mkproj` is found on the command line |

## 2. Install steps

```bash
# Clone into ~/Projects/
cd ~/Projects
git clone https://github.com/BogusException/project-bootstrap
cd project-bootstrap

# Run the installer (checks prereqs, installs missing ones, creates ~/bin/mkproj)
bash install.sh
```

`install.sh` will:

1. Check each prerequisite and print `✓ found` or `✗ not found` with the version and path
2. Run `sudo apt update` and install anything missing (prompts for sudo password if needed)
3. Re-verify every prerequisite after installing — stops with a clear error if anything still fails
4. Create `~/bin/mkproj` (the launcher that calls `bootstrap.sh`)
5. Verify the launcher is executable
6. Check that `~/bin` is on PATH
7. Run `mkproj --help` as a smoke test

## 3. Python 3.12+ not available in apt

On older Ubuntu/Debian systems, `python3.12` may not be in the default apt sources.
The installer will tell you if this happens. Fix it with the deadsnakes PPA:

```bash
sudo add-apt-repository ppa:deadsnakes/ppa
sudo apt update
sudo apt install python3.12 python3.12-venv

# Then re-run the installer
bash install.sh
```

## 4. PATH setup (if ~/bin is not in PATH)

If the installer warns that `~/bin` is not in PATH, add this to `~/.bashrc`:

```bash
export PATH="$HOME/bin:$PATH"
```

Then reload:

```bash
source ~/.bashrc
```

Verify `mkproj` is found and comes from the right place:

```bash
which mkproj
# Should show: /home/<you>/bin/mkproj
```

## 5. Verify

```bash
mkproj --help
```

If that prints the usage text, the install is complete.

## 6. Non-apt systems

`install.sh` only auto-installs on apt-based systems (Ubuntu, Debian, Raspberry Pi OS, etc.).
On other systems it will report what is missing and stop — install those packages manually
using your system's package manager, then re-run `bash install.sh`.

## 7. Updating

```bash
cd ~/Projects/project-bootstrap
git pull
```

`~/bin/mkproj` does not need to be re-run after updates — it always calls the current
`bootstrap.sh` directly.
