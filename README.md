# Docker WordPress Starter

A reusable Docker Compose starter for WordPress with nginx and Let's Encrypt.

This repository contains a minimal public-ready stack for running WordPress in Docker:

- `mariadb` for the database
- `wordpress` PHP-FPM application container
- `nginx` web server with HTTPS support
- `certbot` for obtaining and renewing Let's Encrypt certificates

It now supports two deployment modes:

- Single-site mode (original setup, unchanged)
- Multi-site mode (two fully separate WordPress installs, same server, not WordPress multisite)

> The project is intentionally configured as a reusable starter. It does not ship WordPress core content in `html/` and it uses placeholder domain names that must be updated before deployment.

---

## Repository structure

- `docker-compose.yml` - Docker Compose stack definition
- `docker-compose.multi.yml` - two-site stack definition
- `nginx.conf.template` - nginx template rendered from env variables
- `nginx-multi.conf.template` - nginx template for two-site HTTPS routing
- `nginx-multi-http.conf.template` - nginx template for two-site HTTP routing
- `certbot/run-certbot.sh` - certificate issuance script
- `certbot/run-certbot-multi.sh` - certificate issuance for two-site mode
- `.env.example` - required environment variables
- `certbot/conf/` - certificate storage directory (runtime data)
- `html/` - WordPress site volume mount point
- `php/uploads.ini` - custom PHP upload settings
- `.gitignore` - runtime artifacts excluded from Git

---

## Prerequisites

- Docker Engine
- Docker Compose v2 (`docker compose`)
- DNS records for your domain pointing to the host
- Ports `80` and `443` open on the host

---

## Before you start

Create your env file and update values:

```bash
cp .env.example .env
```

Set at least:

- `DOMAIN` (example: `example.com`)
- `WWW_DOMAIN` (example: `www.example.com`)
- `LETSENCRYPT_EMAIL`
- `WORDPRESS_VERSION` (example: `6.9.4`)
- `PHP_VERSION` (example: `8.3`)
- database and WordPress DB credentials

---

## WordPress and PHP version selection

This project now builds the WordPress image tag from:

- `WORDPRESS_VERSION`
- `PHP_VERSION`

Compose pattern used:

```text
wordpress:${WORDPRESS_VERSION}-php${PHP_VERSION}-fpm
```

Recommended defaults:

- `WORDPRESS_VERSION=6.9.4`
- `PHP_VERSION=8.3`

Practical compatibility guide (for `PHP 7.4` to `8.3`):

| PHP version | Use with WordPress | Recommendation |
|---|---|---|
| 8.3 | 6.8+ (fully compatible in current handbook) | Best choice |
| 8.2 | 6.5+ | Safe choice |
| 8.1 | 6.4+ | Safe choice |
| 8.0 | 6.4+ | Acceptable, but older |
| 7.4 | 6.4+ still supports it | Legacy only, upgrade planned |

Important notes:

- WordPress core support and plugin/theme support are different; newer PHP can still break old plugins.
- `php7.4` Docker tags are old/unmaintained compared with `8.x`; use only for legacy migrations.
- If a specific tag combination does not exist on Docker Hub, `docker compose up` will fail to pull.

References:

- WordPress PHP compatibility matrix: https://make.wordpress.org/core/handbook/references/php-compatibility-and-wordpress-versions/
- WordPress Docker tags: https://hub.docker.com/_/wordpress/tags

---

## Quick start

From the project root:

```bash
docker compose up -d
```

One-command HTTPS bootstrap:

```bash
sh bootstrap-https.sh
```

Issue or renew TLS certificates:

```bash
sh certbot/run-certbot.sh
```

You can override email at runtime:

```bash
sh certbot/run-certbot.sh you@example.com
```

Restart nginx after certificates are created or renewed:

```bash
docker compose restart nginx
```

Visit `https://your-domain` after setting env values.

---

## Choose your mode

### Mode A: Single website (existing behavior)

Use the existing workflow:

```bash
docker compose up -d
sh bootstrap-https.sh
```

This uses:

- `docker-compose.yml`
- `DOMAIN` and `WWW_DOMAIN`

### Mode B: Two separate websites on same server (not multisite)

Use the dedicated multi-file stack:

```bash
docker compose -f docker-compose.multi.yml up -d
sh certbot/run-certbot-multi.sh
docker compose -f docker-compose.multi.yml restart nginx_multi
```

This mode runs:

- `wordpress_site1` + `mariadb_site1` with content in `html/site1`
- `wordpress_site2` + `mariadb_site2` with content in `html/site2`
- one public nginx (`nginx_multi`) on ports `80/443` routing by hostname

Required multi-mode env variables:

- `SITE1_DOMAIN`, `SITE1_WWW_DOMAIN`
- `SITE2_DOMAIN`, `SITE2_WWW_DOMAIN`
- `SITE1_*` DB credentials
- `SITE2_*` DB credentials

Important:

- Do not run single-site and multi-site stacks at the same time on one host because both need ports `80` and `443`.
- This is two independent WordPress installs, not WP multisite.

---

## From-scratch server setup process

1. Install Docker + Compose on server.
2. Clone repo into server directory (example: `/home/wp-fpm`).
3. Copy env template: `cp .env.example .env`.
4. Edit `.env` with real values:
   - `DOMAIN=yourdomain.com`
   - `WWW_DOMAIN=www.yourdomain.com`
   - `LETSENCRYPT_EMAIL=you@domain.com`
   - `WORDPRESS_VERSION=6.9.4`
   - `PHP_VERSION=8.3`
   - DB passwords/users
5. Point DNS `A` records (`@` and `www`) to server public IP.
6. Open inbound ports `80` and `443` in cloud firewall/security group.
7. Start stack: `docker compose up -d`.
8. Bootstrap HTTPS: `sh bootstrap-https.sh`.
9. Verify:
   - `docker compose ps` (all Up)
   - `docker compose logs --tail=100 nginx`
   - visit `https://yourdomain.com`
10. For renewals later:
    - `sh certbot/run-certbot.sh`
    - `docker compose restart nginx`

---

## How it works

- `html/` is mounted into both the `wordpress` and `nginx` containers.
- The official WordPress image initializes site files into `html/` when the volume is empty.
- nginx uses `nginx.conf.template` and Docker's env substitution at container startup.
- `certbot/run-certbot.sh` reads `.env` and requests certs for both `DOMAIN` and `WWW_DOMAIN`.

---

## Persistence

- MariaDB data is stored in the named volume `db_data`
- Certificates are stored in `certbot/conf/`
- WordPress files are created inside `html/`

---

## Troubleshooting

- `docker compose ps`
- `docker compose logs nginx`
- `docker compose logs certbot`
- verify DNS and port access
- `docker compose exec nginx nginx -t` to validate generated config
- if Certbot reports `Connection refused`, confirm nginx is `Up` and host/security-group allows inbound `80/tcp`

---

## License

This repository is intentionally generic and ready to adapt to your own project. Choose a license before publishing.
