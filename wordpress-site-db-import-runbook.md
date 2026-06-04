# WordPress Site DB Import Runbook

Use this runbook when importing or restoring a database for one WordPress site in this Docker multi-site setup.

## Paths

Replace these placeholders before running commands:

```text
PROJECT_PATH=/home/wp-fpm-muli
SITE_FOLDER=your-site-folder
COMPOSE_PROJECT=your_compose_project
TARGET_DB=your_site_database
SQL_DUMP=/path/to/your-dump.sql
SITE_URL=https://www.example.com
TABLE_PREFIX=wp_
```

Common locations:

```text
Proxy stack: $PROJECT_PATH/proxy
Site stack: $PROJECT_PATH/sites/$SITE_FOLDER
Site env: $PROJECT_PATH/sites/$SITE_FOLDER/.env
Proxy env: $PROJECT_PATH/proxy/.env
WordPress files: $PROJECT_PATH/sites/$SITE_FOLDER/html
```

## Read Env Values

Check the target site's database values:

```bash
cat $PROJECT_PATH/sites/$SITE_FOLDER/.env
```

Look for:

```env
WORDPRESS_DB_NAME=
WORDPRESS_DB_USER=
WORDPRESS_DB_PASSWORD=
```

Check the shared MariaDB root password:

```bash
cat $PROJECT_PATH/proxy/.env
```

Look for:

```env
SHARED_MYSQL_ROOT_PASSWORD=
```

Do not commit or share real passwords.

## HeidiSQL Access

The shared MariaDB service lives in the proxy stack. If you need HeidiSQL access, expose MariaDB only on the server localhost:

```yaml
ports:
  - "${MYSQL_BIND_ADDRESS:-127.0.0.1}:${MYSQL_PORT:-3306}:3306"
```

Apply the proxy compose change:

```bash
cd $PROJECT_PATH/proxy
docker compose up -d
```

Use HeidiSQL with an SSH tunnel:

```text
Network type: MySQL (SSH tunnel)

SSH host: server IP
SSH port: 22
SSH user: server SSH user

MySQL host: 127.0.0.1
MySQL port: 3306
Database: value of WORDPRESS_DB_NAME
User: value of WORDPRESS_DB_USER
Password: value of WORDPRESS_DB_PASSWORD
```

Do not bind MySQL to `0.0.0.0` unless the server firewall restricts port `3306` to trusted IPs only.

## Backup Before Import

Always backup the current target database first:

```bash
cd $PROJECT_PATH/proxy

docker compose exec mariadb mariadb-dump \
  -u root \
  -p'REPLACE_WITH_SHARED_MYSQL_ROOT_PASSWORD' \
  $TARGET_DB > $PROJECT_PATH/backup-$TARGET_DB-before-import.sql
```

Do not run:

```bash
docker compose down -v
```

That can delete shared MariaDB data and affect multiple sites.

## Check SQL Dump Before Import

Check for database-level commands:

```bash
grep -a -iE "DROP DATABASE|CREATE DATABASE|^USE " $SQL_DUMP | head -20
```

If the dump contains `DROP DATABASE`, `CREATE DATABASE`, or `USE another_database`, review it before importing. The safest flow is to choose the target database in the import command and avoid database-switching commands inside the dump.

## Import Into One Site Database

Run the import from the proxy folder:

```bash
cd $PROJECT_PATH/proxy

docker compose exec -T mariadb mariadb \
  -u root \
  -p'REPLACE_WITH_SHARED_MYSQL_ROOT_PASSWORD' \
  $TARGET_DB < $SQL_DUMP
```

If the command returns to the prompt without an error, the import completed.

## Check Table Prefix

Imported WordPress databases may use a custom table prefix such as:

```text
wp_
abc_
site1_
```

Check the imported table names with HeidiSQL or MariaDB. The live WordPress config must match:

```php
$table_prefix = 'TABLE_PREFIX';
```

The live config is:

```text
$PROJECT_PATH/sites/$SITE_FOLDER/html/wp-config.php
```

If the database tables are `abc_posts`, `abc_options`, etc., then:

```php
$table_prefix = 'abc_';
```

## Disable Broken Plugins

Old plugins can break on newer PHP versions. For example, old Wordfence versions can fail on PHP 8.x.

Try disabling the plugin with WP-CLI:

```bash
cd $PROJECT_PATH/sites/$SITE_FOLDER

docker compose -p $COMPOSE_PROJECT run --rm wpcli wp plugin deactivate plugin-folder-name \
  --path=/var/www/html \
  --skip-plugins \
  --skip-themes
```

If WP-CLI cannot run because the plugin crashes, rename the plugin folder:

```bash
mv html/wp-content/plugins/plugin-folder-name html/wp-content/plugins/plugin-folder-name.disabled
```

Then retry the WP-CLI command that failed.

## Flush Permalinks

Run from the site folder:

```bash
cd $PROJECT_PATH/sites/$SITE_FOLDER

docker compose -p $COMPOSE_PROJECT run --rm wpcli wp rewrite flush \
  --path=/var/www/html \
  --skip-plugins \
  --skip-themes
```

## Check And Update Site URLs

Read current URLs:

```bash
cd $PROJECT_PATH/sites/$SITE_FOLDER

docker compose -p $COMPOSE_PROJECT run --rm wpcli wp option get siteurl \
  --path=/var/www/html \
  --skip-plugins \
  --skip-themes

docker compose -p $COMPOSE_PROJECT run --rm wpcli wp option get home \
  --path=/var/www/html \
  --skip-plugins \
  --skip-themes
```

Update if needed:

```bash
docker compose -p $COMPOSE_PROJECT run --rm wpcli wp option update siteurl "$SITE_URL" \
  --path=/var/www/html \
  --skip-plugins \
  --skip-themes

docker compose -p $COMPOSE_PROJECT run --rm wpcli wp option update home "$SITE_URL" \
  --path=/var/www/html \
  --skip-plugins \
  --skip-themes
```

If the imported database contains an old URL, replace it:

```bash
docker compose -p $COMPOSE_PROJECT run --rm wpcli wp search-replace \
  'OLD_URL_HERE' \
  "$SITE_URL" \
  --path=/var/www/html \
  --skip-plugins \
  --skip-themes
```

## Check Containers And Logs

Site containers:

```bash
cd $PROJECT_PATH/sites/$SITE_FOLDER
docker compose -p $COMPOSE_PROJECT ps
docker compose -p $COMPOSE_PROJECT logs --tail=100 wordpress
docker compose -p $COMPOSE_PROJECT logs --tail=100 nginx
```

Proxy and database logs:

```bash
cd $PROJECT_PATH/proxy
docker compose logs --tail=100 mariadb
docker compose logs --tail=100 nginx-proxy
```

## Restore Files

A database import does not restore uploads, themes, or plugins. Restore old files into:

```text
$PROJECT_PATH/sites/$SITE_FOLDER/html/wp-content/
```

Most important folders:

```text
wp-content/uploads
wp-content/themes
wp-content/plugins
```

Fix ownership after copying files:

```bash
chown -R www-data:www-data $PROJECT_PATH/sites/$SITE_FOLDER/html/wp-content
```

## Final Verification

Open the site URL in a browser:

```text
$SITE_URL
```

If the site loads but images are missing, restore `wp-content/uploads`.

If the site shows a critical error, check plugin compatibility and container logs.

If WordPress shows a fresh install screen, check the database name and table prefix in `wp-config.php`.
