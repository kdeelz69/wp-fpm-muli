# WordPress Multi-Site Docker Deployment

Deploy multiple WordPress FPM sites on one small server without the second
deployment changing the first site.

This layout is tuned for a 2 GB RAM / 2 CPU server:

- one main public web entry for ports `80` and `443`
- one SSL certificate service using ZeroSSL
- one shared MariaDB container
- one separate database and database user per website
- one WordPress container per website
- one internal nginx container per website

## Folder Layout

```text
proxy/                  main public web entry, SSL service, shared MariaDB
sites/site-template/    template copied for each WordPress site
deploy-site.sh          guided deployment script
```

The main public web entry is the only part exposed to the internet. It receives
traffic for all domains and sends each request to the correct WordPress website.

MariaDB is shared to reduce RAM usage. Each website still gets its own database
and database user inside the shared MariaDB container.

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

## Deploy First Website

From the repository root:

```bash
sh deploy-site.sh
```

Choose:

```text
1) Add a new website or update an existing website
```

The script asks for:

- website folder, for example `site-one`
- Compose project name, for example `site_one`
- domain and `www` domain
- primary domain
- SSL certificate email
- WordPress title and admin login
- website database name, username, and password

For the first website, answer yes when it asks:

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

Example site `.env` values:

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

During deployment the script checks DNS. If it says the domain does not resolve
to the server IP yet, fix your DNS `A` records first:

```text
example.com      -> server public IP
www.example.com  -> server public IP
```

When the script asks for the server public IP, press Enter to use the detected
IP unless you know it is wrong. Do not enter the domain name in that prompt.

Check containers:

```bash
cd proxy
docker compose ps

cd ../sites/site-one
docker compose -p site_one ps
```

## Deploy Second Website Later

Do not create another main public web entry for the second website. The first
website already started it, and the same entry is reused for every website on
the server.

From the repository root:

```bash
sh deploy-site.sh
```

Choose:

```text
1) Add a new website or update an existing website
```

Use a different website folder, Compose project name, database name, and
database user:

```text
Site folder: site-two
Compose project name: site_two
Website database name: site_two_db
Website database username: site_two_user
```

Answer no when it asks to set up the main public web entry:

```text
Set up the main public web entry too? Choose yes for the first website on this server [y/N]: N
```

You can also run:

```bash
sh deploy-site.sh site-two site_two
```

This does not recreate or modify `site_one` containers, files, or database data.
The script creates a new database and database user inside the shared MariaDB
container for `site_two`.

## Important Rules

- Start the main public web entry once for the first website, then leave it running.
- Do not create a second main public web entry for the second website.
- Use a unique folder per website: `site-one`, `site-two`, etc.
- Use a unique Compose project per website: `site_one`, `site_two`, etc.
- Use a unique database name and database user per website.
- Do not publish ports `80` or `443` from individual website stacks.
- Do not expose MariaDB ports publicly.
- Do not reuse database passwords between websites unless you intentionally want that.
- Make sure `DOMAIN`, `WWW_DOMAIN`, and `WORDPRESS_URL` match the real domain.

## Update One Website

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

## Stop One Website

Stop site two without touching site one:

```bash
cd sites/site-two
docker compose -p site_two down
```

Do not add `-v` unless you understand exactly which volumes will be removed.
The shared MariaDB data is in the `proxy/` stack, not the site stack.

## Logs

Main public web entry and shared database logs:

```bash
cd proxy
docker compose logs --tail=100 nginx-proxy
docker compose logs --tail=100 acme-companion
docker compose logs --tail=100 mariadb
```

Website logs:

```bash
cd sites/site-one
docker compose -p site_one logs --tail=100 nginx
docker compose -p site_one logs --tail=100 wordpress
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
5) Fix WordPress upload/import permissions
6) Show running status
0) Exit
```

Use option `3` after changing DNS records. Use option `4` after DNS is correct
if HTTPS was previously failing.

Use option `5` if plugins such as All-in-One WP Migration cannot read or write
backup/import files. It safely fixes writable WordPress folders using
`www-data:www-data`, not `777`.

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
- the website nginx container is running

If WordPress does not install:

```bash
cd sites/site-one
docker compose -p site_one logs --tail=200 wpcli

cd ../../proxy
docker compose logs --tail=200 mariadb
```

If `wpcli` shows `Access denied for user`, check that the site's `.env` database
values are correct:

```env
WORDPRESS_DB_NAME=site_one_db
WORDPRESS_DB_USER=site_one_user
WORDPRESS_DB_PASSWORD=your_db_password
```

Then rerun the deploy script so it creates or updates that database user:

```bash
sh deploy-site.sh site-one site_one
```

Do not run `docker compose down -v` in the `proxy/` folder on a live server
unless you intend to delete the shared MariaDB data for all websites.

If All-in-One WP Migration or another plugin reports that it cannot open a file
inside `wp-content`, fix permissions from the menu:

```bash
sh deploy-site.sh
```

Choose:

```text
5) Fix WordPress upload/import permissions
```

The deploy script also runs this permission repair automatically after a
successful website deployment.

If the deploy script says `Access denied for user 'root'@'localhost'` while
creating the database, the shared MariaDB root login is not ready yet or the
`proxy_db_data` volume was already initialized with a different root password.
For a fresh server with no real website data, reset the shared stack:

```bash
cd proxy
docker compose down -v
docker compose up -d
```

For a live server, do not reset the volume. Use the original
`SHARED_MYSQL_ROOT_PASSWORD` from `proxy/.env`.

If image pull fails, check that this Docker tag exists:

```text
wordpress:${WORDPRESS_VERSION}-php${PHP_VERSION}-fpm
```

Example:

```text
wordpress:6.9.4-php8.3-fpm
```
