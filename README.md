# WordPress Multi-Site Docker Deployment

Run multiple WordPress sites on one small VPS (about 2 GB RAM / 2 CPU) without
later deployments breaking earlier sites.

One shared reverse proxy and database serve every site. Each website still gets
its own folder, containers, database, and database user.

## How it works

```text
Internet :80 / :443
        |
        v
  proxy/  (nginx-proxy + SSL + shared MariaDB)
        |
        +--> sites/site-one/  (WordPress + internal nginx)
        |
        +--> sites/site-two/  (WordPress + internal nginx)
```

| Component | Location | Role |
|-----------|----------|------|
| Public web entry | `proxy/` | Only stack that publishes ports `80` and `443` |
| SSL certificates | `proxy/` (acme-companion + ZeroSSL) | Issues HTTPS for every site domain |
| Shared database | `proxy/` (MariaDB) | One container; separate DB per website |
| Website stack | `sites/<name>/` | WordPress FPM, wp-cli installer, internal nginx |

Traffic flow: browser → shared nginx-proxy → site nginx → WordPress PHP-FPM →
shared MariaDB.

## Requirements

On the server:

- Docker Engine (official install, not Snap)
- Docker Compose v2 (`docker compose version`)
- DNS `A` records for each domain pointing to the server public IP
- Inbound ports `80` and `443` open in the cloud firewall

Recommended before the first deploy:

```bash
docker login
```

A free Docker Hub account raises anonymous pull rate limits and avoids flaky
image downloads on small VPS instances.

## Server setup (one time)

### 1. Install Docker

Use the official Docker Engine install guide for your Linux distribution:
https://docs.docker.com/engine/install/

Verify:

```bash
docker --version
docker compose version
which docker    # should be /usr/bin/docker, not /snap/bin/docker
```

### 2. Clone this repository

```bash
cd /home
git clone <your-repo-url> wp-fpm
cd wp-fpm
```

### 3. Log in to Docker Hub (recommended)

```bash
docker login
```

### 4. Open firewall ports

Allow inbound TCP `80` and `443` to the server (AWS Lightsail networking,
security group, ufw, etc.).

### 5. Point DNS to the server

For each website:

```text
example.com      A  -> 52.x.x.x
www.example.com  A  -> 52.x.x.x
```

## Deploy the first website

From the repository root:

```bash
sh deploy-site.sh
```

Choose **1) Add a new website or update an existing website**.

### Prompts

| Prompt | Example | Notes |
|--------|---------|-------|
| Site folder | `modernpack` | Simple folder name under `sites/` |
| Compose project name | `modernpack` | Lowercase; used by Docker Compose |
| Start proxy? | **yes** | Required for the **first** site on this server |
| Server public IP | press Enter | Uses auto-detected IP for DNS check |
| Apex domain | `modernpack.lk` | No `https://` prefix |
| WWW domain | `www.modernpack.lk` | |
| Primary domain | `www.modernpack.lk` | Used for `WORDPRESS_URL` |
| SSL email | `you@example.com` | ZeroSSL / Let's Encrypt contact |
| WordPress title / admin / DB values | your choice | Saved to `sites/<folder>/.env` |

Direct command (same as the guided flow):

```bash
sh deploy-site.sh modernpack modernpack --start-proxy
```

### What the script does

1. Creates `sites/<folder>/` from `sites/site-template/` if needed
2. Writes or updates `sites/<folder>/.env` and `proxy/.env`
3. Checks DNS for apex and `www` domains
4. **Pulls Docker images one at a time with retries** (avoids Hub rate-limit errors)
5. Starts `proxy/` (nginx-proxy, SSL companion, MariaDB) on first deploy
6. Creates the website database and user in shared MariaDB
7. Pulls site images, then starts the website stack
8. Runs wp-cli to install WordPress and fixes upload folder permissions

You do **not** need to run `docker pull` manually. The deploy script handles it.

### Verify

```bash
cd proxy
docker compose ps

cd ../sites/modernpack
docker compose -p modernpack ps
```

Expected:

- **proxy:** `shared_nginx_proxy`, `shared_acme_companion`, `shared_mariadb` — Up
- **site:** `wordpress`, `nginx` — Up; `wpcli` — exited (install finished)

Open `https://www.example.com` in a browser. SSL may take a few minutes on
first deploy.

## Deploy a second website

The proxy stack already runs after the first site. **Do not** start it again.

```bash
sh deploy-site.sh
```

Choose **1**, use a **new** site folder and compose project name, and answer
**no** when asked to set up the main public web entry.

```bash
sh deploy-site.sh site-two site_two
```

Each site needs a unique:

- folder name (`site-one`, `site-two`, …)
- compose project name (`site_one`, `site_two`, …)
- database name and database user

## Script menu

```bash
sh deploy-site.sh
```

| Option | Purpose |
|--------|---------|
| 1 | Add or update a website |
| 2 | Start the proxy stack only |
| 3 | Check DNS for a site |
| 4 | Retry SSL after DNS is fixed |
| 5 | Fix WordPress upload / migration folder permissions |
| 6 | Show running status |
| 0 | Exit |

