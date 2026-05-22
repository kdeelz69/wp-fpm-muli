# Docker WordPress Starter

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
- database and WordPress DB credentials

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
