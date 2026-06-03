# Docker WordPress Starter

<p align="center">
  <a href="https://github.com/kdeelz69/wp-fpm-docker">
    <img alt="Repo views" src="https://komarev.com/ghpvc/?username=kdeelz69-wp-fpm-docker&label=repo%20views&color=0e75b6&style=for-the-badge">
  </a>
  <a href="https://github.com/kdeelz69/wp-fpm-docker/stargazers">
    <img alt="GitHub stars" src="https://img.shields.io/github/stars/kdeelz69/wp-fpm-docker?style=for-the-badge&logo=github&label=stars">
  </a>
  <a href="https://github.com/kdeelz69/wp-fpm-docker/forks">
    <img alt="GitHub forks" src="https://img.shields.io/github/forks/kdeelz69/wp-fpm-docker?style=for-the-badge&logo=github&label=forks">
  </a>
  <a href="https://github.com/kdeelz69/wp-fpm-docker/watchers">
    <img alt="GitHub watchers" src="https://img.shields.io/github/watchers/kdeelz69/wp-fpm-docker?style=for-the-badge&logo=github&label=watchers">
  </a>
  <a href="https://github.com/kdeelz69/wp-fpm-docker/commits/main">
    <img alt="Last commit" src="https://img.shields.io/github/last-commit/kdeelz69/wp-fpm-docker?style=for-the-badge&logo=git&label=last%20commit">
  </a>
  <a href="https://github.com/kdeelz69/wp-fpm-docker/archive/refs/heads/main.zip">
    <img alt="Git clone" src="https://img.shields.io/badge/git%20clone-ready-2ea44f?style=for-the-badge&logo=git">
  </a>
  <img alt="Repo size" src="https://img.shields.io/github/repo-size/kdeelz69/wp-fpm-docker?style=for-the-badge&label=repo%20size">
  <img alt="License" src="https://img.shields.io/github/license/kdeelz69/wp-fpm-docker?style=for-the-badge&label=license">
</p>

A reusable Docker Compose starter for WordPress with nginx and Let's Encrypt.

This repository contains a minimal public-ready stack for running WordPress in Docker:

- `mariadb` for the database
- `wordpress` PHP-FPM application container
- `nginx` web server with HTTPS support
- `certbot` for obtaining and renewing Let's Encrypt certificates

> The project is intentionally configured as a reusable starter. It does not ship WordPress core content in `html/` and it uses placeholder domain names that must be updated before deployment.

---

## Repository structure

- `docker-compose.yml` - Docker Compose stack definition
- `nginx.conf.template` - nginx template rendered from env variables
- `certbot/run-certbot.sh` - certificate issuance script
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
- WordPress install credentials:
  - `WORDPRESS_URL`
  - `WORDPRESS_SITE_TITLE`
  - `WORDPRESS_ADMIN_USER`
  - `WORDPRESS_ADMIN_PASSWORD`
  - `WORDPRESS_ADMIN_EMAIL`

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

On first startup, the `wpcli` service automatically installs WordPress using
the admin details from `.env`. If WordPress is already installed, it exits
without changing the site.

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
   - `WORDPRESS_URL=https://yourdomain.com`
   - `WORDPRESS_SITE_TITLE="Your Site Name"`
   - `WORDPRESS_ADMIN_USER=your_admin_user`
   - `WORDPRESS_ADMIN_PASSWORD=your_strong_admin_password`
   - `WORDPRESS_ADMIN_EMAIL=you@domain.com`
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
- The `wpcli` service waits for WordPress files and MariaDB, then runs a one-time
  `wp core install` if the site has not already been installed.
- nginx uses `nginx.conf.template` and Docker's env substitution at container startup.
- `certbot/run-certbot.sh` reads `.env` and requests certs for both `DOMAIN` and `WWW_DOMAIN`.

---

## Database restore with HeidiSQL

MariaDB is exposed on the host loopback address by default:

```env
MYSQL_BIND_ADDRESS=127.0.0.1
MYSQL_PORT=3306
```

Use HeidiSQL with an SSH tunnel to the server, then connect to:

```text
Host: 127.0.0.1
Port: 3306
User: value of MYSQL_USER
Password: value of MYSQL_PASSWORD
Database: value of MYSQL_DATABASE
```

Avoid setting `MYSQL_BIND_ADDRESS=0.0.0.0` on a public server unless the port is
strictly firewalled to your IP.

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