## Configuration files

After the first deploy:

```text
proxy/.env                 SHARED_MYSQL_ROOT_PASSWORD, DEFAULT_EMAIL
sites/<folder>/.env        domain, WordPress, and database settings
```

Example `sites/<folder>/.env`:

```env
DOMAIN=example.com
WWW_DOMAIN=www.example.com
PRIMARY_DOMAIN=www.example.com
LETSENCRYPT_EMAIL=you@example.com

WORDPRESS_VERSION=6.9.4
PHP_VERSION=8.3
WORDPRESS_URL=https://www.example.com
WORDPRESS_SITE_TITLE="Example Site"
WORDPRESS_ADMIN_USER=admin
WORDPRESS_ADMIN_PASSWORD=change_this_password
WORDPRESS_ADMIN_EMAIL=you@example.com

WORDPRESS_DB_NAME=site_one_db
WORDPRESS_DB_USER=site_one_user
WORDPRESS_DB_PASSWORD=change_this_db_password
```

Rules:

- `DOMAIN`, `WWW_DOMAIN`, and `PRIMARY_DOMAIN` are hostnames only — not URLs
- `WORDPRESS_URL` must include `https://` and match `PRIMARY_DOMAIN`
- Do not publish ports `80` or `443` from individual site stacks
- Do not expose MariaDB publicly (`proxy/.env` binds MySQL to `127.0.0.1` by default)

## Day-to-day operations

### Update one website

```bash
cd sites/site-one
docker compose -p site_one pull
docker compose -p site_one up -d
```

Or rerun the deploy script (it will pull images with retries automatically):

```bash
sh deploy-site.sh site-one site_one
```

### Stop one website (others keep running)

```bash
cd sites/site-two
docker compose -p site_two down
```

Do not add `-v` unless you know which volumes will be removed. Shared MariaDB
data lives in the `proxy/` stack.

### View logs

Proxy and shared database:

```bash
cd proxy
docker compose logs --tail=100 nginx-proxy
docker compose logs --tail=100 acme-companion
docker compose logs --tail=100 mariadb
```

Website:

```bash
cd sites/site-one
docker compose -p site_one logs --tail=100 nginx
docker compose -p site_one logs --tail=100 wordpress
docker compose -p site_one logs --tail=200 wpcli
```

## Troubleshooting

### Docker image pull fails (`auth.docker.io`, `404`, `timeout`)

The deploy script pulls images **sequentially with retries** and then runs
`docker compose up --pull never` so Compose does not re-pull in parallel.

If deploy still fails:

```bash
docker login
sh deploy-site.sh <site-folder> <compose-project>
```

Test Docker Hub from the server:

```bash
curl -sS -o /dev/null -w "%{http_code}\n" \
  "https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/nginx:pull"
```

Expected: `200`. If not, fix DNS and restart Docker:

```bash
sudo tee /etc/resolv.conf <<'EOF'
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
sudo systemctl restart docker
```

Increase pull retries (optional):

```bash
DOCKER_PULL_RETRIES=8 sh deploy-site.sh modernpack modernpack
```

### Proxy started but site stack failed

Proxy and database may already be running. Finish the site without `--start-proxy`:

```bash
sh deploy-site.sh modernpack modernpack
```

### HTTPS not issued

```bash
cd proxy
docker compose logs --tail=200 acme-companion
```

Check:

- DNS points to this server
- Ports `80` and `443` are open
- Site nginx container is running

After fixing DNS, use menu option **4** or:

```bash
cd proxy && docker compose restart acme-companion
```

### WordPress not installed / wpcli errors

```bash
cd sites/site-one
docker compose -p site_one logs --tail=200 wpcli
cd ../../proxy
docker compose logs --tail=200 mariadb
```

If logs show `Access denied for user`, fix `sites/<folder>/.env` and rerun:

```bash
sh deploy-site.sh site-one site_one
```

### MariaDB root `Access denied` when creating database

The shared MariaDB volume was initialized with a different root password. On a
**fresh** server with no data to keep:

```bash
cd proxy
docker compose down -v
docker compose up -d
```

On a **live** server, use the original `SHARED_MYSQL_ROOT_PASSWORD` from
`proxy/.env`. Never run `docker compose down -v` in `proxy/` on production unless
you intend to delete **all** website databases.

### Plugin cannot write uploads or migration files

```bash
sh deploy-site.sh
```

Choose **5) Fix WordPress upload/import permissions**.

### Invalid WordPress image tag

Confirm the tag exists on Docker Hub:

```text
wordpress:${WORDPRESS_VERSION}-php${PHP_VERSION}-fpm
```

Example: `wordpress:6.9.4-php8.3-fpm`

## Important rules

- Start the proxy stack **once** (first website), then leave it running
- Never start a second proxy stack for additional sites
- One unique folder, compose project, database name, and DB user per website
- Do not run `docker compose down -v` in `proxy/` on a live server without a backup plan

## Related docs

- `wordpress-site-db-import-runbook.md` — import an existing WordPress database
- `deploy-site.sh help` — command-line usage
