#!/bin/sh

# Issue/renew certificates for incremental site2 domains.
# Requires existing public nginx service from docker-compose.yml to be running.

if [ "$1" = "help" ] || [ "$1" = "--help" ]; then
  echo "Usage: sh certbot/run-certbot-site2.sh [email]"
  echo "If email is omitted, LETSENCRYPT_EMAIL from .env is used."
  exit 0
fi

if [ ! -f .env ]; then
  echo "Error: .env file not found. Create it from .env.example first."
  exit 1
fi

set -a
# shellcheck disable=SC1091
. ./.env
set +a

EMAIL="${1:-$LETSENCRYPT_EMAIL}"

if [ -z "$SITE2_DOMAIN" ] || [ -z "$SITE2_WWW_DOMAIN" ]; then
  echo "Error: SITE2_DOMAIN and SITE2_WWW_DOMAIN must be set in .env"
  exit 1
fi

if [ -z "$EMAIL" ]; then
  echo "Error: provide email as argument or set LETSENCRYPT_EMAIL in .env"
  exit 1
fi

case "$SITE2_DOMAIN" in
  *://*|*/?*|*/*)
    echo "Error: SITE2_DOMAIN must be a hostname only (for example: site2.example.com), not a URL."
    exit 1
    ;;
esac

case "$SITE2_WWW_DOMAIN" in
  *://*|*/?*|*/*)
    echo "Error: SITE2_WWW_DOMAIN must be a hostname only (for example: www.site2.example.com), not a URL."
    exit 1
    ;;
esac

echo "Checking nginx container state..."
if ! docker compose ps nginx | grep -Eq "Up|running"; then
  echo "Error: nginx is not healthy/running. Fix nginx first: docker compose logs --tail=200 nginx"
  exit 1
fi

docker compose run --rm --entrypoint certbot certbot certonly \
  --webroot -w /var/www/html \
  -d "$SITE2_DOMAIN" \
  -d "$SITE2_WWW_DOMAIN" \
  --email "$EMAIL" \
  --agree-tos \
  --no-eff-email \
  --config-dir /etc/letsencrypt \
  --work-dir /tmp/letsencrypt \
  --logs-dir /var/log/letsencrypt \
  --non-interactive