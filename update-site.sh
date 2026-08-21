#!/bin/sh

# Controlled WordPress maintenance with backup, compatibility checks, health
# checks, and automatic rollback. Run `check` first and test in staging.
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
BACKUP_ROOT="${WP_UPDATE_BACKUP_ROOT:-$ROOT_DIR/update-backups}"
MODE="${1:-}"
SITE_FOLDER="${2:-}"
PROJECT_NAME="${3:-}"
shift_count=0

usage() {
  cat <<'EOF'
Usage:
  sh update-site.sh check <site-folder> <compose-project> [options]
  sh update-site.sh apply <site-folder> <compose-project> [options]

Options:
  --php VERSION        Target PHP version, for example 8.4
  --wordpress VERSION  Target WordPress container/core version
  --refresh-images     Pull the configured WordPress, Nginx, and WP-CLI images
  --skip-plugins       Do not update plugins
  --skip-themes        Do not update themes

Examples:
  sh update-site.sh check customer-site customer_site
  sh update-site.sh check customer-site customer_site --php 8.4
  sh update-site.sh apply customer-site customer_site --refresh-images
  sh update-site.sh apply customer-site customer_site --php 8.4 --wordpress 6.9.4
EOF
}

case "$MODE" in check|apply) ;; *) usage; exit 2 ;; esac
[ -n "$SITE_FOLDER" ] && [ -n "$PROJECT_NAME" ] || { usage; exit 2; }
shift 3

TARGET_PHP=""
TARGET_WP=""
REFRESH_IMAGES=0
UPDATE_PLUGINS=1
UPDATE_THEMES=1
while [ "$#" -gt 0 ]; do
  case "$1" in
    --php) [ "$#" -ge 2 ] || { usage; exit 2; }; TARGET_PHP="$2"; shift 2 ;;
    --wordpress) [ "$#" -ge 2 ] || { usage; exit 2; }; TARGET_WP="$2"; shift 2 ;;
    --refresh-images) REFRESH_IMAGES=1; shift ;;
    --skip-plugins) UPDATE_PLUGINS=0; shift ;;
    --skip-themes) UPDATE_THEMES=0; shift ;;
    *) echo "Unknown option: $1"; usage; exit 2 ;;
  esac
done

