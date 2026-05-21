#!/bin/sh

set -eu

if [ ! -f .env ]; then
  echo "Error: .env file not found. Create it from .env.example and set your real values."
  exit 1
fi

set -a
. ./.env
set +a

if [ -z "${DOMAIN:-}" ] || [ -z "${WWW_DOMAIN:-}" ] || [ -z "${LETSENCRYPT_EMAIL:-}" ]; then
  echo "Error: DOMAIN, WWW_DOMAIN, and LETSENCRYPT_EMAIL must be set in .env"
  exit 1
fi

echo "[1/4] Starting containers..."
docker compose up -d

echo "[2/4] Waiting for nginx to be ready on HTTP..."
sleep 5

echo "[3/4] Requesting/renewing Let's Encrypt certificate..."
sh certbot/run-certbot.sh

echo "[4/4] Restarting nginx with SSL config..."
docker compose restart nginx

echo "Done. Open: https://${DOMAIN}"
