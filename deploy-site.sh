#!/bin/sh

set -eu

usage() {
  cat <<'EOF'
Usage:
  sh deploy-site.sh <site-folder> <compose-project> [--start-proxy]

Examples:
  sh deploy-site.sh site-one site_one --start-proxy
  sh deploy-site.sh site-two site_two

What it does:
  - copies sites/site-template into sites/<site-folder> if missing
  - creates sites/<site-folder>/.env from .env.example if missing
  - optionally starts the shared proxy stack
  - starts the site with docker compose -p <compose-project> up -d

After the first run, edit sites/<site-folder>/.env with real domain and
credential values, then run the same command again.
EOF
}

if [ "${1:-}" = "help" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  usage
  exit 1
fi

SITE_FOLDER="$1"
PROJECT_NAME="$2"
START_PROXY="${3:-}"

case "$SITE_FOLDER" in
  ""|*/*|*\\*|.*)
    echo "Error: site-folder must be a simple folder name like site-one."
    exit 1
    ;;
esac

case "$PROJECT_NAME" in
  ""|*[^a-zA-Z0-9_-]*)
    echo "Error: compose-project may only contain letters, numbers, underscores, and hyphens."
    exit 1
    ;;
esac

if [ -n "$START_PROXY" ] && [ "$START_PROXY" != "--start-proxy" ]; then
  echo "Error: unknown option: $START_PROXY"
  usage
  exit 1
fi

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
TEMPLATE_DIR="$ROOT_DIR/sites/site-template"
SITE_DIR="$ROOT_DIR/sites/$SITE_FOLDER"
PROXY_DIR="$ROOT_DIR/proxy"
CREATED_ENV=0

if [ ! -d "$TEMPLATE_DIR" ]; then
  echo "Error: missing template directory: $TEMPLATE_DIR"
  exit 1
fi

if [ "$START_PROXY" = "--start-proxy" ]; then
  if [ ! -f "$PROXY_DIR/.env" ]; then
    cp "$PROXY_DIR/.env.example" "$PROXY_DIR/.env"
    CREATED_ENV=1
    echo "Created proxy/.env from proxy/.env.example."
  fi
fi

if [ ! -d "$SITE_DIR" ]; then
  mkdir -p "$SITE_DIR"
  cp -a "$TEMPLATE_DIR/." "$SITE_DIR/"
  echo "Created sites/$SITE_FOLDER from sites/site-template."
fi

if [ ! -f "$SITE_DIR/.env" ]; then
  cp "$SITE_DIR/.env.example" "$SITE_DIR/.env"
  CREATED_ENV=1
  echo "Created sites/$SITE_FOLDER/.env from .env.example."
fi

if [ "$CREATED_ENV" -eq 1 ]; then
  echo "Edit the generated .env file or files with real values, then run this command again:"
  if [ "$START_PROXY" = "--start-proxy" ]; then
    echo "  sh deploy-site.sh $SITE_FOLDER $PROJECT_NAME --start-proxy"
  else
    echo "  sh deploy-site.sh $SITE_FOLDER $PROJECT_NAME"
  fi
  exit 0
fi

if grep -Eq '^(DOMAIN=example\.com|WWW_DOMAIN=www\.example\.com|WORDPRESS_ADMIN_PASSWORD=admin_password_change_me|MYSQL_ROOT_PASSWORD=rootpassword_change_me|MYSQL_PASSWORD=wordpress_db_pass_change_me)' "$SITE_DIR/.env"; then
  echo "Error: sites/$SITE_FOLDER/.env still contains placeholder values."
  echo "Edit it first, then run:"
  echo "  sh deploy-site.sh $SITE_FOLDER $PROJECT_NAME"
  exit 1
fi

if [ "$START_PROXY" = "--start-proxy" ]; then
  echo "Starting shared proxy..."
  (cd "$PROXY_DIR" && docker compose up -d)
fi

echo "Starting site stack: $PROJECT_NAME"
(cd "$SITE_DIR" && docker compose -p "$PROJECT_NAME" up -d)

echo "Done."
