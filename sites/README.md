# Multi-site WordPress deployment

Use this layout when multiple WordPress sites must run on the same server without
one site's later deployment changing another site's containers, database, or files.

## Architecture

- `proxy/` runs the only public containers that bind host ports `80` and `443`.
- Each site is a separate Compose project copied from `sites/site-template/`.
- Each site has its own MariaDB volume, WordPress files, nginx container, and env file.
- Site nginx containers join the shared external Docker network named `webproxy`.
- The shared proxy discovers site nginx containers from their `VIRTUAL_HOST` and
  `LETSENCRYPT_HOST` environment variables and manages HTTPS certificates.

## First-time server setup

Start the shared proxy once:

```bash
cd proxy
cp .env.example .env
nano .env
docker compose up -d
```

This creates the shared Docker network `webproxy`.

Or use the helper script from the repository root:

```bash
sh deploy-site.sh site-one site_one --start-proxy
```

The script creates `sites/site-one/.env` first and stops so you can edit real
domain names, passwords, and WordPress admin details. Run the same command again
after editing `.env`.

## Deploy site 1

Copy the template to a real site directory:

```bash
mkdir -p sites/site-one
cp -a sites/site-template/. sites/site-one/
cd sites/site-one
cp .env.example .env
nano .env
docker compose -p site_one up -d
```

Equivalent helper-script flow:

```bash
sh deploy-site.sh site-one site_one --start-proxy
nano sites/site-one/.env
sh deploy-site.sh site-one site_one
```

Set real values in `.env`, especially:

- `DOMAIN`
- `WWW_DOMAIN`
- `PRIMARY_DOMAIN`
- `LETSENCRYPT_EMAIL`
- `WORDPRESS_URL`
- WordPress admin credentials
- database passwords

Point both DNS records to the server before starting the site:

```text
example.com      -> server public IP
www.example.com  -> server public IP
```

## Deploy site 2 later

Repeat the same copy process with a different folder and project name:

```bash
mkdir -p sites/site-two
cp -a sites/site-template/. sites/site-two/
cd sites/site-two
cp .env.example .env
nano .env
docker compose -p site_two up -d
```

Equivalent helper-script flow:

```bash
sh deploy-site.sh site-two site_two
nano sites/site-two/.env
sh deploy-site.sh site-two site_two
```

This does not recreate or modify `site_one` containers, volumes, or files. The
shared proxy will reload its generated routing when the second site's nginx
container appears.

## Updates per site

Run updates from only that site's folder:

```bash
cd sites/site-one
docker compose -p site_one pull
docker compose -p site_one up -d
```

Do the same for `site_two` when you want to update it. Avoid using the same
Compose project name for two sites because named volumes are scoped by project.

## Important notes

- Do not publish ports `80` or `443` from individual site stacks.
- Keep the proxy stack running before starting site stacks.
- Use unique Compose project names such as `site_one`, `site_two`, or the domain
  without dots.
- If a `wordpress:${WORDPRESS_VERSION}-php${PHP_VERSION}-fpm` tag does not exist,
  Docker will fail while pulling the image.
