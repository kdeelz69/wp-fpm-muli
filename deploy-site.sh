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

ensure_proxy_env() {
  if [ ! -f "$PROXY_DIR/.env" ]; then
    email="$(prompt_required "Default Let's Encrypt email")"
    printf "DEFAULT_EMAIL=%s\n" "$email" > "$PROXY_DIR/.env"
    echo "Created proxy/.env."
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
  site_dir="$ROOT_DIR/sites/$site_folder"
  env_file="$site_dir/.env"

  echo
  echo "Enter website details for sites/$site_folder."
  domain="$(prompt_required "Apex domain, for example example.com")"
  www_domain="$(prompt_default "WWW domain" "www.$domain")"
  primary_domain="$(prompt_default "Primary domain" "$www_domain")"
  email="$(prompt_required "Let's Encrypt email")"
  site_title="$(prompt_required "WordPress site title")"
  admin_user="$(prompt_default "WordPress admin username" "admin")"
  admin_password="$(prompt_required "WordPress admin password")"
  admin_email="$(prompt_default "WordPress admin email" "$email")"
  wp_version="$(prompt_default "WordPress version" "6.9.4")"
  php_version="$(prompt_default "PHP version" "8.3")"
  mysql_root_password="$(prompt_required "MariaDB root password")"
  mysql_password="$(prompt_required "MariaDB WordPress user password")"

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

MYSQL_ROOT_PASSWORD=$mysql_root_password
MYSQL_DATABASE=wordpress
MYSQL_USER=wordpress
MYSQL_PASSWORD=$mysql_password

WORDPRESS_DB_NAME=wordpress
WORDPRESS_DB_USER=wordpress
WORDPRESS_DB_PASSWORD=$mysql_password
EOF

  echo "Saved $env_file."
}

has_placeholder_values() {
  env_file="$1"
  grep -Eq '^(DOMAIN=example\.com|WWW_DOMAIN=www\.example\.com|WORDPRESS_ADMIN_PASSWORD=admin_password_change_me|MYSQL_ROOT_PASSWORD=rootpassword_change_me|MYSQL_PASSWORD=wordpress_db_pass_change_me)' "$env_file"
}

ensure_site_env() {
  site_folder="$1"
  site_dir="$ROOT_DIR/sites/$site_folder"
  env_file="$site_dir/.env"

  if [ ! -f "$env_file" ]; then
    write_site_env_interactive "$site_folder"
    return 0
  fi

  if has_placeholder_values "$env_file"; then
    echo "sites/$site_folder/.env still contains placeholder values."
    if confirm "Replace it using guided questions now?"; then
      write_site_env_interactive "$site_folder"
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
  fi

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
  echo "Starting main public web entry..."
  (cd "$PROXY_DIR" && docker compose up -d)
}

restart_acme() {
  echo "Retrying SSL certificate service..."
  (cd "$PROXY_DIR" && docker compose restart acme-companion)
  echo "Check logs with:"
  echo "  cd proxy && docker compose logs --tail=200 acme-companion"
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
  ensure_site_env "$site_folder"
  check_site_dns "$site_folder"

  if [ "$start_proxy_flag" = "--start-proxy" ]; then
    start_proxy
  fi

  echo "Starting site stack: $project_name"
  (cd "$ROOT_DIR/sites/$site_folder" && docker compose -p "$project_name" up -d)

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
    echo "5) Show running status"
    echo "0) Exit"
    printf "Choose: "
    IFS= read -r choice

    case "$choice" in
      1) guided_deploy ;;
      2) start_proxy ;;
      3) check_dns_menu ;;
      4) restart_acme ;;
      5) show_status ;;
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
