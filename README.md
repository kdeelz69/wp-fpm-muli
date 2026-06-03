# WordPress Multi-Site Docker Deployment

Deploy multiple WordPress FPM sites on one server without the second deployment
changing the first site.

This repo uses:

- one main public web entry for ports `80` and `443`
- one isolated WordPress stack per website
- one MariaDB volume per website
- automatic HTTPS certificates

## Folder Layout

```text
proxy/                  main public web entry + SSL certificate service
sites/site-template/    template copied for each WordPress site
deploy-site.sh          helper script to create and start site stacks
```

The main public web entry is the only part exposed to the internet. It receives
traffic for all domains and sends each request to the correct WordPress website.

The old root `docker-compose.yml` is still kept for single-site testing, but for
two or more websites use the `proxy/` and `sites/` layout.

## Requirements

On the server:

- Docker Engine
- Docker Compose v2
- DNS records pointing to the server IP
- inbound ports `80` and `443` open

Example DNS:

```text
example.com      -> server public IP
www.example.com  -> server public IP
second.com       -> server public IP
www.second.com   -> server public IP
```

## Deploy First Site

From the repository root:

```bash
sh deploy-site.sh
```

Choose:

```text
1) Add a new website or update an existing website
```

The script asks for:

- site folder, for example `site-one`
- Compose project name, for example `site_one`
- domain and `www` domain
- primary domain
- Let's Encrypt email
- WordPress title and admin login
- database passwords

For the first site, answer yes when it asks:

```text
Set up the main public web entry too? Choose yes for the first website on this server
```

You can also run the direct command:

```bash
sh deploy-site.sh site-one site_one --start-proxy
```

The script creates:

```text
proxy/.env
sites/site-one/.env
sites/site-one/
```

If the site `.env` already exists with placeholder values, the script asks if it
should replace it using guided questions. You can also edit it manually:

```bash
nano sites/site-one/.env
```

Set real values:

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

MYSQL_ROOT_PASSWORD=change_this_root_password
MYSQL_DATABASE=wordpress
MYSQL_USER=wordpress
MYSQL_PASSWORD=change_this_db_password

WORDPRESS_DB_NAME=wordpress
WORDPRESS_DB_USER=wordpress
WORDPRESS_DB_PASSWORD=change_this_db_password
```

Start the proxy and first site:

```bash
sh deploy-site.sh site-one site_one --start-proxy
```

During deployment the script checks DNS. If it says the domain does not resolve
to the server IP yet, fix your DNS `A` records first:

```text
example.com      -> server public IP
www.example.com  -> server public IP
```

Containers can start before DNS is correct, but HTTPS and public browser access
will not work until DNS points to the server.

When the script asks for the server public IP, press Enter to use the detected
IP unless you know it is wrong. Do not enter the domain name in that prompt.

Check containers:

```bash
cd proxy
docker compose ps

cd ../sites/site-one
docker compose -p site_one ps
```

Visit:

```text
https://www.example.com
```

## Deploy Second Site Later

From the repository root:

```bash
sh deploy-site.sh
```

Choose:

```text
1) Add a new website or update an existing website
```

Use a different site folder and Compose project name:

```text
Site folder: site-two
Compose project name: site_two
```

Answer no when it asks to set up the main public web entry, because it is
already running from the first site.

You can also run the direct command:

```bash
sh deploy-site.sh site-two site_two
```

Edit the second site settings manually if needed:

```bash
nano sites/site-two/.env
```

Example:

```env
DOMAIN=second.com
WWW_DOMAIN=www.second.com
PRIMARY_DOMAIN=www.second.com
LETSENCRYPT_EMAIL=you@example.com

WORDPRESS_URL=https://www.second.com
WORDPRESS_SITE_TITLE="Second Site"
WORDPRESS_ADMIN_USER=admin
WORDPRESS_ADMIN_PASSWORD=change_this_password
WORDPRESS_ADMIN_EMAIL=you@example.com

MYSQL_ROOT_PASSWORD=change_this_root_password
MYSQL_PASSWORD=change_this_db_password
WORDPRESS_DB_PASSWORD=change_this_db_password
```

Start only the second site:

```bash
sh deploy-site.sh site-two site_two
```

This does not recreate or modify `site_one` containers, files, or database
volumes. The main public web entry detects the new website container and updates
routing.

## Important Rules

- Use a unique folder per site: `site-one`, `site-two`, etc.
- Use a unique Compose project per site: `site_one`, `site_two`, etc.
- Do not publish ports `80` or `443` from individual site stacks.
- Start the main public web entry once, then leave it running.
- Do not reuse the same database passwords between sites unless you intentionally want that.
- Make sure `DOMAIN`, `WWW_DOMAIN`, and `WORDPRESS_URL` match the real domain.

## Update One Site

Update only site one:

```bash
cd sites/site-one
docker compose -p site_one pull
docker compose -p site_one up -d
```

Update only site two:

```bash
cd sites/site-two
docker compose -p site_two pull
docker compose -p site_two up -d
```

## Stop One Site

Stop site two without touching site one:

```bash
cd sites/site-two
docker compose -p site_two down
```

Do not add `-v` unless you want to delete that site's database volume.

## Logs

Main public web entry logs:

```bash
cd proxy
docker compose logs --tail=100 nginx-proxy
docker compose logs --tail=100 acme-companion
```

Site logs:

```bash
cd sites/site-one
docker compose -p site_one logs --tail=100 nginx
docker compose -p site_one logs --tail=100 wordpress
docker compose -p site_one logs --tail=100 mariadb
docker compose -p site_one logs --tail=100 wpcli
```

## Script Menu

Run:

```bash
sh deploy-site.sh
```

Menu options:

```text
1) Add a new website or update an existing website
2) Start the main public web entry only
3) Check if a website domain points to this server
4) Retry SSL certificate after fixing DNS
5) Show running status
0) Exit
```

Use option `3` after changing DNS records. Use option `4` after DNS is correct
if HTTPS was previously failing.

## Troubleshooting

If HTTPS is not issued:

```bash
cd proxy
docker compose logs --tail=200 acme-companion
```

Check:

- DNS points to this server
- ports `80` and `443` are open
- `DOMAIN` and `WWW_DOMAIN` are hostnames only, not URLs
- the site nginx container is running

If WordPress does not install:

```bash
cd sites/site-one
docker compose -p site_one logs --tail=200 wpcli
docker compose -p site_one logs --tail=200 mariadb
```

If image pull fails, check that this Docker tag exists:

```text
wordpress:${WORDPRESS_VERSION}-php${PHP_VERSION}-fpm
```

Example:

```text
wordpress:6.9.4-php8.3-fpm
```

## Manual Commands

The helper script replaces this manual flow:

```bash
mkdir -p sites/site-one
cp -a sites/site-template/. sites/site-one/
cd sites/site-one
cp .env.example .env
nano .env
docker compose -p site_one up -d
```

Use the script instead:

```bash
sh deploy-site.sh site-one site_one --start-proxy
sh deploy-site.sh site-two site_two
```