case "$SITE_FOLDER" in ""|*/*|*\\*|.*) echo "Invalid site folder"; exit 2 ;; esac
case "$PROJECT_NAME" in ""|*[!abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-]*) echo "Invalid project name"; exit 2 ;; esac
case "$TARGET_PHP" in ""|[0-9]*.[0-9]*) ;; *) echo "Invalid PHP version"; exit 2 ;; esac
case "$TARGET_WP" in ""|[0-9]*.[0-9]*) ;; *) echo "Invalid WordPress version"; exit 2 ;; esac

SITE_DIR="$ROOT_DIR/sites/$SITE_FOLDER"
ENV_FILE="$SITE_DIR/.env"
[ -d "$SITE_DIR" ] && [ -f "$SITE_DIR/docker-compose.yml" ] && [ -f "$ENV_FILE" ] || {
  echo "Site deployment not found: $SITE_DIR"; exit 1;
}

resolved_site="$(CDPATH= cd -- "$SITE_DIR" && pwd -P)"
resolved_sites="$(CDPATH= cd -- "$ROOT_DIR/sites" && pwd -P)"
case "$resolved_site" in "$resolved_sites"/*) ;; *) echo "Unsafe site path"; exit 1 ;; esac
[ "$resolved_site" != "$resolved_sites/site-template" ] || { echo "Refusing to update the template"; exit 1; }

compose() { (cd "$SITE_DIR" && docker compose -p "$PROJECT_NAME" "$@"); }
wp() { compose run --rm -T wpcli wp "$@" --path=/var/www/html; }
wordpress_health() {
  wp db check --quiet &&
  wp eval 'echo "WordPress bootstrap passed.\n";' &&
  wp plugin list --status=active --format=count >/dev/null
}
env_value() { sed -n "s/^$1=//p" "$ENV_FILE" | tail -n 1 | sed "s/^[\"']//;s/[\"']$//"; }
set_env() {
  key="$1"; value="$2"; tmp="$ENV_FILE.tmp"
  sed "s|^$key=.*|$key=$value|" "$ENV_FILE" > "$tmp" && mv "$tmp" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
}

DOMAIN="$(env_value PRIMARY_DOMAIN)"
[ -n "$DOMAIN" ] || DOMAIN="$(env_value DOMAIN)"
SITE_URL="https://$DOMAIN"
CURRENT_PHP="$(env_value PHP_VERSION)"
CURRENT_WP="$(env_value WORDPRESS_VERSION)"
TARGET_PHP="${TARGET_PHP:-$CURRENT_PHP}"
TARGET_WP="${TARGET_WP:-$CURRENT_WP}"

echo "Site:       $SITE_FOLDER ($PROJECT_NAME)"
echo "URL:        $SITE_URL"
echo "WordPress:  $CURRENT_WP -> $TARGET_WP"
echo "PHP:        $CURRENT_PHP -> $TARGET_PHP"

compose config --quiet
compose ps --status running --quiet wordpress | grep -q . || { echo "WordPress container is not running"; exit 1; }
wp core is-installed
wp db check --quiet
wp core verify-checksums

echo "\nAvailable updates:"
wp core check-update || true
[ "$UPDATE_PLUGINS" -eq 0 ] || wp plugin list --update=available
[ "$UPDATE_THEMES" -eq 0 ] || wp theme list --update=available

# Lint custom PHP using the requested runtime before changing the live container.
if [ "$TARGET_PHP" != "$CURRENT_PHP" ] || [ "$TARGET_WP" != "$CURRENT_WP" ]; then
  target_image="wordpress:${TARGET_WP}-php${TARGET_PHP}-fpm"
  echo "\nPulling and testing target runtime: $target_image"
  docker pull "$target_image"
  docker run --rm --entrypoint sh -v "$SITE_DIR/html:/var/www/html:ro" "$target_image" -c '
    set -eu
    find /var/www/html/wp-content/plugins /var/www/html/wp-content/themes -type f -name "*.php" -print0 2>/dev/null |
      xargs -0 -r -n 1 php -l >/tmp/php-lint.log
    echo "PHP syntax check passed."
  '
fi

if [ "$MODE" = check ]; then
  echo "\nCHECK COMPLETE: no changes were applied."
  echo "Test the listed updates in staging, then rerun with 'apply'."
  exit 0
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="$BACKUP_ROOT/$SITE_FOLDER/$timestamp"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_ROOT" "$BACKUP_ROOT/$SITE_FOLDER" "$BACKUP_DIR" 2>/dev/null || true

echo "\nCreating rollback backup: $BACKUP_DIR"
cp "$ENV_FILE" "$BACKUP_DIR/site.env"
cp "$SITE_DIR/docker-compose.yml" "$BACKUP_DIR/docker-compose.yml"
wp db export - --add-drop-table --quiet > "$BACKUP_DIR/database.sql"
tar --exclude='html/wp-content/uploads' \
    --exclude='html/wp-content/cache' \
    --exclude='html/wp-content/ai1wm-backups' \
    -czf "$BACKUP_DIR/wordpress-code.tar.gz" -C "$SITE_DIR" html
chmod 600 "$BACKUP_DIR"/*

# Preserve the exact local images as well as the files/database. Mutable tags
# such as nginx:stable can otherwise make a real rollback impossible.
OLD_WP_IMAGE="wordpress:${CURRENT_WP}-php${CURRENT_PHP}-fpm"
OLD_CLI_IMAGE="wordpress:cli-php${CURRENT_PHP}"
OLD_NGINX_IMAGE="nginx:stable"
ROLLBACK_WP_IMAGE="local/wp-update-rollback:${timestamp}-wordpress"
ROLLBACK_CLI_IMAGE="local/wp-update-rollback:${timestamp}-wpcli"
ROLLBACK_NGINX_IMAGE="local/wp-update-rollback:${timestamp}-nginx"
docker image inspect "$OLD_WP_IMAGE" >/dev/null && docker tag "$OLD_WP_IMAGE" "$ROLLBACK_WP_IMAGE"
docker image inspect "$OLD_CLI_IMAGE" >/dev/null && docker tag "$OLD_CLI_IMAGE" "$ROLLBACK_CLI_IMAGE"
docker image inspect "$OLD_NGINX_IMAGE" >/dev/null && docker tag "$OLD_NGINX_IMAGE" "$ROLLBACK_NGINX_IMAGE"

rollback() {
  echo "\nUPDATE FAILED — rolling back code, database, and versions..."
  cp "$BACKUP_DIR/site.env" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  docker tag "$ROLLBACK_WP_IMAGE" "$OLD_WP_IMAGE" 2>/dev/null || true
  docker tag "$ROLLBACK_CLI_IMAGE" "$OLD_CLI_IMAGE" 2>/dev/null || true
  docker tag "$ROLLBACK_NGINX_IMAGE" "$OLD_NGINX_IMAGE" 2>/dev/null || true
  rm -rf "$SITE_DIR/html/wp-admin" "$SITE_DIR/html/wp-includes" \
    "$SITE_DIR/html/wp-content/plugins" "$SITE_DIR/html/wp-content/themes"
  tar -xzf "$BACKUP_DIR/wordpress-code.tar.gz" -C "$SITE_DIR"
  compose up -d --pull never wordpress nginx
  cat "$BACKUP_DIR/database.sql" | wp db import - --quiet || true
  wp maintenance-mode deactivate >/dev/null 2>&1 || true
  echo "Rollback completed. Backup retained at: $BACKUP_DIR"
}
trap 'rollback' HUP INT TERM

wp maintenance-mode activate
update_failed=0

if [ "$TARGET_PHP" != "$CURRENT_PHP" ]; then set_env PHP_VERSION "$TARGET_PHP"; fi
if [ "$TARGET_WP" != "$CURRENT_WP" ]; then set_env WORDPRESS_VERSION "$TARGET_WP"; fi

if [ "$REFRESH_IMAGES" -eq 1 ] || [ "$TARGET_PHP" != "$CURRENT_PHP" ] || [ "$TARGET_WP" != "$CURRENT_WP" ]; then
  docker pull "wordpress:${TARGET_WP}-php${TARGET_PHP}-fpm" || update_failed=1
  docker pull "wordpress:cli-php${TARGET_PHP}" || update_failed=1
  docker pull nginx:stable || update_failed=1
  [ "$update_failed" -ne 0 ] || compose up -d --pull never wordpress nginx || update_failed=1
fi

[ "$update_failed" -ne 0 ] || wp core update --version="$TARGET_WP" || update_failed=1
[ "$update_failed" -ne 0 ] || wp core update-db || update_failed=1

if [ "$update_failed" -eq 0 ] && [ "$UPDATE_PLUGINS" -eq 1 ]; then
  plugins="$(wp plugin list --update=available --field=name 2>/dev/null || true)"
  for plugin in $plugins; do
    echo "Updating plugin: $plugin"
    wp plugin update "$plugin" || { update_failed=1; break; }
    wordpress_health || { update_failed=1; break; }
  done
fi

if [ "$update_failed" -eq 0 ] && [ "$UPDATE_THEMES" -eq 1 ]; then
  themes="$(wp theme list --update=available --field=name 2>/dev/null || true)"
  for theme in $themes; do
    echo "Updating theme: $theme"
    wp theme update "$theme" || { update_failed=1; break; }
    wordpress_health || { update_failed=1; break; }
  done
fi

if [ "$update_failed" -eq 0 ]; then
  wp cache flush || true
  wp core verify-checksums || update_failed=1
  wp db check --quiet || update_failed=1
  compose exec -T wordpress php -v || update_failed=1
  curl -fsS --retry 5 --retry-delay 3 -o /dev/null "$SITE_URL/" || update_failed=1
  curl -fsS --retry 3 --retry-delay 2 -o /dev/null "$SITE_URL/wp-login.php" || update_failed=1
fi

if [ "$update_failed" -ne 0 ]; then
  rollback
  trap - HUP INT TERM
  exit 1
fi

wp maintenance-mode deactivate
trap - HUP INT TERM

echo "\nUPDATE COMPLETE"
echo "Backup: $BACKUP_DIR"
echo "Rollback image tags use: local/wp-update-rollback:${timestamp}-*"
echo "Run: sh security-audit.sh"
echo "Then complete browser functional tests and external WPScan/ZAP checks."
