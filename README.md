# post-install-mint-script

A modular, idempotent Linux Mint post-install automation tool.

## File layout

- `post-install.sh` — entrypoint and module loader
- `core.sh` — execution flow, CLI parsing, module orchestration
- `functions.sh` — shared helpers (logging, apt/repo/state helpers)
- `packages.sh` — package/module definitions (arrays)
- `config.sh` — user-configurable defaults and runtime flags

## Quick start

```bash
chmod +x post-install.sh
./post-install.sh --full
```

## CLI

```text
--full        Install full setup (default)
--dev         Development tools focused setup
--minimal     Essential setup only
--apps        GUI apps only
--dry-run     Print actions only
--low-end     Optimize for low-resource systems
--no-update   Skip apt metadata refresh
--with-recommends Use apt install with recommended packages
--verbose     Debug logs

Feature toggles:
--docker/--no-docker
--node/--no-node
--python/--no-python
--flatpak/--no-flatpak
--tweaks/--no-tweaks
--git-ssh/--no-git-ssh
```

## Key behavior

- Root is detected once and script re-executes with `sudo` when needed.
- State tracking file: `~/.mint-postinstall-state`.
- Re-runnable and idempotent package/repository handling.
- Single apt metadata refresh flow (unless new repos are added).
- Uses `apt-get install -y --no-install-recommends` with retries.
- Low-end mode uses smaller install batches and disables heavy/optional modules.
- Security hardening for downloads: `curl -fL --retry 3`.
- Cleanup: `apt-get autoremove -y` and `apt-get clean`.
