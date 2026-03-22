# post-install-mint-script

A **robust, idempotent bash script** that transforms a fresh Linux Mint installation into a fully configured **data-engineering & software-development environment** — with a single command.

---

## Quick start

```bash
# Clone the repository
git clone https://github.com/Ali-Hegazy-Ai/post-install-mint-script.git
cd post-install-mint-script

# Make executable and run
chmod +x post-install.sh
./post-install.sh
```

> **Run as your normal user** (not root). The script will call `sudo` internally only where system-level access is required.

---

## What the script does

### 1 · System update & media codecs
- Full system upgrade (`apt update && apt upgrade`)
- `mint-meta-codecs`, `ubuntu-restricted-extras`, `libavcodec-extra`
- Interactive prompt to install recommended **Nvidia / AMD proprietary drivers**

### 2 · PostgreSQL (system-wide via official apt repo)
- Adds the official PostgreSQL PGDG apt repository
- Installs `postgresql` + `postgresql-contrib`
- Creates a superuser role and a default database matching your Linux username

### 3 · Isolated apps in `~/apps/` (no hardcoded versions)
All portable apps are downloaded dynamically from their official sources and placed under `~/apps/`. A `.desktop` entry is generated in `~/.local/share/applications/` so they appear in the Linux Mint application menu.

| App | Source | Directory |
|-----|--------|-----------|
| **Telegram** | Official `telegram.org` stable URL | `~/apps/telegram/` |
| **Zen Browser** | Latest GitHub release tarball | `~/apps/zen/` |
| **Zed Editor** | Official `zed.dev/install.sh` | `~/.local/bin/zed` |
| **Discord** | Official `discord.com` stable API | `~/apps/discord/` |
| **DBeaver CE** | Latest GitHub release tarball | `~/apps/dbeaver/` |

### 4 · Repository apps (via apt)
| App | Repository |
|-----|-----------|
| **VS Code** | Official Microsoft apt repo |
| **Spotify** | Official Spotify apt repo |

### 5 · Python development environment
- Installs `python3-venv` and `python3-pip`
- Creates `~/development/python_envs/` as the home for all virtual environments
- Adds a **`mkenv`** helper function and **`lsenvs`** alias to `~/.bashrc` / `~/.zshrc`

```bash
# Create and activate a new environment
mkenv my-project

# Activate an existing environment
mkenv my-project activate

# List all managed environments
lsenvs
```

---

## Directory layout

```
~/
├── apps/
│   ├── telegram/
│   ├── zen/
│   ├── discord/
│   └── dbeaver/
└── development/
    └── python_envs/
        ├── my-project/
        └── data-pipeline/
```

---

## Requirements

- Linux Mint (21.x or later recommended)
- Internet access
- `sudo` privileges
- `curl`, `wget`, `jq` (installed automatically if missing)

---

## Idempotency

Every installation step checks whether the app is already present before doing any work. Re-running the script on an already-configured machine is safe and will skip completed steps.

---

## License

MIT