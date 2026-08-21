#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
failures=0
warnings=0

pass() { printf 'PASS  %s\n' "$1"; }
warn() { printf 'WARN  %s\n' "$1"; warnings=$((warnings + 1)); }
fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }

check_mode() {
  file="$1"
  [ -f "$file" ] || return 0
  mode="$(stat -c '%a' "$file")"
  case "$mode" in
    600|400) pass "$file protects secrets ($mode)" ;;
    *) fail "$file contains secrets but has mode $mode (expected 600)" ;;
  esac
}

printf 'WordPress production security audit\n\n'

check_mode "$ROOT_DIR/proxy/.env"
for env_file in "$ROOT_DIR"/sites/*/.env; do
  [ -f "$env_file" ] || continue
  check_mode "$env_file"
done

if command -v docker >/dev/null 2>&1; then
  listeners="$(ss -lnt 2>/dev/null || true)"
  printf '%s\n' "$listeners" | grep -Eq '(^|[.:])3306[[:space:]]' && \
    printf '%s\n' "$listeners" | grep -Eq '0\.0\.0\.0:3306|\[::\]:3306' && \
    fail 'MariaDB is listening publicly on port 3306' || pass 'MariaDB is not publicly bound'

  if command -v ufw >/dev/null 2>&1; then
    ufw status 2>/dev/null | grep -q 'Status: active' && pass 'UFW is active' || warn 'UFW is inactive; verify the AWS Security Group is restrictive'
  fi

  for site_dir in "$ROOT_DIR"/sites/*; do
    [ -f "$site_dir/docker-compose.yml" ] || continue
    [ "$(basename "$site_dir")" = 'site-template' ] && continue
    project="$(basename "$site_dir" | tr '-' '_')"
    printf '\nSite: %s\n' "$(basename "$site_dir")"
    if (cd "$site_dir" && docker compose -p "$project" ps --status running --quiet wordpress 2>/dev/null | grep -q .); then
      (cd "$site_dir" && docker compose -p "$project" exec -T wordpress sh -lc '
        set -eu
        test "$(php -r "echo ini_get(\"expose_php\");")" = "" || { echo "FAIL  expose_php is enabled"; exit 1; }
        test -f /var/www/html/wp-config.php
        mode=$(stat -c %a /var/www/html/wp-config.php)
        case "$mode" in 640|600|440|400) ;; *) echo "FAIL  wp-config.php mode is $mode"; exit 1;; esac
        find /var/www/html/wp-content/uploads -type f -name "*.php" ! -name index.php -print -quit 2>/dev/null | grep -q . && { echo "WARN  unexpected PHP files exist under uploads"; exit 1; } || true
      ') && pass 'runtime PHP and WordPress file checks' || fail 'runtime PHP or WordPress file checks'
    else
      warn "$project WordPress container is not running"
    fi
  done
else
  warn 'Docker is not installed; runtime checks skipped'
fi

printf '\nSummary: %s failure(s), %s warning(s)\n' "$failures" "$warnings"
[ "$failures" -eq 0 ]
