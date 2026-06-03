#!/bin/sh

set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
TEMPLATE_DIR="$ROOT_DIR/sites/site-template"
PROXY_DIR="$ROOT_DIR/proxy"

usage() {
  cat <<'EOF'
Usage:
  sh deploy-site.sh
  sh deploy-site.sh <site-folder> <compose-project> [--start-proxy]

Examples:
  sh deploy-site.sh
  sh deploy-site.sh site-one site_one --start-proxy
  sh deploy-site.sh site-two site_two

Run without arguments for the guided menu.
EOF
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

is_ipv4() {
  case "$1" in
    *[!0123456789.]*|""|*.*.*.*.*) return 1 ;;
    *.*.*.*) return 0 ;;
    *) return 1 ;;
  esac
}

valid_site_folder() {
  case "$1" in
    ""|*/*|*\\*|.*) return 1 ;;
    *) return 0 ;;
  esac
}

valid_project_name() {
  case "$1" in
    ""|[!abcdefghijklmnopqrstuvwxyz0123456789]*|*[!abcdefghijklmnopqrstuvwxyz0123456789_-]*) return 1 ;;
    *) return 0 ;;
  esac
}

valid_db_identifier() {
  case "$1" in
    ""|[!abcdefghijklmnopqrstuvwxyz_]*|*[!abcdefghijklmnopqrstuvwxyz0123456789_]*) return 1 ;;
    *) return 0 ;;
  esac
}

prompt_required() {
  label="$1"
  value=""
  while [ -z "$value" ]; do
    printf "%s: " "$label" >&2
    IFS= read -r value
  done
  printf "%s" "$value"
}

prompt_default() {
  label="$1"
  default="$2"
  printf "%s [%s]: " "$label" "$default" >&2
  IFS= read -r value
  if [ -z "$value" ]; then
    value="$default"
  fi
  printf "%s" "$value"
}

confirm() {
  label="$1"
  printf "%s [y/N]: " "$label"
  IFS= read -r answer
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

get_public_ip() {
  if command_exists curl; then
    ip="$(curl -fsS https://api.ipify.org 2>/dev/null || true)"
    if [ -n "$ip" ]; then
      printf "%s" "$ip"
      return 0
    fi
  fi

  if command_exists hostname; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
    if [ -n "$ip" ]; then
      printf "%s" "$ip"
      return 0
    fi
  fi

  return 1
}

resolve_domain() {
  domain="$1"

  if command_exists getent; then
    ip="$(getent ahostsv4 "$domain" 2>/dev/null | awk '{print $1; exit}' || true)"
    if [ -n "$ip" ]; then
      printf "%s" "$ip"
      return 0
    fi
  fi

  if command_exists dig; then
    ip="$(dig +short A "$domain" 2>/dev/null | awk 'NF {print; exit}' || true)"
    if [ -n "$ip" ]; then
      printf "%s" "$ip"
      return 0
    fi
  fi

  if command_exists host; then
    ip="$(host "$domain" 2>/dev/null | awk '/has address/ {print $4; exit}' || true)"
    if [ -n "$ip" ]; then
      printf "%s" "$ip"
      return 0
    fi
  fi

  return 1
}

check_dns_name() {
  domain="$1"
  expected_ip="$2"
  actual_ip="$(resolve_domain "$domain" || true)"

  if [ -z "$actual_ip" ]; then
    echo "DNS check failed: $domain does not resolve yet."
    return 1
  fi

  if [ "$actual_ip" != "$expected_ip" ]; then
    echo "DNS check failed: $domain resolves to $actual_ip, expected $expected_ip."
    return 1
  fi

  echo "DNS ok: $domain -> $actual_ip"
  return 0
}

load_env_value() {
  file="$1"
  key="$2"
  sed -n "s/^$key=//p" "$file" | tail -n 1 | sed 's/^"//; s/"$//'
}

sql_escape() {
  printf "%s" "$1" | sed "s/'/''/g"
}

ensure_proxy_env() {
  if [ ! -f "$PROXY_DIR/.env" ]; then
    email="$(prompt_required "Default SSL certificate email")"
    root_password="$(prompt_required "Shared MariaDB root password")"
    {
      printf "DEFAULT_EMAIL=%s\n" "$email"
      printf "SHARED_MYSQL_ROOT_PASSWORD=%s\n" "$root_password"
    } > "$PROXY_DIR/.env"
    echo "Created proxy/.env."
    return 0
  fi

  if ! grep -q '^SHARED_MYSQL_ROOT_PASSWORD=' "$PROXY_DIR/.env"; then
    root_password="$(prompt_required "Shared MariaDB root password")"
    printf "SHARED_MYSQL_ROOT_PASSWORD=%s\n" "$root_password" >> "$PROXY_DIR/.env"
    echo "Added SHARED_MYSQL_ROOT_PASSWORD to proxy/.env."
  fi
}

ensure_site_dir() {
  site_folder="$1"
  site_dir="$ROOT_DIR/sites/$site_folder"

  if [ ! -d "$TEMPLATE_DIR" ]; then
    echo "Error: missing template directory: $TEMPLATE_DIR"
    exit 1
  fi

  if [ ! -d "$site_dir" ]; then
    mkdir -p "$site_dir"
    cp -a "$TEMPLATE_DIR/." "$site_dir/"
    echo "Created sites/$site_folder from sites/site-template."
  fi
}

write_site_env_interactive() {
  site_folder="$1"
  project_name="$2"
  site_dir="$ROOT_DIR/sites/$site_folder"
  env_file="$site_dir/.env"
  default_db_prefix="$(printf "%s" "$project_name" | tr '-' '_')"

  echo
  echo "Enter website details for sites/$site_folder."
  domain="$(prompt_required "Apex domain, for example example.com")"
  www_domain="$(prompt_default "WWW domain" "www.$domain")"
  primary_domain="$(prompt_default "Primary domain" "$www_domain")"
  email="$(prompt_required "SSL certificate email")"
  site_title="$(prompt_required "WordPress site title")"
  admin_user="$(prompt_default "WordPress admin username" "admin")"
  admin_password="$(prompt_required "WordPress admin password")"
  admin_email="$(prompt_default "WordPress admin email" "$email")"
  wp_version="$(prompt_default "WordPress version" "6.9.4")"
  php_version="$(prompt_default "PHP version" "8.3")"
  db_name="$(prompt_default "Website database name" "${default_db_prefix}_db")"
  while ! valid_db_identifier "$db_name"; do
    echo "Use lowercase letters, numbers, and underscores. Start with a letter or underscore."
    db_name="$(prompt_required "Website database name")"
  done
  db_user="$(prompt_default "Website database username" "${default_db_prefix}_user")"
  while ! valid_db_identifier "$db_user"; do
    echo "Use lowercase letters, numbers, and underscores. Start with a letter or underscore."
    db_user="$(prompt_required "Website database username")"
  done
  db_password="$(prompt_required "Website database password")"

  cat > "$env_file" <<EOF
DOMAIN=$domain
WWW_DOMAIN=$www_domain
PRIMARY_DOMAIN=$primary_domain
LETSENCRYPT_EMAIL=$email

WORDPRESS_VERSION=$wp_version
PHP_VERSION=$php_version
WORDPRESS_URL=https://$primary_domain
WORDPRESS_SITE_TITLE="$site_title"
WORDPRESS_ADMIN_USER=$admin_user
WORDPRESS_ADMIN_PASSWORD=$admin_password
WORDPRESS_ADMIN_EMAIL=$admin_email

WORDPRESS_DB_NAME=$db_name
WORDPRESS_DB_USER=$db_user
WORDPRESS_DB_PASSWORD=$db_password
EOF

  echo "Saved $env_file."
}

has_placeholder_values() {
  env_file="$1"
  grep -Eq '^(DOMAIN=example\.com|WWW_DOMAIN=www\.example\.com|WORDPRESS_ADMIN_PASSWORD=admin_password_change_me|WORDPRESS_DB_PASSWORD=wordpress_db_pass_change_me)' "$env_file"
}

ensure_site_env() {
  site_folder="$1"
  project_name="$2"
  site_dir="$ROOT_DIR/sites/$site_folder"
  env_file="$site_dir/.env"

  if [ ! -f "$env_file" ]; then
    write_site_env_interactive "$site_folder" "$project_name"
    return 0
  fi

  if has_placeholder_values "$env_file"; then
    echo "sites/$site_folder/.env still contains placeholder values."
    if confirm "Replace it using guided questions now?"; then
      write_site_env_interactive "$site_folder" "$project_name"
    else
      echo "Edit $env_file manually, then run this script again."
      exit 1
    fi
  fi
}

check_site_dns() {
  site_folder="$1"
  site_dir="$ROOT_DIR/sites/$site_folder"
  env_file="$site_dir/.env"

  domain="$(load_env_value "$env_file" DOMAIN)"
  www_domain="$(load_env_value "$env_file" WWW_DOMAIN)"

  server_ip="$(get_public_ip || true)"
  if [ -z "$server_ip" ]; then
    server_ip="$(prompt_required "Could not auto-detect public IP. Enter server public IP")"
  else
    server_ip="$(prompt_default "Server public IP for DNS check. Press Enter to use detected IP" "$server_ip")"
  fi

  while ! is_ipv4 "$server_ip"; do
    echo "Error: expected an IP address like 52.221.194.219, not '$server_ip'."
    server_ip="$(prompt_required "Enter server public IP")"
  done

  echo
  echo "Loaded site DNS values:"
  echo "  DOMAIN=$domain"
  echo "  WWW_DOMAIN=$www_domain"
  echo "  Expected server IP=$server_ip"
  echo
  echo "Checking DNS. If you changed DNS recently, propagation can take time."
  ok=1
  check_dns_name "$domain" "$server_ip" || ok=0
  check_dns_name "$www_domain" "$server_ip" || ok=0

  if [ "$ok" -ne 1 ]; then
    echo
    echo "Fix DNS A records first:"
    echo "  $domain -> $server_ip"
    echo "  $www_domain -> $server_ip"
    echo
    echo "Containers can start without DNS, but public access and HTTPS will fail until DNS is correct."
    if ! confirm "Continue starting containers anyway?"; then
      exit 1
    fi
  fi
}

start_proxy() {
  ensure_proxy_env
  echo "Starting main public web entry and shared database..."
  (cd "$PROXY_DIR" && docker compose up -d)
}

create_site_database() {
  site_folder="$1"
  project_name="$2"
  env_file="$ROOT_DIR/sites/$site_folder/.env"

  ensure_proxy_env

  db_name="$(load_env_value "$env_file" WORDPRESS_DB_NAME)"
  db_user="$(load_env_value "$env_file" WORDPRESS_DB_USER)"
  db_password="$(load_env_value "$env_file" WORDPRESS_DB_PASSWORD)"
  root_password="$(load_env_value "$PROXY_DIR/.env" SHARED_MYSQL_ROOT_PASSWORD)"

  if ! valid_db_identifier "$db_name"; then
    echo "Error: WORDPRESS_DB_NAME must use lowercase letters, numbers, and underscores."
    exit 1
  fi

  if ! valid_db_identifier "$db_user"; then
    echo "Error: WORDPRESS_DB_USER must use lowercase letters, numbers, and underscores."
    exit 1
  fi

  if [ -z "$db_password" ] || [ -z "$root_password" ]; then
    echo "Error: missing database password values."
    exit 1
  fi

  attempts=0
  until (cd "$PROXY_DIR" && docker compose exec -T mariadb mariadb -uroot --password="$root_password" -e "SELECT 1" >/dev/null 2>&1); do
    attempts=$((attempts + 1))
    if [ "$attempts" -ge 40 ]; then
      echo "Error: shared MariaDB is not ready for root login."
      echo "Check logs:"
      echo "  cd proxy && docker compose logs --tail=100 mariadb"
      echo
      echo "If proxy_db_data already existed, the shared MariaDB root password may be the old password from the first initialization."
      exit 1
    fi
    echo "Waiting for shared MariaDB root login..."
    sleep 3
  done

  escaped_user="$(sql_escape "$db_user")"
  escaped_password="$(sql_escape "$db_password")"

  echo "Creating or updating database for this website in shared MariaDB..."
  sql="
CREATE DATABASE IF NOT EXISTS \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$escaped_user'@'%' IDENTIFIED BY '$escaped_password';
ALTER USER '$escaped_user'@'%' IDENTIFIED BY '$escaped_password';
GRANT ALL PRIVILEGES ON \`$db_name\`.* TO '$escaped_user'@'%';
FLUSH PRIVILEGES;
"

  if ! printf "%s" "$sql" | (cd "$PROXY_DIR" && docker compose exec -T mariadb mariadb -uroot --password="$root_password"); then
    echo "Error: could not create database/user in shared MariaDB."
    echo "Check the shared database status:"
    echo "  cd proxy && docker compose ps mariadb"
    echo "  cd proxy && docker compose logs --tail=100 mariadb"
    exit 1
  fi

  echo "Database ready: $db_name, user: $db_user"
}

restart_acme() {
  echo "Retrying SSL certificate service..."
  (cd "$PROXY_DIR" && docker compose restart acme-companion)
  echo "Check logs with:"
  echo "  cd proxy && docker compose logs --tail=200 acme-companion"
}

fix_wordpress_permissions() {
  site_folder="$1"
  project_name="$2"
  site_dir="$ROOT_DIR/sites/$site_folder"

  if [ ! -d "$site_dir" ]; then
    echo "Error: missing site folder: sites/$site_folder"
    exit 1
  fi

  echo "Fixing WordPress writable folder permissions for $project_name..."
  if ! (cd "$site_dir" && docker compose -p "$project_name" exec -T wordpress sh -lc '
set -eu
mkdir -p /var/www/html/wp-content/uploads
mkdir -p /var/www/html/wp-content/upgrade
mkdir -p /var/www/html/wp-content/ai1wm-backups
if [ -d /var/www/html/wp-content/plugins/all-in-one-wp-migration ]; then
  mkdir -p /var/www/html/wp-content/plugins/all-in-one-wp-migration/storage
  touch /var/www/html/wp-content/plugins/all-in-one-wp-migration/storage/index.php
  touch /var/www/html/wp-content/plugins/all-in-one-wp-migration/storage/index.html
fi
chown -R www-data:www-data /var/www/html/wp-content/uploads
chown -R www-data:www-data /var/www/html/wp-content/upgrade
chown -R www-data:www-data /var/www/html/wp-content/ai1wm-backups
if [ -d /var/www/html/wp-content/plugins/all-in-one-wp-migration/storage ]; then
  chown -R www-data:www-data /var/www/html/wp-content/plugins/all-in-one-wp-migration/storage
fi
find /var/www/html/wp-content/uploads /var/www/html/wp-content/upgrade /var/www/html/wp-content/ai1wm-backups -type d -exec chmod 775 {} \;
find /var/www/html/wp-content/uploads /var/www/html/wp-content/upgrade /var/www/html/wp-content/ai1wm-backups -type f -exec chmod 664 {} \;
if [ -d /var/www/html/wp-content/plugins/all-in-one-wp-migration/storage ]; then
  for dir in /var/www/html/wp-content/plugins/all-in-one-wp-migration/storage/*; do
    [ -d "$dir" ] || continue
    if [ ! -f "$dir/retention.json" ]; then
      printf "%s" "{}" > "$dir/retention.json"
    fi
  done
  chown -R www-data:www-data /var/www/html/wp-content/plugins/all-in-one-wp-migration/storage
  find /var/www/html/wp-content/plugins/all-in-one-wp-migration/storage -type d -exec chmod 775 {} \;
  find /var/www/html/wp-content/plugins/all-in-one-wp-migration/storage -type f -exec chmod 664 {} \;
fi
'); then
    echo "Error: could not fix permissions. Make sure the website containers are running."
    echo "Check status:"
    echo "  cd sites/$site_folder && docker compose -p $project_name ps"
    exit 1
  fi

  echo "Permissions fixed."
}

deploy_site() {
  site_folder="$1"
  project_name="$2"
  start_proxy_flag="$3"

  if ! valid_site_folder "$site_folder"; then
    echo "Error: site-folder must be a simple folder name like site-one."
    exit 1
  fi

  if ! valid_project_name "$project_name"; then
    echo "Error: compose-project must start with a lowercase letter or number and may only contain lowercase letters, numbers, underscores, and hyphens."
    exit 1
  fi

  ensure_site_dir "$site_folder"
  ensure_site_env "$site_folder" "$project_name"
  check_site_dns "$site_folder"

  if [ "$start_proxy_flag" = "--start-proxy" ]; then
    start_proxy
  fi

  create_site_database "$site_folder" "$project_name"

  echo "Starting site stack: $project_name"
  if ! (cd "$ROOT_DIR/sites/$site_folder" && docker compose -p "$project_name" up -d); then
    echo
    echo "Website stack did not finish starting."
    echo
    echo "Check the installer logs:"
    echo "  cd sites/$site_folder && docker compose -p $project_name logs --tail=200 wpcli"
    echo
    echo "If the logs say 'Access denied for user', check this website's database values:"
    echo "  sites/$site_folder/.env"
    echo
    echo "Then rerun this script so it creates or updates that database user in shared MariaDB:"
    echo "  sh deploy-site.sh $site_folder $project_name"
    echo
    echo "Do not use down -v in the proxy folder on a live server unless you intend to delete all shared database data."
    exit 1
  fi

  fix_wordpress_permissions "$site_folder" "$project_name"

  echo
  echo "Done."
  echo "Status commands:"
  echo "  cd proxy && docker compose ps"
  echo "  cd sites/$site_folder && docker compose -p $project_name ps"
}

guided_deploy() {
  echo
  site_folder="$(prompt_default "Site folder" "site-one")"
  while ! valid_site_folder "$site_folder"; do
    echo "Use a simple folder name like site-one."
    site_folder="$(prompt_required "Site folder")"
  done

  default_project="$(printf "%s" "$site_folder" | tr '-' '_')"
  project_name="$(prompt_default "Compose project name" "$default_project")"
  while ! valid_project_name "$project_name"; do
    echo "Use lowercase letters, numbers, underscores, or hyphens. Start with a letter or number."
    project_name="$(prompt_required "Compose project name")"
  done

  start_proxy_flag=""
  if confirm "Set up the main public web entry too? Choose yes for the first website on this server"; then
    start_proxy_flag="--start-proxy"
  fi

  deploy_site "$site_folder" "$project_name" "$start_proxy_flag"
}

check_dns_menu() {
  site_folder="$(prompt_required "Site folder to check, for example site-one")"
  env_file="$ROOT_DIR/sites/$site_folder/.env"
  if [ ! -f "$env_file" ]; then
    echo "Error: missing $env_file"
    return 0
  fi
  check_site_dns "$site_folder"
}

fix_permissions_menu() {
  site_folder="$(prompt_required "Website folder, for example site-one")"
  default_project="$(printf "%s" "$site_folder" | tr '-' '_')"
  project_name="$(prompt_default "Compose project name" "$default_project")"
  fix_wordpress_permissions "$site_folder" "$project_name"
}

show_status() {
  echo
  echo "Main public web entry:"
  (cd "$PROXY_DIR" && docker compose ps) || true
  echo
  echo "Website folders:"
  find "$ROOT_DIR/sites" -mindepth 1 -maxdepth 1 -type d ! -name site-template -print 2>/dev/null || true
}

menu() {
  while :; do
    echo
    echo "WordPress website deployment"
    echo "1) Add a new website or update an existing website"
    echo "2) Start the main public web entry only"
    echo "3) Check if a website domain points to this server"
    echo "4) Retry SSL certificate after fixing DNS"
    echo "5) Fix WordPress upload/import permissions"
    echo "6) Show running status"
    echo "0) Exit"
    printf "Choose: "
    IFS= read -r choice

    case "$choice" in
      1) guided_deploy ;;
      2) start_proxy ;;
      3) check_dns_menu ;;
      4) restart_acme ;;
      5) fix_permissions_menu ;;
      6) show_status ;;
      0) exit 0 ;;
      *) echo "Unknown option." ;;
    esac
  done
}

if [ "${1:-}" = "help" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ $# -eq 0 ]; then
  menu
fi

if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  usage
  exit 1
fi

SITE_FOLDER="$1"
PROJECT_NAME="$2"
START_PROXY="${3:-}"

if [ -n "$START_PROXY" ] && [ "$START_PROXY" != "--start-proxy" ]; then
  echo "Error: unknown option: $START_PROXY"
  usage
  exit 1
fi

deploy_site "$SITE_FOLDER" "$PROJECT_NAME" "$START_PROXY"
