#!/bin/sh

# Multi-site certbot helper.
# Reads SITE1_* and SITE2_* domains from .env and requests both certificates.

if [ "$1" = "help" ] || [ "$1" = "--help" ]; then
  echo "Usage: sh certbot/run-certbot-multi.sh [email]"
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

if [ -z "${SITE1_DOMAIN:-}" ] || [ -z "${SITE1_WWW_DOMAIN:-}" ] || [ -z "${SITE2_DOMAIN:-}" ] || [ -z "${SITE2_WWW_DOMAIN:-}" ]; then
  echo "Error: SITE1_DOMAIN, SITE1_WWW_DOMAIN, SITE2_DOMAIN, SITE2_WWW_DOMAIN must be set in .env"
  exit 1
fi

if [ -z "$EMAIL" ]; then
  echo "Error: provide email as argument or set LETSENCRYPT_EMAIL in .env"
  exit 1
fi

echo "Checking nginx_multi container state..."
if ! docker compose -f docker-compose.multi.yml ps nginx_multi | grep -Eq "Up|running"; then
  echo "Error: nginx_multi is not healthy/running. Fix nginx first: docker compose -f docker-compose.multi.yml logs --tail=200 nginx_multi"
  exit 1
fi

for domain in "$SITE1_DOMAIN" "$SITE1_WWW_DOMAIN" "$SITE2_DOMAIN" "$SITE2_WWW_DOMAIN"; do
  case "$domain" in
    *://*|*/?*|*/*)
      echo "Error: invalid hostname in .env: $domain"
      exit 1
      ;;
  esac
done

docker compose -f docker-compose.multi.yml run --rm --entrypoint certbot certbot_multi certonly \
  --webroot -w /var/www/challenges \
  -d "$SITE1_DOMAIN" \
  -d "$SITE1_WWW_DOMAIN" \
  -d "$SITE2_DOMAIN" \
  -d "$SITE2_WWW_DOMAIN" \
  --email "$EMAIL" \
  --agree-tos \
  --no-eff-email \
  --config-dir /etc/letsencrypt \
  --work-dir /tmp/letsencrypt \
  --logs-dir /var/log/letsencrypt \
  --non-interactive
