# LockMyCal - Docker Deployment Guide

**Enterprise-grade meeting scheduling platform built with Elixir/Phoenix LiveView**

> For a comprehensive overview of LockMyCal's features and capabilities, see the [Core README](README.md).

## Overview

Deploy LockMyCal using Docker. The image ships without a database — PostgreSQL runs as its own container, for independent backups and cleaner separation of concerns than bundling the database into the app image. You get:

- **Volume persistence** for data and uploads
- **Easy deployment** on any Docker-compatible platform

---

## System Requirements

- **Docker** (version 20.10+ recommended)
- **500MB RAM** minimum (1GB recommended)
- **Domain name** (optional, for production use)

---

## Quick start

LockMyCal does not publish a prebuilt image: you build it from this repository with Docker Compose, and it runs next to its own `postgres` container.

> 📖 For the complete, always-current configuration reference — every environment variable, plus SMTP, Postmark, OAuth/OIDC, reverse proxy, and backups — see the online docs at **<https://learn.lockmycal.com/en>**. This README is the self-contained quick path; the sections below link to the matching online articles.

Configuration lives in a `.env` file. Compose reads a `.env` next to it (see below), and `docker run` has two alternatives: `--env-file ./my-env` on the host, or a `.env` file inside the `/app/data` volume, which the app reads at boot and which survives image updates because the volume does. Values passed with `-e` or `--env-file` win over that file, so it works as the defaults layer under one-off overrides. Five keys are the exception and are ignored in that file with a warning at boot: `POSTGRES_USER`, `POSTGRES_DB`, `DATABASE_URL`, `DATABASE_HOST` and `DATABASE_PORT`. They decide which database the container uses and which role the embedded cluster is created with, so they are container settings (`-e`, `--env-file` or Compose), and earlier releases never read them from that file, so a stale copy left there would otherwise point an upgraded install at an empty database or an unreachable host. `POSTGRES_PASSWORD` is honoured, and the embedded cluster's role is brought in line with it on every start. Copy [`.env.example`](.env.example) as your starting point; it documents every variable.

> **Keep `tymeslot_pgdata:/var/lib/postgresql/data` (and `tymeslot_data:/app/data`) as named volumes.** Swapping either for a host path (e.g. `./pgdata:/var/lib/postgresql/data`) can break first-run initialization on Docker Desktop, rootless Docker, userns-remap, or SELinux-enforcing hosts because the mount arrives with ownership the container can't change. If you need the database on a specific host path, use an [external PostgreSQL](#using-an-external-database) instead.

> ⚠️ **Email defaults to silent discard.** Without email configuration, `EMAIL_ADAPTER` defaults to `test`, which **drops every message** — password resets, booking confirmations and reminders all vanish with no error. Configure SMTP, Postmark, SendGrid, Mailgun or AhaSend (below) before going live. See **<https://learn.lockmycal.com/en/self-hosting/environment-variables>** and **<https://learn.lockmycal.com/en/notifications-automation/email-postmark>**.

### Build from source (Docker Compose)

Docker builds
straight from the repository URL, so cloning is only necessary if you want to
modify the source.

#### 1. Get the source

**Without cloning (quickest).** Create an empty directory and put this
`compose.yaml` in it. Docker does the checkout itself as part of the build:

```yaml
services:
  tymeslot:
    build:
      # Docker clones the repository itself. The fragment after `#` selects
      # which branch or tag to build.
      context: https://github.com/lockmycal/lockmycal.git#${TYMESLOT_VERSION:-main}
      dockerfile: Dockerfile.docker
    image: tymeslot:${TYMESLOT_VERSION:-main}
    container_name: tymeslot
    restart: unless-stopped
    ports:
      - "${PORT:-4000}:${PORT:-4000}"
    # Forward every variable from .env into the container, so SMTP, OAuth and
    # DATA_ENCRYPTION_KEY settings reach LockMyCal as well.
    env_file:
      - .env
    environment:
      DEPLOYMENT_TYPE: docker
      DATABASE_HOST: postgres
      DATABASE_PORT: 5432
      # Same value .env already supplies. It is repeated here only so Compose
      # refuses to start with this message rather than booting a broken
      # container when the secret is missing.
      SECRET_KEY_BASE: "${SECRET_KEY_BASE:?required, generate one with: openssl rand -base64 64}"
    depends_on:
      postgres:
        condition: service_healthy
    volumes:
      - tymeslot_data:/app/data

  postgres:
    image: postgres:17-alpine
    container_name: tymeslot-postgres
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB:-tymeslot}
      POSTGRES_USER: ${POSTGRES_USER:-tymeslot}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:?POSTGRES_PASSWORD must be set in .env}
    volumes:
      - tymeslot_pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -h 127.0.0.1 -p 5432 -U ${POSTGRES_USER:-tymeslot} -d ${POSTGRES_DB:-tymeslot}"]
      interval: 5s
      timeout: 5s
      retries: 12
      start_period: 10s

# Volume names are pinned with `name:` so they match the manual `docker run`
# commands below instead of being prefixed with the Compose project name.
volumes:
  tymeslot_data:
    name: tymeslot_data
  tymeslot_pgdata:
    name: tymeslot_pgdata

