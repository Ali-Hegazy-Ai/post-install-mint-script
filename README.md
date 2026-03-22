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

### 2 · System tools, utilities & development core (apt)
| Package | Purpose |
|---------|---------|
| `timeshift` | System snapshot / restore |
| `gnome-disk-utility` | GNOME Disks — disk management GUI |
| `gnome-terminal` | Terminal emulator (set as system default) |
| `btop` | Beautiful resource monitor |
| `vlc` | Media player |
| `git` | Version control |
| `build-essential` | C/C++ compiler toolchain (gcc, make, etc.) |
| `cmake` | Cross-platform build system |
| `gdb` | GNU debugger |

`gnome-terminal` is set as the system default via `update-alternatives` and `gsettings` (Cinnamon).

### 3 · PostgreSQL (system-wide via official PGDG apt repo)
- Adds the official PostgreSQL PGDG apt repository
- Installs `postgresql` + `postgresql-contrib`
- Creates a superuser role and a default database matching your Linux username

### 4 · Docker (system-wide via official Docker apt repo)
- Installs `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`
- Adds your user to the `docker` group (no `sudo` needed after logout/login)

### 5 · GitHub CLI (system-wide via official GitHub apt repo)
- Installs `gh` from `cli.github.com/packages`

### 6 · Isolated apps in `~/apps/` (no hardcoded versions)
All portable apps are downloaded dynamically from their official sources and placed under `~/apps/`. A `.desktop` entry is generated in `~/.local/share/applications/` so they appear in the Linux Mint application menu.

| App | Source | Directory |
|-----|--------|-----------|
| **Telegram** | Official `telegram.org` stable URL | `~/apps/telegram/` |
| **Zen Browser** | Latest GitHub release tarball | `~/apps/zen/` |
| **Zed Editor** | Official `zed.dev/install.sh` | `~/.local/bin/zed` |
| **Discord** | Official `discord.com` stable API | `~/apps/discord/` |
| **DBeaver CE** | Latest GitHub release tarball | `~/apps/dbeaver/` |
| **GitKraken** | Official `release.gitkraken.com` stable URL | `~/apps/gitkraken/` |
| **CLion** | JetBrains API latest release tarball | `~/apps/clion/` |

### 7 · Repository apps (via apt)
| App | Repository |
|-----|-----------|
| **VS Code** | Official Microsoft apt repo |
| **Spotify** | Official Spotify apt repo |

### 8 · Python development environment
- Installs `python3-venv` and `python3-pip`
- Creates `~/development/python_envs/` as the home for all virtual environments
- Adds a **`mkenv`** helper function and **`lsenvs`** alias to **both** `~/.bashrc` and `~/.zshrc` (if it exists)

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
│   ├── dbeaver/
│   ├── gitkraken/
│   └── clion/
└── development/
    └── python_envs/
        ├── my-project/
        └── data-pipeline/
```

---

## Requirements

- Linux Mint 21.x or later (or any Ubuntu-based derivative that sets `UBUNTU_CODENAME` in `/etc/os-release`)
- Internet access
- `sudo` privileges
- `curl`, `wget`, `jq` (installed automatically if missing)

> **Linux Mint codename compatibility:** Linux Mint uses its own release codenames (e.g. `virginia`, `wilma`) which break standard Ubuntu PPAs. The script detects the underlying Ubuntu codename from `/etc/os-release` and uses it for every third-party apt repository (PostgreSQL, Docker, VS Code, Spotify, GitHub CLI). If `UBUNTU_CODENAME` is not set, the script will abort with a clear error rather than silently adding a broken repository.

> **Note on Docker:** After the script runs, you must log out and back in (or run `newgrp docker`) before you can use Docker without `sudo`.

---

## Idempotency

Every installation step checks whether the app is already present before doing any work. Re-running the script on an already-configured machine is safe and will skip completed steps.

---

## License

MIT