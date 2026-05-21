#!/bin/sh

# Run this from the project root. It loads values from .env and
# generates or renews certificates into ./certbot/conf.

if [ "$1" = "help" ] || [ "$1" = "--help" ]; then
  echo "Usage: sh certbot/run-certbot.sh [email]"
  echo "If email is omitted, LETSENCRYPT_EMAIL from .env is used."
  exit 0
fi

if [ ! -f .env ]; then
  echo "Error: .env file not found. Create it from .env.example first."
  exit 1
fi

set -a
. ./.env
set +a

EMAIL="${1:-$LETSENCRYPT_EMAIL}"

if [ -z "$DOMAIN" ] || [ -z "$WWW_DOMAIN" ]; then
  echo "Error: DOMAIN and WWW_DOMAIN must be set in .env"
  exit 1
fi

if [ -z "$EMAIL" ]; then
  echo "Error: provide email as argument or set LETSENCRYPT_EMAIL in .env"
  exit 1
fi

docker compose run --rm --entrypoint certbot certbot certonly \
  --webroot -w /var/www/html \
  -d "$DOMAIN" \
  -d "$WWW_DOMAIN" \
  --email "$EMAIL" \
  --agree-tos \
  --no-eff-email \
  --config-dir /etc/letsencrypt \
  --work-dir /tmp/letsencrypt \
  --logs-dir /var/log/letsencrypt \
  --non-interactive