networks:
  default:
    name: tymeslot_network
```

`TYMESLOT_VERSION` decides what gets built. Leave it unset to track `main`, or
set it in `.env` to a tag or commit for a reproducible build:

```bash
TYMESLOT_VERSION=v1.4.4
```

The available tags are listed on the [tags page](https://github.com/lockmycal/lockmycal/tags).
Building from a git URL needs BuildKit, which is the default from Docker 23.0
onwards.

**With a clone.** Take this path if you intend to modify the source, or to use
the build script:

```bash
git clone https://github.com/lockmycal/lockmycal.git
cd lockmycal
```

Save the same `compose.yaml` shown above next to the checkout, but change its
`build.context` from the git URL to `.` so it builds your working tree instead
of cloning it again — everything else about the file stays the same.

#### 2. Configure Environment

Both paths read the same `.env` file, sitting next to your Compose file.

```bash
# Start from the environment template
cp .env.example .env                # in a clone
curl -o .env https://raw.githubusercontent.com/lockmycal/lockmycal/main/.env.example   # without one

# Generate required secrets
openssl rand -base64 64 | tr -d '\n'  # For SECRET_KEY_BASE
openssl rand -base64 32 | tr -d '\n'  # For POSTGRES_PASSWORD

# Edit .env and fill in the required values
nano .env
```

**Required Configuration** (`.env` file):

```bash
# REQUIRED: Must be at least 64 characters
SECRET_KEY_BASE=<paste_generated_secret>

# REQUIRED: Your domain (or "localhost" for testing)
PHX_HOST=localhost

# REQUIRED: Database credentials
POSTGRES_DB=tymeslot
POSTGRES_USER=tymeslot
POSTGRES_PASSWORD=<paste_generated_password>

# OPTIONAL: Port (defaults to 4000)
PORT=4000
```

#### 3. Build and run

**Method 1 — Docker Compose (recommended, works for both paths):**

```bash
docker compose up -d --build
```

Same command either way — the only difference is whether `build.context` in
your `compose.yaml` points at the git URL or at `.` (see above). Compose reads
your `.env`, builds the image, and starts the `tymeslot` and `postgres`
containers, with the `tymeslot_data` and `tymeslot_pgdata` volumes. It reads
`.env` twice over: once to fill in the `${...}` placeholders in the Compose
file, and once through `env_file` to forward every variable into the
container. The second part is what carries your SMTP, OAuth and
`DATA_ENCRYPTION_KEY` settings through, so keep `env_file` in place if you
adapt the file.

To move to a newer release later, set the new tag and rebuild:

```bash
TYMESLOT_VERSION=v1.5.0 docker compose up -d --build
```

(In a clone, `git pull` first instead — the build context is your working
tree, so `TYMESLOT_VERSION` has no effect there.)

The repository also ships a minimal `docker-compose.build.yml` fragment (just
`build:` + `env_file:`) for iterating on the image itself without the full
stack, e.g. `docker compose -f docker-compose.build.yml build` to confirm the
image still builds after a source change. It isn't meant to be run standalone
— it has no `ports:`, `postgres` service, or volumes of its own.

**Method 2 — Build script (clone only):**

```bash
# Run from the repository root
./build-docker.sh
```

The script validates your `.env`, builds the image, and offers to start the container.

**Method 3 — Manual Docker commands (clone only):**

The image ships without a database, so it needs a PostgreSQL container of its
own:

```bash
source .env
docker network create tymeslot

docker run -d \
  --name tymeslot-postgres \
  --network tymeslot \
  -e POSTGRES_DB=tymeslot \
  -e POSTGRES_USER=tymeslot \
  -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  -v tymeslot_pgdata:/var/lib/postgresql/data \
  postgres:17-alpine

# Build image
docker build -f Dockerfile.docker -t tymeslot:local .

# Run container
docker run -d \
  --name tymeslot \
  --network tymeslot \
  -p ${PORT:-4000}:${PORT:-4000} \
  --env-file .env \
  -e DATABASE_HOST=tymeslot-postgres \
  -v tymeslot_data:/app/data \
  tymeslot:local
```

#### 4. Access Your Installation

Wait 30-60 seconds for initialization, then visit:

- **URL**: `http://localhost:4000`

For production deployment with SSL/HTTPS, configure your reverse proxy (Nginx, Caddy, Traefik, etc.) separately — see the [Reverse Proxy Setup](https://learn.lockmycal.com/en/self-hosting/reverse-proxy) guide for full Nginx and Caddy walkthroughs.

### 5. Becoming an admin

The first user to register on a fresh install is automatically promoted to admin. To promote additional users (or recover if no admin exists), use the release helper from inside the container:

```bash
docker exec -it tymeslot bin/tymeslot rpc 'Tymeslot.Release.promote_admin("you@example.com")'
```

See [`docs/ADMIN.md`](docs/ADMIN.md) for the full guide (demote, list, recovery paths).

---

## Understanding the Deployment Scripts

LockMyCal uses two scripts for Docker deployment:

### build-docker.sh (Host Machine)

Runs on your host machine to prepare and build the LockMyCal image, via `docker-compose.build.yml`.

**Responsibilities**:
- Validates `.env` file exists
- Validates required environment variables, including `POSTGRES_PASSWORD` for the sidecar Postgres container
- Checks SECRET_KEY_BASE meets security requirements (64+ characters)
- Builds the Docker image
- Optionally starts LockMyCal and its own PostgreSQL container

**Usage**:
```bash
./build-docker.sh
```

### start-docker.sh (Container Entrypoint)

Runs automatically inside the container when it starts.

**Responsibilities**:
- Runs database migrations
- Starts Phoenix web server

**Note**: This script runs automatically - you never call it directly.

---

## Configuration

### Required Environment Variables

```bash
SECRET_KEY_BASE=<64+ characters>    # Generate with: openssl rand -base64 64 | tr -d '\n'
PHX_HOST=<your-domain-or-localhost>
POSTGRES_DB=tymeslot
POSTGRES_USER=tymeslot
POSTGRES_PASSWORD=<secure-password> # Generate with: openssl rand -base64 32 | tr -d '\n'
```

### Essential for Production

Email configuration is **required for production deployments** to enable:
- Password reset emails
- Booking confirmations and reminders
- Calendar event notifications
- User invitations

`EMAIL_ADAPTER` picks how mail leaves the container. Every option below is equally supported; the API adapters differ from SMTP mainly in reporting failures usefully and in not needing an outbound SMTP port.

| `EMAIL_ADAPTER` | Additional variables |
|---|---|
| `smtp` | `SMTP_HOST`, `SMTP_PORT` (default 587), `SMTP_USERNAME` and `SMTP_PASSWORD` (leave both unset for a relay that needs no login), optional `SMTP_SSL`, and for a self-hosted relay `SMTP_CACERTFILE` or `SMTP_TLS_VERIFY` (see below) |
| `postmark` | `POSTMARK_API_KEY` |
| `sendgrid` | `SENDGRID_API_KEY` |
| `mailgun` | `MAILGUN_API_KEY`, `MAILGUN_DOMAIN`, optional `MAILGUN_BASE_URL` for EU accounts |
| `ahasend` | `AHASEND_API_KEY`, `AHASEND_ACCOUNT_ID` |
| `test` | none — every message is discarded |

Any provider not listed works over `smtp`; point `SMTP_HOST` at the relay it gives you. An `EMAIL_ADAPTER` value LockMyCal does not recognise stops the container at boot instead of silently discarding mail.

**Option 1: SMTP (works with every provider)**
```bash
EMAIL_ADAPTER=smtp
EMAIL_FROM_NAME="Your Company"
EMAIL_FROM_ADDRESS=noreply@yourdomain.com
SMTP_HOST=smtp.example.com
SMTP_PORT=587
SMTP_USERNAME=your-smtp-username
SMTP_PASSWORD=your-smtp-password
```

Port 587 (STARTTLS) and port 465 (implicit TLS) are both supported; any other port negotiates TLS opportunistically. A provider that serves implicit TLS on another port (2465, 8465) needs `SMTP_SSL=true`; without it the connection hangs waiting for a greeting. A relay that authorises by network rather than by login (a local Postfix, a company relay) needs no `SMTP_USERNAME` or `SMTP_PASSWORD`; set both or neither. The certificate is verified against the system trust store, which is what you want for a commercial relay but usually fails against your own mail server: Stalwart, Mailcow and Mailu all serve a self-signed certificate until you point them at Let's Encrypt.

Two variables cover that case. Prefer the first, which keeps the connection authenticated:

```bash
# Trust the CA that issued your relay's certificate (a PEM bundle you mount
# into the container).
SMTP_CACERTFILE=/app/data/smtp-ca.pem

# Last resort: accept any certificate. Mail is still encrypted, but the
# relay's identity is no longer checked, so an intercepted connection cannot
# be detected.
SMTP_TLS_VERIFY=none
```

Rarely, a firewall or proxy between the container and the relay drops a TLS 1.3 handshake because it does not look like TLS 1.2. The symptom is a connection that times out or closes during the handshake while the same relay works from other mail clients; `SMTP_TLS_MIDDLEBOX_COMPAT=true` restores the TLS 1.2 shape. Leave it off otherwise: relays that do not expect it abort every handshake, and the health check at boot says so explicitly when they do.

**Option 2: a provider API (clearer delivery errors, no SMTP port needed)**
```bash
EMAIL_ADAPTER=postmark
EMAIL_FROM_NAME="Your Company"
EMAIL_FROM_ADDRESS=noreply@yourdomain.com
POSTMARK_API_KEY=your-postmark-api-key
```

Swap in `sendgrid`, `mailgun` or `ahasend` with the variables from the table above. Whichever you choose, LockMyCal validates the credentials once at startup (without sending anything) and logs the result, so a bad key shows up in the container logs immediately rather than on the first booking.

**Development/Testing Only**: You can use `EMAIL_ADAPTER=test` to skip email configuration during development. Emails will be logged to console instead of being sent.

### HTTP Proxy Configuration

> Full details, including whitelist domains and troubleshooting: [HTTP Proxy](https://learn.lockmycal.com/en/self-hosting/http-proxy).

If your environment requires outbound HTTP requests to go through a proxy (common in corporate/secured environments), LockMyCal supports standard proxy environment variables:

**Standard Configuration (Recommended)**
```bash
# For HTTPS requests (most external APIs)
HTTPS_PROXY=http://username:password@proxy.example.com:3128

# For HTTP requests (if different from HTTPS)
HTTP_PROXY=http://username:password@proxy.example.com:3128

# Bypass proxy for specific hosts (comma-separated)
NO_PROXY=localhost,127.0.0.1,*.internal.company.com,10.0.0.0/8
```

**Environment Variable Details:**
- `HTTPS_PROXY` / `https_proxy` - Proxy for HTTPS requests (recommended)
- `HTTP_PROXY` / `http_proxy` - Proxy for HTTP requests
- `NO_PROXY` / `no_proxy` - Comma-separated list of hosts/patterns to bypass proxy

**NO_PROXY Patterns:**
- Exact hostname: `internal.example.com`
- Wildcard domain: `*.example.com` (matches any subdomain)
- CIDR notation: `10.0.0.0/8`, `192.168.0.0/16`
- Special: `*` (bypass proxy for all hosts)

**Example Configurations:**

Same proxy for HTTP and HTTPS:
```bash
HTTPS_PROXY=http://user:pass@proxy.company.com:3128
NO_PROXY=localhost,*.internal.company.com
```

Different proxies for HTTP and HTTPS:
```bash
HTTP_PROXY=http://user:pass@http-proxy.company.com:3128
HTTPS_PROXY=http://user:pass@https-proxy.company.com:3129
NO_PROXY=localhost,127.0.0.1,10.0.0.0/8
```

No authentication:
```bash
HTTPS_PROXY=http://proxy.company.com:8080
NO_PROXY=localhost,*.internal.company.com
```

**What Uses the Proxy:**

All outbound HTTP/HTTPS requests including:
- CalDAV calendar integrations (Nextcloud, Radicale, etc.)
- Google Calendar API
- Microsoft Outlook/Office 365 API
- Video provider APIs (Google Meet, Microsoft Teams, Zoom, Nextcloud Talk)
- Reachability tests for self-hosted meeting servers (MiroTalk, Jitsi Meet, kMeet, custom links)
- OAuth token exchanges
- All other external API calls

**Important**: If your proxy uses a whitelist-based access control, ensure the following domains are allowed:
- `www.googleapis.com` (Google Calendar, Google Meet)
- `graph.microsoft.com` (Outlook Calendar, Microsoft Teams)
- `oauth2.googleapis.com` (OAuth)
- Your CalDAV server domains
- `kmeet.infomaniak.com` (kMeet)
- Your own meeting server domains (MiroTalk, Jitsi Meet, Nextcloud Talk)
- Any custom video provider endpoints

### Using an External Database

LockMyCal's default image ships without PostgreSQL and expects one already running: another container (see below), another host, or a managed service, PostgreSQL 14 or newer.

**With a connection string** (what managed providers hand you):

```bash
DATABASE_URL=postgres://user:password@db.example.com:5432/tymeslot
DATABASE_SSL=true
```

**With discrete variables:**

```bash
DATABASE_HOST=db.example.com
DATABASE_PORT=5432
POSTGRES_DB=tymeslot
POSTGRES_USER=tymeslot
POSTGRES_PASSWORD=your_db_password
DATABASE_SSL=true
```

`DATABASE_URL` wins where the two overlap, so there is no need to set both.

**Important**: When using an external database:
- The database and user must already exist; LockMyCal creates neither.
- The database must accept connections from your container's network, and firewall rules must allow it.
- Migrations run automatically on every start, so the user needs schema privileges on that database.

**TLS.** Set `DATABASE_SSL=true` for managed databases. It verifies the server certificate and hostname against the system trust store. If your provider uses a private CA, download its bundle onto the `/app/data` volume and set `DATABASE_SSL_CACERT_FILE=/app/data/your-ca.pem`. For a self-signed certificate on a network you already trust, `DATABASE_SSL=verify-none` encrypts the connection without verifying it. Omit the variable entirely for a database on the same host or a private Docker network.

An `sslmode` query parameter in `DATABASE_URL` (as issued by most managed providers) is honoured when `DATABASE_SSL` is unset: `require` encrypts without verification, matching its libpq meaning, while `verify-ca` and `verify-full` verify the certificate like `DATABASE_SSL=true`. An explicit `DATABASE_SSL` always wins over the URL parameter.

**Detection.** The container switches to external mode when `DATABASE_URL` names a remote host, or when `DATABASE_HOST` is anything other than `localhost`/`127.0.0.1`. In external mode it never initialises or starts the bundled PostgreSQL.

A `DATABASE_URL` pointing at `localhost`, `127.0.0.1` or `::1` is treated as the bundled database on images that ship one: the container logs a warning, ignores the variable, and connects with the discrete `POSTGRES_*` credentials the bundled cluster is created with. The slim image bundles no server, so there a local URL is honoured as given and expected to reach a PostgreSQL you run yourself.

**Upgrading from 1.4.4 or earlier.** Those releases ignored `DATABASE_URL` on this image and always used the bundled PostgreSQL. If you have a `DATABASE_URL` left over from another deployment and want to keep using the bundled database, remove it before upgrading, or confirm it points at `localhost` so the guard above applies. A `DATABASE_URL` naming a remote host now takes effect and the bundled PostgreSQL is left unused.

### Running PostgreSQL as its own container

This is the default — and only — packaging; see [Build from source](#build-from-source-docker-compose) for the full `compose.yaml`, with independent backups, an existing backup routine, or plain separation of concerns as the payoff. It runs two containers: `tymeslot` (the database-free image) and `tymeslot-postgres` (`postgres:17-alpine`), with the app waiting on the database's health check before it starts. The database lives in its own `tymeslot_pgdata` volume, so `docker exec tymeslot-postgres pg_dump …` is all a backup takes.

To use a database you already run elsewhere, delete the `postgres` service and the `depends_on` block from your `compose.yaml` and set `DATABASE_URL` in your `.env` — see [Using an External Database](#using-an-external-database) above.

### Podman

Everything above works with Podman; `podman` is a drop-in for `docker`, and `podman compose` for `docker compose`.

**SELinux.** On Fedora, RHEL, and derivatives, add `:Z` to bind mounts so they are relabelled: `-v ./data:/app/data:Z`. Named volumes need no such flag.

```bash
podman compose up -d
```

To run it as a system service, generate a systemd unit from the running containers:

```bash
podman generate systemd --new --name tymeslot > ~/.config/systemd/user/tymeslot.service
systemctl --user enable --now tymeslot
```

### Optional Environment Variables

> The complete, annotated list of every supported variable lives in [`.env.example`](.env.example) and online at [Environment Variable Reference](https://learn.lockmycal.com/en/self-hosting/environment-variables). The most common knobs are shown below.

```bash
# Application
PORT=4000                    # HTTP port (default: 4000)
DATABASE_URL=                # Full connection string (default: unset; wins over the variables below)
DATABASE_HOST=localhost      # Database host (default: localhost)
DATABASE_PORT=5432          # Database port (default: 5432)
DATABASE_SSL=                # TLS: true / verify-full / verify-none / false (default: unset, no TLS)
DATABASE_SSL_CACERT_FILE=    # CA bundle for certificate verification (default: system trust store)
DATABASE_POOL_SIZE=10        # DB pool size (default: 10)

# HTTP Proxy (for environments with restricted outbound access)
HTTP_PROXY=                  # Proxy for HTTP requests (e.g., http://user:pass@proxy.example.com:3128)
HTTPS_PROXY=                 # Proxy for HTTPS requests (e.g., http://user:pass@proxy.example.com:3128)
NO_PROXY=                    # Bypass proxy for these hosts (e.g., localhost,*.internal.com,10.0.0.0/8)

# OAuth Providers (optional - configure through dashboard after setup)
GITHUB_CLIENT_ID=
GITHUB_CLIENT_SECRET=
GOOGLE_CLIENT_ID=
GOOGLE_CLIENT_SECRET=
GOOGLE_STATE_SECRET=         # Self-generated random string (required with Google OAuth)
OUTLOOK_CLIENT_ID=           # From Azure AD App Registration (used for both Outlook & Teams)
OUTLOOK_CLIENT_SECRET=       # From Azure AD App Registration (used for both Outlook & Teams)
OUTLOOK_STATE_SECRET=        # Self-generated random string (required with Microsoft OAuth)
ENABLE_GOOGLE_AUTH=false     # Enable Google login/signup
ENABLE_GITHUB_AUTH=false     # Enable GitHub login/signup
ENABLE_MICROSOFT_AUTH=false  # Enable Microsoft login/signup (uses the OUTLOOK_* app)
```

### Booking Analytics (optional)

Booking analytics — page-view tracking, cookie-less visitor counting, and the
attribution dashboard — is **disabled by default**. Most self-hosters do not
enable it and can ignore this section entirely.

If you opt in (`config :tymeslot, :booking_analytics_enabled, true`), then
`ANALYTICS_SALT_SECRET` becomes **required** and the app will **fail fast at
boot** if it is missing:

```bash
# Required ONLY when booking analytics is enabled.
# Keys the cookie-less daily visitor fingerprint. Generate ONCE with:
#   openssl rand -base64 48
# It must stay constant across deployments — changing it re-hashes the same
# visitor and double-counts uniques.
ANALYTICS_SALT_SECRET=<paste_generated_secret>
```

When analytics is left disabled (the default), this variable is not read and
need not be set.

### Generate Secrets

```bash
# Generate SECRET_KEY_BASE (64+ characters)
openssl rand -base64 64 | tr -d '\n'

# Generate DATA_ENCRYPTION_KEY (recommended)
openssl rand -base64 48 | tr -d '\n'

# Generate database password
openssl rand -base64 32 | tr -d '\n'

# Generate OAuth state secrets (for GOOGLE_STATE_SECRET, OUTLOOK_STATE_SECRET, etc.)
# Note: These are self-generated for security, NOT provided by Google/Microsoft
openssl rand -base64 32 | tr -d '\n'
```

---

## Data-at-rest encryption

Integration credentials (calendar tokens, CalDAV passwords, video API keys, Slack/Telegram
tokens, webhook secrets) are encrypted at rest with AES-256-GCM.

By default the encryption key is derived from `SECRET_KEY_BASE`. That works, but it welds
your data-at-rest protection to the cookie-signing secret: **rotating `SECRET_KEY_BASE` would
make every stored credential undecryptable**, forcing every user to reconnect every
integration.

Setting a dedicated **`DATA_ENCRYPTION_KEY`** decouples the two, so the session secret can be
rotated freely without touching stored data.

### Enabling it on an existing install

1. Generate a key and add it to your `.env` (keep it stable forever — losing it makes stored
   credentials unrecoverable):

   ```bash
   echo "DATA_ENCRYPTION_KEY=$(openssl rand -base64 48 | tr -d '\n')" >> .env
   ```

2. Restart so the app starts writing new values under the new key. Existing values keep
   decrypting under the old (`SECRET_KEY_BASE`-derived) key automatically — nothing breaks.

3. Migrate existing rows onto the new key:

   ```bash
   docker exec tymeslot /app/bin/tymeslot eval \
     'Ecto.Migrator.with_repo(Tymeslot.Repo, fn _ -> IO.inspect(Tymeslot.Security.CredentialReencryption.run(), label: "reencryption") end)'
   ```

   Re-run until the reported `migrated_values` is `0` to confirm every credential is on the
   new key. The sweep is idempotent and safe to run repeatedly.

Only after the sweep reports zero migrated values is it safe to rotate `SECRET_KEY_BASE`.

### Rotating the data key in the future

The versioned format is built for rotation, not just the one-time legacy migration above. A new
key gets its own version and coexists with the current one: new writes use the new key, existing
values keep opening under the previous key, and the re-encryption sweep walks the data onto the
new key. Only once the sweep reports zero is the previous key retired. Nothing is ever wiped.

**Do not rotate by simply changing `DATA_ENCRYPTION_KEY` to a new value.** Replacing it in place
would strand every credential already written under the old key — the old key would no longer be
in the keyring to decrypt them. True rotation keeps both keys available until the sweep finishes,
which requires a release that registers the additional key. When key rotation is supported, follow
the upgrade notes for that version rather than editing the value by hand.

---

## Common Commands

```bash
# View logs
docker logs -f tymeslot

# Stop container
docker stop tymeslot

# Start container
docker start tymeslot

# Restart container
docker restart tymeslot

# Remove container
docker stop tymeslot && docker rm tymeslot

# Shell access
docker exec -it tymeslot /bin/bash

# Access Elixir console
docker exec -it tymeslot bin/tymeslot remote
```

---

## Updates

### Update to Latest Version

```bash
# Pull latest code
git pull origin main

# Rebuild and restart
./build-docker.sh
```

Or with Docker Compose (in a clone):

```bash
git pull origin main
docker compose down
docker compose up -d --build
```

---

## Troubleshooting

### Container Won't Start

```bash
# Check logs for errors
docker logs tymeslot

# Common causes:
# - Missing or invalid environment variables
# - SECRET_KEY_BASE too short (must be 64+ characters)
# - Port 4000 already in use
# - Insufficient disk space
```

**Verify configuration**:
```bash
source .env
echo "SECRET_KEY_BASE length: ${#SECRET_KEY_BASE}"  # Should be >= 64
echo "PHX_HOST: $PHX_HOST"
echo "POSTGRES_PASSWORD set: $([ -n "$POSTGRES_PASSWORD" ] && echo 'Yes' || echo 'No')"
```

### Container Starts But Can't Access Application

Wait 30-60 seconds for:
- PostgreSQL initialization
- Database migrations
- Phoenix server startup

Check startup progress:
```bash
docker logs -f tymeslot
```

Look for: `Running TymeslotWeb.Endpoint` message.

### Database Issues

The image ships without a database, so PostgreSQL always runs in its own container:

```bash
# Check PostgreSQL is running and verify the connection
docker exec -it tymeslot-postgres pg_isready -U $POSTGRES_USER -d $POSTGRES_DB
docker exec -it tymeslot-postgres psql -U $POSTGRES_USER -d $POSTGRES_DB -c 'SELECT version();'

# Reset database (WARNING: Destroys all data)
# Stop and remove the postgres container first — the volume can't be removed while in use.
docker rm -f tymeslot-postgres
docker volume rm tymeslot_pgdata
```

If a host-path bind mount at `/var/lib/postgresql/data` fails to initialize on
Docker Desktop, rootless Docker, or an SELinux-enforcing host without a
`:z`/`:Z` label, switch to the named `tymeslot_pgdata` volume from the
quick-start instead — named volumes live inside Docker's own storage and are
immune to host filesystem ownership quirks.

### Port Already in Use

```bash
# Check what's using port 4000
sudo lsof -i :4000

# Either stop the conflicting service or change PORT in .env
PORT=8080  # Use a different port
```

### OAuth Not Working

- Verify redirect URLs exactly match the ones specified in the OAuth Setup section below
- Check PHX_HOST matches your domain
- Ensure credentials are correctly set in `.env`
- For Microsoft OAuth, ensure both redirect URIs are configured in Azure AD

---

## OAuth Provider Setup

LockMyCal supports multiple OAuth providers for authentication and calendar/video integrations. Configure the providers you need by following the setup guides below. Each provider also has a dedicated online walkthrough with screenshots:

- [Google OAuth](https://learn.lockmycal.com/en/account-administration/google-oauth) · [Google Calendar](https://learn.lockmycal.com/en/calendar-sync/google-calendar) · [Google Meet](https://learn.lockmycal.com/en/video-conferencing/google-meet)
- [Microsoft OAuth](https://learn.lockmycal.com/en/account-administration/microsoft-oauth) · [Outlook Calendar](https://learn.lockmycal.com/en/calendar-sync/microsoft-outlook) · [Teams](https://learn.lockmycal.com/en/video-conferencing/ms-teams)
- [GitHub login](https://learn.lockmycal.com/en/account-administration/github-login) · [Generic OIDC / SSO](https://learn.lockmycal.com/en/account-administration/oidc-sso)
- [CalDAV](https://learn.lockmycal.com/en/calendar-sync/caldav) (Nextcloud, Radicale, Zimbra, mailbox.org)
- [MiroTalk](https://learn.lockmycal.com/en/video-conferencing/mirotalk) · [Jitsi Meet](https://learn.lockmycal.com/en/video-conferencing/jitsi-meet) · [Nextcloud Talk](https://learn.lockmycal.com/en/video-conferencing/nextcloud-talk) · [kMeet](https://learn.lockmycal.com/en/video-conferencing/kmeet) · [Custom video link](https://learn.lockmycal.com/en/video-conferencing/custom-video-link) (no OAuth app needed)

### Google OAuth Setup

**Used for**: Google Calendar integration, Google Meet video integration, Google login/signup

1. **Create Google Cloud Project**
   - Go to [Google Cloud Console](https://console.cloud.google.com/)
   - Create a new project or select existing one

2. **Enable Required APIs**
   - Go to **APIs & Services** → **Library**
   - Enable the following APIs:
     - Google Calendar API (required for calendar sync)
     - Google Meet API (required for Meet integration)

3. **Create OAuth Credentials**
   - Go to **APIs & Services** → **Credentials**
   - Click **Create Credentials** → **OAuth 2.0 Client IDs**
   - Configure OAuth consent screen if prompted
   - Application type: **Web application**
   - Add authorized redirect URI:
     ```
     https://your-domain.com/auth/google/callback
     ```
   - Click **Create** and copy the **Client ID** and **Client Secret**

4. **Configure Environment Variables**
   ```bash
   GOOGLE_CLIENT_ID=<your_google_client_id>
   GOOGLE_CLIENT_SECRET=<your_google_client_secret>
   GOOGLE_STATE_SECRET=$(openssl rand -base64 32 | tr -d '\n')  # Self-generated
   ENABLE_GOOGLE_AUTH=true  # Optional: Enable Google login/signup
   ```

### GitHub OAuth Setup

**Used for**: GitHub login/signup

1. **Create GitHub OAuth App**
   - Go to **Settings** → **Developer settings** → **OAuth Apps**
   - Click **New OAuth App**

2. **Configure Application**
   ```
   Application name: LockMyCal
   Homepage URL: https://your-domain.com
   Authorization callback URL: https://your-domain.com/auth/github/callback
   ```

3. **Configure Environment Variables**
   ```bash
   GITHUB_CLIENT_ID=<your_github_client_id>
   GITHUB_CLIENT_SECRET=<your_github_client_secret>
   ENABLE_GITHUB_AUTH=true  # Optional: Enable GitHub login/signup
   ```

### Microsoft OAuth Setup (Outlook Calendar & Teams)

**Important**: Both Outlook Calendar and Microsoft Teams use the **same** OAuth app. Configure this once to enable both integrations.

**Used for**: Outlook Calendar integration, Microsoft Teams video integration, and (optionally) Microsoft login/signup

1. **Create Azure AD App Registration**
   - Go to [Azure Portal](https://portal.azure.com/)
   - Navigate to **Microsoft Entra ID** (formerly Azure Active Directory)
   - Go to **App registrations** → **New registration**

2. **Configure Application**
   ```
   Name: LockMyCal
   Supported account types: Accounts in any organizational directory and personal Microsoft accounts
   Redirect URI: Leave blank for now (we'll add both URIs in the next step)
   ```
   - Click **Register**

3. **Configure Redirect URIs**
   - In your app registration, go to **Authentication**
   - Click **Add a platform** → **Web**
   - Add **BOTH** redirect URIs (both are required for full functionality):
     ```
     https://your-domain.com/auth/outlook/calendar/callback
     https://your-domain.com/auth/teams/video/callback
     ```
   - If you enable Microsoft login/signup (`ENABLE_MICROSOFT_AUTH=true`), also add:
     ```
     https://your-domain.com/auth/microsoft/callback
     ```
   - Leave **Access tokens** and **ID tokens** under **Implicit grant and hybrid flows** unchecked: every flow uses the authorization code flow, which gets its ID token from the token endpoint
   - Click **Save**

4. **Configure API Permissions**
   - Go to **API permissions** → **Add a permission** → **Microsoft Graph**
   - Select **Delegated permissions** and add the following:
     ```
     Calendars.ReadWrite - Read and write to user calendars
     User.Read - Sign in and read user profile
     offline_access - Maintain access to data you have given it access to
     openid - Sign users in
     profile - View users' basic profile
     email - View users' email address (Microsoft login)
     ```
   - Click **Add permissions**
   - (Optional) Click **Grant admin consent** if deploying for an organization

5. **Create Client Secret**
   - Go to **Certificates & secrets** → **Client secrets**
   - Click **New client secret**
   - Add a description (e.g., "LockMyCal Production")
   - Choose an expiration period (recommendation: 24 months, set a reminder to rotate before expiry)
   - Click **Add**
   - **Important**: Copy the **Value** immediately (this is your `OUTLOOK_CLIENT_SECRET`) - you won't be able to see it again!

6. **Get Application (client) ID**
   - Go to **Overview**
   - Copy the **Application (client) ID** (this is your `OUTLOOK_CLIENT_ID`)

7. **Configure Environment Variables**
   ```bash
   OUTLOOK_CLIENT_ID=<your_application_client_id>
   OUTLOOK_CLIENT_SECRET=<your_client_secret_value>
   OUTLOOK_STATE_SECRET=$(openssl rand -base64 32 | tr -d '\n')  # Self-generated
   ```

**Note**: The `STATE_SECRET` variables (GOOGLE_STATE_SECRET, OUTLOOK_STATE_SECRET) are self-generated random strings for security (CSRF protection). They are NOT provided by Google or Microsoft. Generate them using the openssl command shown above.

---

## Production Checklist

- [ ] **SSL/TLS certificate** configured (via reverse proxy)
- [ ] **Domain name** pointing to your server
- [ ] **Strong secrets** generated for all passwords and keys
- [ ] **Environment variables** validated and set correctly
- [ ] **Email service** configured (REQUIRED - Postmark or SMTP)
  - [ ] Test password reset functionality
  - [ ] Verify booking confirmation emails work
- [ ] **OAuth providers** configured (if needed)
- [ ] **Firewall** configured appropriately
- [ ] **Backups** scheduled for Docker volumes

---

## Further documentation

The online docs at **<https://learn.lockmycal.com/en>** stay in lock-step with each release. The articles most relevant to self-hosting:

- [Docker deployment](https://learn.lockmycal.com/en/self-hosting/docker) — this guide, online
- [Environment Variable Reference](https://learn.lockmycal.com/en/self-hosting/environment-variables) — every supported variable
- [Reverse Proxy Setup](https://learn.lockmycal.com/en/self-hosting/reverse-proxy) — Nginx & Caddy with SSL
- [Backup & Restore](https://learn.lockmycal.com/en/self-hosting/backup-restore) — protecting your data volumes
- [Upgrading](https://learn.lockmycal.com/en/self-hosting/upgrading) — moving between versions safely
- [SMTP](https://learn.lockmycal.com/en/self-hosting/environment-variables) / [Postmark](https://learn.lockmycal.com/en/notifications-automation/email-postmark) — email delivery
- [MiroTalk](https://learn.lockmycal.com/en/video-conferencing/mirotalk) · [Jitsi Meet](https://learn.lockmycal.com/en/video-conferencing/jitsi-meet) · [Nextcloud Talk](https://learn.lockmycal.com/en/video-conferencing/nextcloud-talk) · [kMeet](https://learn.lockmycal.com/en/video-conferencing/kmeet) · [Custom video link](https://learn.lockmycal.com/en/video-conferencing/custom-video-link)
- [Generic OIDC / SSO](https://learn.lockmycal.com/en/account-administration/oidc-sso) · [reCAPTCHA](https://learn.lockmycal.com/en/self-hosting/recaptcha) · [Telegram](https://learn.lockmycal.com/en/notifications-automation/telegram-slack)

---

## Support

### Getting Help

- **Check logs first**: `docker logs tymeslot`
- **GitHub Issues**: Report bugs and feature requests
- **Documentation**: Review error messages and this guide

### Useful Commands

```bash
# Container information
docker inspect tymeslot

# Container resource usage
docker stats tymeslot --no-stream

# Copy files to/from container
docker cp file.txt tymeslot:/app/
docker cp tymeslot:/app/logs/ ./logs/

# Check health
curl http://localhost:4000/healthcheck
```

---

## Next Steps

1. **Create your first user account**
2. **Test email functionality** (use "Forgot Password" to verify emails are working)
3. Configure your profile and availability
4. Connect calendar integrations (Google Calendar, Outlook)
5. Share your booking link: `http://your-domain.com/your-username`
6. Configure OAuth providers (optional)

---

**Congratulations!** 🎉 LockMyCal is now running in Docker.
